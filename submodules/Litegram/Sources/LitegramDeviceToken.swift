import Foundation

public final class LitegramDeviceToken {
    private static let suiteName = "litegram"
    private static let keyDeviceToken = "device_token"
    private static let keyAccessToken = "access_token"

    private static var cachedDeviceToken: String?
    private static var cachedAccessToken: String?

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
}
