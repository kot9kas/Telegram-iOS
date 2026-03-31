import Foundation

public struct BubaforkServerInfo {
    public let host: String
    public let port: Int
    public let secret: String

    public init(host: String, port: Int, secret: String) {
        self.host = host
        self.port = port
        self.secret = secret
    }
}

public struct BubaforkAuthResult {
    public let accessToken: String
    public let userId: String

    public init(accessToken: String, userId: String) {
        self.accessToken = accessToken
        self.userId = userId
    }
}

public final class BubaforkApi {
    private let session: URLSession
    public var accessToken: String?

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = BubaforkConfig.connectionTimeout
        config.timeoutIntervalForResource = BubaforkConfig.connectionTimeout * 3
        self.session = URLSession(configuration: config)
    }

    public func claimTempProxy(deviceToken: String, completion: @escaping (Result<BubaforkServerInfo, Error>) -> Void) {
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

    public func register(telegramId: String, deviceToken: String, completion: @escaping (Result<BubaforkAuthResult, Error>) -> Void) {
        let body: [String: Any] = [
            "telegramId": telegramId,
            "deviceToken": deviceToken,
            "platform": BubaforkConfig.platform
        ]
        httpPost(path: "/auth/register", body: body) { [weak self] result in
            switch result {
            case let .success(json):
                guard let token = json["accessToken"] as? String, !token.isEmpty else {
                    completion(.failure(BubaforkApiError.noAccessToken))
                    return
                }
                self?.accessToken = token

                var userId = ""
                if let user = json["user"] as? [String: Any] {
                    userId = "\(user["id"] ?? "")"
                }
                completion(.success(BubaforkAuthResult(accessToken: token, userId: userId)))
            case let .failure(error):
                completion(.failure(error))
            }
        }
    }

    public func getProxyServers(completion: @escaping (Result<[BubaforkServerInfo], Error>) -> Void) {
        httpGet(path: "/proxy/servers") { result in
            switch result {
            case let .success(json):
                var servers: [BubaforkServerInfo] = []

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

    // MARK: - Private

    private func httpGet(path: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: BubaforkConfig.apiURL(path))
        request.httpMethod = "GET"
        if let token = accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        perform(request: request, completion: completion)
    }

    private func httpPost(path: String, body: [String: Any], completion: @escaping (Result<[String: Any], Error>) -> Void) {
        var request = URLRequest(url: BubaforkConfig.apiURL(path))
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
                completion(.failure(BubaforkApiError.noData))
                return
            }
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(BubaforkApiError.noData))
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(BubaforkApiError.httpError(httpResponse.statusCode, body)))
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                completion(.failure(BubaforkApiError.invalidJSON))
                return
            }
            completion(.success(json))
        }.resume()
    }

    private static func parseServer(_ dict: [String: Any]) -> BubaforkServerInfo? {
        guard let host = dict["host"] as? String,
              let secret = dict["secret"] as? String else {
            return nil
        }
        let port = dict["port"] as? Int ?? 443
        return BubaforkServerInfo(host: host, port: port, secret: secret)
    }

    private static func parseFirstServer(_ json: [String: Any]) throws -> BubaforkServerInfo {
        if let regular = json["regular"] as? [[String: Any]], let first = regular.first, let server = parseServer(first) {
            return server
        }
        if let bypass = json["bypass"] as? [[String: Any]], let first = bypass.first, let server = parseServer(first) {
            return server
        }
        if let server = parseServer(json) {
            return server
        }
        throw BubaforkApiError.noServer
    }
}

public enum BubaforkApiError: Error, LocalizedError {
    case noData
    case invalidJSON
    case httpError(Int, String)
    case noAccessToken
    case noServer

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
        }
    }
}
