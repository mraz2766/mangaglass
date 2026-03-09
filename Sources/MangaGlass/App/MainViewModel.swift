import AppKit
import Foundation
import SwiftUI

enum SortDirection: String, CaseIterable, Identifiable {
    case ascending = "正序"
    case descending = "倒序"

    var id: String { rawValue }
}

@MainActor
final class MainViewModel: ObservableObject {
    @Published var inputURL = ""
    @Published var authCookie = ""
    @Published var proxyType: ProxyType = .none
    @Published var proxyHost = ""
    @Published var proxyPort = ""
    @Published var proxyUsername = ""
    @Published var proxyPassword = ""
    @Published var comic: ComicInfo?
    @Published var selectedVolumeIDs: Set<String> = []
    @Published var selectedChapterIDs: Set<String> = []
    @Published var chapterSortDirection: SortDirection = .ascending
    @Published var destinationFolder: URL = {
        let path = UserDefaults.standard.string(forKey: "lastDestinationPath") ?? "/Users/mraz/Downloads/漫画/"
        return URL(fileURLWithPath: path, isDirectory: true)
    }()
    @Published var statusText = "输入漫画链接后点击加载。"
    @Published var isLoading = false
    @Published var errorText = ""
    @Published var logLines: [String] = []
    @Published var showParseDone = false
    @Published var parseDoneText = ""
    @Published var parseLiveText = ""

    let api: CopyMangaAPI
    let downloader: DownloadCoordinator
    private var lastSelectedChapterID: String?
    private var loadingComicKey: String?

    init() {
        let api = CopyMangaAPI()
        self.api = api
        self.downloader = DownloadCoordinator(api: api)
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
        appendLog("解析器版本：2026-03-09-r6")
    }

    var displayVolumes: [ComicVolume] {
        guard let comic else { return [] }
        return comic.volumes
    }

    var visibleChapters: [ComicChapter] {
        let chapters = displayVolumes
            .filter { selectedVolumeIDs.contains($0.id) }
            .flatMap(\.chapters)
        let sorted = chapters.sorted { lhs, rhs in
            let left = normalizedSortValue(from: lhs.displayName, fallback: lhs.order)
            let right = normalizedSortValue(from: rhs.displayName, fallback: rhs.order)
            if left == right {
                return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
            }
            return left < right
        }
        if chapterSortDirection == .ascending {
            return sorted
        }
        return sorted.reversed()
    }

    func loadComic() {
        guard !isLoading else { return }
        isLoading = true
        showParseDone = false
        parseDoneText = ""
        parseLiveText = "阶段 1/3：读取页面结构..."
        errorText = ""
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
            UserDefaults.standard.set(url.path, forKey: "lastDestinationPath")
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
