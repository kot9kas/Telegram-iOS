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

    @discardableResult
    public func start(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        guard !started else { return .single(()) }
        started = true
        self.accountManager = accountManager

        if let token = LitegramDeviceToken.getAccessToken() {
            api.accessToken = token
            NotificationCenter.default.post(name: .litegramAuthDidUpdate, object: nil)
        }

        let proxyReady: Signal<Void, NoError>
        let cached = LitegramConfig.getCachedServers()
        print("[Litegram] start: cached=\(cached.count)")
        for (i, s) in cached.enumerated() {
            print("[Litegram] start: server[\(i)] = \(s.host):\(s.port) (\(s.country.isEmpty ? "?" : s.country))")
        }

        let reachableServer = findReachableServer(from: cached)

        if let server = reachableServer, let secretData = dataFromHexString(server.secret) {
            print("[Litegram] start: using reachable \(server.host):\(server.port)")
            let proxyServer = ProxyServerSettings(
                host: server.host,
                port: Int32(server.port),
                connection: .mtp(secret: secretData)
            )
            proxyReady = updateProxySettingsInteractively(accountManager: accountManager) { settings in
                var settings = settings
                settings.activeServer = proxyServer
                settings.enabled = true
                return settings
            }
            |> map { _ in
                print("[Litegram] start: proxyReady COMPLETED — proxy written to accountManager")
            }
            self.lastConnectedServer = server
        } else if !cached.isEmpty, let server = cached.first, let secretData = dataFromHexString(server.secret) {
            print("[Litegram] start: no reachable server found, fallback to first cached \(server.host):\(server.port)")
            let proxyServer = ProxyServerSettings(
                host: server.host,
                port: Int32(server.port),
                connection: .mtp(secret: secretData)
            )
            proxyReady = updateProxySettingsInteractively(accountManager: accountManager) { settings in
                var settings = settings
                settings.activeServer = proxyServer
                settings.enabled = true
                return settings
            }
            |> map { _ in
                print("[Litegram] start: proxyReady COMPLETED (fallback)")
            }
            self.lastConnectedServer = server
        } else {
            print("[Litegram] start: NO cached servers, proxyReady = immediate")
            proxyReady = .single(())
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.connectProxy()
        }

        return proxyReady
    }

    private func findReachableServer(from servers: [LitegramServerInfo]) -> LitegramServerInfo? {
        let preferred = preferredServer(from: servers)
        let ordered: [LitegramServerInfo]
        if let preferred = preferred {
            ordered = [preferred] + servers.filter { $0.host != preferred.host }
        } else {
            ordered = servers
        }

        for server in ordered {
            if Self.tcpCheck(host: server.host, port: UInt16(server.port), timeout: 2) {
                return server
            }
            print("[Litegram] start: \(server.host):\(server.port) UNREACHABLE")
        }
        return nil
    }

    private static func tcpCheck(host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        var hints = addrinfo()
        hints.ai_socktype = SOCK_STREAM
        hints.ai_family = AF_UNSPEC
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "\(port)", &hints, &res) == 0, let info = res else { return false }
        defer { freeaddrinfo(res) }

        let sock = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let flags = fcntl(sock, F_GETFL, 0)
        _ = fcntl(sock, F_SETFL, flags | O_NONBLOCK)

        let connectResult = connect(sock, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if connectResult == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
        let pollResult = poll(&pfd, 1, Int32(timeout * 1000))
        guard pollResult > 0 else { return false }

        var optErr: Int32 = 0
        var optLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &optErr, &optLen)
        return optErr == 0
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
                        guard let self = self else { return }
                        if case let .success(servers) = serversResult, !servers.isEmpty {
                            LitegramConfig.saveCachedServers(servers)
                            if let server = self.findReachableServer(from: servers) {
                                self.applyProxy(server: server)
                            } else {
                                self.applyProxy(server: self.preferredServer(from: servers) ?? servers[0])
                            }
                        } else {
                            self.applyBestCachedOrAnonymous()
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
            guard let self = self else { return }
            switch result {
            case let .success(servers):
                if !servers.isEmpty {
                    LitegramConfig.saveCachedServers(servers)
                    if let server = self.findReachableServer(from: servers) {
                        self.applyProxy(server: server)
                    } else {
                        self.applyProxy(server: self.preferredServer(from: servers) ?? servers[0])
                    }
                    return
                }
                self.applyBestCachedOrAnonymous()
            case let .failure(error):
                Logger.shared.log("Litegram", "getProxyServers failed: \(error.localizedDescription)")
                if case LitegramApiError.authExpired = error {
                    self.reAuthenticate {
                        self.connectAuthenticated()
                    }
                } else {
                    self.applyBestCachedOrAnonymous()
                }
            }
        }
    }

    private func applyBestCachedOrAnonymous() {
        let cached = LitegramConfig.getCachedServers()
        if let server = findReachableServer(from: cached) {
            applyProxy(server: server)
        } else if !cached.isEmpty {
            applyProxy(server: preferredServer(from: cached) ?? cached[0])
        } else {
            connectAnonymous()
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
