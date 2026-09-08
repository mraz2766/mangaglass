import AppKit
import Combine
import Foundation
import QuartzCore
import SwiftUI

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending = "正序"
    case descending = "倒序"

    var id: String { rawValue }
}

enum AppThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "暗黑模式"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum EnqueueResult: Equatable {
    case added(Int)
    case alreadyQueued
    case unavailable
}

private enum StorageKey {
    static let inputURL = "inputURL"
    static let authCookie = "authCookie"
    static let lastDestinationPath = "lastDestinationPath"
    static let recentRecords = "recentRecords"
    static let lastComic = "lastComic"
    static let downloadQueue = "downloadQueue"
    static let themeMode = "themeMode"
}

@MainActor
final class MainViewModel: ObservableObject {
    struct FilteredVolumeSection: Identifiable {
        let id: String
        let volumeName: String
        let chapters: [ComicChapter]

        var chapterCount: Int { chapters.count }
    }

    struct TerminationConfirmation: Identifiable {
        let id = UUID()
        let message: String
        let confirm: () -> Void
    }

    @Published var inputURL = "" {
        didSet { persistString(inputURL, key: StorageKey.inputURL) }
    }
    @Published var authCookie = "" {
        didSet { persistString(authCookie, key: StorageKey.authCookie) }
    }
    @Published var windowCloseBehavior: WindowCloseBehavior = .ask {
        didSet { persistString(windowCloseBehavior.rawValue, key: WindowCloseBehavior.storageKey) }
    }
    @Published var themeMode: AppThemeMode = {
        let raw = UserDefaults.standard.string(forKey: StorageKey.themeMode) ?? AppThemeMode.system.rawValue
        return AppThemeMode(rawValue: raw) ?? .system
    }() {
        didSet {
            persistString(themeMode.rawValue, key: StorageKey.themeMode)
            updateAppAppearance()
        }
    }
    @Published var comic: ComicInfo? {
        didSet { persistCodable(comic, key: StorageKey.lastComic) }
    }
    @Published var selectedVolumeIDs: Set<String> = []
    @Published var selectedChapterIDs: Set<String> = []
    @Published var collapsedVolumeIDs: Set<String> = []
    @Published var chapterSortDirection: SortDirection = .ascending
    @Published var chapterSearchQuery = ""
    @Published var destinationFolder: URL = {
        let path = UserDefaults.standard.string(forKey: StorageKey.lastDestinationPath) ?? "/Users/mraz/Documents/life/漫画/"
        return URL(fileURLWithPath: path, isDirectory: true)
    }() {
        didSet { persistString(destinationFolder.path, key: StorageKey.lastDestinationPath) }
    }
    @Published var statusText = "输入漫画链接后点击加载。"
    @Published var isLoading = false
    @Published var errorText = ""
    @Published var logLines: [String] = []
    @Published var showParseDone = false
    @Published var parseDoneText = ""
    @Published var parseLiveText = ""
    @Published var recentRecords: [RecentComicRecord] = []
    @Published var showOnlyErrorLogs = false
    @Published var lastMirrorSuggestion: CopyMangaMirror?
    @Published var lastFailedInput: String = ""
    @Published var shouldOfferRestoredQueuePrompt = false
    @Published var terminationConfirmation: TerminationConfirmation?

    let api: CopyMangaAPI
    let downloader: DownloadCoordinator
    private var lastSelectedChapterID: String?
    private var loadingTask: Task<Void, Never>?
    private var parsingRequestID: UUID?
    private var loadingComicKey: String?
    private var cancellables: Set<AnyCancellable> = []

    private let persistsState: Bool
    private let queueStore: DownloadQueueStore?

