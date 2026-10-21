import AppKit
import SwiftUI
import XCTest
@testable import MangaGlass

/// Regression: starting with unfinished downloads must not attach a sheet to the window
/// (on macOS 27 it could end up invisible and block every click).
@MainActor
final class RestoredQueuePromptTests: XCTestCase {
    func testRestorePromptIsInlineAndWindowStaysClickable() async throws {
        _ = NSApplication.shared
        let vm = MainViewModel(persistsState: false)
        vm.applyFetchedComic(SelectionTests.fixture(chapterCount: 55, groups: 2), final: true, sourceText: "test")
        vm.shouldOfferRestoredQueuePrompt = true
        let size = NSSize(width: 974, height: 740)
        let host = NSHostingView(rootView: ContentView(vm: vm))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(1200))

        XCTAssertNil(window.attachedSheet, "the restore prompt must not be a sheet")
        XCTAssertFalse(NSApp.windows.contains { $0 is NSPanel && $0.isVisible && $0.sheetParent == window })

        let point = NSPoint(x: 122, y: size.height - 408)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(vm.selectedChapterIDs.count, 1, "clicks reach the page while the banner is shown")
        XCTAssertTrue(vm.shouldOfferRestoredQueuePrompt, "banner stays until the user picks an option")
    }
}
