import XCTest
@testable import MangaGlass

@MainActor
final class DownloadConflictTests: XCTestCase {
    func testExistingOutputInspectionMatchesDownloadLayout() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassConflictTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let comic = SelectionTests.fixture(chapterCount: 2, groups: 1)
        let chapter = try XCTUnwrap(comic.volumes.first?.chapters.first)
        let chapterFolder = DownloadOutputLayout.chapterFolder(
            comic: comic,
            chapter: chapter,
            destination: root,
            usesGroupFolder: false
        )
        try FileManager.default.createDirectory(at: chapterFolder, withIntermediateDirectories: true)
        try Data("page-1".utf8).write(to: chapterFolder.appendingPathComponent("0001.jpg"))
        try Data("page-2".utf8).write(to: chapterFolder.appendingPathComponent("0002.jpg"))

        let vm = MainViewModel(persistsState: false)
        vm.destinationFolder = root
        vm.applyFetchedComic(comic, final: true, sourceText: "测试")
        vm.selectedChapterIDs = [chapter.id]
        let preparation = await vm.prepareSelectedDownload()
        let prepared = try XCTUnwrap(preparation)

        XCTAssertEqual(prepared.existingOutput, ExistingOutputSummary(chapterCount: 1, fileCount: 2))
        XCTAssertFalse(prepared.usesGroupFolder)
    }

    func testRemovingChapterFolderDoesNotTouchSiblingChapter() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassOverwriteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("第01话", isDirectory: true)
        let sibling = root.appendingPathComponent("第02话", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("0001.jpg"))
        try Data("keep".utf8).write(to: sibling.appendingPathComponent("0001.jpg"))

        try DownloadOutputLayout.removeChapterFolder(at: target)

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
    }

    func testReplacingFailedTaskCreatesRealQueuedReplacement() throws {
        let comic = SelectionTests.fixture(chapterCount: 2, groups: 1)
        let chapter = try XCTUnwrap(comic.volumes.first?.chapters.first)
        let destination = URL(fileURLWithPath: "/tmp/MangaGlassRetry", isDirectory: true)
        let failed = DownloadTaskItem(
            comic: comic,
            chapter: chapter,
            state: .failed("HTTP 404"),
            destination: destination,
            cookie: nil
        )
        let coordinator = DownloadCoordinator(api: CopyMangaAPI())
        coordinator.restoreQueue([failed])

        let added = coordinator.add(
            chapters: [chapter],
            comic: comic,
            destination: destination,
            cookie: nil,
            replacingFinished: true
        )

        XCTAssertEqual(added, 1)
        XCTAssertEqual(coordinator.taskItems.count, 1)
        XCTAssertEqual(coordinator.taskItems.first?.state, .queued)
        XCTAssertNotEqual(coordinator.taskItems.first?.id, failed.id)
    }

    func testReplacingFinishedNeverReplacesActiveDuplicate() throws {
        let comic = SelectionTests.fixture(chapterCount: 2, groups: 1)
        let chapter = try XCTUnwrap(comic.volumes.first?.chapters.first)
        let destination = URL(fileURLWithPath: "/tmp/MangaGlassActive", isDirectory: true)
        let active = DownloadTaskItem(
            comic: comic,
            chapter: chapter,
            state: .running,
            destination: destination,
            cookie: nil
        )
        let coordinator = DownloadCoordinator(api: CopyMangaAPI())
        coordinator.restoreQueue([active])

        let added = coordinator.add(
            chapters: [chapter],
            comic: comic,
            destination: destination,
            cookie: nil,
            replacingFinished: true
        )

        XCTAssertEqual(added, 0)
        XCTAssertEqual(coordinator.taskItems.count, 1)
        XCTAssertEqual(coordinator.taskItems.first?.id, active.id)
    }

    func testCopyChapterFailureClassificationProtectsAgainstRateLimitAndHTML404() throws {
        let rateLimit = try XCTUnwrap(
            DownloadCoordinator.copyFailureOutcome(CopyMangaError.httpStatus(429, "too many requests"))
        )
        XCTAssertTrue(rateLimit.immediate)
        XCTAssertEqual(rateLimit.cooldown, 20 * 60)

        let html404 = try XCTUnwrap(
            DownloadCoordinator.copyFailureOutcome(CopyMangaError.httpStatus(404, "<!DOCTYPE html><html></html>"))
        )
        XCTAssertFalse(html404.immediate)
        XCTAssertEqual(html404.cooldown, 5 * 60)

        XCTAssertNil(DownloadCoordinator.copyFailureOutcome(CopyMangaError.invalidURL))
    }
}
