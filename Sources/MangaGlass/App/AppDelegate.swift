import AppKit
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    weak var viewModel: MainViewModel?

    private var observer: NSObjectProtocol?
    private var configuredWindowNumbers: Set<Int> = []
    private var didConfirmTermination = false

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        requestTerminationConfirmation() ? .terminateNow : .terminateCancel
    }

    private func configureIfNeeded(_ window: NSWindow) {
        window.delegate = self

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
        window.minSize = NSSize(width: 720, height: 540)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if requestTerminationConfirmation() {
            NSApp.terminate(nil)
        }

        return false
    }

    private func requestTerminationConfirmation() -> Bool {
        if didConfirmTermination {
            return true
        }

        guard let viewModel else {
            return true
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
