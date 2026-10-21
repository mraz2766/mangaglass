import XCTest
@testable import MangaGlass

@MainActor
final class RequestBudgetTests: XCTestCase {
    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mg-catalogs-\(UUID().uuidString).json")
    }

    func testCatalogSurvivesRelaunch() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let comic = SelectionTests.fixture(chapterCount: 12, groups: 2)
        let first = ComicInfoCache(fileURL: file)
        await first.set(comic, slug: comic.slug, site: comic.site)

        let relaunched = ComicInfoCache(fileURL: file)
        let restored = await relaunched.get(slug: comic.slug, site: comic.site)
        XCTAssertEqual(restored?.volumes.reduce(0) { $0 + $1.chapters.count }, 12)
    }

    func testCatalogExpiresAfterTwelveHours() async {
        let file = tempFile()
        defer { try? FileManager.default.removeItem(at: file) }
        let comic = SelectionTests.fixture()
        let start = Date()
        await ComicInfoCache(fileURL: file, now: { start }).set(comic, slug: comic.slug, site: comic.site)

        let later = ComicInfoCache(fileURL: file, now: { start.addingTimeInterval(ComicInfoCache.ttl - 60) })
        let stillFresh = await later.get(slug: comic.slug, site: comic.site)
        XCTAssertNotNil(stillFresh)
        let expired = ComicInfoCache(fileURL: file, now: { start.addingTimeInterval(ComicInfoCache.ttl + 60) })
        let gone = await expired.get(slug: comic.slug, site: comic.site)
        XCTAssertNil(gone)
    }

    func testCopyMirrorsShareCatalogEntries() async {
        let comic = SelectionTests.fixture()
        let cache = ComicInfoCache()
        await cache.set(comic, slug: "same-slug", site: CopyMangaMirror.copy2026.siteConfig(preferredHost: "www.2026copy.com"))
        let fromOtherMirror = await cache.get(slug: "same-slug", site: CopyMangaMirror.copy4000.siteConfig(preferredHost: "www.copy4000.com"))
        XCTAssertNotNil(fromOtherMirror)
        let otherSite = await cache.get(slug: "same-slug", site: .manhuaGui)
        XCTAssertNil(otherSite)
    }

    func testClearRemovesCatalogFile() async {
        let file = tempFile()
        let comic = SelectionTests.fixture()
        let cache = ComicInfoCache(fileURL: file)
        await cache.set(comic, slug: comic.slug, site: comic.site)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        await cache.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testOnlyReachabilityFailuresSwitchMirrors() {
        XCTAssertTrue(CopyMangaAPI.isMirrorReachabilityFailure(URLError(.cannotFindHost)))
        XCTAssertTrue(CopyMangaAPI.isMirrorReachabilityFailure(URLError(.timedOut)))
        XCTAssertTrue(CopyMangaAPI.isMirrorReachabilityFailure(CopyMangaError.httpStatus(502, "")))
        // Throttle-shaped failures: the other mirrors are the same site behind the same limit.
        XCTAssertFalse(CopyMangaAPI.isMirrorReachabilityFailure(URLError(.secureConnectionFailed)))
        XCTAssertFalse(CopyMangaAPI.isMirrorReachabilityFailure(URLError(.networkConnectionLost)))
        XCTAssertFalse(CopyMangaAPI.isMirrorReachabilityFailure(CopyMangaError.httpStatus(429, "")))
        XCTAssertFalse(CopyMangaAPI.isMirrorReachabilityFailure(CopyMangaError.parseBlocked("x")))
    }

    func testMissingChapterImagesCountAsCopyThrottle() {
        let outcome = DownloadCoordinator.copyFailureOutcome(CopyMangaError.noImageInChapter("第 1 话"))
        XCTAssertEqual(outcome?.cooldown, 20 * 60)
        XCTAssertEqual(DownloadCoordinator.copySuspiciousFailureThreshold, 2)
    }

    func testSharedCooldownHoldsParsingUntilCleared() async throws {
        let api = CopyMangaAPI()
        await api.noteCopyCooldown(seconds: 600)
        let site = CopyMangaMirror.copy2026.siteConfig(preferredHost: "www.2026copy.com")
        do {
            _ = try await api.fetchComic(slug: "anything", site: site, cookie: nil, preferCache: false)
            XCTFail("parsing should wait out the download cooldown without a request")
        } catch CopyMangaError.cooldown {
        } catch CopyMangaError.copyMirrorsUnavailable(let attempts) {
            XCTAssertTrue(attempts.joined().contains("冷却"), attempts.joined())
        }
    }

    func testRelativeAge() {
        let now = Date()
        XCTAssertEqual(MainViewModel.relativeAge(of: now.addingTimeInterval(-20), now: now), "刚刚")
        XCTAssertEqual(MainViewModel.relativeAge(of: now.addingTimeInterval(-5 * 60), now: now), "5 分钟前")
        XCTAssertEqual(MainViewModel.relativeAge(of: now.addingTimeInterval(-3 * 3600), now: now), "3 小时前")
    }
}
