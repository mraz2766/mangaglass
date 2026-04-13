import Foundation

enum ProxySessionFactory {
    static func makeSession(timeoutRequest: TimeInterval, timeoutResource: TimeInterval, maxConnections: Int) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutRequest
        config.timeoutIntervalForResource = timeoutResource
        config.httpMaximumConnectionsPerHost = maxConnections
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always

        return URLSession(configuration: config)
    }
}
