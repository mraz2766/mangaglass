import Foundation
import UserNotifications

@MainActor
final class DownloadCoordinator: ObservableObject {
    @Published var taskItems: [DownloadTaskItem] = []
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var message = ""
    @Published var speedText = ""
    @Published var currentTaskTitle = ""

    private let api: CopyMangaAPI
    private let fileManager = FileManager.default
    private var session: URLSession
    private let pauseGate = PauseGate()
    private let requestPacer = RequestPacer(
        minDelayMS: 80,
        maxDelayMS: 180,
        maxPenaltyMS: 3000,
        throttleStepMS: 400,
        relaxStepMS: 50
    )
    private let manhuaGuiPacer = RequestPacer(
        minDelayMS: 220,
        maxDelayMS: 460,
        maxPenaltyMS: 7000,
        throttleStepMS: 700,
        relaxStepMS: 150
    )
    private var masterTask: Task<Void, Never>?
    private var logger: ((String) -> Void)?
    private var manhuaGuiPreferredHost: String?
    private var chapterExpectedPages: [UUID: Int] = [:]
    private var chapterCompletedPages: [UUID: Int] = [:]
    private var chapterResolvedPageCounts: Set<UUID> = []
    private var shouldUseGroupFolder = true
    private var sleepActivity: NSObjectProtocol?
    private var downloadStartTime: Date?
    private var lastSpeedSampleTime: Date?
    private var lastSpeedSampleCompletedPages = 0
    private var smoothedPagesPerSecond: Double?

    private let speedSampleInterval: TimeInterval = 1.0
    private let etaWarmupDuration: TimeInterval = 5
    private let etaMinimumCompletedPages = 8
    private let etaResolvedChapterThreshold = 3
    private let etaKnownPageThreshold = 60
    private let speedSmoothingFactor = 0.3

    init(api: CopyMangaAPI) {
        self.api = api
        self.session = ProxySessionFactory.makeSession(
            proxy: nil,
            timeoutRequest: 45,
            timeoutResource: 240,
            maxConnections: 24
        )
    }

    func updateProxy(_ proxy: ProxySettings?) {
        api.updateProxy(proxy)
        self.session = ProxySessionFactory.makeSession(
            proxy: proxy,
            timeoutRequest: 45,
            timeoutResource: 240,
            maxConnections: 24
        )
        log(proxy == nil ? "代理未启用" : "代理已更新")
    }

    func setLogger(_ logger: @escaping (String) -> Void) {
        self.logger = logger
    }

    func add(chapters: [ComicChapter], comic: ComicInfo, destination: URL, cookie: String?) {
        let existing = Set(taskItems.map(\.queueIdentity))
        let newItems = chapters.compactMap { chapter -> DownloadTaskItem? in
            let item = DownloadTaskItem(comic: comic, chapter: chapter, state: .queued, destination: destination, cookie: cookie)
            return existing.contains(item.queueIdentity) ? nil : item
        }
        taskItems.append(contentsOf: newItems)
        updateCurrentTaskTitle()
        if newItems.isEmpty {
            message = "所选章节已在队列中。"
            log("添加任务跳过：\(comic.name) 所选章节均已在队列中")
            return
        }
        message = "队列共 \(taskItems.count) 话。"
        log("添加任务：由 \(comic.name) 添加 \(newItems.count) 话，当前队列共 \(taskItems.count) 话")
    }

    func restoreQueue(_ items: [DownloadTaskItem]) {
        taskItems = items.map { item in
            var restored = item
            if restored.state == .running {
                restored.state = .queued
            }
            return restored
        }
        pruneProgressTracking()
        updateCurrentTaskTitle()
        updateProgress()
        if !taskItems.isEmpty {
            message = "已恢复上次未完成队列，共 \(taskItems.count) 话。"
        }
    }

    func resetQueueIfIdle() -> Bool {
        guard !isRunning else { return false }
        clearQueueState()
        return true
    }

    func clearCompletedTasks() -> Int {
        let before = taskItems.count
        taskItems = taskItems.filter { $0.state != .done }
        let removed = before - taskItems.count
        if removed > 0 {
            pruneProgressTracking()
            updateProgress()
            updateCurrentTaskTitle()
            if taskItems.isEmpty && !isRunning {
                message = ""
                speedText = ""
            } else {
                message = "已清空完成项 \(removed) 条。"
            }
        }
        return removed
    }

