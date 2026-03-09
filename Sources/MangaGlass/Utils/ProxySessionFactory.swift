import CFNetwork
import Foundation

enum ProxySessionFactory {
    static func makeSession(proxy: ProxySettings?, timeoutRequest: TimeInterval, timeoutResource: TimeInterval, maxConnections: Int) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeoutRequest
        config.timeoutIntervalForResource = timeoutResource
        config.httpMaximumConnectionsPerHost = maxConnections

        if let proxy {
            config.connectionProxyDictionary = proxyDictionary(proxy)
        }

        return URLSession(configuration: config)
    }

    private static func proxyDictionary(_ proxy: ProxySettings) -> [AnyHashable: Any] {
        var dict: [AnyHashable: Any] = [:]

        switch proxy.type {
        case .none:
            break
        case .http:
            dict[kCFNetworkProxiesHTTPEnable as String] = 1
            dict[kCFNetworkProxiesHTTPProxy as String] = proxy.host
            dict[kCFNetworkProxiesHTTPPort as String] = proxy.port
            dict[kCFNetworkProxiesHTTPSEnable as String] = 1
            dict[kCFNetworkProxiesHTTPSProxy as String] = proxy.host
            dict[kCFNetworkProxiesHTTPSPort as String] = proxy.port
        case .socks5:
            dict[kCFNetworkProxiesSOCKSEnable as String] = 1
            dict[kCFNetworkProxiesSOCKSProxy as String] = proxy.host
            dict[kCFNetworkProxiesSOCKSPort as String] = proxy.port
        }

        if let username = proxy.username, !username.isEmpty {
            dict[kCFProxyUsernameKey as String] = username
        }
        if let password = proxy.password, !password.isEmpty {
            dict[kCFProxyPasswordKey as String] = password
        }

        return dict
    }
}
