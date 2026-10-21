import AppKit
import SwiftUI
import XCTest
@testable import MangaGlass

/// Regression: the banner's fill-scaled, enlarged cover overflowed its clip and swallowed clicks
/// on the sidebar next to it (only with a real cover loaded, so earlier probes never saw it).
@MainActor
final class BannerHitTestTests: XCTestCase {
    func testBannerBackdropDoesNotCoverNeighbouringButton() async throws {
        _ = NSApplication.shared
        let coverURL = FileManager.default.temporaryDirectory.appendingPathComponent("mg-banner-cover-\(UUID().uuidString).png")
        try Self.portraitPNG().write(to: coverURL)
        defer { try? FileManager.default.removeItem(at: coverURL) }

        final class Counter { var taps = 0 }
        let counter = Counter()
        let size = NSSize(width: 760, height: 400)
        let root = HStack(spacing: 0) {
            Button { counter.taps += 1 } label: {
                Color.gray.opacity(0.2).frame(width: 72, height: 400)
            }
            .buttonStyle(.plain)
            MGHeroBanner(coverURL: coverURL) { Text("Banner") }
                .padding(16)
        }
        .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(800))

        // Inside the sidebar column, level with the banner (where the enlarged cover used to overflow).
        let point = NSPoint(x: 50, y: size.height - 200)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(counter.taps, 1)
    }

    private static func portraitPNG() throws -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 138, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 100, height: 138).fill()
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
