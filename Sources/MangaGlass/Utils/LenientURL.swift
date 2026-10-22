import Foundation

enum MGURL {
    /// Characters a URL string may carry as-is: RFC 3986 unreserved + reserved, plus `%` so
    /// existing escapes survive.
    private static let allowed: CharacterSet = {
        var set = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        set.insert(charactersIn: "-._~:/?#[]@!$&'()*+,;=%")
        return set
    }()

    /// Builds a URL from text that may mix raw characters (中文, spaces) with ones the site
    /// already percent-encoded. `URL(string:)` on macOS 14+ escapes the *whole* string once it
    /// sees a raw character, turning an existing `%E5` into `%25E5` (a different file → 404).
    /// Here only the raw characters are encoded, so every character ends up encoded exactly once.
    static func lenient(_ string: String, relativeTo base: URL? = nil) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) ?? trimmed
        if let base {
            return URL(string: encoded, relativeTo: base)?.absoluteURL
        }
        return URL(string: encoded)
    }
}
