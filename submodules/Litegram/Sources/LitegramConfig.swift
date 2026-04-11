import Foundation
import Security

public enum LitegramConfig {
    public static let apiBaseURL = "https://test.enderfall.net"
    public static let apiVersion = "v1"
    public static let platform = "ios"
    public static let connectionTimeout: TimeInterval = 10

    public static func apiURL(_ path: String) -> URL {
        URL(string: "\(apiBaseURL)/api/\(apiVersion)\(path)")!
    }

    private static let suiteName = "litegram"
    private static let keySubStatus = "sub_status"
    private static let keySubExpires = "sub_expires"
    private static let keySaveTraffic = "save_traffic"
    private static let keyCachedServers = "cached_proxy_servers_v1"
    private static let cachedServersKeychainService = "io.litegram.cache"
    private static let cachedServersKeychainAccount = "proxy_servers"
    private static let cachedServersSchemaVersion = 1
    private static let cachedServersTtl: TimeInterval = 60 * 60 * 24 * 90

    private static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }
    
    private struct CachedServersEnvelope: Codable {
        let version: Int
        let savedAt: TimeInterval
        let servers: [LitegramServerInfo]
    }

    public static func saveSubscription(status: String, expiresAt: String?) {
        let d = defaults
        d.set(status, forKey: keySubStatus)
        if let exp = expiresAt {
            d.set(exp, forKey: keySubExpires)
        } else {
            d.removeObject(forKey: keySubExpires)
        }
    }

    public static var subscriptionStatus: String {
        defaults.string(forKey: keySubStatus) ?? "none"
    }

    public static var subscriptionExpiresAt: String? {
        defaults.string(forKey: keySubExpires)
    }

    public static var isSubscriptionActive: Bool {
        let status = subscriptionStatus
        guard status == "active" || status == "trial" else { return false }
        guard let expires = subscriptionExpiresAt, !expires.isEmpty else { return true }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fmt.date(from: expires) {
            if date < Date() {
                saveSubscription(status: "expired", expiresAt: expires)
                return false
            }
        }
        let fmt2 = ISO8601DateFormatter()
        fmt2.formatOptions = [.withInternetDateTime]
        if let date = fmt2.date(from: expires) {
            if date < Date() {
                saveSubscription(status: "expired", expiresAt: expires)
                return false
            }
        }
        return true
    }

    public static var isSaveTrafficEnabled: Bool {
        get { defaults.object(forKey: keySaveTraffic) as? Bool ?? true }
        set { defaults.set(newValue, forKey: keySaveTraffic) }
    }

    private static let keyThemeApplied = "default_theme_applied_v2"
    // Keep a stable primary default theme. Do not reorder.
    public static let defaultThemeSlugs = ["CnQmN19GGAm7hJRg", "UVfCBD0qw76lPMyM", "J5if4oa5U3jcEmRQ"]

    public static var hasAppliedDefaultTheme: Bool {
        get { defaults.bool(forKey: keyThemeApplied) }
        set { defaults.set(newValue, forKey: keyThemeApplied) }
    }

    private static let keySelectedServer = "selected_server_host"

    public static var selectedServerHost: String? {
        get { defaults.string(forKey: keySelectedServer) }
        set {
            if let v = newValue {
                defaults.set(v, forKey: keySelectedServer)
            } else {
                defaults.removeObject(forKey: keySelectedServer)
            }
        }
    }

    public static func saveCachedServers(_ servers: [LitegramServerInfo]) {
        let envelope = CachedServersEnvelope(
            version: cachedServersSchemaVersion,
            savedAt: Date().timeIntervalSince1970,
            servers: servers
        )
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        _ = setKeychainData(data, service: cachedServersKeychainService, account: cachedServersKeychainAccount)
        defaults.removeObject(forKey: keyCachedServers)
    }

    public static func getCachedServers() -> [LitegramServerInfo] {
        var servers: [LitegramServerInfo] = []

        if let data = getKeychainData(service: cachedServersKeychainService, account: cachedServersKeychainAccount),
           let envelope = try? JSONDecoder().decode(CachedServersEnvelope.self, from: data),
           envelope.version == cachedServersSchemaVersion {
            if Date().timeIntervalSince1970 - envelope.savedAt <= cachedServersTtl {
                servers = envelope.servers
            } else {
                _ = removeKeychainData(service: cachedServersKeychainService, account: cachedServersKeychainAccount)
            }
        }

        if servers.isEmpty,
           let legacyData = defaults.data(forKey: keyCachedServers),
           let legacyServers = try? JSONDecoder().decode([LitegramServerInfo].self, from: legacyData),
           !legacyServers.isEmpty {
            saveCachedServers(legacyServers)
            defaults.removeObject(forKey: keyCachedServers)
            servers = legacyServers
        }

        servers.sort { a, b in
            let aIsRU = a.country.uppercased() == "RU"
            let bIsRU = b.country.uppercased() == "RU"
            if aIsRU != bIsRU { return aIsRU }
            return false
        }
        return servers
    }
    
    @discardableResult
    private static func setKeychainData(_ data: Data, service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        var insertQuery = query
        insertQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(insertQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
    }
    
    private static func getKeychainData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }
    
    @discardableResult
    private static func removeKeychainData(service: String, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
