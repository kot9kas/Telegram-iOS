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

    private var connectionMonitorDisposable: Disposable?
    private var connectingTimer: Timer?
    private var lastReconnectTime: CFAbsoluteTime = 0
    private let reconnectCooldown: TimeInterval = 15
    private var consecutiveFailures: Int = 0
    private let maxConsecutiveFailures = 5

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
        Logger.shared.log("Litegram", "start: cached=\(cached.count)")
        for (i, s) in cached.enumerated() {
            Logger.shared.log("Litegram", "start: server[\(i)] = \(s.host):\(s.port) (\(s.country.isEmpty ? "?" : s.country))")
        }

        let reachableServer = findReachableServer(from: cached)

        if let server = reachableServer, let secretData = dataFromHexString(server.secret) {
            Logger.shared.log("Litegram", "start: using reachable \(server.host):\(server.port)")
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
                Logger.shared.log("Litegram", "start: proxyReady COMPLETED")
            }
            self.lastConnectedServer = server
        } else if !cached.isEmpty, let server = cached.first, let secretData = dataFromHexString(server.secret) {
            Logger.shared.log("Litegram", "start: fallback to first cached \(server.host):\(server.port)")
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
                Logger.shared.log("Litegram", "start: proxyReady COMPLETED (fallback)")
            }
            self.lastConnectedServer = server
        } else {
            Logger.shared.log("Litegram", "start: no cached servers, fetching from API")
            proxyReady = self.fetchProxyBeforeStart(accountManager: accountManager)
        }

        if !cached.isEmpty {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.connectProxy()
            }
        }

        return proxyReady
    }

    private func fetchProxyBeforeStart(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Void, NoError> {
        return Signal { subscriber in
            let fetchBlock = { [weak self] in
                guard let self = self else {
                    subscriber.putNext(())
                    subscriber.putCompletion()
                    return
                }

                let done = { (server: LitegramServerInfo?) in
                    if let server = server, let secretData = dataFromHexString(server.secret) {
                        Logger.shared.log("Litegram", "start: fetched \(server.host):\(server.port) from API")
                        LitegramConfig.saveCachedServers([server])
                        let proxyServer = ProxyServerSettings(
                            host: server.host,
                            port: Int32(server.port),
                            connection: .mtp(secret: secretData)
                        )
                        let _ = (updateProxySettingsInteractively(accountManager: accountManager) { settings in
                            var settings = settings
                            settings.activeServer = proxyServer
                            settings.enabled = true
                            return settings
                        }
                        |> deliverOnMainQueue).start(completed: {
                            Logger.shared.log("Litegram", "start: proxyReady COMPLETED (first launch)")
                            subscriber.putNext(())
                            subscriber.putCompletion()
                        })
                        self.lastConnectedServer = server
                    } else {
                        Logger.shared.log("Litegram", "start: API returned no usable proxy, proceeding without")
                        subscriber.putNext(())
                        subscriber.putCompletion()
                    }
                }

                if LitegramDeviceToken.hasAccessToken {
                    self.api.getProxyServers { result in
                        switch result {
                        case let .success(servers) where !servers.isEmpty:
                            LitegramConfig.saveCachedServers(servers)
                            let server = self.findReachableServer(from: servers) ?? self.preferredServer(from: servers) ?? servers[0]
                            done(server)
                        default:
                            let deviceToken = LitegramDeviceToken.getDeviceToken()
                            self.api.claimTempProxy(deviceToken: deviceToken) { claimResult in
                                if case let .success(server) = claimResult {
                                    done(server)
                                } else {
                                    done(nil)
                                }
                            }
                        }
                    }
                } else {
                    let deviceToken = LitegramDeviceToken.getDeviceToken()
                    self.api.claimTempProxy(deviceToken: deviceToken) { result in
                        if case let .success(server) = result {
                            done(server)
                        } else {
                            done(nil)
                        }
                    }
                }
            }

            DispatchQueue.global(qos: .userInitiated).async(execute: fetchBlock)
            return EmptyDisposable
        }
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
            Logger.shared.log("Litegram", "start: \(server.host):\(server.port) UNREACHABLE")
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

    // MARK: - Connection Monitor

    public func startConnectionMonitor(network: Network) {
        guard connectionMonitorDisposable == nil else { return }

        connectionMonitorDisposable = (network.connectionStatus
            |> deliverOnMainQueue).startStrict(next: { [weak self] status in
                self?.handleConnectionStatus(status)
            })
        Logger.shared.log("Litegram", "monitor: started")
    }

    private func handleConnectionStatus(_ status: ConnectionStatus) {
        switch status {
        case .online:
            connectingTimer?.invalidate()
            connectingTimer = nil
            consecutiveFailures = 0

        case let .connecting(_, proxyHasIssues):
            let timeout: TimeInterval = proxyHasIssues ? 5 : 12
            if connectingTimer == nil {
                connectingTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
                    self?.connectingTimer = nil
                    self?.attemptAutoReconnect()
                }
            }

        case .waitingForNetwork:
            if connectingTimer == nil {
                connectingTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: false) { [weak self] _ in
                    self?.connectingTimer = nil
                    self?.attemptAutoReconnect()
                }
            }

        case .updating:
            connectingTimer?.invalidate()
            connectingTimer = nil
        }
    }

    private func attemptAutoReconnect() {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReconnectTime >= reconnectCooldown else {
            Logger.shared.log("Litegram", "monitor: cooldown active, skipping reconnect")
            return
        }
        guard consecutiveFailures < maxConsecutiveFailures else {
            Logger.shared.log("Litegram", "monitor: max failures (\(maxConsecutiveFailures)) reached, stopping auto-reconnect")
            return
        }

        lastReconnectTime = now
        consecutiveFailures += 1
        Logger.shared.log("Litegram", "monitor: auto-reconnect attempt \(consecutiveFailures)")

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.rotateToNextServer()
        }
    }

    private func rotateToNextServer() {
        let cached = LitegramConfig.getCachedServers()
        guard !cached.isEmpty else {
            Logger.shared.log("Litegram", "monitor: no cached servers for rotation, fetching")
            connectProxy()
            return
        }

        let currentHost = lastConnectedServer?.host
        let otherServers = cached.filter { $0.host != currentHost }
        let candidates = otherServers.isEmpty ? cached : otherServers

        if let reachable = findReachableServer(from: candidates) {
            Logger.shared.log("Litegram", "monitor: rotating to \(reachable.host):\(reachable.port)")
            applyProxy(server: reachable)
        } else {
            Logger.shared.log("Litegram", "monitor: no reachable servers, refetching from API")
            connectProxy()
        }
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
