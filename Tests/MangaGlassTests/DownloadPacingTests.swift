import XCTest
@testable import MangaGlass

final class DownloadPacingTests: XCTestCase {
    func testModesOrderFromSafeToEfficientForEverySite() {
        for family in SiteFamily.allCases {
            let safe = SitePacing.make(mode: .safe, family: family)
            let smart = SitePacing.make(mode: .smart, family: family)
            let efficient = SitePacing.make(mode: .efficient, family: family)
            let start = { (p: SitePacing) in AdaptivePacingState(pacing: p).chapterConcurrency }
            XCTAssertLessThanOrEqual(start(safe), start(smart), "\(family)")
            XCTAssertLessThanOrEqual(start(smart), start(efficient), "\(family)")
            XCTAssertGreaterThanOrEqual(safe.imageSpacingMS.lowerBound, smart.imageSpacingMS.lowerBound, "\(family)")
            XCTAssertGreaterThanOrEqual(smart.imageSpacingMS.lowerBound, efficient.imageSpacingMS.lowerBound, "\(family)")
            XCTAssertGreaterThan(safe.chapterGapMS.lowerBound, efficient.chapterGapMS.lowerBound, "\(family)")
            XCTAssertLessThan(safe.restEveryChapters, efficient.restEveryChapters, "\(family)")
            XCTAssertEqual(safe.successesToStepUp, 0, "safe never speeds up")
        }
    }

    func testSmartIsGentlerThanTheOldManhuaGuiPace() {
        // Old fixed pace: 4 chapters at once, 240–460ms between images, no rests.
        let smart = SitePacing.make(mode: .smart, family: .manhuaGui)
        XCTAssertLessThan(AdaptivePacingState(pacing: smart).chapterConcurrency, 4)
        XCTAssertGreaterThan(smart.imageSpacingMS.lowerBound, 240)
        XCTAssertGreaterThan(smart.restEveryChapters, 0)
    }

    func testSmartStepsUpOnSuccessAndDropsToFloorOnThrottle() {
        var state = AdaptivePacingState(pacing: .make(mode: .smart, family: .manhuaGui))
        XCTAssertEqual(state.chapterConcurrency, 2)
        for _ in 0..<59 { XCTAssertFalse(state.noteSuccess()) }
        XCTAssertTrue(state.noteSuccess())
        XCTAssertEqual(state.chapterConcurrency, 3)
        for _ in 0..<200 { _ = state.noteSuccess() }
        XCTAssertEqual(state.chapterConcurrency, 3, "capped at the range top")
        XCTAssertTrue(state.noteThrottle())
        XCTAssertEqual(state.chapterConcurrency, 1)
        XCTAssertFalse(state.noteThrottle(), "already at the floor")
    }

    func testCopyGlobalImageConcurrencyAdapts() {
        var state = AdaptivePacingState(pacing: .make(mode: .smart, family: .copy))
        XCTAssertEqual(state.globalImageConcurrency, 5)
        _ = state.noteThrottle()
        XCTAssertEqual(state.globalImageConcurrency, 4)
        XCTAssertEqual(AdaptivePacingState(pacing: .make(mode: .efficient, family: .copy)).globalImageConcurrency, 8)
        XCTAssertEqual(AdaptivePacingState(pacing: .make(mode: .safe, family: .copy)).globalImageConcurrency, 3)
    }

    func testChapterStartsAreSpacedAndRestInserted() {
        var pacing = SitePacing.make(mode: .safe, family: .manhuaGui)
        pacing.restEveryChapters = 3
        var state = AdaptivePacingState(pacing: pacing)
        let now = Date(timeIntervalSince1970: 1_000)
        // Three chapters requested at the same instant start 5s apart (no burst).
        let waits = (0..<3).map { _ in state.reserveChapterSlot(now: now, gap: 5, rest: 100) }
        XCTAssertEqual(waits.map(\.wait), [0, 5, 10])
        XCTAssertEqual(waits.map(\.rested), [false, false, false])
        // The fourth comes after a rest.
        let fourth = state.reserveChapterSlot(now: now, gap: 5, rest: 100)
        XCTAssertTrue(fourth.rested)
        XCTAssertEqual(fourth.wait, 115)
    }

    func testPostponeDelaysNextChapter() {
        var state = AdaptivePacingState(pacing: .make(mode: .smart, family: .manhuaGui))
        let now = Date(timeIntervalSince1970: 0)
        state.postpone(until: now.addingTimeInterval(480))
        XCTAssertEqual(state.reserveChapterSlot(now: now, gap: 3, rest: 60).wait, 480)
    }

    func testConnectionResetsCountAsThrottle() {
        XCTAssertTrue(DownloadCoordinator.isConnectionThrottle(URLError(.secureConnectionFailed)))
        XCTAssertTrue(DownloadCoordinator.isConnectionThrottle(URLError(.networkConnectionLost)))
        XCTAssertTrue(DownloadCoordinator.isConnectionThrottle(CopyMangaError.connectionReset("漫画柜章节取图")))
        XCTAssertFalse(DownloadCoordinator.isConnectionThrottle(URLError(.badURL)))
        XCTAssertFalse(DownloadCoordinator.isConnectionThrottle(CopyMangaError.htmlParse("x")))
    }

    func testSiteFamilies() {
        XCTAssertEqual(SiteFamily.of(.manhuaGui), .manhuaGui)
        XCTAssertEqual(SiteFamily.of(.mangaCopy), .copy)
        XCTAssertEqual(SiteFamily.of(.baoziManga), .other)
    }
}

final class ChapterTitlePartsTests: XCTestCase {
    func testNumbersWithAndWithoutPrefixRenderTheSameWay() {
        for (title, number, unit) in [("第62话", "62", "话"), ("54话", "54", "话"), ("55.5话", "55.5", "话"),
                                      ("第 72.5 話", "72.5", "話"), ("1卷", "1", "卷")] {
            let parts = MGChapterTitleParts(title)
            XCTAssertEqual(parts?.number, number, title)
            XCTAssertEqual(parts?.unit, unit, title)
        }
        XCTAssertNil(MGChapterTitleParts("番外篇"))
    }
}
