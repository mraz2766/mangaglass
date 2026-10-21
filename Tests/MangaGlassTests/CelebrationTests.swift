import AppKit
import SwiftUI
import XCTest
@testable import MangaGlass

@MainActor
final class CelebrationTests: XCTestCase {
    func testBurstPiecesStayInsideTheWindowWidth() {
        let burst = MGConfettiBurst(count: 200)
        XCTAssertEqual(burst.pieces.count, 200)
        XCTAssertTrue(burst.pieces.allSatisfy { (0.05...0.95).contains($0.x) && $0.delay <= 0.5 })
    }

    /// Renders one mid-flight frame so the drawing can be eyeballed (MANGAGLASS_SNAPSHOT_DIR).
    func testRenderConfettiFrame() throws {
        guard let dir = ProcessInfo.processInfo.environment["MANGAGLASS_SNAPSHOT_DIR"] else {
            throw XCTSkip("snapshot only")
        }
        _ = NSApplication.shared
        let view = MGConfettiView(burst: MGConfettiBurst(start: Date().addingTimeInterval(-0.9)))
            .frame(width: 760, height: 520)
            .background(Color.white)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 760, height: 520)
        host.layoutSubtreeIfNeeded()
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("confetti.png"))
    }
}
