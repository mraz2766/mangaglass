import AppKit
import XCTest
@testable import MangaGlass

@MainActor
final class WindowCloseBehaviorTests: XCTestCase {
    func testDefaultAndStoredPreferences() {
        let name = "MangaGlassCloseTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(WindowCloseBehavior.load(from: defaults), .ask)
        for behavior in WindowCloseBehavior.allCases {
            defaults.set(behavior.rawValue, forKey: WindowCloseBehavior.storageKey)
            XCTAssertEqual(WindowCloseBehavior.load(from: defaults), behavior)
        }
        defaults.set("unknown-future-value", forKey: WindowCloseBehavior.storageKey)
        XCTAssertEqual(WindowCloseBehavior.load(from: defaults), .ask)
    }

    func testBackgroundPreservesWindowAndQueueAndReopens() async {
        _ = NSApplication.shared
        let vm = MainViewModel(persistsState: false)
        vm.applyFetchedComic(SelectionTests.fixture(), final: true, sourceText: "测试")
        vm.selectAllVisible()
        vm.enqueueSelectedChapters()
        vm.windowCloseBehavior = .background
        let delegate = AppDelegate()
        delegate.viewModel = vm
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
        defer { window.orderOut(nil) }
        XCTAssertFalse(delegate.windowShouldClose(window))
        XCTAssertFalse(window.isVisible)
        XCTAssertNil(vm.terminationConfirmation)
        XCTAssertEqual(vm.downloader.taskItems.count, 34)
        XCTAssertFalse(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        XCTAssertTrue(window.isVisible)
        XCTAssertFalse(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApp))
        // Explicit quit still asks, even when the close preference is background.
        XCTAssertEqual(delegate.applicationShouldTerminate(NSApp), .terminateCancel)
        XCTAssertNotNil(vm.terminationConfirmation)
        vm.cancelTermination()
        XCTAssertNil(vm.terminationConfirmation)
    }

    func testDefaultCloseAsksAndPanelsCloseNormally() async {
        _ = NSApplication.shared
        let vm = MainViewModel(persistsState: false)
        let delegate = AppDelegate()
        delegate.viewModel = vm
        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: false)
        XCTAssertFalse(delegate.windowShouldClose(window))
        XCTAssertNotNil(vm.terminationConfirmation)
        vm.cancelTermination()
        XCTAssertTrue(delegate.windowShouldClose(NSPanel()))
        XCTAssertNil(vm.terminationConfirmation)
    }
}
