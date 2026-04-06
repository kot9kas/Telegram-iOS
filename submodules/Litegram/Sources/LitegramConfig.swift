import Foundation

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

    private static var defaults: UserDefaults { UserDefaults(suiteName: suiteName) ?? .standard }

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

    private static let keyThemeApplied = "default_theme_applied"
    public static let defaultThemeSlugs = ["CnQmN19GGAm7hJRg", "UVfCBD0qw76lPMyM"]

    public static var hasAppliedDefaultTheme: Bool {
        get { defaults.bool(forKey: keyThemeApplied) }
        set { defaults.set(newValue, forKey: keyThemeApplied) }
    }
}