    init(persistsState: Bool = true, queueStore: DownloadQueueStore? = nil) {
        self.persistsState = persistsState
        self.queueStore = persistsState ? (queueStore ?? DownloadQueueStore()) : nil
        let api = CopyMangaAPI()
        self.api = api
        self.downloader = DownloadCoordinator(api: api)
        if persistsState {
            windowCloseBehavior = WindowCloseBehavior.load()
            restorePersistedState()
            updateAppAppearance()
        }
        self.api.setLogger { [weak self] message in
            Task { @MainActor in self?.appendLog(message) }
        }
        self.downloader.setLogger { [weak self] message in
            Task { @MainActor in self?.appendLog(message) }
        }
        bindPersistence()
        appendLog("解析器版本：2026-03-09-r6")
    }

    var displayVolumes: [ComicVolume] {
        guard let comic else { return [] }
        return comic.volumes
    }

    var filteredVolumeSections: [FilteredVolumeSection] {
        displayVolumes
            .filter { selectedVolumeIDs.contains($0.id) }
            .map { volume in
                let chapters = volume.chapters
                    .filter { chapterMatchesSearch($0) }
                    .sorted { lhs, rhs in
                        let left = normalizedSortValue(from: lhs.displayName, fallback: lhs.order)
                        let right = normalizedSortValue(from: rhs.displayName, fallback: rhs.order)
                        if left == right {
                            return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
                        }
                        return left < right
                    }

                return FilteredVolumeSection(
                    id: volume.id,
                    volumeName: volume.displayName,
                    chapters: chapterSortDirection == .ascending ? chapters : chapters.reversed()
                )
            }
    }

    var visibleChapters: [ComicChapter] {
        filteredVolumeSections.filter { !collapsedVolumeIDs.contains($0.id) }.flatMap(\.chapters)
    }

    var visibleChapterCount: Int {
        visibleChapters.count
    }

    var selectedChapters: [ComicChapter] {
        displayVolumes.flatMap(\.chapters).filter { selectedChapterIDs.contains($0.id) }
    }

    var hiddenSelectedChapterCount: Int {
        max(0, selectedChapters.count - selectedVisibleChapterCount)
    }

    func clearChapterSelection() {
        selectedChapterIDs.removeAll()
        lastSelectedChapterID = nil
    }

    var selectedVisibleChapterCount: Int {
        visibleChapters.reduce(into: 0) { partial, chapter in
            if selectedChapterIDs.contains(chapter.id) {
                partial += 1
            }
        }
    }

    var totalChapterCount: Int {
        displayVolumes.reduce(0) { $0 + $1.chapters.count }
    }

    var hasAnyParsedChapters: Bool {
        totalChapterCount > 0
    }

    var hasAnyMatchingChapters: Bool {
        filteredVolumeSections.contains { !$0.chapters.isEmpty }
    }

    var filteredLogLines: [String] {
        if !showOnlyErrorLogs {
            return logLines
        }
        return logLines.filter { line in
            let lowered = line.lowercased()
            return lowered.contains("失败") || lowered.contains("错误") || lowered.contains("error") || lowered.contains("http 4") || lowered.contains("http 5")
        }
    }

    var preferredColorScheme: ColorScheme? {
        themeMode.colorScheme
    }

    func updateAppAppearance() {
        CATransaction.begin()
        switch themeMode {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }

        for window in NSApp.windows {
            window.appearance = NSApp.appearance
            window.invalidateShadow()
            window.contentView?.displayIfNeeded()
        }
        CATransaction.commit()
    }

    var restoredQueuePromptSummary: String {
        let counts = downloader.countsSummary()
        return "已恢复上次队列：排队 \(counts.queued) 话，失败或已取消 \(counts.failed) 话，已完成 \(counts.done) 话。"
    }

    var canOpenRecentDownload: Bool {
        downloader.lastCompletedOutputURL != nil || downloader.countsSummary().done > 0
    }

    func presentTerminationConfirmation(message: String, confirm: @escaping () -> Void) {
        terminationConfirmation = TerminationConfirmation(message: message, confirm: confirm)
    }

    func confirmTermination() {
        let confirmation = terminationConfirmation
        terminationConfirmation = nil
        confirmation?.confirm()
    }

