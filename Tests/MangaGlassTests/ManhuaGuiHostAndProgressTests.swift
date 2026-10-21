import XCTest
@testable import MangaGlass

final class ManhuaGuiHostAndProgressTests: XCTestCase {
    private let signed = URL(string: "https://i.hamreus.com/ps3/q/qdz/13/001.jpg.webp?e=1700000000&m=abc")!

    func testCandidatesIncludeReachableMirrorAndKeepSignature() {
        let urls = DownloadCoordinator.manhuaGuiImageCandidates(for: signed, preferredHost: nil)
        XCTAssertEqual(urls.first?.host, "i.hamreus.com", "payload host is tried first when nothing has worked yet")
        XCTAssertEqual(urls.dropFirst().first?.host, "cf.hamreus.com", "cf is the first fallback")
        XCTAssertTrue(urls.allSatisfy { $0.query == signed.query && $0.path == signed.path })
        XCTAssertEqual(Set(urls.map(\.absoluteString)).count, urls.count)
    }

    func testPreferredHostGoesFirst() {
        let urls = DownloadCoordinator.manhuaGuiImageCandidates(for: signed, preferredHost: "cf.hamreus.com")
        XCTAssertEqual(urls.map { $0.host! }.prefix(2), ["cf.hamreus.com", "i.hamreus.com"])
    }

    func testNonHamreusImagesAreLeftAlone() {
        let other = URL(string: "https://example.com/a.jpg")!
        XCTAssertEqual(DownloadCoordinator.manhuaGuiImageCandidates(for: other, preferredHost: "cf.hamreus.com"), [other])
    }

    /// The reported case: 63 done, 1 failed, 3 running (unresolved), 5 queued must not read 100%.
    func testProgressWithFailuresAndPendingChaptersIsNotComplete() {
        var states: [(state: DownloadTaskItem.State, resolved: Bool, completedPages: Int, expectedPages: Int)] =
            Array(repeating: (.done, true, 40, 40), count: 63)
        states.append((.failed("TLS"), false, 0, 1))
        states += Array(repeating: (.running, false, 0, 1), count: 3)
        states += Array(repeating: (.queued, false, 0, 1), count: 5)
        let progress = DownloadCoordinator.chapterWeightedProgress(states: states)
        XCTAssertEqual(progress, (63 + 3 * 0.03) / 72, accuracy: 0.0001)
        XCTAssertLessThan(progress, 0.9)
    }

    func testProgressDoesNotJumpWhenPageCountResolves() {
        let before = DownloadCoordinator.chapterWeightedProgress(states: [
            (.done, true, 30, 30), (.running, false, 0, 1), (.queued, false, 0, 1), (.queued, false, 0, 1)
        ])
        let after = DownloadCoordinator.chapterWeightedProgress(states: [
            (.done, true, 30, 30), (.running, true, 0, 30), (.queued, false, 0, 1), (.queued, false, 0, 1)
        ])
        XCTAssertEqual(before, after, accuracy: 0.0001)
        XCTAssertEqual(before, 0.2575, accuracy: 0.0001)
    }

    func testCanceledChaptersLeaveTheDenominator() {
        let progress = DownloadCoordinator.chapterWeightedProgress(states: [
            (.done, true, 10, 10), (.canceled, false, 0, 1)
        ])
        XCTAssertEqual(progress, 1)
    }
}
