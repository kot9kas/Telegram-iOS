import Foundation

public enum BubaforkConfig {
    public static let apiBaseURL = "https://test.enderfall.net"
    public static let apiVersion = "v1"
    public static let platform = "ios"
    public static let connectionTimeout: TimeInterval = 10

    public static func apiURL(_ path: String) -> URL {
        URL(string: "\(apiBaseURL)/api/\(apiVersion)\(path)")!
    }
}