    func cancelTermination() {
        terminationConfirmation = nil
    }

    var hasHomeContent: Bool {
        !inputURL.isEmpty || comic != nil || isLoading || !errorText.isEmpty || !chapterSearchQuery.isEmpty
    }

    func clearHome() {
        parsingRequestID = nil
        loadingTask?.cancel()
        loadingTask = nil
        loadingComicKey = nil
        inputURL = ""
        comic = nil
        selectedVolumeIDs.removeAll()
        clearChapterSelection()
        collapsedVolumeIDs.removeAll()
        chapterSearchQuery = ""
        chapterSortDirection = .ascending
        isLoading = false
        errorText = ""
        showParseDone = false
        parseDoneText = ""
        parseLiveText = ""
        lastMirrorSuggestion = nil
        lastFailedInput = ""
        statusText = "输入漫画链接后点击解析。"
    }

    func loadComic(fetch: ((String, MangaSiteConfig, String?) async throws -> ComicInfo)? = nil) {
        guard !isLoading else { return }
        guard !CopyMangaMirror.isRetired(inputURL) else {
            presentRetiredSiteMessage()
            return
        }
        isLoading = true
        showParseDone = false
        parseDoneText = ""
        parseLiveText = "阶段 1/3：读取页面结构..."
        errorText = ""
        lastMirrorSuggestion = nil
        lastFailedInput = ""
        chapterSearchQuery = ""
        statusText = "加载中..."
        let normalizedInput = normalizeCopyURLIfNeeded(inputURL)
        if normalizedInput != inputURL {
            inputURL = normalizedInput
        }
        appendLog("开始加载：\(normalizedInput)")

        let cookie = normalizedCookie
        let requestID = UUID()
        parsingRequestID = requestID
        api.setIntermediateComicHandler { [weak self] partial in
            guard !Task.isCancelled else { return }
            Task { @MainActor in
                guard let self, self.parsingRequestID == requestID, self.isLoading,
                      self.loadingComicKey == self.comicKey(slug: partial.slug, site: partial.site) else { return }
                self.applyFetchedComic(partial, final: false, sourceText: "阶段结果")
            }
        }
        loadingTask = Task {
            guard parsingRequestID == requestID, !Task.isCancelled else { return }
            do {
                let target = try api.resolveTarget(from: normalizedInput)
                loadingComicKey = comicKey(slug: target.slug, site: target.site)
                let fetched: ComicInfo
                if let fetch {
                    fetched = try await fetch(target.slug, target.site, cookie)
                } else {
                    fetched = try await api.fetchComic(slug: target.slug, site: target.site, cookie: cookie, preferCache: false)
                }
                guard parsingRequestID == requestID, !Task.isCancelled else { return }
                applyFetchedComic(fetched, final: true, sourceText: fetched.site.displayName)
            } catch {
                guard parsingRequestID == requestID, !Task.isCancelled else { return }
                let message = error.localizedDescription
                errorText = message
                statusText = "加载失败"
                parseLiveText = ""
                lastFailedInput = normalizedInput
                lastMirrorSuggestion = suggestedMirrorFallback(for: normalizedInput)
                appendLog("加载失败：\(message)")
            }
            loadingComicKey = nil
            parsingRequestID = nil
            loadingTask = nil
            isLoading = false
        }
    }

    private func comicKey(slug: String, site: MangaSiteConfig) -> String {
        let host = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        return "\(host)::\(slug.lowercased())"
    }

