import Foundation

enum ProxyType: String, CaseIterable, Identifiable {
    case none
    case http
    case socks5

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "不使用"
        case .http:
            return "HTTP"
        case .socks5:
            return "SOCKS5"
        }
    }
}

struct ProxySettings {
    let type: ProxyType
    let host: String
    let port: Int
    let username: String?
    let password: String?
}

enum ProxyValidationError: LocalizedError {
    case missingHost
    case invalidPort

    var errorDescription: String? {
        switch self {
        case .missingHost:
            return "代理已启用，但未填写主机地址。"
        case .invalidPort:
            return "代理端口无效，请填写 1~65535。"
        }
    }
}
