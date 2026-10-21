import AppKit
import SwiftUI
import XCTest
@testable import MangaGlass

/// Opt-in rendering of production views; no user defaults, cookies, or queue writes.
@MainActor
final class LayoutSnapshots: XCTestCase {
    func testRenderAcceptanceMatrix() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MANGAGLASS_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set MANGAGLASS_SNAPSHOT_DIR to render the visual acceptance matrix.")
        }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { MGTheme.style = .ink }
        for style in AppThemeStyle.allCases {
            MGTheme.style = style
            for dark in [false, true] {
                let vm = MainViewModel(persistsState: false)
                vm.themeStyle = style
                vm.applyFetchedComic(SelectionTests.fixture(chapterCount: 160, groups: 4), final: true, sourceText: "测试")
                vm.selectedChapterIDs = ["0", "4", "8", "1"]
                try await render(ContentView(vm: vm).environment(\.colorScheme, dark ? .dark : .light),
                                 size: NSSize(width: 1200, height: 800),
                                 name: "theme-\(style.rawValue)-\(dark ? "dark" : "light")", output: output, dark: dark)
            }
        }
        let sizes: [(Int, Int)] = [(1200, 800), (1080, 760), (720, 540), (1440, 900)]
        for dark in [false, true] {
            for (width, height) in sizes {
                let vm = MainViewModel(persistsState: false)
                vm.themeStyle = .ink
                vm.applyFetchedComic(SelectionTests.fixture(chapterCount: 160, groups: 4), final: true, sourceText: "测试")
                vm.selectedChapterIDs = ["0", "4", "8", "1"]
                let root = ContentView(vm: vm)
                    .environment(\.colorScheme, dark ? .dark : .light)
                try await render(root, size: NSSize(width: width, height: height),
                                 name: "home-\(width)x\(height)-\(dark ? "dark" : "light")", output: output, dark: dark)
            }
            let vm = MainViewModel(persistsState: false)
            vm.applyFetchedComic(SelectionTests.fixture(), final: true, sourceText: "测试")
            vm.selectAllVisible()
            vm.enqueueSelectedChapters()
            vm.recentRecords = [RecentComicRecord(title: "测试漫画", input: "https://www.mangacopy.com/comic/test-fixture-long-link", siteName: "主站")]
            for style in AppThemeStyle.allCases {
            vm.themeStyle = style
            for page in [WorkspaceDestination.queue, .history] {
                for (width, height) in style == .ink ? [(1200, 800), (720, 540)] : [(1200, 800)] {
                    let body: AnyView
                    switch page {
                    case .queue: body = AnyView(QueueWorkspaceView(vm: vm, showLogs: .constant(false)))
                    case .history: body = AnyView(HistoryWorkspaceView(vm: vm, openDownload: {}))
                    default: continue
                    }
                    let root = HStack(spacing: 0) {
                        WorkspaceSidebar(downloader: vm.downloader, destination: .constant(page)).frame(width: 72)
                        Divider()
                        body.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .foregroundStyle(MGTheme.palette.text)
                    .tint(MGTheme.accent)
                    .background(MGTheme.background(for: dark ? .dark : .light))
                    .environment(\.colorScheme, dark ? .dark : .light)
                    try await render(root, size: NSSize(width: width, height: height),
                                     name: "\(page.rawValue)-\(style.rawValue)-\(width)x\(height)-\(dark ? "dark" : "light")", output: output, dark: dark)
                }
            }
            }
            vm.themeStyle = .ink
            // Settings window (each tab is its own pane; the TabView renders the first).
            for accent in [false, true] {
                vm.themeStyle = .classic
                vm.followsSystemAccent = accent
                let settings = SettingsView(vm: vm).environment(\.colorScheme, dark ? .dark : .light)
                try await render(settings, size: NSSize(width: 560, height: 520),
                                 name: "settings-\(accent ? "system-accent" : "theme-accent")-\(dark ? "dark" : "light")", output: output, dark: dark)
            }
            vm.followsSystemAccent = false
            vm.themeStyle = .ink
        }
        for scenario in ["empty", "loading", "error", "no-results", "no-categories", "collapsed", "many-categories"] {
            let vm = MainViewModel(persistsState: false)
            if scenario != "empty" {
                vm.applyFetchedComic(SelectionTests.fixture(chapterCount: 160, groups: scenario == "many-categories" ? 30 : 4), final: true, sourceText: "测试")
                vm.selectedChapterIDs = ["0", "1"]
            }
            switch scenario {
            case "loading": vm.isLoading = true
            case "error": vm.errorText = "解析失败：测试错误信息。请检查链接或通过站点入口切换有效镜像。"
            case "no-results": vm.chapterSearchQuery = "没有匹配内容"
            case "no-categories": vm.deselectAllVolumes()
            case "collapsed": vm.collapsedVolumeIDs = Set(vm.displayVolumes.map(\.id))
            default: break
            }
            try await render(ContentView(vm: vm), size: NSSize(width: 720, height: 540), name: "home-\(scenario)", output: output, dark: false)
        }
    }

    /// Opt-in README screenshots with neutral sample data (no real titles or covers).
    func testRenderReadmeShowcase() async throws {
        guard let directory = ProcessInfo.processInfo.environment["MANGAGLASS_README_DIR"] else {
            throw XCTSkip("Set MANGAGLASS_README_DIR to render README screenshots.")
        }
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { MGTheme.style = .ink }

        // A generated, colorful stand-in cover (no real artwork) so banners show a real blurred backdrop.
        let coverURL = output.appendingPathComponent("sample-cover.png")
        try Self.sampleCover().write(to: coverURL)
        _ = await CoverImageCache.shared.image(for: coverURL)

        func sample() -> MainViewModel {
            let groups = [("话", 96), ("单行本", 12), ("番外", 6)]
            let volumes = groups.enumerated().map { offset, group in
                ComicVolume(id: "v\(offset)", displayName: group.0, pathWord: "v\(offset)", chapters: (0..<group.1).map { index in
                    ComicChapter(id: "\(offset)-\(index)", uuid: "\(offset)-\(index)",
                                 displayName: offset == 1 ? "第 \(index + 1) 卷" : (offset == 2 ? "番外 \(index + 1)" : String(format: "第 %02d 话", index + 1)),
                                 order: Double(index), volumeID: "v\(offset)", volumeName: group.0)
                })
            }
            let comic = ComicInfo(slug: "sample", name: "示例漫画：星海旅人", coverURL: coverURL, volumes: volumes,
                                  site: .mangaCopy, apiPathPrefix: "", apiBaseURL: MangaSiteConfig.mangaCopy.apiBaseURLs[0])
            let vm = MainViewModel(persistsState: false)
            vm.applyFetchedComic(comic, final: true, sourceText: "示例")
            vm.recentRecords = [
                RecentComicRecord(title: "示例漫画：星海旅人", input: "https://www.mangacopy.com/comic/sample", siteName: "拷贝漫画", coverURL: coverURL),
                RecentComicRecord(title: "山间小店", input: "https://www.manhuagui.com/comic/1/", siteName: "漫画柜", updatedAt: Date().addingTimeInterval(-7200)),
                RecentComicRecord(title: "午夜列车", input: "https://www.baozimh.com/comic/sample", siteName: "包子漫画", updatedAt: Date().addingTimeInterval(-90000)),
            ]
            return vm
        }

        for style in AppThemeStyle.allCases {
            let vm = sample()
            vm.themeStyle = style
            vm.selectedChapterIDs = ["0-2", "0-3", "0-4", "0-9", "0-10"]
            try await render(ContentView(vm: vm).environment(\.colorScheme, .light),
                             size: NSSize(width: 1200, height: 760), name: "readme-home-\(style.rawValue)", output: output, dark: false)
        }

        let vm = sample()
        vm.themeStyle = .graphite
        vm.selectedChapterIDs = ["0-0", "0-1", "0-2", "0-3", "1-0", "2-0"]
        _ = vm.enqueueSelectedChapters()
        let queue = HStack(spacing: 0) {
            WorkspaceSidebar(downloader: vm.downloader, destination: .constant(.queue)).frame(width: 72)
            Divider()
            QueueWorkspaceView(vm: vm, showLogs: .constant(false)).padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MGTheme.background(for: .dark))
        .foregroundStyle(MGTheme.palette.text)
        .tint(MGTheme.accent)
        .environment(\.colorScheme, .dark)
        try await render(queue, size: NSSize(width: 1200, height: 760), name: "readme-download-graphite-dark", output: output, dark: true)

        let empty = MainViewModel(persistsState: false)
        empty.themeStyle = .ink
        empty.recentRecords = sample().recentRecords
        try await render(ContentView(vm: empty).environment(\.colorScheme, .dark),
                         size: NSSize(width: 1200, height: 760), name: "readme-start-ink-dark", output: output, dark: true)
    }

    private static func sampleCover() -> Data {
        let width = 600, height = 840
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors = [CGColor(red: 0.10, green: 0.16, blue: 0.36, alpha: 1), CGColor(red: 0.20, green: 0.55, blue: 0.62, alpha: 1),
                      CGColor(red: 0.95, green: 0.62, blue: 0.38, alpha: 1)] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1])!
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        context.setFillColor(CGColor(red: 1, green: 0.92, blue: 0.75, alpha: 0.9))
        context.fillEllipse(in: CGRect(x: 360, y: 560, width: 150, height: 150))
        context.setFillColor(CGColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 0.85))
        context.fill(CGRect(x: 60, y: 80, width: 480, height: 120))
        let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
        return rep.representation(using: .png, properties: [:])!
    }

    private func render<V: View>(_ view: V, size: NSSize, name: String, output: URL, dark: Bool) async throws {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        window.setContentSize(size)
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent(name + ".png"))
        XCTAssertEqual(host.bounds.width, size.width)
        XCTAssertEqual(host.bounds.height, size.height)
    }
}
