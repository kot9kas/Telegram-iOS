import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

public final class LitegramProxyController {
    public static let shared = LitegramProxyController()

    public let api = LitegramApi()
    private(set) public var accountManager: AccountManager<TelegramAccountManagerTypes>?
    private var started = false
    public private(set) var lastConnectedServer: LitegramServerInfo?

    private init() {}

    public func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        guard !started else { return }
        started = true
        self.accountManager = accountManager

        if let token = LitegramDeviceToken.getAccessToken() {
            api.accessToken = token
            NotificationCenter.default.post(name: .litegramAuthDidUpdate, object: nil)
        }

        ensureProxyReady()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.connectProxy()
        }
    }

    private func ensureProxyReady() {
        let cached = LitegramConfig.getCachedServers()
        Logger.shared.log("Litegram", "ensureProxyReady: cached=\(cached.count)")
        if !cached.isEmpty {
            let server = preferredServer(from: cached) ?? cached[0]
            Logger.shared.log("Litegram", "ensureProxyReady: using cached \(server.host):\(server.port)")
            applyProxySync(server: server)
            return
        }

        let semaphore = DispatchSemaphore(value: 0)
        var fetched: LitegramServerInfo?

        let hasToken = LitegramDeviceToken.hasAccessToken
        Logger.shared.log("Litegram", "ensureProxyReady: no cache, hasToken=\(hasToken), fetching from API...")

        if hasToken {
            api.getProxyServers { result in
                switch result {
                case let .success(servers):
                    Logger.shared.log("Litegram", "ensureProxyReady: API returned \(servers.count) servers")
                    if let first = servers.first {
                        LitegramConfig.saveCachedServers(servers)
                        fetched = first
                    }
                case let .failure(error):
                    Logger.shared.log("Litegram", "ensureProxyReady: getProxyServers failed: \(error)")
                }
                semaphore.signal()
            }
        } else {
            let deviceToken = LitegramDeviceToken.getDeviceToken()
            api.claimTempProxy(deviceToken: deviceToken) { result in
                switch result {
                case let .success(server):
                    Logger.shared.log("Litegram", "ensureProxyReady: claimTempProxy got \(server.host):\(server.port)")
                    LitegramConfig.saveCachedServers([server])
                    fetched = server
                case let .failure(error):
                    Logger.shared.log("Litegram", "ensureProxyReady: claimTempProxy failed: \(error)")
                }
                semaphore.signal()
            }
        }

        let waitResult = semaphore.wait(timeout: .now() + 10.0)
        if waitResult == .timedOut {
            Logger.shared.log("Litegram", "ensureProxyReady: TIMEOUT waiting for API")
        }

        if let server = fetched {
            Logger.shared.log("Litegram", "ensureProxyReady: applying fetched \(server.host):\(server.port)")
            applyProxySync(server: server)
        } else {
            Logger.shared.log("Litegram", "ensureProxyReady: NO server available")
        }
    }

    private func applyProxySync(server: LitegramServerInfo) {
        guard let accountManager = self.accountManager else {
            Logger.shared.log("Litegram", "applyProxySync: no accountManager!")
            return
        }
        guard let secretData = dataFromHexString(server.secret) else {
            Logger.shared.log("Litegram", "applyProxySync: invalid secret for \(server.host)")
            return
        }

        let proxyServer = ProxyServerSettings(
            host: server.host,
            port: Int32(server.port),
            connection: .mtp(secret: secretData)
        )

        let proxySettings = ProxySettings(enabled: true, servers: [proxyServer], activeServer: proxyServer, useForCalls: false)
        _litegramProxyOverride = proxySettings
        print("[Litegram] applyProxySync: _litegramProxyOverride SET for \(server.host):\(server.port), secret=\(server.secret.prefix(8))...")

        let sem = DispatchSemaphore(value: 0)
        let _ = updateProxySettingsInteractively(accountManager: accountManager) { settings in
            var settings = settings
            settings.activeServer = proxyServer
            settings.enabled = true
            return settings
        }.start(completed: {
            sem.signal()
        })
        sem.wait()

        self.lastConnectedServer = server
        Logger.shared.log("Litegram", "applyProxySync: DONE \(server.host):\(server.port)")
        print("[Litegram] applyProxySync: accountManager updated DONE \(server.host):\(server.port)")
    }

    private var lastRegisteredTelegramId: Int64?

    public func ensureRegistered(telegramId: Int64) {
        guard lastRegisteredTelegramId != telegramId else { return }
        lastRegisteredTelegramId = telegramId
        onTelegramAuth(telegramId: telegramId)
    }

    public func onTelegramAuth(telegramId: Int64) {
        LitegramDeviceToken.saveTelegramId("\(telegramId)")
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let deviceToken = LitegramDeviceToken.getDeviceToken()
            self.api.register(telegramId: "\(telegramId)", deviceToken: deviceToken) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .success(authResult):
                    LitegramDeviceToken.saveAccessToken(authResult.accessToken)
                    self.api.accessToken = authResult.accessToken
                    NotificationCenter.default.post(name: .litegramAuthDidUpdate, object: nil)
                    if let status = authResult.subscriptionStatus {
                        LitegramConfig.saveSubscription(status: status, expiresAt: authResult.subscriptionExpiresAt)
                    }
                    self.api.getProxyServers { [weak self] serversResult in
                        if case let .success(servers) = serversResult, !servers.isEmpty {
                            LitegramConfig.saveCachedServers(servers)
                            let server = self?.preferredServer(from: servers) ?? servers[0]
                            self?.applyProxy(server: server)
                        } else {
                            let cached = LitegramConfig.getCachedServers()
                            if !cached.isEmpty {
                                let server = self?.preferredServer(from: cached) ?? cached[0]
                                self?.applyProxy(server: server)
                            }
                        }
                    }
                case let .failure(error):
                    Logger.shared.log("Litegram", "register failed: \(error.localizedDescription)")
                }
            }
        }
    }

    public func reconnect() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.connectProxy()
        }
    }

    public func disconnect() {
        guard let accountManager = self.accountManager else { return }
        self.lastConnectedServer = nil
        let _ = updateProxySettingsInteractively(accountManager: accountManager) { settings in
            var settings = settings
            settings.activeServer = nil
            settings.enabled = false
            return settings
        }.start()
    }

    public func applyServer(_ server: LitegramServerInfo) {
        applyProxy(server: server)
    }

    public func refreshSubscription(completion: (() -> Void)? = nil) {
        guard api.accessToken != nil else {
            completion?()
            return
        }
        api.getUserProfile { [weak self] result in
            switch result {
            case let .success(profile):
                LitegramConfig.saveSubscription(
                    status: profile.subscriptionStatus.rawValue,
                    expiresAt: profile.subscriptionExpiresAt
                )
                completion?()
            case let .failure(error):
                if case LitegramApiError.authExpired = error {
                    self?.reAuthenticate { completion?() }
                } else {
                    completion?()
                }
            }
        }
    }

    private func reAuthenticate(completion: (() -> Void)? = nil) {
        guard let telegramId = LitegramDeviceToken.getTelegramId() else {
            LitegramDeviceToken.clearAccessToken()
            completion?()
            return
        }
        let deviceToken = LitegramDeviceToken.getDeviceToken()
        api.register(telegramId: telegramId, deviceToken: deviceToken) { [weak self] result in
            switch result {
            case let .success(authResult):
                LitegramDeviceToken.saveAccessToken(authResult.accessToken)
                self?.api.accessToken = authResult.accessToken
                if let status = authResult.subscriptionStatus {
                    LitegramConfig.saveSubscription(status: status, expiresAt: authResult.subscriptionExpiresAt)
                }
                NotificationCenter.default.post(name: .litegramAuthDidUpdate, object: nil)
            case let .failure(error):
                Logger.shared.log("Litegram", "re-auth failed: \(error.localizedDescription)")
            }
            completion?()
        }
    }

    // MARK: - Private

    private func connectProxy() {
        if LitegramDeviceToken.hasAccessToken {
            connectAuthenticated()
        } else {
            connectAnonymous()
        }
    }

    private func connectAuthenticated() {
        api.getProxyServers { [weak self] result in
            switch result {
            case let .success(servers):
                if !servers.isEmpty {
                    LitegramConfig.saveCachedServers(servers)
                    let server = self?.preferredServer(from: servers) ?? servers[0]
                    self?.applyProxy(server: server)
                    return
                }
                let cached = LitegramConfig.getCachedServers()
                if !cached.isEmpty {
                    let server = self?.preferredServer(from: cached) ?? cached[0]
                    self?.applyProxy(server: server)
                } else {
                    self?.connectAnonymous()
                }
            case let .failure(error):
                if case LitegramApiError.authExpired = error {
                    self?.reAuthenticate {
                        self?.connectAuthenticated()
                    }
                } else {
                    let cached = LitegramConfig.getCachedServers()
                    if !cached.isEmpty {
                        let server = self?.preferredServer(from: cached) ?? cached[0]
                        self?.applyProxy(server: server)
                    } else {
                        self?.connectAnonymous()
                    }
                }
            }
        }
    }

    private func preferredServer(from servers: [LitegramServerInfo]) -> LitegramServerInfo? {
        guard let savedHost = LitegramConfig.selectedServerHost else { return nil }
        return servers.first(where: { $0.host == savedHost })
    }

    private func connectAnonymous() {
        let deviceToken = LitegramDeviceToken.getDeviceToken()
        api.claimTempProxy(deviceToken: deviceToken) { [weak self] result in
            switch result {
            case let .success(server):
                LitegramConfig.saveCachedServers([server])
                self?.applyProxy(server: server)
            case let .failure(error):
                Logger.shared.log("Litegram", "claimTempProxy failed: \(error.localizedDescription)")
                let cached = LitegramConfig.getCachedServers()
                if !cached.isEmpty {
                    let server = self?.preferredServer(from: cached) ?? cached[0]
                    self?.applyProxy(server: server)
                }
            }
        }
    }

    private func applyProxy(server: LitegramServerInfo) {
        guard let accountManager = self.accountManager else { return }
        guard let secretData = dataFromHexString(server.secret) else {
            Logger.shared.log("Litegram", "invalid hex secret")
            return
        }

        let proxyServer = ProxyServerSettings(
            host: server.host,
            port: Int32(server.port),
            connection: .mtp(secret: secretData)
        )

        let _ = updateProxySettingsInteractively(accountManager: accountManager) { settings in
            var settings = settings
            settings.activeServer = proxyServer
            settings.enabled = true
            return settings
        }.start()

        self.lastConnectedServer = server
        Logger.shared.log("Litegram", "proxy applied")
    }
}

public extension Notification.Name {
    static let litegramAuthDidUpdate = Notification.Name("litegram.authDidUpdate")
}

private func dataFromHexString(_ hex: String) -> Data? {
    var data = Data(capacity: hex.count / 2)
    var index = hex.startIndex
    while index < hex.endIndex {
        guard let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) else {
            return nil
        }
        guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
            return nil
        }
        data.append(byte)
        index = nextIndex
    }
    return data
}
