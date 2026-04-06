import Foundation

public struct LitegramServerInfo {
    public let host: String
    public let port: Int
    public let secret: String
    public let name: String
    public let country: String

    public init(host: String, port: Int, secret: String, name: String = "", country: String = "") {
        self.host = host
        self.port = port
        self.secret = secret
        self.name = name
        self.country = country
    }
}

public struct LitegramAuthResult {
    public let accessToken: String
    public let userId: String
    public let subscriptionStatus: String?
    public let subscriptionExpiresAt: String?

    public init(accessToken: String, userId: String, subscriptionStatus: String? = nil, subscriptionExpiresAt: String? = nil) {
        self.accessToken = accessToken
        self.userId = userId
        self.subscriptionStatus = subscriptionStatus
        self.subscriptionExpiresAt = subscriptionExpiresAt
    }
}

public struct LitegramAdInfo {
    public let id: String
    public let title: String
    public let description: String
    public let imageUrl: String?
    public let linkUrl: String?
}

public enum LitegramSubscriptionStatus: String {
    case none = "none"
    case trial = "trial"
    case active = "active"
    case expired = "expired"
    case cancelled = "cancelled"
    
    public var displayName: String {
        switch self {
        case .none: return "Free"
        case .trial: return "Trial"
        case .active: return "Active"
        case .expired: return "Expired"
        case .cancelled: return "Cancelled"
        }
    }
    
    public var isActive: Bool {
        return self == .active || self == .trial
    }
}

public struct LitegramUserProfile {
    public let id: String
    public let telegramId: String
    public let subscriptionStatus: LitegramSubscriptionStatus
    public let subscriptionExpiresAt: String?
}

public final class LitegramApi {
    private let session: URLSession
    public var accessToken: String?

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = LitegramConfig.connectionTimeout
        config.timeoutIntervalForResource = LitegramConfig.connectionTimeout * 3
        self.session = URLSession(configuration: config)
    }

    public func claimTempProxy(deviceToken: String, completion: @escaping (Result<LitegramServerInfo, Error>) -> Void) {
        let body: [String: Any] = ["deviceToken": deviceToken]
        httpPost(path: "/proxy/public/claim", body: body) { result in
            switch result {
            case let .success(json):
                do {
                    let server = try Self.parseFirstServer(json)
                    completion(.success(server))
                } catch {
                    completion(.failure(error))
                }
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func register(telegramId: String, deviceToken: String, completion: @escaping (Result<LitegramAuthResult, Error>) -> Void) {
        let body: [String: Any] = [
            "telegramId": telegramId,
            "deviceToken": deviceToken,
            "platform": LitegramConfig.platform
        ]
        httpPost(path: "/auth/register", body: body) { [weak self] result in
            switch result {
            case let .success(json):
                guard let token = json["accessToken"] as? String, !token.isEmpty else {
                    completion(.failure(LitegramApiError.noAccessToken))
                    return
                }
                self?.accessToken = token

                var userId = ""
                var subStatus: String?
                var subExpires: String?
                if let user = json["user"] as? [String: Any] {
                    userId = "\(user["id"] ?? "")"
                    subStatus = user["subscriptionStatus"] as? String
                    subExpires = user["subscriptionExpiresAt"] as? String
                }
                completion(.success(LitegramAuthResult(
                    accessToken: token,
                    userId: userId,
                    subscriptionStatus: subStatus,
                    subscriptionExpiresAt: subExpires
                )))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func getUserProfile(completion: @escaping (Result<LitegramUserProfile, Error>) -> Void) {
        httpGet(path: "/user/me") { result in
            switch result {
            case let .success(json):
                let id = "\(json["id"] ?? "")"
                let telegramId = "\(json["telegramId"] ?? "")"
                let statusStr = json["subscriptionStatus"] as? String ?? "none"
                let status = LitegramSubscriptionStatus(rawValue: statusStr) ?? .none
                let expiresAt = json["subscriptionExpiresAt"] as? String
                completion(.success(LitegramUserProfile(
                    id: id,
                    telegramId: telegramId,
                    subscriptionStatus: status,
                    subscriptionExpiresAt: expiresAt
                )))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func getProxyServers(completion: @escaping (Result<[LitegramServerInfo], Error>) -> Void) {
        httpGet(path: "/proxy/servers") { result in
            switch result {
            case let .success(json):
                var servers: [LitegramServerInfo] = []

                if let regular = json["regular"] as? [[String: Any]] {
                    for s in regular {
                        if let server = Self.parseServer(s) {
                            servers.append(server)
                        }
                    }
                }
                if let bypass = json["bypass"] as? [[String: Any]] {
                    for s in bypass {
                        if let server = Self.parseServer(s) {
                            servers.append(server)
                        }
                    }
                }
                completion(.success(servers))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func getActiveAd(completion: @escaping (Result<LitegramAdInfo?, Error>) -> Void) {
        httpGet(path: "/advertising/active") { result in
            switch result {
            case let .success(json):
                guard !json.isEmpty else {
                    completion(.success(nil))
                    return
                }
                let id = "\(json["id"] ?? "")"
                let title = json["title"] as? String ?? ""
                let desc = json["description"] as? String ?? ""
                let imageUrl = json["imageUrl"] as? String
                let linkUrl = json["linkUrl"] as? String
                completion(.success(LitegramAdInfo(
                    id: id, title: title, description: desc,
                    imageUrl: imageUrl, linkUrl: linkUrl
                )))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private

    private func httpGet(path: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: LitegramConfig.apiURL(path))
        request.httpMethod = "GET"
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        perform(request: request, completion: completion)
    }

    private func httpPost(path: String, body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: LitegramConfig.apiURL(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        perform(request: request, completion: completion)
    }

    private func perform(request: URLRequest, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(LitegramApiError.noData))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(LitegramApiError.noData))
                return
            }
            if httpResponse.statusCode == 401 {
                completion(.failure(LitegramApiError.authExpired))
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(LitegramApiError.httpError(httpResponse.statusCode, body)))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(LitegramApiError.invalidJSON))
                return
            }
            completion(.success(json))
        }.resume()
    }

    private static func parseServer(_ dict: [String: Any]) -> LitegramServerInfo? {
        guard let host = dict["host"] as? String,
              let secret = dict["secret"] as? String else {
            return nil
        }
        let port = dict["port"] as? Int ?? 443
        let name = dict["name"] as? String ?? ""
        let country = dict["country"] as? String ?? ""
        return LitegramServerInfo(host: host, port: port, secret: secret, name: name, country: country)
    }

    private static func parseFirstServer(_ json: [String: Any]) throws -> LitegramServerInfo {
        if let regular = json["regular"] as? [[String: Any]], let first = regular.first, let server = parseServer(first) {
            return server
        }
        if let bypass = json["bypass"] as? [[String: Any]], let first = bypass.first, let server = parseServer(first) {
            return server
        }
        if let server = parseServer(json) {
            return server
        }
        throw LitegramApiError.noServer
    }
}

public enum LitegramApiError: Error, LocalizedError {
    case noData
    case invalidJSON
    case httpError(Int, String)
    case noAccessToken
    case noServer
    case authExpired

    public var errorDescription: String? {
        switch self {
        case .noData:
            return "No data received"
        case .invalidJSON:
            return "Invalid JSON response"
        case let .httpError(code, body):
            return "HTTP \(code): \(body)"
        case .noAccessToken:
            return "No access token in response"
        case .noServer:
            return "No server in response"
        case .authExpired:
            return "JWT token expired (401)"
        }
    }
}
