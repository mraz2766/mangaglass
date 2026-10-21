import CommonCrypto
import XCTest
@testable import MangaGlass

/// Serves a fake Copy site and records every request, so the parse path's request count is pinned.
final class StubCopySite: URLProtocol {
    nonisolated(unsafe) static var chaptersPayload = ""
    nonisolated(unsafe) static var requests: [URL] = []
    static let key = "0123456789abcdef"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.append(url)
        let body: String
        if url.path.contains("/comicdetail/") {
            body = Self.chaptersPayload
        } else {
            body = """
            <html><head><meta property="og:title" content="测试"></head><body>
            <h6 title="测试漫画">测试漫画</h6>
            <script>var ccz = '\(Self.key)';</script>
            </body></html>
            """
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// `{"results": iv + hex(AES-CBC(json))}`, the format Copy's chapters endpoint uses.
    static func encryptedEnvelope(_ json: String) -> String {
        let iv = "abcdefghijklmnop"
        let plain = Data(json.utf8)
        var out = Data(count: plain.count + kCCBlockSizeAES128)
        var written = 0
        let outCount = out.count
        _ = out.withUnsafeMutableBytes { outPtr in
            plain.withUnsafeBytes { inPtr in
                CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                        key, kCCKeySizeAES128, iv, inPtr.baseAddress, plain.count,
                        outPtr.baseAddress, outCount, &written)
            }
        }
        let hex = out.prefix(written).map { String(format: "%02x", $0) }.joined()
        return #"{"code":200,"message":"请求成功","results":"\#(iv)\#(hex)"}"#
    }
}

@MainActor
final class CopyParseRequestCountTests: XCTestCase {
    private func makeAPI() -> CopyMangaAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubCopySite.self]
        StubCopySite.requests = []
        return CopyMangaAPI(session: URLSession(configuration: config))
    }

    private func catalog(_ count: Int) -> String {
        let chapters = (1...max(count, 1)).prefix(count).map { #"{"type": 1, "name": "第\#($0)話", "id": "c\#($0)"}"# }
        return #"{"build": {"path_word": "t", "type": [{"id": 1, "name": "話"}]}, "groups": {"default": {"path_word": "default", "count": \#(count), "name": "默認", "chapters": [\#(chapters.joined(separator: ","))]}}}"#
    }

    func testNormalParseUsesTwoRequests() async throws {
        let api = makeAPI()
        StubCopySite.chaptersPayload = StubCopySite.encryptedEnvelope(catalog(43))
        let site = CopyMangaMirror.copy2026.siteConfig(preferredHost: "www.2026copy.com")
        let comic = try await api.fetchComic(slug: "t", site: site, cookie: nil, preferCache: false)
        XCTAssertEqual(comic.volumes.reduce(0) { $0 + $1.chapters.count }, 43)
        XCTAssertEqual(StubCopySite.requests.count, 2, StubCopySite.requests.map(\.absoluteString).joined(separator: "\n"))
    }

    func testRateLimitedParseStopsWithoutRotatingMirrors() async throws {
        let api = makeAPI()
        StubCopySite.chaptersPayload = StubCopySite.encryptedEnvelope(catalog(0))
        let site = CopyMangaMirror.copy2026.siteConfig(preferredHost: "www.2026copy.com")
        do {
            _ = try await api.fetchComic(slug: "t", site: site, cookie: nil, preferCache: false)
            XCTFail("an empty catalog is rate limiting")
        } catch CopyMangaError.parseBlocked {
        }
        XCTAssertEqual(StubCopySite.requests.count, 2)
        XCTAssertEqual(Set(StubCopySite.requests.compactMap(\.host)).count, 1, "no other mirror is tried")
    }
}
