import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observer: NSObjectProtocol?
    private var configuredWindowNumbers: Set<Int> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            for window in NSApp.windows {
                self.configureIfNeeded(window)
            }
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeMainNotification,
            object: nil,
            queue: .main
        ) { note in
            guard let window = note.object as? NSWindow else { return }
            Task { @MainActor in
                self.configureIfNeeded(window)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func configureIfNeeded(_ window: NSWindow) {
        if configuredWindowNumbers.contains(window.windowNumber) {
            return
        }
        configuredWindowNumbers.insert(window.windowNumber)

        window.styleMask.insert(.titled)
        window.styleMask.insert(.closable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .automatic
        window.minSize = NSSize(width: 980, height: 720)
    }
}
