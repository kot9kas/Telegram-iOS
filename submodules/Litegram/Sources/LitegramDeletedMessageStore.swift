import Foundation
import TelegramCore

public struct LitegramDeletedMessage: Codable, Identifiable {
    public let id: String
    public let messageId: Int32
    public let peerId: Int64
    public let authorId: Int64?
    public let authorName: String?
    public let text: String
    public let timestamp: Int32
    public let mediaDescription: String?
    public let savedAt: TimeInterval
    
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
                id: "\(info.peerId)_\(info.messageId)",
                messageId: info.messageId,
                peerId: info.peerId,
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
                NotificationCenter.default.post(name: .litegramDeletedMessagesUpdated, object: nil)
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