    func applyFetchedComic(_ fetched: ComicInfo, final: Bool, sourceText: String) {
        let isNewComic = comic?.slug != fetched.slug || comic?.site != fetched.site
        let previousVolumeIDs = Set(displayVolumes.map(\.id))
        comic = fetched
        if isNewComic {
            selectedVolumeIDs = Set(fetched.volumes.map(\.id))
            clearChapterSelection()
            collapsedVolumeIDs.removeAll()
            chapterSearchQuery = ""
        } else {
            selectedVolumeIDs.formUnion(Set(fetched.volumes.map(\.id)).subtracting(previousVolumeIDs))
        }
        statusText = final
            ? "加载成功：\(fetched.name)（\(fetched.site.displayName)）"
            : "已显示\(sourceText)：\(fetched.name)，正在补全..."
        let stats = parsedStats(from: fetched)
        if final {
            parseDoneText = "解析完成 · 分类 \(stats.groups) · 章节 \(stats.chapters)"
            parseLiveText = ""
            showParseDone = true
        } else {
            showParseDone = false
            parseLiveText = "阶段 2/3：分类 \(stats.groups) · 章节 \(stats.chapters)（补全中）"
        }
        appendLog("加载成功：\(fetched.name)，分类 \(stats.groups)，章节 \(stats.chapters)")
        if final {
            rememberRecentComic(title: fetched.name, input: inputURL, siteName: fetched.site.displayName)
        }
    }

    private func parsedStats(from comic: ComicInfo) -> (groups: Int, chapters: Int) {
        let groups = comic.volumes.count
        let chapters = comic.volumes.reduce(0) { $0 + $1.chapters.count }
        return (groups, chapters)
    }

    private func normalizeCopyURLIfNeeded(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = destinationFolder

        if panel.runModal() == .OK, let url = panel.url {
            destinationFolder = url
        }
    }

    func selectAllVisible() {
        selectedChapterIDs.formUnion(visibleChapters.map(\.id))
    }

    func deselectAllVisible() {
        selectedChapterIDs.subtract(visibleChapters.map(\.id))
    }

    func selectChapter(_ chapter: ComicChapter, modifiers: NSEvent.ModifierFlags) {
        let orderedIDs = visibleChapters.map(\.id)

        if modifiers.contains(.shift),
           let anchor = lastSelectedChapterID,
           let from = orderedIDs.firstIndex(of: anchor),
           let to = orderedIDs.firstIndex(of: chapter.id) {
            let low = min(from, to)
            let high = max(from, to)
            let rangeIDs = Set(orderedIDs[low...high])
            if modifiers.contains(.command) {
                selectedChapterIDs.formUnion(rangeIDs)
            } else {
                selectedChapterIDs = rangeIDs
            }
            lastSelectedChapterID = chapter.id
            return
        }

        if selectedChapterIDs.contains(chapter.id) {
            selectedChapterIDs.remove(chapter.id)
        } else {
            selectedChapterIDs.insert(chapter.id)
        }
        lastSelectedChapterID = chapter.id
    }

    func applyDragSelection(_ chapterIDs: Set<String>, additive: Bool) {
        let nextSelection = additive ? selectedChapterIDs.union(chapterIDs) : chapterIDs
        guard nextSelection != selectedChapterIDs else { return }
        selectedChapterIDs = nextSelection
    }

    func toggleVolume(_ volumeID: String) {
        if selectedVolumeIDs.contains(volumeID) {
            selectedVolumeIDs.remove(volumeID)
        } else {
            selectedVolumeIDs.insert(volumeID)
        }

    }

    func selectAllVolumes() {
        selectedVolumeIDs = Set(comic?.volumes.map(\.id) ?? [])
    }

    func deselectAllVolumes() {
        selectedVolumeIDs = []
    }

