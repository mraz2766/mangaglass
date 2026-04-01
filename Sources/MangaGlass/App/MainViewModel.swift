import AppKit
import Combine
import Foundation
import SwiftUI

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending = "正序"
    case descending = "倒序"

    var id: String { rawValue }
}

private enum StorageKey {
    static let inputURL = "inputURL"
    static let authCookie = "authCookie"
    static let proxyType = "proxyType"
    static let proxyHost = "proxyHost"
    static let proxyPort = "proxyPort"
    static let proxyUsername = "proxyUsername"
    static let proxyPassword = "proxyPassword"
    static let lastDestinationPath = "lastDestinationPath"
    static let recentRecords = "recentRecords"
    static let lastComic = "lastComic"
    static let downloadQueue = "downloadQueue"
}

@MainActor
final class MainViewModel: ObservableObject {
    struct FilteredVolumeSection: Identifiable {
        let id: String
        let volumeName: String
        let chapters: [ComicChapter]

        var chapterCount: Int { chapters.count }
    }

    @Published var inputURL = "" {
        didSet { persistString(inputURL, key: StorageKey.inputURL) }
    }
    @Published var authCookie = "" {
        didSet { persistString(authCookie, key: StorageKey.authCookie) }
    }
    @Published var proxyType: ProxyType = .none {
        didSet { persistString(proxyType.rawValue, key: StorageKey.proxyType) }
    }
    @Published var proxyHost = "" {
        didSet { persistString(proxyHost, key: StorageKey.proxyHost) }
    }
    @Published var proxyPort = "" {
        didSet { persistString(proxyPort, key: StorageKey.proxyPort) }
    }
    @Published var proxyUsername = "" {
        didSet { persistString(proxyUsername, key: StorageKey.proxyUsername) }
    }
    @Published var proxyPassword = "" {
        didSet { persistString(proxyPassword, key: StorageKey.proxyPassword) }
    }
    @Published var comic: ComicInfo? {
        didSet { persistCodable(comic, key: StorageKey.lastComic) }
    }
    @Published var selectedVolumeIDs: Set<String> = []
    @Published var selectedChapterIDs: Set<String> = []
    @Published var chapterSortDirection: SortDirection = .ascending
    @Published var destinationFolder: URL = {
        let path = UserDefaults.standard.string(forKey: StorageKey.lastDestinationPath) ?? "/Users/mraz/Downloads/漫画/"
        return URL(fileURLWithPath: path, isDirectory: true)
    }() {
        didSet { UserDefaults.standard.set(destinationFolder.path, forKey: StorageKey.lastDestinationPath) }
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

    let api: CopyMangaAPI
    let downloader: DownloadCoordinator
    private var lastSelectedChapterID: String?
    private var loadingComicKey: String?
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let api = CopyMangaAPI()
        self.api = api
        self.downloader = DownloadCoordinator(api: api)
        restorePersistedState()
        self.api.setLogger { [weak self] message in
            Task { @MainActor in self?.appendLog(message) }
        }
        self.api.setIntermediateComicHandler { [weak self] partial in
            Task { @MainActor in
                guard let self else { return }
                guard self.isLoading else { return }
                guard self.loadingComicKey == self.comicKey(slug: partial.slug, site: partial.site) else { return }
                self.applyFetchedComic(partial, final: false, sourceText: "阶段结果")
            }
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
        filteredVolumeSections.flatMap(\.chapters)
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

    func loadComic() {
        guard !isLoading else { return }
        isLoading = true
        showParseDone = false
        parseDoneText = ""
        parseLiveText = "阶段 1/3：读取页面结构..."
        errorText = ""
        lastMirrorSuggestion = nil
        lastFailedInput = ""
        statusText = "加载中..."
        let normalizedInput = normalizeCopyURLIfNeeded(inputURL)
        if normalizedInput != inputURL {
            inputURL = normalizedInput
        }
        appendLog("开始加载：\(normalizedInput)")

        let cookie = normalizedCookie
        Task {
            do {
                try applyProxyIfNeeded()
                let target = try api.resolveTarget(from: normalizedInput)
                loadingComicKey = comicKey(slug: target.slug, site: target.site)
                let fetched = try await api.fetchComic(slug: target.slug, site: target.site, cookie: cookie, preferCache: false)
                applyFetchedComic(fetched, final: true, sourceText: fetched.site.displayName)
            } catch {
                let message = error.localizedDescription
                errorText = message
                statusText = "加载失败"
                parseLiveText = ""
                lastFailedInput = normalizedInput
                lastMirrorSuggestion = suggestedMirrorFallback(for: normalizedInput)
                appendLog("加载失败：\(message)")
            }
            loadingComicKey = nil
            isLoading = false
        }
    }

    private func comicKey(slug: String, site: MangaSiteConfig) -> String {
        let host = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        return "\(host)::\(slug.lowercased())"
    }

    private func applyFetchedComic(_ fetched: ComicInfo, final: Bool, sourceText: String) {
        comic = fetched
        selectedVolumeIDs = Set(fetched.volumes.map(\.id))
        selectedChapterIDs = []
        lastSelectedChapterID = nil
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
        if additive {
            selectedChapterIDs.formUnion(chapterIDs)
        } else {
            selectedChapterIDs = chapterIDs
        }
    }

    func toggleVolume(_ volumeID: String) {
        if selectedVolumeIDs.contains(volumeID) {
            selectedVolumeIDs.remove(volumeID)
        } else {
            selectedVolumeIDs.insert(volumeID)
        }

        // Keep chapter selection coherent with current volume selection.
        let visibleIDs = Set(visibleChapters.map(\.id))
        selectedChapterIDs = selectedChapterIDs.intersection(visibleIDs)
    }

    func selectAllVolumes() {
        selectedVolumeIDs = Set(comic?.volumes.map(\.id) ?? [])
    }

    func deselectAllVolumes() {
        selectedVolumeIDs = []
        selectedChapterIDs = []
    }

    func selectVolumeChapters(volumeID: String) {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return }
        selectedChapterIDs.formUnion(volume.chapters.map(\.id))
    }

    func deselectVolumeChapters(volumeID: String) {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return }
        selectedChapterIDs.subtract(volume.chapters.map(\.id))
    }

