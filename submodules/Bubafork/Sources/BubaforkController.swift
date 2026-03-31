import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

public final class BubaforkController {
    public static let shared = BubaforkController()

    private let api = BubaforkApi()
    private var accountManager: AccountManager<TelegramAccountManagerTypes>?
    private var started = false

    private init() {}

    public func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        guard !started else { return }
        started = true
        self.accountManager = accountManager

        if let token = BubaforkDeviceToken.getAccessToken() {
            api.accessToken = token
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.connectProxy()
        }
    }

    public func onTelegramAuth(telegramId: Int64) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let deviceToken = BubaforkDeviceToken.getDeviceToken()
            self.api.register(telegramId: "\(telegramId)", deviceToken: deviceToken) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case let .success(authResult):
                    BubaforkDeviceToken.saveAccessToken(authResult.accessToken)
                    self.api.getProxyServers { [weak self] serversResult in
                        if case let .success(servers) = serversResult, let first = servers.first {
                            self?.applyProxy(server: first)
                        }
                    }
                case let .failure(error):
                    Logger.shared.log("Bubafork", "register failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Private

    private func connectProxy() {
        if BubaforkDeviceToken.hasAccessToken {
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
            case .failure:
                self?.connectAnonymous()
            }
        }
    }

    private func connectAnonymous() {
        let deviceToken = BubaforkDeviceToken.getDeviceToken()
        api.claimTempProxy(deviceToken: deviceToken) { [weak self] result in
            switch result {
            case let .success(server):
                self?.applyProxy(server: server)
            case let .failure(error):
                Logger.shared.log("Bubafork", "claimTempProxy failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyProxy(server: BubaforkServerInfo) {
        guard let accountManager = self.accountManager else { return }
        guard let secretData = dataFromHexString(server.secret) else {
            Logger.shared.log("Bubafork", "invalid hex secret")
            return
        }

        let proxyServer = ProxyServerSettings(
            host: server.host,
            port: Int32(server.port),
            connection: .mtp(secret: secretData)
        )

        let _ = updateProxySettingsInteractively(accountManager: accountManager) { settings in
            var settings = settings
            if !settings.servers.contains(proxyServer) {
                settings.servers.insert(proxyServer, at: 0)
            }
            settings.activeServer = proxyServer
            settings.enabled = true
            return settings
        }.start()

        Logger.shared.log("Bubafork", "proxy applied")
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
