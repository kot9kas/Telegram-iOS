import Foundation

public final class LitegramAdManager {
    public static let shared = LitegramAdManager()

    private static let suiteName = "litegram"
    private static let keyLastAdShown = "last_ad_shown_ts"
    private static let cooldownSeconds: TimeInterval = 3600

    private var hasFetched = false
    private var cachedAd: LitegramAdInfo?

    private init() {}

    public var shouldShowAd: Bool {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        let lastShown = defaults.double(forKey: Self.keyLastAdShown)
        guard lastShown > 0 else { return true }
        return Date().timeIntervalSince1970 - lastShown >= Self.cooldownSeconds
    }

    public func markAdShown() {
        let defaults = UserDefaults(suiteName: Self.suiteName) ?? .standard
        defaults.set(Date().timeIntervalSince1970, forKey: Self.keyLastAdShown)
    }

    public func fetchActiveAd(completion: @escaping (LitegramAdInfo?) -> Void) {
        if hasFetched {
            completion(cachedAd)
            return
        }
        let api = LitegramProxyController.shared.api
        api.getActiveAd { [weak self] result in
            switch result {
            case let .success(ad):
                self?.cachedAd = ad
                self?.hasFetched = true
                completion(ad)
            case .failure:
                completion(nil)
            }
        }
    }

    public func resetCache() {
        hasFetched = false
        cachedAd = nil
    }
}