    func toggleVolumeChapterSelection(volumeID: String) {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return }
        let chapterIDs = Set(volume.chapters.map(\.id))
        if chapterIDs.isSubset(of: selectedChapterIDs) {
            selectedChapterIDs.subtract(chapterIDs)
        } else {
            selectedChapterIDs.formUnion(chapterIDs)
        }
    }

    func areAllChaptersSelected(in volumeID: String) -> Bool {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return false }
        let chapterIDs = Set(volume.chapters.map(\.id))
        return !chapterIDs.isEmpty && chapterIDs.isSubset(of: selectedChapterIDs)
    }

    func selectedChapterCount(in volumeID: String) -> Int {
        guard let volume = displayVolumes.first(where: { $0.id == volumeID }) else { return 0 }
        return volume.chapters.reduce(into: 0) { partial, chapter in
            if selectedChapterIDs.contains(chapter.id) {
                partial += 1
            }
        }
    }

    func startDownload() {
        let queueConcurrent = queueMaxConcurrent()
        if let comic = comic {
            let selected: [ComicChapter]
            if !selectedChapterIDs.isEmpty {
                selected = visibleChapters.filter { selectedChapterIDs.contains($0.id) }
            } else {
                selected = visibleChapters
            }
            if !selected.isEmpty {
                do {
                    try applyProxyIfNeeded()
                } catch {
                    errorText = error.localizedDescription
                    statusText = "代理配置错误"
                    appendLog("下载未开始：代理配置错误 - \(error.localizedDescription)")
                    return
                }
                let concurrent = comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true ? 3 : 5
                appendLog("加入队列：\(comic.name) - \(selected.count) 话，并发 \(concurrent)")
                downloader.add(chapters: selected, comic: comic, destination: destinationFolder, cookie: normalizedCookie)
            }
        }
        
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
        downloader.resume()
        if !downloader.isRunning {
            let concurrent = comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true ? 3 : 6
            downloader.start(maxConcurrent: concurrent)
        }
    }

    func cancelDownload() {
        downloader.cancel()
    }

    func retryItem(_ item: DownloadTaskItem) {
        do {
            try applyProxyIfNeeded()
        } catch {
            errorText = error.localizedDescription
            statusText = "代理配置错误"
            appendLog("重试未开始：代理配置错误 - \(error.localizedDescription)")
            return
        }
        
        appendLog("重试单独章节：\(item.chapter.displayName)")
        downloader.taskItems.removeAll { $0.id == item.id }
        downloader.add(chapters: [item.chapter], comic: item.comic, destination: item.destination, cookie: item.cookie)
        if !downloader.isRunning {
             let concurrent = item.comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true ? 3 : 6
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

        do {
            try applyProxyIfNeeded()
        } catch {
            errorText = error.localizedDescription
            statusText = "代理配置错误"
            appendLog("重试未开始：代理配置错误 - \(error.localizedDescription)")
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
        
        downloader.start()
    }

    private func queueMaxConcurrent() -> Int {
        let hasManhuaGui = downloader.taskItems.contains {
            $0.comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true
        }
        return hasManhuaGui ? 3 : 5
    }

    func clearLogs() {
        logLines = []
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
                self?.persistCodable(items, key: StorageKey.downloadQueue)
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
        proxyType = ProxyType(rawValue: defaults.string(forKey: StorageKey.proxyType) ?? "") ?? .none
        proxyHost = defaults.string(forKey: StorageKey.proxyHost) ?? ""
        proxyPort = defaults.string(forKey: StorageKey.proxyPort) ?? ""
        proxyUsername = defaults.string(forKey: StorageKey.proxyUsername) ?? ""
        proxyPassword = defaults.string(forKey: StorageKey.proxyPassword) ?? ""
        recentRecords = loadCodable([RecentComicRecord].self, key: StorageKey.recentRecords) ?? []
        comic = loadCodable(ComicInfo.self, key: StorageKey.lastComic)
        if let comic {
            selectedVolumeIDs = Set(comic.volumes.map(\.id))
        }
        if let restoredItems = loadCodable([DownloadTaskItem].self, key: StorageKey.downloadQueue), !restoredItems.isEmpty {
            downloader.restoreQueue(restoredItems)
        }
    }

    private func persistString(_ value: String, key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private func persistCodable<T: Codable>(_ value: T?, key: String) {
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

    private func applyProxyIfNeeded() throws {
        let proxy = try resolvedProxySettings()
        api.updateProxy(proxy)
        downloader.updateProxy(proxy)
        if let proxy {
            appendLog("代理：已启用 \(proxy.type.displayName)")
        } else {
            appendLog("代理：未启用")
        }
    }

    private func resolvedProxySettings() throws -> ProxySettings? {
        if proxyType == .none {
            return nil
        }

        let host = proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            throw ProxyValidationError.missingHost
        }

        guard let port = Int(proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else {
            throw ProxyValidationError.invalidPort
        }

        let username = proxyUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = proxyPassword.trimmingCharacters(in: .whitespacesAndNewlines)

        return ProxySettings(
            type: proxyType,
            host: host,
            port: port,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
    }

    private func normalizedSortValue(from text: String, fallback: Double) -> Double {
        guard let range = text.range(of: #"(\d+(?:\.\d+)?)"#, options: .regularExpression) else {
            return fallback
        }
        return Double(text[range]) ?? fallback
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