    func selectVolumeChapters(volumeID: String) {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return }
        selectedChapterIDs.formUnion(volume.chapters.filter(chapterMatchesSearch).map(\.id))
    }

    func deselectVolumeChapters(volumeID: String) {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return }
        selectedChapterIDs.subtract(volume.chapters.filter(chapterMatchesSearch).map(\.id))
    }

    func toggleVolumeChapterSelection(volumeID: String) {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return }
        let chapterIDs = Set(volume.chapters.filter(chapterMatchesSearch).map(\.id))
        if chapterIDs.isSubset(of: selectedChapterIDs) {
            selectedChapterIDs.subtract(chapterIDs)
        } else {
            selectedChapterIDs.formUnion(chapterIDs)
        }
    }

    func areAllChaptersSelected(in volumeID: String) -> Bool {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return false }
        let chapterIDs = Set(volume.chapters.filter(chapterMatchesSearch).map(\.id))
        return !chapterIDs.isEmpty && chapterIDs.isSubset(of: selectedChapterIDs)
    }

    func selectedChapterCount(in volumeID: String) -> Int {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return 0 }
        return volume.chapters.filter(chapterMatchesSearch).reduce(into: 0) { partial, chapter in
            if selectedChapterIDs.contains(chapter.id) {
                partial += 1
            }
        }
    }

    func isVolumeChapterSelectionPartial(volumeID: String) -> Bool {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return false }
        let selected = selectedChapterCount(in: volumeID)
        let matchingCount = volume.chapters.filter(chapterMatchesSearch).count
        return selected > 0 && selected < matchingCount
    }

    @discardableResult
    func enqueueSelectedChapters() -> EnqueueResult {
        guard let comic, !selectedChapters.isEmpty else { return .unavailable }
        if isRetiredCopySite(comic.site) {
            presentRetiredSiteMessage()
            return .unavailable
        }
        let addedCount = downloader.add(
            chapters: selectedChapters,
            comic: comic,
            destination: destinationFolder,
            cookie: normalizedCookie
        )
        guard addedCount > 0 else {
            statusText = "所选章节已在队列中。"
            return .alreadyQueued
        }
        let saved = checkpointDownloadQueue()
        appendLog("加入队列：\(comic.name) - 新增 \(addedCount) 话")
        statusText = saved ? "已加入队列 \(addedCount) 话。" : "已加入 \(addedCount) 话，但队列保存失败。"
        clearChapterSelection()
        return .added(addedCount)
    }

    @discardableResult
    func startDownload() -> EnqueueResult {
        guard let comic, !selectedChapters.isEmpty else { return .unavailable }
        guard !isRetiredCopySite(comic.site) else {
            presentRetiredSiteMessage()
            return .unavailable
        }
        let result = enqueueSelectedChapters()
        guard result != .unavailable else { return result }
        startQueuedDownloads()
        return result
    }

    func startQueuedDownloads() {
        if downloader.taskItems.contains(where: { $0.state == .queued && isRetiredCopySite($0.comic.site) }) {
            presentRetiredSiteMessage()
            return
        }
        let queueConcurrent = queueMaxConcurrent()
        
        let pendingItems = downloader.taskItems.filter { $0.state == .queued }
        if pendingItems.isEmpty {
            statusText = "无挂起的下载任务。"
            appendLog("下载未开始：当前可等待下载章节为 0")
            return
        }

        downloader.start(maxConcurrent: queueConcurrent)
    }



    func pauseDownload() {
        downloader.pause()
    }

    func resumeDownload() {
        guard let comic else { return }
        guard !isRetiredCopySite(comic.site),
              !downloader.taskItems.contains(where: { ($0.state == .queued || $0.state == .running) && isRetiredCopySite($0.comic.site) }) else {
            presentRetiredSiteMessage()
            return
        }
        downloader.resume()
        if !downloader.isRunning {
            let concurrent = downloadConcurrent(for: comic.site)
            downloader.start(maxConcurrent: concurrent)
        }
    }

    func cancelDownload() {
        downloader.cancel()
    }

    func cancelAndClearAllDownloads() {
        let count = downloader.taskItems.count
        downloader.cancelAndClearAll()
        appendLog("已取消并清空下载队列：\(count) 条")
        statusText = count > 0 ? "已取消并清空 \(count) 条下载任务。" : "下载队列已清空。"
    }

    func cancelItem(_ item: DownloadTaskItem) {
        downloader.cancelItem(item.id)
    }

    func retryItem(_ item: DownloadTaskItem) {
        guard !isRetiredCopySite(item.comic.site) else {
            presentRetiredSiteMessage()
            return
        }
        appendLog("重试单独章节：\(item.chapter.displayName)")
        downloader.taskItems.removeAll { $0.id == item.id }
        downloader.add(chapters: [item.chapter], comic: item.comic, destination: item.destination, cookie: item.cookie)
        if !downloader.isRunning {
             let concurrent = downloadConcurrent(for: item.comic.site)
             downloader.start(maxConcurrent: concurrent)
        }
    }

    func retryFailed() {
        let failed = downloader.failedItems()
        guard !failed.isEmpty else {
            statusText = "没有失败任务可重下。"
            appendLog("重试跳过：没有失败任务")
            return
        }
        guard !failed.contains(where: { isRetiredCopySite($0.comic.site) }) else {
            presentRetiredSiteMessage()
            return
        }

        appendLog("重试失败任务：\(failed.count) 话")
        
        let chaptersByComicAndDestination = Dictionary(grouping: failed) { item in
            "\(item.comic.slug)-\(item.destination.path)"
        }
        
        for (_, items) in chaptersByComicAndDestination {
            if let first = items.first {
                let chaptersToRetry = items.map { $0.chapter }
                downloader.add(chapters: chaptersToRetry, comic: first.comic, destination: first.destination, cookie: first.cookie)
            }
        }
        
        // Remove old failed tasks that we just re-added
        let failedIDs = Set(failed.map { $0.id })
        downloader.taskItems.removeAll { failedIDs.contains($0.id) }
        
        downloader.start(maxConcurrent: queueMaxConcurrent())
    }

    private func queueMaxConcurrent() -> Int {
        let hasManhuaGui = downloader.taskItems.contains {
            $0.comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true
        }
        if hasManhuaGui {
            return 4
        }
        let hasCopy = downloader.taskItems.contains {
            isCopyFamily($0.comic.site)
        }
        if hasCopy {
            return 4
        }
        return 5
    }

    private func downloadConcurrent(for site: MangaSiteConfig) -> Int {
        if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
            return 4
        }
        if isCopyFamily(site) {
            return 4
        }
        return 5
    }

    private func isCopyFamily(_ site: MangaSiteConfig) -> Bool {
        guard let host = site.webBase.host?.lowercased() else { return false }
        return CopyMangaMirror.mirror(for: host) != nil
    }

    private func isRetiredCopySite(_ site: MangaSiteConfig) -> Bool {
        CopyMangaMirror.isRetired(site.webBase.host)
    }

    private func presentRetiredSiteMessage() {
        errorText = CopyMangaMirror.retiredMessage
        statusText = "站点已停用"
        showParseDone = false
        parseDoneText = ""
        parseLiveText = ""
        lastMirrorSuggestion = nil
        appendLog(CopyMangaMirror.retiredMessage)
    }

    func clearLogs() {
        logLines = []
    }

    func copyCurrentError() {
        let text = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            statusText = "当前没有可复制的错误。"
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusText = "已复制错误信息。"
        appendLog("已复制当前错误信息")
    }

    func dismissRestoredQueuePrompt() {
        shouldOfferRestoredQueuePrompt = false
    }

    func resumeRestoredQueue() {
        shouldOfferRestoredQueuePrompt = false
        guard !downloader.taskItems.contains(where: { $0.state == .queued && isRetiredCopySite($0.comic.site) }) else {
            presentRetiredSiteMessage()
            return
        }
        let counts = downloader.countsSummary()
        guard counts.queued > 0 else {
            statusText = "恢复的队列中没有排队任务，可在下载管理中重试失败项。"
            appendLog("恢复队列继续下载跳过：没有排队任务")
            return
        }
        appendLog("继续上次恢复队列：排队 \(counts.queued) 话")
        downloader.start(maxConcurrent: queueMaxConcurrent())
    }

    func openDownloadDirectory() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destinationFolder.path)
    }

    func openRecentDownload() {
        let url = downloader.lastCompletedOutputURL ?? destinationFolder
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        statusText = "已在 Finder 中显示下载位置。"
    }

    func openManhuaGuiWebCheck() {
        let url = URL(string: "https://www.manhuagui.com")!
        NSWorkspace.shared.open(url)
        statusText = "已打开漫画柜网页，请确认是否可访问。"
        appendLog("已打开漫画柜网页供用户检查")
    }

    func continueManhuaGuiDownloadAfterCheck() {
        downloader.clearManhuaGuiSoftCircuit()
        appendLog("用户确认漫画柜网页可访问，继续下载")
        downloader.start(maxConcurrent: queueMaxConcurrent())
    }

    func clearCaches() {
        Task {
            await api.clearCaches()
            await MainActor.run {
                inputURL = ""
                comic = nil
                selectedVolumeIDs = []
                selectedChapterIDs = []
                lastSelectedChapterID = nil
                isLoading = false
                errorText = ""
                showParseDone = false
                parseDoneText = ""
                parseLiveText = ""
                lastMirrorSuggestion = nil
                lastFailedInput = ""
                loadingComicKey = nil
                statusText = "已清空缓存与当前解析内容。"
                appendLog("已手动清空缓存与当前解析内容")
            }
        }
    }

    func copyRecentLogs() {
        let lines = Array(filteredLogLines.suffix(50))
        let content = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        statusText = lines.isEmpty ? "当前没有可复制的日志。" : "已复制最近 \(lines.count) 条日志。"
    }

    func applyRecentRecord(_ record: RecentComicRecord) {
        inputURL = record.input
        loadComic()
    }

    func removeRecentRecord(_ record: RecentComicRecord) {
        recentRecords.removeAll { $0.id == record.id }
        statusText = "已删除历史：\(record.title)"
        appendLog("已删除历史记录：\(record.title)")
    }

    func clearRecentRecords() {
        guard !recentRecords.isEmpty else {
            statusText = "当前没有历史记录。"
            appendLog("清空历史跳过：当前没有历史记录")
            return
        }
        let removed = recentRecords.count
        recentRecords = []
        statusText = "已清空历史记录 \(removed) 条。"
        appendLog("已清空历史记录：\(removed) 条")
    }

    func applySuggestedMirrorAndReload() {
        guard let suggestion = lastMirrorSuggestion else { return }
        let trimmed = lastFailedInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host else {
            return
        }
        let targetHost = host.hasPrefix("www.") ? suggestion.wwwHost : suggestion.bareHost
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.host = targetHost
        if let nextURL = components?.url {
            inputURL = nextURL.absoluteString
            loadComic()
        }
    }

    func clearQueue() {
        if downloader.resetQueueIfIdle() {
            appendLog("已清空下载队列")
            statusText = "下载队列已清空。"
        } else {
            appendLog("清空队列失败：下载进行中")
            statusText = "下载进行中，无法清空全部队列。"
        }
    }

    func clearCompletedTasks() {
        let removed = downloader.clearCompletedTasks()
        if removed > 0 {
            appendLog("已清空完成任务：\(removed) 条")
            statusText = "已清空完成任务 \(removed) 条。"
        } else {
            appendLog("清空完成任务：当前无可清理项")
            statusText = "没有已完成任务可清空。"
        }
    }

    private func bindPersistence() {
        downloader.$taskItems
            .sink { [weak self] items in
                self?.queueStore?.save(items)
            }
            .store(in: &cancellables)

        $recentRecords
            .dropFirst()
            .sink { [weak self] items in
                self?.persistCodable(items, key: StorageKey.recentRecords)
            }
            .store(in: &cancellables)
    }

    private func restorePersistedState() {
        let defaults = UserDefaults.standard
        inputURL = defaults.string(forKey: StorageKey.inputURL) ?? ""
        authCookie = defaults.string(forKey: StorageKey.authCookie) ?? ""
        recentRecords = loadCodable([RecentComicRecord].self, key: StorageKey.recentRecords) ?? []
        comic = loadCodable(ComicInfo.self, key: StorageKey.lastComic)
        if let comic {
            selectedVolumeIDs = Set(comic.volumes.map(\.id))
            let stats = parsedStats(from: comic)
            statusText = "已恢复上次解析：\(comic.name)"
            parseDoneText = "已恢复 · 分类 \(stats.groups) · 章节 \(stats.chapters)"
            showParseDone = true
        }
        let durableItems = queueStore?.load()
        let legacyItems = durableItems == nil
            ? loadCodable([DownloadTaskItem].self, key: StorageKey.downloadQueue)
            : nil
        if let restoredItems = durableItems ?? legacyItems, !restoredItems.isEmpty {
            downloader.restoreQueue(restoredItems)
            let counts = downloader.countsSummary()
            shouldOfferRestoredQueuePrompt = counts.queued > 0 || counts.failed > 0
        }
        if durableItems == nil, let legacyItems, queueStore?.saveSynchronously(legacyItems) == true {
            defaults.removeObject(forKey: StorageKey.downloadQueue)
            appendLog("已将旧版下载队列迁移为可靠快照")
        }
    }

    @discardableResult
    func checkpointDownloadQueue() -> Bool {
        guard let queueStore else { return !persistsState }
        return queueStore.saveSynchronously(downloader.taskItems)
    }

    private func persistString(_ value: String, key: String) {
        guard persistsState else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistCodable<T: Codable>(_ value: T?, key: String) {
        guard persistsState else { return }
        let defaults = UserDefaults.standard
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private func loadCodable<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func rememberRecentComic(title: String, input: String, siteName: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let next = RecentComicRecord(title: title, input: trimmed, siteName: siteName)
        recentRecords.removeAll { $0.input == trimmed }
        recentRecords.insert(next, at: 0)
        if recentRecords.count > 8 {
            recentRecords = Array(recentRecords.prefix(8))
        }
    }

    private func suggestedMirrorFallback(for input: String) -> CopyMangaMirror? {
        guard let url = URL(string: input), let host = url.host?.lowercased() else {
            return nil
        }
        guard let current = CopyMangaMirror.mirror(for: host) else {
            return nil
        }
        return CopyMangaMirror.allCases.first { $0 != current }
    }

    private var normalizedCookie: String? {
        let value = authCookie.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func normalizedSortValue(from text: String, fallback: Double) -> Double {
        guard let range = text.range(of: #"(\d+(?:\.\d+)?)"#, options: .regularExpression) else {
            return fallback
        }
        return Double(text[range]) ?? fallback
    }

    private func chapterMatchesSearch(_ chapter: ComicChapter) -> Bool {
        let query = chapterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || chapter.displayName.localizedCaseInsensitiveContains(query)
    }

    private func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "[\(formatter.string(from: Date()))] \(message)"
        logLines.append(line)
        if logLines.count > 400 {
            logLines.removeFirst(logLines.count - 400)
        }
        refreshParseLiveProgress(from: message)
    }

    private func refreshParseLiveProgress(from message: String) {
        guard isLoading else { return }
        if message.contains("使用 HTML 章节提取") {
            parseLiveText = "阶段 1/3：已拿到初步章节..."
            return
        }
        if message.contains("使用 comicdetail 接口") {
            parseLiveText = "阶段 2/3：接口补齐中..."
            return
        }
        if message.contains("API 补齐成功") {
            parseLiveText = "阶段 2/3：API 补齐成功，继续校验..."
            return
        }
        if message.contains("尝试渲染 DOM 补齐") {
            parseLiveText = "阶段 3/3：渲染补齐中..."
            return
        }
        if message.contains("渲染 DOM 补齐成功") {
            parseLiveText = "阶段 3/3：渲染补齐完成，准备收尾..."
            return
        }
    }
}
