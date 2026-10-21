import Foundation

enum MGUserAgent {
    /// A complete desktop Safari identifier. The old truncated "AppleWebKit/537.36" string matched no real
    /// browser, which makes requests easy for sites to single out.
    static let browser = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
}
