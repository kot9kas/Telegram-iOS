import Foundation
import Postbox

public final class LitegramDeletedMessagesHook {
    public struct DeletedMessageInfo {
        public let messageId: Int32
        public let peerId: Int64
        public let authorId: Int64?
        public let authorName: String?
        public let text: String
        public let timestamp: Int32
        public let mediaDescription: String?
    }
    
    public static var isEnabled: (() -> Bool)?
    public static var onMessagesDeleted: (([DeletedMessageInfo]) -> Void)?
    
    static func extractAndNotify(transaction: Transaction, ids: [MessageId]) {
        guard let isEnabled = isEnabled, isEnabled(), let handler = onMessagesDeleted else { return }
        
        var infos: [DeletedMessageInfo] = []
        for id in ids {
            guard let message = transaction.getMessage(id) else { continue }
            guard message.flags.contains(.Incoming) else { continue }
            
            infos.append(DeletedMessageInfo(
                messageId: id.id,
                peerId: id.peerId.id._internalGetInt64Value(),
                authorId: message.author?.id.id._internalGetInt64Value(),
                authorName: extractAuthorName(message: message),
                text: message.text,
                timestamp: message.timestamp,
                mediaDescription: extractMediaDescription(message: message)
            ))
        }
        
        if !infos.isEmpty {
            handler(infos)
        }
    }
    
    static func extractAndNotifyGlobal(transaction: Transaction, globalIds: [Int32]) {
        guard isEnabled != nil, onMessagesDeleted != nil else { return }
        
        let messageIds = transaction.messageIdsForGlobalIds(globalIds)
        guard !messageIds.isEmpty else { return }
        extractAndNotify(transaction: transaction, ids: messageIds)
    }
    
    private static func extractAuthorName(message: Message) -> String? {
        guard let author = message.author else { return nil }
        if let user = author as? TelegramUser {
            return [user.firstName, user.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if let channel = author as? TelegramChannel {
            return channel.title
        }
        if let group = author as? TelegramGroup {
            return group.title
        }
        return nil
    }
    
    private static func extractMediaDescription(message: Message) -> String? {
        for media in message.media {
            if media is TelegramMediaImage { return "photo" }
            if let file = media as? TelegramMediaFile {
                if file.isVideo { return "video" }
                if file.isVoice { return "voice" }
                if file.isInstantVideo { return "video_message" }
                if file.isSticker { return "sticker" }
                if file.isAnimatedSticker { return "animated_sticker" }
                return "file: \(file.fileName ?? "unknown")"
            }
            if media is TelegramMediaContact { return "contact" }
            if media is TelegramMediaMap { return "location" }
        }
        return nil
    }
}
