import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var viewModel: MainViewModel?

    private var observer: NSObjectProtocol?
    private var configuredWindowNumbers: Set<Int> = []
    private var didConfirmTermination = false
    private weak var mainWindow: NSWindow?

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
        _ = viewModel?.checkpointDownloadQueue()
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestTerminationConfirmation() ? .terminateNow : .terminateCancel
    }

    func configureIfNeeded(_ window: NSWindow) {
        guard Self.isAppContentWindow(window) else { return }
        mainWindow = window
        window.delegate = self

        if configuredWindowNumbers.contains(window.windowNumber) {
            return
        }
        configuredWindowNumbers.insert(window.windowNumber)

        // Only write what actually differs: restyling a window that has a sheet attached breaks the
        // sheet on macOS 27 (it stays attached but invisible, blocking every click).
        var mask = window.styleMask
        mask.formUnion([.titled, .closable, .miniaturizable, .resizable])
        // Content runs under a transparent titlebar so the sidebar and page colors reach the top edge
        // instead of meeting a differently tinted system titlebar.
        mask.insert(.fullSizeContentView)
        if mask != window.styleMask { window.styleMask = mask }
        if !window.title.isEmpty { window.title = "" }
        if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
        if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
        if window.toolbarStyle != .automatic { window.toolbarStyle = .automatic }
        window.minSize = NSSize(width: 720, height: 540)
    }

    /// Only the app's own document window gets styled. `NSApp.windows` also lists AppKit-private
    /// windows (on macOS 27 an alert brings an `_NSGlassEffectWindow`, plus `TUINSWindow` for text
    /// input); changing their style mask trips an AppKit assertion and crashes the app at launch.
    static func isAppContentWindow(_ window: NSWindow) -> Bool {
        guard window.sheetParent == nil, !(window is NSPanel) else { return false }
        // Swift classes are module-qualified ("AppKit._NSGlassEffectWindow"); check the bare name.
        let className = NSStringFromClass(type(of: window)).split(separator: ".").last.map(String.init) ?? ""
        return !className.hasPrefix("_") && !className.hasPrefix("TUI")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.sheetParent == nil, !(sender is NSPanel) else { return true }
        switch viewModel?.windowCloseBehavior ?? .ask {
        case .quit:
            didConfirmTermination = true
            NSApp.terminate(nil)
        case .background:
            mainWindow = sender
            sender.orderOut(nil)
        case .ask:
            if requestTerminationConfirmation() { NSApp.terminate(nil) }
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let mainWindow else { return true }
        mainWindow.makeKeyAndOrderFront(nil)
        sender.activate(ignoringOtherApps: true)
        return false
    }

    private func requestTerminationConfirmation() -> Bool {
        if didConfirmTermination {
            return true
        }

        guard let viewModel else {
            return true
        }

        if let mainWindow, !mainWindow.isVisible {
            mainWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }

        viewModel.presentTerminationConfirmation(message: terminationInformativeText()) { [weak self] in
            self?.didConfirmTermination = true
            NSApp.terminate(nil)
        }
        return false
    }

    private func terminationInformativeText() -> String {
        guard let viewModel else {
            return "关闭窗口将完全退出应用。"
        }

        let counts = viewModel.downloader.countsSummary()
        let activeCount = counts.running + counts.queued
        let issueCount = counts.failed
        if activeCount > 0 || issueCount > 0 {
            return "当前还有进行中/排队 \(activeCount) 话，失败或已取消 \(issueCount) 话。退出会停止当前下载，但队列会保留到下次打开。"
        }

        if counts.done > 0 {
            return "当前队列已有 \(counts.done) 话完成。退出后 MangaGlass 会完全关闭。"
        }

        return "关闭窗口将完全退出应用。"
    }
}
