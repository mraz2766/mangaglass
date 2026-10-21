import AppKit

/// Cross-fades the app's visible windows across an appearance change: snapshot each window as it
/// looks now, lay the picture on top, apply the change, then fade the picture out.
@MainActor
enum MGWindowCrossfade {
    static func run(duration: TimeInterval = 0.32) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        for window in NSApp.windows where window.isVisible && !(window is NSPanel) && window.sheetParent == nil {
            // The content view spans the whole window (full-size content under a transparent titlebar).
            guard let frameView = window.contentView,
                  let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { continue }
            frameView.cacheDisplay(in: frameView.bounds, to: rep)
            let image = NSImage(size: frameView.bounds.size)
            image.addRepresentation(rep)

            let cover = NSImageView(frame: frameView.bounds)
            cover.image = image
            cover.imageScaling = .scaleNone
            cover.autoresizingMask = [.width, .height]
            cover.wantsLayer = true
            frameView.addSubview(cover, positioned: .above, relativeTo: nil)

            // Let the new appearance render underneath first, then reveal it.
            DispatchQueue.main.async {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    cover.animator().alphaValue = 0
                } completionHandler: {
                    cover.removeFromSuperview()
                }
            }
        }
    }
}
