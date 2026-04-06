import Foundation

public final class LitegramDeviceToken {
    private static let suiteName = "litegram"
    private static let keyDeviceToken = "device_token"
    private static let keyAccessToken = "access_token"
    private static let keyTelegramId = "telegram_id"

    private static var cachedDeviceToken: String?
    private static var cachedAccessToken: String?
    private static var cachedTelegramId: String?

    public static func getDeviceToken() -> String {
        if let cached = cachedDeviceToken {
            return cached
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        if let stored = defaults.string(forKey: keyDeviceToken), !stored.isEmpty {
            cachedDeviceToken = stored
            return stored
        }
        let token = UUID().uuidString
        defaults.set(token, forKey: keyDeviceToken)
        cachedDeviceToken = token
        return token
    }

    public static func saveAccessToken(_ token: String) {
        cachedAccessToken = token
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(token, forKey: keyAccessToken)
    }

    public static func getAccessToken() -> String? {
        if let cached = cachedAccessToken {
            return cached.isEmpty ? nil : cached
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let stored = defaults.string(forKey: keyAccessToken) ?? ""
        cachedAccessToken = stored
        return stored.isEmpty ? nil : stored
    }

    public static var hasAccessToken: Bool {
        return getAccessToken() != nil
    }

    public static func saveTelegramId(_ id: String) {
        cachedTelegramId = id
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.set(id, forKey: keyTelegramId)
    }

    public static func getTelegramId() -> String? {
        if let cached = cachedTelegramId, !cached.isEmpty {
            return cached
        }
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let stored = defaults.string(forKey: keyTelegramId) ?? ""
        cachedTelegramId = stored
        return stored.isEmpty ? nil : stored
    }

    public static var hasTelegramId: Bool {
        return getTelegramId() != nil
    }

    public static func clearAccessToken() {
        cachedAccessToken = nil
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removeObject(forKey: keyAccessToken)
    }
}
