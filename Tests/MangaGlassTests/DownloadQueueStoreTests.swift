import XCTest
@testable import MangaGlass

@MainActor
final class DownloadQueueStoreTests: XCTestCase {
    func testCompactSnapshotRoundTripsWithoutRepeatingComic() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassQueueStoreTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("queue.json")
        let store = DownloadQueueStore(fileURL: fileURL)
        let comic = SelectionTests.fixture(chapterCount: 80, groups: 2)
        let chapters = comic.volumes.flatMap(\.chapters)
        let tasks = chapters.map {
            DownloadTaskItem(
                comic: comic,
                chapter: $0,
                state: $0.id == "0" ? .running : .queued,
                destination: URL(fileURLWithPath: "/tmp/MangaGlass", isDirectory: true),
                cookie: "test-cookie",
                existingFilePolicy: $0.id == "0" ? .overwrite : .keepExisting,
                usesGroupFolder: true,
                resolvedImageURLs: [URL(string: "https://img.example.com/\($0.id).jpg")!],
                copyImageQuality: .standard
            )
        }

        XCTAssertTrue(store.saveSynchronously(tasks))
        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.count, tasks.count)
        XCTAssertEqual(restored.map(\.queueIdentity), tasks.map(\.queueIdentity))
        XCTAssertEqual(restored.first?.state, .running)
        XCTAssertEqual(restored.first?.cookie, "test-cookie")
        XCTAssertEqual(restored.first?.existingFilePolicy, .overwrite)
        XCTAssertEqual(restored.first?.usesGroupFolder, true)
        XCTAssertNil(restored.first?.resolvedImageURLs)
        XCTAssertEqual(restored.first?.copyImageQuality, .standard)

        let coordinator = DownloadCoordinator(api: CopyMangaAPI())
        coordinator.restoreQueue(restored)
        XCTAssertEqual(coordinator.taskItems.first?.state, .queued)

        let compactSize = try Data(contentsOf: fileURL).count
        let legacySize = try JSONEncoder().encode(tasks).count
        XCTAssertLessThan(compactSize, legacySize / 4)
    }

    func testCorruptLatestSnapshotFallsBackToLastGoodBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassQueueBackupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("queue.json")
        let store = DownloadQueueStore(fileURL: fileURL)
        let comic = SelectionTests.fixture(chapterCount: 2, groups: 1)
        let chapter = try XCTUnwrap(comic.volumes.first?.chapters.first)
        let queued = DownloadTaskItem(
            comic: comic,
            chapter: chapter,
            state: .queued,
            destination: directory,
            cookie: nil
        )
        var completed = queued
        completed.state = .done

        XCTAssertTrue(store.saveSynchronously([queued]))
        XCTAssertTrue(store.saveSynchronously([completed]))
        try Data("incomplete".utf8).write(to: fileURL, options: .atomic)

        let restored = try XCTUnwrap(store.load())
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored.first?.state, .queued)
    }
}
