import AppKit
import XCTest
@testable import MangaGlass

/// Private AppKit windows that must never be restyled (doing so crashed launch on macOS 27).
final class _NSGlassEffectWindowStandIn: NSWindow {}
final class TUINSWindowStandIn: NSWindow {}

@MainActor
final class WindowConfigurationTests: XCTestCase {
    func testOnlyAppContentWindowsAreStyled() {
        _ = NSApplication.shared
        let rect = NSRect(x: 0, y: 0, width: 200, height: 200)
        let main = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertTrue(AppDelegate.isAppContentWindow(main))

        let privateWindow = _NSGlassEffectWindowStandIn(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertFalse(AppDelegate.isAppContentWindow(privateWindow))

        let panel = NSPanel(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: true)
        XCTAssertFalse(AppDelegate.isAppContentWindow(panel))

        let textInput = TUINSWindowStandIn(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: true)
        XCTAssertFalse(AppDelegate.isAppContentWindow(textInput))
    }

    func testConfiguringPrivateWindowLeavesItUntouched() {
        _ = NSApplication.shared
        let delegate = AppDelegate()
        let window = _NSGlassEffectWindowStandIn(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                                 styleMask: [.borderless], backing: .buffered, defer: true)
        delegate.configureIfNeeded(window)
        XCTAssertEqual(window.styleMask, [.borderless])
        XCTAssertNil(window.delegate)
    }
}
