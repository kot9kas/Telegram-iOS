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
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.connectProxy()
        }
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
                    if let status = authResult.subscriptionStatus {
                        LitegramConfig.saveSubscription(status: status, expiresAt: authResult.subscriptionExpiresAt)
                    }
                    self.api.getProxyServers { [weak self] serversResult in
                        if case let .success(servers) = serversResult, let first = servers.first {
                            self?.applyProxy(server: first)
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
                if let first = servers.first {
                    self?.applyProxy(server: first)
                    return
                }
                self?.connectAnonymous()
            case let .failure(error):
                if case LitegramApiError.authExpired = error {
                    self?.reAuthenticate {
                        self?.connectAuthenticated()
                    }
                } else {
                    self?.connectAnonymous()
                }
            }
        }
    }

    private func connectAnonymous() {
        let deviceToken = LitegramDeviceToken.getDeviceToken()
        api.claimTempProxy(deviceToken: deviceToken) { [weak self] result in
            switch result {
            case let .success(server):
                self?.applyProxy(server: server)
            case let .failure(error):
                Logger.shared.log("Litegram", "claimTempProxy failed: \(error.localizedDescription)")
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
