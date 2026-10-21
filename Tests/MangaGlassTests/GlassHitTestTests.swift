import AppKit
import SwiftUI
import XCTest
@testable import MangaGlass

/// Regression: the 经典 theme's frosted window glass must never swallow clicks.
@MainActor
final class GlassHitTestTests: XCTestCase {
    func testClassicGlassDoesNotCaptureClicks() async throws {
        _ = NSApplication.shared
        let vm = MainViewModel(persistsState: false)
        vm.themeStyle = .classic
        defer { vm.themeStyle = .ink }
        vm.applyFetchedComic(SelectionTests.fixture(chapterCount: 55, groups: 2), final: true, sourceText: "probe")
        vm.collapsedVolumeIDs = []  // groups fold by default; this test clicks a tile
        let size = NSSize(width: 974, height: 740)
        let host = NSHostingView(rootView: ContentView(vm: vm))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(600))

        for (x, y) in [(32.0, 710.0), (122.0, 408.0), (500.0, 300.0)] {
            let hit = host.hitTest(NSPoint(x: x, y: size.height - y))
            XCTAssertFalse(hit is NSVisualEffectView, "glass captured the click at \(x),\(y)")
        }
        // A real click on a tile must change the selection.
        let point = NSPoint(x: 122, y: size.height - 408)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.selectedChapterIDs.count, 1)
    }
}
