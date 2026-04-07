import Foundation
import TelegramCore

public struct LitegramDeletedMessage: Codable, Identifiable {
    private enum CodingKeys: String, CodingKey {
        case id
        case messageId
        case peerId
        case peerNamespace
        case authorId
        case authorName
        case text
        case timestamp
        case mediaDescription
        case savedAt
    }

    public let id: String
    public let messageId: Int32
    public let peerId: Int64
    public let peerNamespace: Int32
    public let authorId: Int64?
    public let authorName: String?
    public let text: String
    public let timestamp: Int32
    public let mediaDescription: String?
    public let savedAt: TimeInterval
    
    public init(
        id: String,
        messageId: Int32,
        peerId: Int64,
        peerNamespace: Int32,
        authorId: Int64?,
        authorName: String?,
        text: String,
        timestamp: Int32,
        mediaDescription: String?,
        savedAt: TimeInterval
    ) {
        self.id = id
        self.messageId = messageId
        self.peerId = peerId
        self.peerNamespace = peerNamespace
        self.authorId = authorId
        self.authorName = authorName
        self.text = text
        self.timestamp = timestamp
        self.mediaDescription = mediaDescription
        self.savedAt = savedAt
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.messageId = try c.decode(Int32.self, forKey: .messageId)
        self.peerId = try c.decode(Int64.self, forKey: .peerId)
        self.peerNamespace = try c.decodeIfPresent(Int32.self, forKey: .peerNamespace) ?? 0
        self.authorId = try c.decodeIfPresent(Int64.self, forKey: .authorId)
        self.authorName = try c.decodeIfPresent(String.self, forKey: .authorName)
        self.text = try c.decode(String.self, forKey: .text)
        self.timestamp = try c.decode(Int32.self, forKey: .timestamp)
        self.mediaDescription = try c.decodeIfPresent(String.self, forKey: .mediaDescription)
        self.savedAt = try c.decode(TimeInterval.self, forKey: .savedAt)
    }
    
    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
    
    public var savedDate: Date {
        Date(timeIntervalSince1970: savedAt)
    }
    
    public var displayText: String {
        if !text.isEmpty { return text }
        if let media = mediaDescription { return "[\(mediaLocalizedName(media))]" }
        return "[сообщение]"
    }
}

private func mediaLocalizedName(_ desc: String) -> String {
    switch desc {
    case "photo": return "Фото"
    case "video": return "Видео"
    case "voice": return "Голосовое"
    case "video_message": return "Видеосообщение"
    case "sticker", "animated_sticker": return "Стикер"
    case "contact": return "Контакт"
    case "location": return "Геолокация"
    default:
        if desc.hasPrefix("file:") {
            return "Файл: \(desc.dropFirst(6))"
        }
        return desc
    }
}

public final class LitegramDeletedMessageStore {
    public static let shared = LitegramDeletedMessageStore()
    
    private let queue = DispatchQueue(label: "litegram.deleted-messages", qos: .utility)
    private let maxMessages = 500
    private var messages: [LitegramDeletedMessage] = []
    private var loaded = false
    
    private init() {}
    
    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("litegram_deleted_messages.json")
    }
    
    public func setup() {
        LitegramDeletedMessagesHook.isEnabled = {
            LitegramConfig.isSaveDeletedMessagesEnabled
        }
        LitegramDeletedMessagesHook.onMessagesDeleted = { [weak self] infos in
            self?.save(infos)
        }
        queue.async { [weak self] in
            self?.loadFromDisk()
        }
    }
    
    private func save(_ infos: [LitegramDeletedMessagesHook.DeletedMessageInfo]) {
        let now = Date().timeIntervalSince1970
        let newMessages = infos.map { info in
            LitegramDeletedMessage(
                id: "\(info.peerNamespace)_\(info.peerId)_\(info.messageId)",
                messageId: info.messageId,
                peerId: info.peerId,
                peerNamespace: info.peerNamespace,
                authorId: info.authorId,
                authorName: info.authorName,
                text: info.text,
                timestamp: info.timestamp,
                mediaDescription: info.mediaDescription,
                savedAt: now
            )
        }
        
        queue.async { [weak self] in
            guard let self else { return }
            if !self.loaded { self.loadFromDisk() }
            
            let existingIds = Set(self.messages.map(\.id))
            let unique = newMessages.filter { !existingIds.contains($0.id) }
            self.messages.append(contentsOf: unique)
            
            if self.messages.count > self.maxMessages {
                self.messages = Array(self.messages.suffix(self.maxMessages))
            }
            
            self.saveToDisk()
            
            DispatchQueue.main.async {
                if let latest = unique.last {
                    NotificationCenter.default.post(
                        name: .litegramDeletedMessagesUpdated,
                        object: nil,
                        userInfo: [
                            LitegramDeletedMessageNotificationKey.peerId: NSNumber(value: latest.peerId),
                            LitegramDeletedMessageNotificationKey.peerNamespace: NSNumber(value: latest.peerNamespace),
                            LitegramDeletedMessageNotificationKey.authorName: latest.authorName ?? "",
                            LitegramDeletedMessageNotificationKey.text: latest.displayText
                        ]
                    )
                } else {
                    NotificationCenter.default.post(name: .litegramDeletedMessagesUpdated, object: nil)
                }
            }
        }
    }
    
    public func allMessages() -> [LitegramDeletedMessage] {
        if !loaded { loadFromDisk() }
        return messages.sorted { $0.timestamp > $1.timestamp }
    }
    
    public func messages(forPeerId peerId: Int64) -> [LitegramDeletedMessage] {
        return allMessages().filter { $0.peerId == peerId }
    }
    
    public func messages(forPeerId peerId: Int64, peerNamespace: Int32) -> [LitegramDeletedMessage] {
        return allMessages().filter { $0.peerId == peerId && $0.peerNamespace == peerNamespace }
    }
    
    public func deleteMessage(id: String) {
        queue.async { [weak self] in
            guard let self else { return }
            self.messages.removeAll { $0.id == id }
            self.saveToDisk()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .litegramDeletedMessagesUpdated, object: nil)
            }
        }
    }
    
    public func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            self.messages.removeAll()
            self.saveToDisk()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .litegramDeletedMessagesUpdated, object: nil)
            }
        }
    }
    
    public var count: Int {
        if !loaded { loadFromDisk() }
        return messages.count
    }
    
    private func loadFromDisk() {
        guard !loaded else { return }
        loaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            messages = try JSONDecoder().decode([LitegramDeletedMessage].self, from: data)
        } catch {
            messages = []
        }
    }
    
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: fileURL, options: .atomic)
        } catch {}
    }
}

public extension Notification.Name {
    static let litegramDeletedMessagesUpdated = Notification.Name("litegram.deletedMessagesUpdated")
}

public enum LitegramDeletedMessageNotificationKey {
    public static let peerId = "peerId"
    public static let peerNamespace = "peerNamespace"
    public static let authorName = "authorName"
    public static let text = "text"
}
