import AppKit
import SwiftUI

struct WindowAccessor: NSViewRepresentable {
    final class Coordinator {
        var configuredWindowNumber: Int?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                configure(window, coordinator: context.coordinator)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                configure(window, coordinator: context.coordinator)
            }
        }
    }

    private func configure(_ window: NSWindow, coordinator: Coordinator) {
        if coordinator.configuredWindowNumber == window.windowNumber {
            return
        }
        coordinator.configuredWindowNumber = window.windowNumber

        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .automatic
        window.collectionBehavior.remove(.fullScreenNone)
        window.minSize = NSSize(width: 980, height: 720)
    }
}
