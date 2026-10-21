import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import MangaGlass

enum ImageFixtures {
    static func cgImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func encode(_ image: CGImage, as type: UTType) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    static func png(width: Int, height: Int) -> Data { encode(cgImage(width: width, height: height), as: .png) }
    static func jpeg(width: Int, height: Int) -> Data { encode(cgImage(width: width, height: height), as: .jpeg) }
}

final class DownloadQualityTests: XCTestCase {
    // MARK: integrity

    func testWholePagesPass() throws {
        XCTAssertEqual(try DownloadIntegrity.verify(data: ImageFixtures.jpeg(width: 800, height: 1200)), .jpeg)
        XCTAssertEqual(try DownloadIntegrity.verify(data: ImageFixtures.png(width: 800, height: 1200)), .png)
    }

    func testTruncatedJPEGIsRejected() {
        let full = ImageFixtures.jpeg(width: 800, height: 1200)
        let cut = full.prefix(full.count * 2 / 3)
        XCTAssertThrowsError(try DownloadIntegrity.verify(data: Data(cut))) { error in
            XCTAssertEqual(error as? DownloadIntegrityError, .truncatedImage)
        }
    }

    func testShortBodyVersusContentLengthIsRejected() {
        let full = ImageFixtures.png(width: 300, height: 300)
        XCTAssertThrowsError(try DownloadIntegrity.verify(data: full, expectedLength: Int64(full.count + 500))) { error in
            XCTAssertEqual(error as? DownloadIntegrityError, .truncatedImage)
        }
    }

    func testPlaceholderPixelIsRejected() {
        XCTAssertThrowsError(try DownloadIntegrity.verify(data: ImageFixtures.png(width: 1, height: 1))) { error in
            XCTAssertEqual(error as? DownloadIntegrityError, .placeholderImage(width: 1, height: 1))
        }
    }

    func testSignatureOnlyPayloadIsRejected() {
        var fake = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        fake.append(Data(repeating: 0, count: 120))
        XCTAssertThrowsError(try DownloadIntegrity.verify(data: fake))
    }

    // MARK: retry policy

    func testBlocksAreNotRetriedAndRateLimitsRetryOnce() {
        XCTAssertEqual(DownloadCoordinator.retryLimit(for: DownloadRequestError.httpStatus(403, retryAfter: nil), default: 3), 1)
        XCTAssertEqual(DownloadCoordinator.retryLimit(for: DownloadRequestError.httpStatus(429, retryAfter: 5), default: 3), 2)
        XCTAssertEqual(DownloadCoordinator.retryLimit(for: DownloadRequestError.httpStatus(500, retryAfter: nil), default: 3), 3)
        XCTAssertEqual(DownloadCoordinator.retryLimit(for: DownloadIntegrityError.nonImagePayload("text/html"), default: 3), 2)
        XCTAssertEqual(DownloadCoordinator.retryLimit(for: URLError(.timedOut), default: 3), 3)
    }

    // MARK: speed display

    func testSpeedFormatting() {
        XCTAssertEqual(DownloadCoordinator.formatByteRate(2.5 * 1_048_576), "2.5 MB/s")
        XCTAssertEqual(DownloadCoordinator.formatByteRate(300 * 1024), "300 KB/s")
        XCTAssertEqual(DownloadCoordinator.formatRemaining(125), "02:05")
        XCTAssertEqual(DownloadCoordinator.formatRemaining(3725), "1:02:05")
    }

    func testSmoothedRateDecaysDuringStall() {
        var rate = DownloadCoordinator.ema(nil, 4, alpha: 0.3)
        XCTAssertEqual(rate, 4)
        rate = DownloadCoordinator.ema(rate, 0, alpha: 0.3)
        XCTAssertEqual(rate, 2.8, accuracy: 0.0001)
    }

    // MARK: CopyManga request diet

    func testThrottleReplyIsRecognized() {
        let reply = #"{"code":210,"message":"Request was throttled. Expected available in 46 seconds."}"#
        XCTAssertEqual(CopyMangaAPI.copyThrottleSeconds(inText: reply), 46)
        XCTAssertEqual(CopyMangaAPI.copyThrottleSeconds(inText: #"{"code":210,"message":"slow down"}"#), 60)
        XCTAssertEqual(CopyMangaAPI.copyThrottleSeconds(inText: #"{"code":200,"message":"请求成功","results":"abc"}"#), nil)
        XCTAssertEqual(CopyMangaAPI.copyThrottleSeconds(inText: "<html>普通页面</html>"), nil)
        XCTAssertEqual(CopyMangaAPI.copyThrottleSeconds(inText: #"{"code":400,"message":"访问过于频繁，请 10 秒后再试"}"#), 30)
    }

    func testNextLinkCrawlOnlyWhenCatalogIsMissing() {
        // The reported case: 11 chapters from the detail API, page shows "1".
        XCTAssertFalse(CopyMangaAPI.shouldCrawlCopyNextLinks(currentCount: 11, expectedChapters: 1, detailProvidedChapters: true))
        XCTAssertTrue(CopyMangaAPI.shouldCrawlCopyNextLinks(currentCount: 0, expectedChapters: 0, detailProvidedChapters: false))
        XCTAssertTrue(CopyMangaAPI.shouldCrawlCopyNextLinks(currentCount: 5, expectedChapters: 30, detailProvidedChapters: false))
        XCTAssertFalse(CopyMangaAPI.shouldCrawlCopyNextLinks(currentCount: 12, expectedChapters: 14, detailProvidedChapters: false))
    }

    func testMirrorWalkIsCapped() {
        XCTAssertEqual(CopyMangaAPI.maxCopyMirrorAttempts, 3)
    }

    // MARK: request budget

    func testBudgetWakesWaiterOnRelease() async throws {
        let budget = HostRequestBudget()
        try await budget.acquire(key: "k", kind: .image, maxConcurrent: 1)
        let waiter = Task { try await budget.acquire(key: "k", kind: .image, maxConcurrent: 1) }
        try await Task.sleep(for: .milliseconds(80))
        let activeWhileWaiting = await budget.activeCount(key: "k")
        XCTAssertEqual(activeWhileWaiting, 1, "second request waits for the slot")
        await budget.release(key: "k", outcome: .success)
        try await waiter.value
        let activeAfter = await budget.activeCount(key: "k")
        XCTAssertEqual(activeAfter, 1)
    }

    func testCancelledWaiterGivesUp() async throws {
        let budget = HostRequestBudget()
        try await budget.acquire(key: "k", kind: .image, maxConcurrent: 1)
        let waiter = Task { try await budget.acquire(key: "k", kind: .image, maxConcurrent: 1) }
        try await Task.sleep(for: .milliseconds(50))
        waiter.cancel()
        await budget.wakeAll()
        do {
            try await waiter.value
            XCTFail("cancelled waiter must not take the slot")
        } catch is CancellationError {}
        let active = await budget.activeCount(key: "k")
        XCTAssertEqual(active, 1)
    }
}
