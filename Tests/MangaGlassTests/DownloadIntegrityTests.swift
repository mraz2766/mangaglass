import XCTest
@testable import MangaGlass

final class DownloadIntegrityTests: XCTestCase {
    func testRecognizesSupportedImageSignatures() throws {
        XCTAssertEqual(try DownloadIntegrity.detectFormat(data: payload([0xFF, 0xD8, 0xFF])), .jpeg)
        XCTAssertEqual(try DownloadIntegrity.detectFormat(data: payload([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])), .png)
        XCTAssertEqual(try DownloadIntegrity.detectFormat(data: payload(Array("GIF89a".utf8))), .gif)
        XCTAssertEqual(try DownloadIntegrity.detectFormat(data: payload(Array("RIFF0000WEBP".utf8))), .webp)
        XCTAssertEqual(try DownloadIntegrity.detectFormat(data: payload([0, 0, 0, 24] + Array("ftypavif".utf8))), .avif)
    }

    func testRejectsHTMLJSONAndTruncatedPayloads() throws {
        XCTAssertThrowsError(try DownloadIntegrity.detectFormat(
            data: payload(Array("<html>challenge".utf8)),
            mimeType: "text/html"
        ))
        XCTAssertThrowsError(try DownloadIntegrity.detectFormat(
            data: payload(Array("{\"error\":true}".utf8)),
            mimeType: "application/json"
        ))
        XCTAssertThrowsError(try DownloadIntegrity.detectFormat(data: Data([0xFF, 0xD8, 0xFF])))
    }

    func testExistingPageKeepsValidContentAndRemovesCorruptFile() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let corrupt = folder.appendingPathComponent("page-0001.jpg")
        try Data("<html>blocked</html>".utf8).write(to: corrupt)

        XCTAssertNil(DownloadIntegrity.existingPage(in: folder, baseName: "page-0001", index: 1))
        XCTAssertFalse(FileManager.default.fileExists(atPath: corrupt.path))

        let legacyExtension = folder.appendingPathComponent("page-0001.jpg")
        try ImageFixtures.png(width: 200, height: 300).write(to: legacyExtension)
        let page = try XCTUnwrap(DownloadIntegrity.existingPage(in: folder, baseName: "page-0001", index: 1))
        XCTAssertEqual(page.format, .png)
        XCTAssertEqual(page.fileName, "page-0001.jpg")
    }

    func testManifestRoundTripRecordsCompleteness() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let pages = [
            VerifiedDownloadPage(index: 2, fileName: "002.png", byteCount: 64, format: .png),
            VerifiedDownloadPage(index: 1, fileName: "001.jpg", byteCount: 80, format: .jpeg)
        ]

        let imageURLs = [URL(string: "https://img.example.com/1.jpg")!, URL(string: "https://img.example.com/2.jpg")!]
        try DownloadIntegrity.writeManifest(
            chapterID: "chapter",
            expectedPages: 2,
            imageURLs: imageURLs,
            pages: pages,
            complete: true,
            to: folder
        )
        let manifest = try XCTUnwrap(DownloadIntegrity.loadManifest(from: folder))
        XCTAssertTrue(manifest.isComplete)
        XCTAssertEqual(manifest.pages.map(\.index), [1, 2])
        XCTAssertEqual(manifest.imageURLs, imageURLs)

        try DownloadIntegrity.writeManifest(chapterID: "chapter", expectedPages: 3, pages: pages, complete: true, to: folder)
        XCTAssertFalse(try XCTUnwrap(DownloadIntegrity.loadManifest(from: folder)).isComplete)
    }

    func testHostBudgetLimitsConcurrentRequests() async throws {
        let budget = HostRequestBudget()
        try await budget.acquire(key: "copy", kind: .image, maxConcurrent: 1)
        let second = Task {
            try await budget.acquire(key: "copy", kind: .image, maxConcurrent: 1)
            await budget.release(key: "copy", outcome: .success)
        }
        try await Task.sleep(for: .milliseconds(60))
        let activeWhileBlocked = await budget.activeCount(key: "copy")
        XCTAssertEqual(activeWhileBlocked, 1)
        await budget.release(key: "copy", outcome: .success)
        try await second.value
        let activeAfterRelease = await budget.activeCount(key: "copy")
        XCTAssertEqual(activeAfterRelease, 0)
    }

    private func payload(_ prefix: [UInt8]) -> Data {
        Data(prefix + Array(repeating: 0x41, count: max(0, 64 - prefix.count)))
    }

    private func temporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaGlassIntegrityTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
