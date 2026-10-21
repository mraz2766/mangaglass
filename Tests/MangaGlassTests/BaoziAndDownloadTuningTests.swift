import XCTest
@testable import MangaGlass

final class BaoziAndDownloadTuningTests: XCTestCase {
    func testBaoziLiveParsingWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["MANGAGLASS_LIVE_BAOZI"] == "1" else {
            throw XCTSkip("Set MANGAGLASS_LIVE_BAOZI=1 to verify the current Baozi pages.")
        }
        let api = CopyMangaAPI()
        let comic = try await api.fetchComic(
            slug: "yaoshenji-taxuedongman",
            site: .baoziManga,
            cookie: nil,
            preferCache: false
        )
        XCTAssertGreaterThan(comic.volumes.flatMap(\.chapters).count, 500)
        let chapter = try XCTUnwrap(comic.volumes.first?.chapters.last)
        let images = try await api.fetchImageURLs(
            slug: comic.slug,
            chapterUUID: chapter.uuid,
            chapterName: chapter.displayName,
            site: comic.site,
            preferredPrefix: comic.apiPathPrefix,
            preferredBaseURL: comic.apiBaseURL,
            cookie: nil
        )
        XCTAssertGreaterThan(images.count, 3)
    }

    func testBaoziTargetAndCatalogParsing() throws {
        let api = CopyMangaAPI()
        let target = try api.resolveTarget(from: "https://www.baozimh.com/comic/test-comic")
        XCTAssertEqual(target.slug, "test-comic")
        XCTAssertEqual(target.site, .baoziManga)

        let html = """
        <meta name="og:novel:book_name" content="测试&amp;漫画">
        <meta name="og:image" content="https://static-tw.baozimh.com/cover/test-comic.jpg?w=285&amp;h=375">
        <a href="/user/page_direct?comic_id=test-comic&amp;section_slot=0&amp;chapter_slot=2"><span>第 3 話</span></a>
        <a href="/user/page_direct?comic_id=test-comic&amp;section_slot=0&amp;chapter_slot=0"><span>第 1 話</span></a>
        <a href="/user/page_direct?comic_id=test-comic&amp;section_slot=0&amp;chapter_slot=0"><span>重复入口</span></a>
        <a href="/user/page_direct?comic_id=test-comic&amp;section_slot=1&amp;chapter_slot=1"><span>番外 2</span></a>
        """
        let comic = try api.parseBaoziComicHTML(html, slug: "test-comic")
        XCTAssertEqual(comic.name, "测试&漫画")
        XCTAssertEqual(comic.coverURL?.host, "static-tw.baozimh.com")
        XCTAssertEqual(comic.volumes.count, 2)
        XCTAssertEqual(comic.volumes[0].chapters.map(\.displayName), ["第 1 話", "第 3 話"])
        XCTAssertEqual(comic.volumes[0].chapters.first?.uuid, "/user/page_direct?comic_id=test-comic&section_slot=0&chapter_slot=0")
    }

    func testBaoziImageParsingUsesReaderImagesAndDeduplicates() {
        let html = """
        <amp-img src="https://s1.bzcdn.net/comic/1.jpg" data-src="https://s1.bzcdn.net/comic/1-hd.jpg" class="comic-contain__item"></amp-img>
        <amp-img class="comic-contain__item" src="https://s1.bzcdn.net/comic/2.jpg"></amp-img>
        <img class="advertisement" src="https://ads.example.com/ad.jpg">
        <amp-img class="comic-contain__item" src="https://s1.bzcdn.net/comic/2.jpg"></amp-img>
        """
        let urls = CopyMangaAPI().parseBaoziImageURLs(html)
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://s1.bzcdn.net/comic/1-hd.jpg",
            "https://s1.bzcdn.net/comic/2.jpg"
        ])
    }

    func testBaoziImageCandidatesKeepOriginalAndAddReachableHosts() throws {
        let original = try XCTUnwrap(URL(string: "https://s1.bzcdn.net/scomic/test/0/1.jpg"))
        XCTAssertEqual(
            DownloadCoordinator.baoziImageCandidates(for: original).map(\.absoluteString),
            [
                original.absoluteString,
                "https://static-tw.baozimh.com/scomic/test/0/1.jpg",
                "https://s1.baozimh.com/scomic/test/0/1.jpg"
            ]
        )
        XCTAssertTrue(DownloadCoordinator.shouldTryNextBaoziImageHost(after: URLError(.secureConnectionFailed)))
        XCTAssertFalse(DownloadCoordinator.shouldTryNextBaoziImageHost(after: URLError(.cancelled)))
    }

    func testCopyHighResolutionCandidatesKeepStandardFallback() throws {
        let standard = try XCTUnwrap(URL(string: "https://img.example.com/path/c800x.webp"))
        XCTAssertEqual(
            DownloadCoordinator.copyResolutionCandidates(for: standard, quality: .high).map(\.absoluteString),
            ["https://img.example.com/path/c1500x.webp", standard.absoluteString]
        )
        XCTAssertEqual(
            DownloadCoordinator.copyResolutionCandidates(for: standard, quality: .standard),
            [standard]
        )
        let original = try XCTUnwrap(URL(string: "https://img.example.com/path/original.jpg"))
        XCTAssertEqual(DownloadCoordinator.copyResolutionCandidates(for: original, quality: .high), [original])
    }

    func testStagingFolderPublishesOnlyCompleteManifest() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassStagingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let final = root.appendingPathComponent("第 1 话", isDirectory: true)
        try FileManager.default.createDirectory(at: final, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: final.appendingPathComponent("legacy.jpg"))
        let staging = try DownloadOutputLayout.prepareStagingFolder(for: final, overwrite: false)
        XCTAssertEqual(staging.lastPathComponent, ".下载中-第 1 话")
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.appendingPathComponent("legacy.jpg").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.appendingPathComponent("legacy.jpg").path))

        XCTAssertThrowsError(try DownloadOutputLayout.publishStagingFolder(staging, as: final))
        XCTAssertTrue(FileManager.default.fileExists(atPath: staging.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))

        let page = VerifiedDownloadPage(index: 1, fileName: "001.jpg", byteCount: 64, format: .jpeg)
        try DownloadIntegrity.writeManifest(
            chapterID: "chapter",
            expectedPages: 1,
            pages: [page],
            complete: true,
            to: staging
        )
        try DownloadOutputLayout.publishStagingFolder(staging, as: final)
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.appendingPathComponent("legacy.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))
    }

    func testOverwriteKeepsPublishedChapterUntilReplacementIsComplete() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassOverwriteStagingTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let final = root.appendingPathComponent("第 2 话", isDirectory: true)
        try FileManager.default.createDirectory(at: final, withIntermediateDirectories: true)
        try Data("published".utf8).write(to: final.appendingPathComponent("old.jpg"))

        let staging = try DownloadOutputLayout.prepareStagingFolder(for: final, overwrite: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.appendingPathComponent("old.jpg").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.appendingPathComponent("old.jpg").path))
    }
}

@MainActor
final class DownloadTuningViewModelTests: XCTestCase {
    func testPacingDefaultsToSmartAndReachesTheCoordinator() {
        let vm = MainViewModel(persistsState: false)
        XCTAssertEqual(vm.downloadPacingMode, .smart)
        XCTAssertEqual(vm.copyImageQuality, .high)
        XCTAssertEqual(vm.downloader.pacingMode, .smart)
        vm.downloadPacingMode = .safe
        XCTAssertEqual(vm.downloader.pacingMode, .safe)
        XCTAssertEqual(vm.downloader.pacingState(for: .manhuaGui).chapterConcurrency, 1)
    }
}
