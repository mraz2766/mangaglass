import XCTest
@testable import MangaGlass

/// Rate-limited Copy answers the chapters endpoint with HTTP 200 "请求成功" and an empty catalog.
final class CopySoftBlockTests: XCTestCase {
    private let empty = #"{"build": {"path_word": "x", "type": [{"id": 1, "name": "話"}]}, "groups": {"default": {"path_word": "default", "count": 0, "name": "默認", "chapters": []}}}"#
    private let full = #"{"build": {"path_word": "x"}, "groups": {"default": {"path_word": "default", "count": 2, "name": "默認", "chapters": [{"type": 1, "name": "第01話", "id": "a"}, {"type": 1, "name": "第02話", "id": "b"}]}}}"#

    private func envelope(_ results: String) -> String {
        #"{"code":200,"message":"请求成功","results":"#.appending(results).appending("}")
    }

    func testEncryptedEmptyCatalogIsSoftBlock() {
        let text = envelope(#""ENCRYPTED""#)
        XCTAssertTrue(CopyMangaAPI.isEmptyCopyCatalogPayload(text: text) { $0 == "ENCRYPTED" ? self.empty : nil })
    }

    func testCatalogWithChaptersIsNotSoftBlock() {
        XCTAssertFalse(CopyMangaAPI.isEmptyCopyCatalogPayload(text: envelope(#""ENCRYPTED""#)) { _ in self.full })
        XCTAssertFalse(CopyMangaAPI.isEmptyCopyCatalogPayload(text: envelope(full)) { _ in nil })
    }

    func testUndecryptableOrOddPayloadIsNotSoftBlock() {
        // Unknown shapes must fall through to the normal parse path, not be reported as rate limiting.
        XCTAssertFalse(CopyMangaAPI.isEmptyCopyCatalogPayload(text: envelope(#""ENCRYPTED""#)) { _ in nil })
        XCTAssertFalse(CopyMangaAPI.isEmptyCopyCatalogPayload(text: #"{"code":200,"results":{"groups":{}}}"#) { _ in nil })
        XCTAssertFalse(CopyMangaAPI.isEmptyCopyCatalogPayload(text: "<html></html>") { _ in nil })
    }

    func testCooldownCoversEveryCopyMirror() async throws {
        let guardian = AntiBanGuard()
        let blocked = CopyMangaMirror.copy2026.siteConfig(preferredHost: "www.2026copy.com")
        let other = CopyMangaMirror.mangacopy.siteConfig(preferredHost: "www.mangacopy.com")
        await guardian.block(site: blocked, seconds: 600)
        do {
            try await guardian.check(site: other)
            XCTFail("another Copy mirror should share the cooldown")
        } catch CopyMangaError.cooldown(let seconds) {
            XCTAssertGreaterThan(seconds, 500)
            XCTAssertTrue(CopyMangaError.cooldown(seconds).localizedDescription.contains("分钟"))
        }
        try await guardian.check(site: .manhuaGui)
    }
}