    private func clearQueueState() {
        taskItems = []
        progress = 0
        isPaused = false
        message = ""
        currentTaskTitle = ""
        manhuaGuiPreferredHost = nil
        chapterExpectedPages = [:]
        chapterCompletedPages = [:]
        chapterResolvedPageCounts = []
        resetSpeedEstimateState()
    }

    private func pruneProgressTracking() {
        let alive = Set(taskItems.map(\.id))
        chapterExpectedPages = chapterExpectedPages.filter { alive.contains($0.key) }
        chapterCompletedPages = chapterCompletedPages.filter { alive.contains($0.key) }
        chapterResolvedPageCounts = chapterResolvedPageCounts.intersection(alive)
    }

    func failedItems() -> [DownloadTaskItem] {
        taskItems.filter {
            switch $0.state {
            case .failed, .canceled: return true
            default: return false
            }
        }
    }

    func start(maxConcurrent: Int = 4) {
        guard !isRunning else {
            log("启动跳过：已有下载任务运行中")
            return
        }
        let pendingItems = taskItems.filter { $0.state == .queued }
        guard !pendingItems.isEmpty else {
            message = "队列中没有等待下载的章节。"
            log("启动失败：队列为空")
            return
        }

        isRunning = true
        isPaused = false
        message = "下载开始..."
        updateCurrentTaskTitle()
        log("下载开始：并发 \(maxConcurrent)")
        applySleepAssertion(active: true)
        
        if progress == 0 || downloadStartTime == nil {
            downloadStartTime = Date()
            resetSpeedEstimateState(placeholder: "计算中...")
        }

        let items = taskItems
        masterTask = Task { [weak self] in
            guard let self else { return }
            await self.pauseGate.resume()

            await withTaskGroup(of: Void.self) { group in
                var iterator = items.filter { $0.state == .queued }.makeIterator()
                
                for _ in 0..<maxConcurrent {
                    if let item = iterator.next() {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            if Task.isCancelled { return }
                            await self.run(item: item)
                        }
                    }
                }
                
                while let _ = await group.next() {
                    if Task.isCancelled { continue }
                    if let item = iterator.next() {
                        group.addTask { [weak self] in
                            guard let self else { return }
                            if Task.isCancelled { return }
                            await self.run(item: item)
                        }
                    }
                }
            }

            await MainActor.run {
                self.isRunning = false
                self.isPaused = false
                self.applySleepAssertion(active: false)
                self.resetSpeedEstimateState()
                self.updateCurrentTaskTitle()
                let failed = self.taskItems.filter {
                    switch $0.state {
                    case .failed, .canceled:
                        return true
                    default:
                        return false
                    }
                }.count
                self.message = failed == 0 ? "全部下载完成。" : "完成，失败/取消 \(failed) 话。"
                self.log(failed == 0 ? "下载全部完成" : "下载完成，失败/取消 \(failed) 话")
                self.notifyCompletion(failedCount: failed)
            }
        }
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        isPaused = true
        message = "已暂停。"
        speedText = "暂停"
        log("下载已暂停")
        applySleepAssertion(active: false)
        Task { await pauseGate.pause() }
    }

    func resume() {
        guard isRunning, isPaused else { return }
        isPaused = false
        message = "继续下载..."
        log("下载继续")
        applySleepAssertion(active: true)
        downloadStartTime = Date()
        resetSpeedEstimateState(placeholder: "计算中...")
        Task { await pauseGate.resume() }
    }

    func cancel() {
        guard isRunning else { return }
        message = "正在取消..."
        log("收到取消请求")
        masterTask?.cancel()
        Task { await pauseGate.resume() }

        for idx in taskItems.indices {
            switch taskItems[idx].state {
            case .queued, .running:
                taskItems[idx].state = .canceled
            default:
                break
            }
        }
        updateProgress()
        isRunning = false
        isPaused = false
        message = "已取消。"
        resetSpeedEstimateState()
        updateCurrentTaskTitle()
        applySleepAssertion(active: false)
        log("下载已取消")
    }

    private func run(item: DownloadTaskItem) async {
        if Task.isCancelled {
            await MainActor.run { self.setState(.canceled, for: item.id) }
            return
        }

        await pauseGate.waitIfPaused()
        if Task.isCancelled {
            await MainActor.run { self.setState(.canceled, for: item.id) }
            return
        }

        await MainActor.run {
            self.setState(.running, for: item.id)
            self.setChapterExpectedPages(1, for: item.id, resolved: false)
            self.setChapterCompletedPages(0, for: item.id)
            self.currentTaskTitle = "[\(item.chapter.volumeName)] \(item.chapter.displayName)"
            self.updateProgress()
        }
        log("开始章节：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName)")

        do {
            let imageURLs = try await api.fetchImageURLs(
                slug: item.comic.slug,
                chapterUUID: item.chapter.uuid,
                chapterName: item.chapter.displayName,
                site: item.comic.site,
                preferredPrefix: item.comic.apiPathPrefix,
                preferredBaseURL: item.comic.apiBaseURL,
                cookie: item.cookie
            )
            await MainActor.run {
                self.setChapterExpectedPages(max(1, imageURLs.count), for: item.id, resolved: true)
                self.setChapterCompletedPages(min(self.chapterCompletedPages[item.id] ?? 0, max(1, imageURLs.count)), for: item.id)
                self.updateProgress()
            }
            try await downloadChapter(item: item, imageURLs: imageURLs)
            await MainActor.run {
                self.setState(.done, for: item.id)
                self.markChapterFinished(for: item.id)
                self.updateProgress()
            }
            log("章节完成：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName)，共 \(imageURLs.count) 张")
        } catch is CancellationError {
            await MainActor.run {
                self.setState(.canceled, for: item.id)
                self.markChapterFinished(for: item.id)
                self.updateProgress()
            }
            log("章节取消：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName)")
        } catch {
            await MainActor.run {
                self.setState(.failed(error.localizedDescription), for: item.id)
                self.markChapterFinished(for: item.id)
                self.updateProgress()
            }
            log("章节失败：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName) - \(error.localizedDescription)")
        }
    }

    private func updateProgress() {
        let total = taskItems.reduce(0) { partial, item in
            partial + max(1, chapterExpectedPages[item.id] ?? 1)
        }

        let completedWeighted = taskItems.reduce(0.0) { partial, item in
            let expected = Double(max(1, chapterExpectedPages[item.id] ?? 1))
            let done = Double(min(Int(expected), max(0, chapterCompletedPages[item.id] ?? 0)))

            switch item.state {
            case .queued:
                return partial + 0
            case .running:
                // Show visible progress during "解析章节/获取图片列表" phase.
                let baseline = min(0.12 * expected, max(0, expected - 0.1))
                return partial + max(done, baseline)
            case .done, .failed, .canceled:
                return partial + expected
            }
        }

        progress = total == 0 ? 0 : min(1, completedWeighted / Double(total))
        updateCurrentTaskTitle()
        
        if isRunning && !isPaused, let start = downloadStartTime {
            let elapsed = Date().timeIntervalSince(start)
            let currentCompleted = taskItems.reduce(0) { sum, item in
                sum + (chapterCompletedPages[item.id] ?? 0)
            }
            updateSpeedEstimate(elapsed: elapsed, currentCompleted: currentCompleted)
        }
    }

    private func setState(_ state: DownloadTaskItem.State, for id: UUID) {
        guard let idx = taskItems.firstIndex(where: { $0.id == id }) else { return }
        taskItems[idx].state = state
    }

    private func downloadChapter(item: DownloadTaskItem, imageURLs: [URL]) async throws {
        let comicFolder = item.destination.appendingPathComponent(sanitize(item.comic.name), isDirectory: true)
        let groupName = canonicalGroupName(item.chapter.volumeName)
        
        // Calculate if we need group folder
        let selectedKinds = Set(taskItems.filter { $0.comic.slug == item.comic.slug }.map { canonicalGroupKey($0.chapter.volumeName) })
        let useGroupFolder = selectedKinds.count > 1

        let volumeFolder: URL
        if useGroupFolder {
            volumeFolder = comicFolder.appendingPathComponent(sanitize(groupName), isDirectory: true)
        } else {
            volumeFolder = comicFolder
        }
        let chapterFolder = volumeFolder.appendingPathComponent(sanitize(item.chapter.displayName), isDirectory: true)

        try createDirIfNeeded(comicFolder)
        try createDirIfNeeded(volumeFolder)
        try createDirIfNeeded(chapterFolder)

        // Intra-chapter concurrency speeds up image downloading drastically
        // while the request pacer prevents API burst spikes and mitigates bans.
        let isManhuaGui = item.comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true
        let maxImageConcurrent = isManhuaGui ? 2 : 3
        try await withThrowingTaskGroup(of: Void.self) { group in
            var iterator = imageURLs.enumerated().makeIterator()
            var completedCount = 0

            for _ in 0..<maxImageConcurrent {
                if let (index, imageURL) = iterator.next() {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try Task.checkCancellation()
                        await self.pauseGate.waitIfPaused()
                        try Task.checkCancellation()
                        try await self.downloadImage(
                            url: imageURL,
                            to: chapterFolder,
                            fileName: self.fileName(comic: item.comic.name, volume: groupName, chapter: item.chapter.displayName, index: index + 1),
                            site: item.comic.site,
                            cookie: item.cookie
                        )
                    }
                }
            }

            while let _ = try await group.next() {
                completedCount += 1
                await MainActor.run { [weak self] in
                    self?.increaseCompletedPage(for: item.id)
                    self?.updateProgress()
                }
                if completedCount % 20 == 0 || completedCount == imageURLs.count {
                    log("章节进度：[\(item.chapter.volumeName)] \(item.chapter.displayName) \(completedCount)/\(imageURLs.count)")
                }

                if let (index, imageURL) = iterator.next() {
                    group.addTask { [weak self] in
                        guard let self else { return }
                        try Task.checkCancellation()
                        await self.pauseGate.waitIfPaused()
                        try Task.checkCancellation()
                        try await self.downloadImage(
                            url: imageURL,
                            to: chapterFolder,
                            fileName: self.fileName(comic: item.comic.name, volume: groupName, chapter: item.chapter.displayName, index: index + 1),
                            site: item.comic.site,
                            cookie: item.cookie
                        )
                    }
                }
            }
        }
    }

    private func downloadImage(url: URL, to folder: URL, fileName: String, site: MangaSiteConfig, cookie: String?) async throws {
        let dst = folder.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: dst.path) {
            return
        }

        let candidates = candidateImageURLs(for: url, site: site)
        var lastError: Error?

        for (index, candidate) in candidates.enumerated() {
            do {
                try await retrying(times: 3) {
                    try Task.checkCancellation()
                    let pacer = self.pacer(for: site)
                    await pacer.waitTurn()
                    var req = URLRequest(url: candidate)
                    req.setValue(site.webBase.absoluteString, forHTTPHeaderField: "Referer")
                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                    if let cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        req.setValue(cookie, forHTTPHeaderField: "Cookie")
                    }
                    let (data, response) = try await self.session.data(for: req)
                    guard let http = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    guard (200...299).contains(http.statusCode) else {
                        if [403, 429, 503].contains(http.statusCode) {
                            await pacer.markThrottled()
                        }
                        throw DownloadRequestError.httpStatus(http.statusCode, retryAfter: self.retryAfter(from: http))
                    }
                    await pacer.markSuccess()
                    try data.write(to: dst, options: .atomic)
                    self.rememberPreferredHost(from: candidate, site: site)
                }
                return
            } catch let error as DownloadRequestError where error.statusCode == 404 && index + 1 < candidates.count {
                lastError = error
                log("图片 404，切换备用域名重试：\(candidate.host ?? "-") -> \(candidates[index + 1].host ?? "-")")
                continue
            } catch {
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    await self.pacer(for: site).markThrottled()
                    log("图片请求超时，自动降速后重试：\(candidate.absoluteString)")
                }
                throw error
            }
        }

        throw lastError ?? DownloadRequestError.httpStatus(404, retryAfter: nil)
    }

    private func fileName(comic: String, volume: String, chapter: String, index: Int) -> String {
        let cleanComic = sanitize(comic)
        let cleanVolume = sanitize(volume)
        let cleanChapter = sanitize(chapter)
        let prefix: String
        if cleanVolume.isEmpty || isDefaultVolumeName(cleanVolume) {
            prefix = "\(cleanComic)-\(cleanChapter)"
        } else {
            prefix = "\(cleanComic)-\(cleanVolume)-\(cleanChapter)"
        }
        let number = String(format: "%04d", index)
        return "\(prefix)-\(number).jpg"
    }

    private func createDirIfNeeded(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func sanitize(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let comps = value.components(separatedBy: forbidden)
        return comps.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func retrying(times: Int, operation: @escaping () async throws -> Void) async throws {
        var lastError: Error?
        var backoffMS = 450
        for attempt in 1...times {
            do {
                try await operation()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as DownloadRequestError {
                if error.statusCode == 404 {
                    throw error
                }
                lastError = error
                if attempt < times {
                    let serverWait = (error.retryAfter ?? 0) * 1000
                    let waitMS = max(Int(serverWait), backoffMS + Int.random(in: 120...420))
                    log("下载请求重试：第 \(attempt) 次失败（HTTP \(error.statusCode)），\(waitMS)ms 后重试")
                    try await Task.sleep(for: .milliseconds(waitMS))
                    backoffMS = min(backoffMS * 2, 5000)
                }
            } catch {
                lastError = error
                if attempt < times {
                    let timedOut = (error as? URLError)?.code == .timedOut
                    let extra = timedOut ? 900 : 0
                    log("下载请求重试：第 \(attempt) 次失败（\(error.localizedDescription)）")
                    try await Task.sleep(for: .milliseconds(backoffMS + Int.random(in: 80...220) + extra))
                    backoffMS = min(backoffMS * 2, 5000)
                }
            }
        }
        throw lastError ?? URLError(.cannotLoadFromNetwork)
    }

    private func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let raw = response.value(forHTTPHeaderField: "Retry-After")?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let seconds = TimeInterval(raw) {
            return max(0, seconds)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        if let date = formatter.date(from: raw) {
            return max(0, date.timeIntervalSinceNow)
        }
        return nil
    }

    private func log(_ message: String) {
        logger?("[下载] \(message)")
    }

    private func setChapterExpectedPages(_ count: Int, for id: UUID, resolved: Bool = false) {
        chapterExpectedPages[id] = max(1, count)
        if resolved {
            chapterResolvedPageCounts.insert(id)
        } else {
            chapterResolvedPageCounts.remove(id)
        }
    }

    private func setChapterCompletedPages(_ count: Int, for id: UUID) {
        chapterCompletedPages[id] = max(0, count)
    }

    private func increaseCompletedPage(for id: UUID) {
        chapterCompletedPages[id] = (chapterCompletedPages[id] ?? 0) + 1
    }

    private func markChapterFinished(for id: UUID) {
        let expected = max(1, chapterExpectedPages[id] ?? 1)
        chapterCompletedPages[id] = expected
    }

    private func resetSpeedEstimateState(placeholder: String = "") {
        speedText = placeholder
        lastSpeedSampleTime = nil
        lastSpeedSampleCompletedPages = 0
        smoothedPagesPerSecond = nil
    }

    private func updateSpeedEstimate(elapsed: TimeInterval, currentCompleted: Int) {
        let now = Date()
        if lastSpeedSampleTime == nil {
            lastSpeedSampleTime = now
            lastSpeedSampleCompletedPages = currentCompleted
        } else if let lastSampleTime = lastSpeedSampleTime,
                  now.timeIntervalSince(lastSampleTime) >= speedSampleInterval {
            let deltaTime = now.timeIntervalSince(lastSampleTime)
            let deltaPages = max(0, currentCompleted - lastSpeedSampleCompletedPages)
            if deltaTime > 0, deltaPages > 0 {
                let instantRate = Double(deltaPages) / deltaTime
                if let previous = smoothedPagesPerSecond {
                    smoothedPagesPerSecond = previous * (1 - speedSmoothingFactor) + instantRate * speedSmoothingFactor
                } else {
                    smoothedPagesPerSecond = instantRate
                }
            }
            lastSpeedSampleTime = now
            lastSpeedSampleCompletedPages = currentCompleted
        }

        guard let rate = smoothedPagesPerSecond, rate > 0 else {
            speedText = elapsed >= etaWarmupDuration ? "剩余时间预估中" : "计算中..."
            return
        }

        let (knownExpectedPages, completedKnownPages, unresolvedChapters, resolvedCount) = estimateInputs()

        guard elapsed >= etaWarmupDuration, currentCompleted >= etaMinimumCompletedPages else {
            speedText = String(format: "约 %.1f 页/秒 · 剩余时间预估中", rate)
            return
        }

        let canShowETA = unresolvedChapters == 0
            || resolvedCount >= etaResolvedChapterThreshold
            || knownExpectedPages >= etaKnownPageThreshold

        guard canShowETA, knownExpectedPages > 0 else {
            speedText = String(format: "约 %.1f 页/秒 · 剩余时间预估中", rate)
            return
        }

        let averagePagesPerResolvedChapter = Double(knownExpectedPages) / Double(max(1, resolvedCount))
        let estimatedTotalPages = Double(knownExpectedPages) + averagePagesPerResolvedChapter * Double(unresolvedChapters)
        let remainingPages = max(0, estimatedTotalPages - Double(completedKnownPages))
        let remaining = remainingPages / rate
        let remMin = Int(remaining) / 60
        let remSec = Int(remaining) % 60
        speedText = String(format: "约 %.1f 页/秒 · 剩余 %02d:%02d", rate, remMin, remSec)
    }

    private func estimateInputs() -> (knownExpectedPages: Int, completedKnownPages: Int, unresolvedChapters: Int, resolvedCount: Int) {
        let relevantItems = taskItems.filter { item in
            switch item.state {
            case .queued, .running, .done:
                return true
            case .failed, .canceled:
                return false
            }
        }

        let resolvedIDs = chapterResolvedPageCounts.intersection(Set(relevantItems.map(\.id)))
        let knownExpectedPages = resolvedIDs.reduce(0) { partial, id in
            partial + max(1, chapterExpectedPages[id] ?? 1)
        }
        let completedKnownPages = resolvedIDs.reduce(0) { partial, id in
            partial + min(max(1, chapterExpectedPages[id] ?? 1), max(0, chapterCompletedPages[id] ?? 0))
        }
        let unresolvedChapters = relevantItems.reduce(0) { partial, item in
            partial + (resolvedIDs.contains(item.id) ? 0 : 1)
        }
        return (knownExpectedPages, completedKnownPages, unresolvedChapters, resolvedIDs.count)
    }

    func countsSummary() -> (queued: Int, running: Int, failed: Int, done: Int) {
        taskItems.reduce(into: (queued: 0, running: 0, failed: 0, done: 0)) { partial, item in
            switch item.state {
            case .queued:
                partial.queued += 1
            case .running:
                partial.running += 1
            case .done:
                partial.done += 1
            case .failed, .canceled:
                partial.failed += 1
            }
        }
    }

    func failureSummary() -> [(reason: String, count: Int)] {
        let buckets = taskItems.reduce(into: [String: Int]()) { partial, item in
            let key: String
            switch item.state {
            case .failed(let reason):
                key = classifyFailure(reason)
            case .canceled:
                key = "已取消"
            default:
                return
            }
            partial[key, default: 0] += 1
        }
        return buckets
            .map { (reason: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count == rhs.count {
                    return lhs.reason < rhs.reason
                }
                return lhs.count > rhs.count
            }
    }

    private func classifyFailure(_ reason: String) -> String {
        let normalized = reason.lowercased()
        if normalized.contains("403") || normalized.contains("429") || normalized.contains("503") || normalized.contains("风控") {
            return "403/限流/风控"
        }
        if normalized.contains("timed out") || normalized.contains("timeout") || normalized.contains("超时") {
            return "网络超时"
        }
        if normalized.contains("图片") || normalized.contains("image") || normalized.contains("404") {
            return "图片资源异常"
        }
        return "其他错误"
    }

    private func updateCurrentTaskTitle() {
        if let running = taskItems.first(where: { $0.state == .running }) {
            currentTaskTitle = "[\(running.chapter.volumeName)] \(running.chapter.displayName)"
            return
        }
        if let queued = taskItems.first(where: { $0.state == .queued }) {
            currentTaskTitle = "待下载：[\(queued.chapter.volumeName)] \(queued.chapter.displayName)"
            return
        }
        currentTaskTitle = ""
    }

    private func notifyCompletion(failedCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = failedCount == 0 ? "MangaGlass 下载完成" : "MangaGlass 下载结束"
        content.body = failedCount == 0 ? "全部章节已完成下载。" : "下载完成，但有 \(failedCount) 话失败或被取消。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "mangaglass.download.complete.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func candidateImageURLs(for original: URL, site: MangaSiteConfig) -> [URL] {
        guard site.webBase.host?.lowercased().contains("manhuagui.com") == true else {
            return [original]
        }
        guard let host = original.host?.lowercased(), host.contains("hamreus.com") else {
            return [original]
        }

        let fallbackHosts = ["i.hamreus.com", "eu.hamreus.com", "us.hamreus.com", "us2.hamreus.com", "eu2.hamreus.com"]
        var urls: [URL] = []
        var seen: Set<String> = []

        if let preferred = manhuaGuiPreferredHost, let preferredURL = replacingHost(of: original, with: preferred) {
            urls.append(preferredURL)
            seen.insert(preferredURL.absoluteString)
        }

        if seen.insert(original.absoluteString).inserted {
            urls.append(original)
        }

        for fallback in fallbackHosts where fallback != host {
            guard let url = replacingHost(of: original, with: fallback) else { continue }
            if seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func replacingHost(of url: URL, with host: String) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.host = host
        return components.url
    }

    private func rememberPreferredHost(from url: URL, site: MangaSiteConfig) {
        guard site.webBase.host?.lowercased().contains("manhuagui.com") == true else { return }
        guard let host = url.host?.lowercased(), host.contains("hamreus.com") else { return }
        if manhuaGuiPreferredHost != host {
            manhuaGuiPreferredHost = host
            log("图片域名已锁定：\(host)")
        }
    }

    private func pacer(for site: MangaSiteConfig) -> RequestPacer {
        if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
            return manhuaGuiPacer
        }
        return requestPacer
    }
    
    private func applySleepAssertion(active: Bool) {
        if active && sleepActivity == nil {
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "MangaGlass Downloading")
        } else if !active && sleepActivity != nil {
            ProcessInfo.processInfo.endActivity(sleepActivity!)
            sleepActivity = nil
        }
    }
}

private struct DownloadRequestError: LocalizedError {
    let statusCode: Int
    let retryAfter: TimeInterval?

    static func httpStatus(_ statusCode: Int, retryAfter: TimeInterval?) -> DownloadRequestError {
        DownloadRequestError(statusCode: statusCode, retryAfter: retryAfter)
    }

    var errorDescription: String? {
        switch statusCode {
        case 401:
            return "图片请求失败（HTTP 401），请检查 Cookie 是否有效。"
        case 403:
            return "图片请求失败（HTTP 403），可能被站点拦截或需要登录。"
        case 404:
            return "图片请求失败（HTTP 404），图片地址可能已失效。"
        case 429:
            return "图片请求失败（HTTP 429），请求过于频繁。"
        case 500...599:
            return "图片请求失败（HTTP \(statusCode)），站点服务异常。"
        default:
            return "图片请求失败（HTTP \(statusCode)）。"
        }
    }

    var recoverySuggestion: String? {
        guard let retryAfter, retryAfter > 0 else { return nil }
        return "建议约 \(Int(retryAfter.rounded())) 秒后重试。"
    }
}

actor RequestPacer {
    private let minDelayMS: Int
    private let maxDelayMS: Int
    private let maxPenaltyMS: Int
    private let throttleStepMS: Int
    private let relaxStepMS: Int
    private var penaltyMS: Int = 0
    private var nextAllowedAt: Date = .distantPast

    init(minDelayMS: Int, maxDelayMS: Int, maxPenaltyMS: Int, throttleStepMS: Int, relaxStepMS: Int) {
        self.minDelayMS = minDelayMS
        self.maxDelayMS = max(maxDelayMS, minDelayMS)
        self.maxPenaltyMS = max(maxPenaltyMS, 0)
        self.throttleStepMS = max(1, throttleStepMS)
        self.relaxStepMS = max(1, relaxStepMS)
    }

    func waitTurn() async {
        let spacingMS = Int.random(in: minDelayMS...maxDelayMS) + penaltyMS
        let now = Date()
        let scheduled = max(now, nextAllowedAt)
        nextAllowedAt = scheduled.addingTimeInterval(Double(spacingMS) / 1000.0)
        let waitMS = Int(max(0, scheduled.timeIntervalSince(now) * 1000))
        if waitMS > 0 {
            try? await Task.sleep(for: .milliseconds(waitMS))
        }
    }

    func markThrottled() {
        penaltyMS = min(maxPenaltyMS, penaltyMS + throttleStepMS)
    }

    func markSuccess() {
        penaltyMS = max(0, penaltyMS - relaxStepMS)
    }
}



actor PauseGate {
    private var paused = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pause() {
        paused = true
    }

    func resume() {
        paused = false
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    func waitIfPaused() async {
        if !paused { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
