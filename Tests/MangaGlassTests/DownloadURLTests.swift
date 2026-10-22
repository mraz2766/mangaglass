import XCTest
@testable import MangaGlass

final class DownloadURLTests: XCTestCase {
    /// The 七大罪 番外篇13 case: raw folder name + already-encoded file name.
    func testMixedRawAndEncodedTextIsEncodedOnce() throws {
        let url = try XCTUnwrap(MGURL.lenient(
            "https://cf.hamreus.com/ps1/q/qiyuanzui/番外篇13/IMG_5052%E5%89%AF%E6%9C%AC.jpg.webp?e=1793584165&m=BHvcP9-059lIcjY0nvu6zA"))
        XCTAssertEqual(url.absoluteString,
                       "https://cf.hamreus.com/ps1/q/qiyuanzui/%E7%95%AA%E5%A4%96%E7%AF%8713/IMG_5052%E5%89%AF%E6%9C%AC.jpg.webp?e=1793584165&m=BHvcP9-059lIcjY0nvu6zA")
        XCTAssertFalse(url.absoluteString.contains("%25"))
    }

    func testRawAndAlreadyEncodedTextBothEndUpTheSame() {
        let raw = MGURL.lenient("https://i.hamreus.com/ps1/q/番外篇13/IMG_5052副本.jpg")
        let encoded = MGURL.lenient("https://i.hamreus.com/ps1/q/%E7%95%AA%E5%A4%96%E7%AF%8713/IMG_5052%E5%89%AF%E6%9C%AC.jpg")
        XCTAssertEqual(raw, encoded)
    }

    func testPlainASCIIURLIsUntouched() {
        let text = "https://s2.bzcdn.net/scomic/yaoshenji/0/1-c5pl/1.jpg?token=a%2Fb+c"
        XCTAssertEqual(MGURL.lenient(text)?.absoluteString, text)
    }

    func testSpacesAreEncoded() {
        XCTAssertEqual(MGURL.lenient("https://x.com/a b.jpg")?.absoluteString, "https://x.com/a%20b.jpg")
    }

    func testBaoziChapterLinksMoveToTheWorkingPageHost() {
        let api = CopyMangaAPI()
        let base = CopyMangaAPI.baoziMirrors[0].webBase
        XCTAssertEqual(base.host, "www.twmanga.com")
        let relative = api.baoziChapterURL(chapterUUID: "/user/page_direct?comic_id=abc&section_slot=0&chapter_slot=3", slug: "abc", base: base)
        XCTAssertEqual(relative?.absoluteString, "https://www.twmanga.com/user/page_direct?comic_id=abc&section_slot=0&chapter_slot=3")
        let absolute = api.baoziChapterURL(chapterUUID: "https://www.baozimh.com/comic/chapter/abc/0_3.html", slug: "abc", base: base)
        XCTAssertEqual(absolute?.host, "www.twmanga.com")
        let foreign = api.baoziChapterURL(chapterUUID: "https://example.com/x.html", slug: "abc", base: base)
        XCTAssertEqual(foreign?.host, "example.com")
    }

    func testBaoziBrowserCheckIsRecognised() {
        XCTAssertTrue(CopyMangaAPI.isBaoziBrowserCheck("<title>正在验证浏览器</title><script>window.gatekeeperChallenge</script>"))
        XCTAssertFalse(CopyMangaAPI.isBaoziBrowserCheck("<div class=\"comics-chapters__item\">第1话</div>"))
    }

    func testSanitizedNamesAreVisibleNonEmptyAndShort() {
        XCTAssertEqual(DownloadOutputLayout.sanitize("第 1 话 / 上"), "第 1 话 _ 上")
        XCTAssertEqual(DownloadOutputLayout.sanitize(".5 话"), "5 话", "leading dot would hide the folder")
        XCTAssertEqual(DownloadOutputLayout.sanitize("..."), "未命名")
        XCTAssertEqual(DownloadOutputLayout.sanitize("   "), "未命名")
        XCTAssertLessThanOrEqual(DownloadOutputLayout.sanitize(String(repeating: "长", count: 300)).utf8.count, 200)
    }
}
