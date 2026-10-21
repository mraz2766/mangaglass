import Foundation
import UserNotifications

@MainActor
final class DownloadCoordinator: ObservableObject {
    struct ComicDurationSummary: Identifiable, Equatable {
        let id: String
        let comicName: String
        let totalTasks: Int
        let completedTasks: Int
        let failedOrCanceledTasks: Int
        let isRunning: Bool
        let startedAt: Date?
        let finishedAt: Date?
        let elapsedSeconds: TimeInterval

        var durationText: String {
            DownloadCoordinator.formatDuration(elapsedSeconds)
        }
    }

    struct ManhuaGuiSoftCircuit: Equatable {
        let statusCode: Int
        let host: String
        let chapterTitle: String
        let triggeredAt: Date
        /// Set for rate-limit cooldowns (connection resets): the moment the cooldown ends.
        var autoResumeAt: Date? = nil
        /// False once the user cancels auto-continue; the cooldown still runs, then waits for a manual continue.
        var autoResumeEnabled = true

        var isCooldown: Bool { autoResumeAt != nil }

        var remainingSeconds: Int {
            max(0, Int(ceil((autoResumeAt ?? Date()).timeIntervalSinceNow)))
        }

        var message: String {
            if isCooldown {
                if remainingSeconds == 0 { return "漫画柜冷却已结束，可以继续下载。" }
                return autoResumeEnabled
                    ? "漫画柜正在限流（连接被站点断开），已暂停漫画柜请求，约 \(remainingSeconds) 秒后自动继续。"
                    : "漫画柜冷却中，约 \(remainingSeconds) 秒后可继续（已取消自动继续）。"
            }
            return "漫画柜疑似触发风控（HTTP \(statusCode)，\(host)）。请先打开网页确认是否可访问，再决定是否继续下载。"
        }
    }

    struct CopySoftCircuit: Equatable {
        let reason: String
        let host: String
        let chapterTitle: String
        let triggeredAt: Date
        let cooldownUntil: Date
        var autoResumeEnabled = true

        var remainingSeconds: Int {
            max(0, Int(ceil(cooldownUntil.timeIntervalSinceNow)))
        }

        var message: String {
            if remainingSeconds == 0 { return "拷贝漫画冷却已结束，可以继续下载。" }
            return autoResumeEnabled
                ? "拷贝漫画连续返回异常目录或页面，已暂停后续请求，约 \(remainingSeconds) 秒后自动继续。"
                : "拷贝漫画冷却中，约 \(remainingSeconds) 秒后可继续（已取消自动继续）。"
        }
    }

    private struct ChapterFailureTracker {
        var notFound = 0
        var throttled = 0
        var timeout = 0

        mutating func reset() {
            notFound = 0
            throttled = 0
            timeout = 0
        }
    }

    private enum ImageFailureKind {
        case notFound
        case throttled
        case timeout
    }

    private struct DownloadProtectionState {
        private let chapter404StopThreshold: Int
        private let chapterThrottleStopThreshold: Int
        private let chapterTimeoutStopThreshold: Int
        private let hostThrottleCooldownThreshold: Int
        private let hostTimeoutCooldownThreshold: Int
        private let hostThrottleCooldownSeconds: TimeInterval
        private let hostTimeoutCooldownSeconds: TimeInterval

        private var chapterFailureTrackers: [UUID: ChapterFailureTracker] = [:]
        private var hostThrottleFailures: [String: Int] = [:]
        private var hostTimeoutFailures: [String: Int] = [:]
        private var hostCooldownUntil: [String: Date] = [:]

        init(
            chapter404StopThreshold: Int,
            chapterThrottleStopThreshold: Int,
            chapterTimeoutStopThreshold: Int,
            hostThrottleCooldownThreshold: Int,
            hostTimeoutCooldownThreshold: Int,
            hostThrottleCooldownSeconds: TimeInterval,
            hostTimeoutCooldownSeconds: TimeInterval
        ) {
            self.chapter404StopThreshold = chapter404StopThreshold
            self.chapterThrottleStopThreshold = chapterThrottleStopThreshold
            self.chapterTimeoutStopThreshold = chapterTimeoutStopThreshold
            self.hostThrottleCooldownThreshold = hostThrottleCooldownThreshold
            self.hostTimeoutCooldownThreshold = hostTimeoutCooldownThreshold
            self.hostThrottleCooldownSeconds = hostThrottleCooldownSeconds
            self.hostTimeoutCooldownSeconds = hostTimeoutCooldownSeconds
        }

        mutating func clear() {
            chapterFailureTrackers = [:]
            hostThrottleFailures = [:]
            hostTimeoutFailures = [:]
            hostCooldownUntil = [:]
        }

        mutating func prune(aliveIDs: Set<UUID>) {
            chapterFailureTrackers = chapterFailureTrackers.filter { aliveIDs.contains($0.key) }
        }

        mutating func reset(itemID: UUID) {
            chapterFailureTrackers.removeValue(forKey: itemID)
        }

        mutating func noteSuccess(itemID: UUID, host: String?) {
            if var tracker = chapterFailureTrackers[itemID] {
                tracker.reset()
                chapterFailureTrackers[itemID] = tracker
            }
            guard let host else { return }
            hostThrottleFailures[host] = 0
            hostTimeoutFailures[host] = 0
            if let until = hostCooldownUntil[host], until <= Date() {
                hostCooldownUntil.removeValue(forKey: host)
            }
        }

        mutating func noteFailure(itemID: UUID, host: String?, kind: ImageFailureKind) -> (message: String?, cooldownHost: String?) {
            var tracker = chapterFailureTrackers[itemID] ?? ChapterFailureTracker()
            switch kind {
            case .notFound:
                tracker.notFound += 1
                tracker.throttled = 0
                tracker.timeout = 0
                chapterFailureTrackers[itemID] = tracker
                if tracker.notFound >= chapter404StopThreshold {
                    return ("该章节连续 404，已停止继续请求。", nil)
                }
            case .throttled:
                tracker.throttled += 1
                tracker.notFound = 0
                tracker.timeout = 0
                chapterFailureTrackers[itemID] = tracker
                if let host {
                    let count = (hostThrottleFailures[host] ?? 0) + 1
                    hostThrottleFailures[host] = count
                    if count >= hostThrottleCooldownThreshold {
                        hostCooldownUntil[host] = Date().addingTimeInterval(hostThrottleCooldownSeconds)
                        hostThrottleFailures[host] = 0
                        if tracker.throttled >= chapterThrottleStopThreshold {
                            return ("该章节连续触发风控，已停止继续请求。", host)
                        }
                        return (nil, host)
                    }
                }
                if tracker.throttled >= chapterThrottleStopThreshold {
                    return ("该章节连续触发风控，已停止继续请求。", nil)
                }
            case .timeout:
                tracker.timeout += 1
                tracker.notFound = 0
                tracker.throttled = 0
                chapterFailureTrackers[itemID] = tracker
                if let host {
                    let count = (hostTimeoutFailures[host] ?? 0) + 1
                    hostTimeoutFailures[host] = count
                    if count >= hostTimeoutCooldownThreshold {
                        hostCooldownUntil[host] = Date().addingTimeInterval(hostTimeoutCooldownSeconds)
                        hostTimeoutFailures[host] = 0
                        if tracker.timeout >= chapterTimeoutStopThreshold {
                            return ("该章节连续超时，已停止继续请求。", host)
                        }
                        return (nil, host)
                    }
                }
                if tracker.timeout >= chapterTimeoutStopThreshold {
                    return ("该章节连续超时，已停止继续请求。", nil)
                }
            }
            return (nil, nil)
        }

        mutating func cooldownRemaining(for host: String?) -> TimeInterval? {
            guard let host else { return nil }
            guard let until = hostCooldownUntil[host] else { return nil }
            let remaining = until.timeIntervalSinceNow
            if remaining > 0 {
                return remaining
            }
            hostCooldownUntil.removeValue(forKey: host)
            return nil
        }
    }

    @Published var taskItems: [DownloadTaskItem] = [] {
        didSet {
            cachedCounts = nil
            cachedProgressSummary = nil
        }
    }
    @Published var progress: Double = 0
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var message = ""
    @Published var speedText = ""
    @Published var currentTaskTitle = ""
    @Published var lastCompletedOutputURL: URL?
    @Published var manhuaGuiSoftCircuit: ManhuaGuiSoftCircuit?
    @Published var copySoftCircuit: CopySoftCircuit?

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
        minDelayMS: 240,
        maxDelayMS: 460,
        maxPenaltyMS: 10000,
        throttleStepMS: 1000,
        relaxStepMS: 100
    )
    private let copyHostBudget = HostRequestBudget()
    private var masterTask: Task<Void, Never>?
    private var logger: ((String) -> Void)?
    private var manhuaGuiPreferredHost: String?
    private var chapterExpectedPages: [UUID: Int] = [:] {
        didSet { cachedProgressSummary = nil }
    }
    private var chapterCompletedPages: [UUID: Int] = [:] {
        didSet { cachedProgressSummary = nil }
    }
    /// Views read these on every progress tick; recompute only after the inputs change.
    private var cachedCounts: (queued: Int, running: Int, failed: Int, done: Int)?
    private var cachedProgressSummary: (completedPages: Int, totalPages: Int, completedTasks: Int, totalTasks: Int, pagesKnown: Bool)?
    private var chapterResolvedPageCounts: Set<UUID> = []
    private var explicitlyCanceledItemIDs: Set<UUID> = []
    private var shouldUseGroupFolder = true
    private var sleepActivity: NSObjectProtocol?
    private var downloadStartTime: Date?
    /// Pages and bytes actually fetched from the network this run (reused files don't count),
    /// so speed reflects real transfer and never resets when a chapter finishes.
    private(set) var networkPagesThisRun = 0
    private var networkBytesThisRun = 0
    private var lastNetworkPageAt: Date?
    private var lastSpeedSampleTime: Date?
    private var lastSpeedSamplePages = 0
    private var lastSpeedSampleBytes = 0
    private var smoothedPagesPerSecond: Double?
    private var smoothedBytesPerSecond: Double?
    private var lastSpeedDiagnosticTime: Date?
    private var speedTicker: Task<Void, Never>?
    /// Copy comics whose c1500x images keep returning 404; they go straight to standard images.
    private var copyHighResMisses: [String: Int] = [:]
    private var copyHighResUnavailable: Set<String> = []
    private let copyHighResMissThreshold = 3
    /// Pages per finished chapter that fell back to standard quality.
    private var standardQualityPages: [UUID: Int] = [:]
    private var currentRunID = UUID()
    private var progressRefreshTask: Task<Void, Never>?
    private var isCancelling = false
    private let speedSampleInterval: TimeInterval = 1.0
    private let manhuaGuiSpeedSampleInterval: TimeInterval = 2.4
    private let etaWarmupDuration: TimeInterval = 5
    private let etaMinimumCompletedPages = 8
    private let etaResolvedChapterThreshold = 3
    private let etaKnownPageThreshold = 60
    private let speedSmoothingFactor = 0.3
    private let manhuaGuiSpeedSmoothingFactor = 0.18
    private let stallThreshold: TimeInterval = 5
    private let chapter404StopThreshold = 4
    private let chapterThrottleStopThreshold = 3
    private let chapterTimeoutStopThreshold = 3
    private let hostThrottleCooldownThreshold = 3
    private let hostTimeoutCooldownThreshold = 3
    private let hostThrottleCooldownSeconds: TimeInterval = 90
    private let hostTimeoutCooldownSeconds: TimeInterval = 45
    private var protectionState = DownloadProtectionState(
        chapter404StopThreshold: 4,
        chapterThrottleStopThreshold: 3,
        chapterTimeoutStopThreshold: 3,
        hostThrottleCooldownThreshold: 3,
        hostTimeoutCooldownThreshold: 3,
        hostThrottleCooldownSeconds: 90,
        hostTimeoutCooldownSeconds: 45
    )
    private var copySuspiciousChapterFailures = 0
    private var copyRecoveryProbeActive = false
    private var copyRecoverySuccessfulChapters = 0
    private(set) var pacingMode: DownloadPacingMode = .smart
    private var pacingStates: [SiteFamily: AdaptivePacingState] = [:]
    private var connectionResetStreak: [SiteFamily: Int] = [:]
    /// Chapters that failed on a connection reset; requeued when a cooldown starts.
    private var connectionResetFailedIDs: Set<UUID> = []
    private var autoResumeTask: Task<Void, Never>?

    init(api: CopyMangaAPI) {
        self.api = api
        self.session = ProxySessionFactory.makeSession(
            timeoutRequest: 45,
            timeoutResource: 240,
            maxConnections: 24
        )
    }

    func setLogger(_ logger: @escaping (String) -> Void) {
        self.logger = logger
    }

    func configure(pacingMode: DownloadPacingMode) {
        self.pacingMode = pacingMode
        pacingStates = [:]
        let manhuaGuiSpacing = SitePacing.make(mode: pacingMode, family: .manhuaGui).imageSpacingMS
        let otherSpacing = SitePacing.make(mode: pacingMode, family: .other).imageSpacingMS
        Task {
            await manhuaGuiPacer.setDelayRange(manhuaGuiSpacing)
            await requestPacer.setDelayRange(otherSpacing)
        }
    }

    func pacingState(for family: SiteFamily) -> AdaptivePacingState {
        if let state = pacingStates[family] { return state }
        let state = AdaptivePacingState(pacing: .make(mode: pacingMode, family: family))
        pacingStates[family] = state
        return state
    }

    /// The most conservative chapter concurrency among sites that still have work.
    private func desiredChapterConcurrency() -> Int {
        let families = Set(taskItems.filter { $0.state == .queued || $0.state == .running }.map { SiteFamily.of($0.comic.site) })
        return families.map { pacingState(for: $0).chapterConcurrency }.min() ?? 1
    }

    private func notePacingSuccess(_ site: MangaSiteConfig) {
        let family = SiteFamily.of(site)
        var state = pacingState(for: family)
        if state.noteSuccess() {
            let images = family == .copy ? "，图片并发 \(state.globalImageConcurrency)" : ""
            log("节奏：\(family.title) 运行顺利，提速到章节并发 \(state.chapterConcurrency)\(images)")
        }
        pacingStates[family] = state
    }

    private func notePacingThrottle(_ site: MangaSiteConfig, reason: String) {
        let family = SiteFamily.of(site)
        var state = pacingState(for: family)
        let dropped = state.noteThrottle()
        pacingStates[family] = state
        if dropped {
            log("节奏：\(family.title) 出现限流信号（\(reason)），降到章节并发 \(state.chapterConcurrency)")
        }
    }

    /// Connection-level failures sites use to rate-limit (TLS reset, dropped connection, timeout).
    nonisolated static func isConnectionThrottle(_ error: Error) -> Bool {
        if case CopyMangaError.connectionReset = error { return true }
        if let urlError = error as? URLError {
            return [.secureConnectionFailed, .networkConnectionLost, .cannotConnectToHost, .timedOut].contains(urlError.code)
        }
        return false
    }

    /// Waits for this chapter's start slot: chapters of one site start `chapterGap` apart,
    /// with a longer rest every `restEveryChapters` chapters.
    private func waitForChapterTurn(_ item: DownloadTaskItem) async throws {
        let family = SiteFamily.of(item.comic.site)
        var state = pacingState(for: family)
        let gap = Double(Int.random(in: state.pacing.chapterGapMS)) / 1000
        let rest = Double(Int.random(in: state.pacing.restSeconds))
        let slot = state.reserveChapterSlot(now: Date(), gap: gap, rest: rest)
        pacingStates[family] = state
        if slot.rested {
            log("节奏：\(family.title) 已连续开始 \(state.pacing.restEveryChapters) 话，休息约 \(Int(rest)) 秒")
        }
        if slot.wait > 0.05 {
            try await Task.sleep(for: .milliseconds(Int(slot.wait * 1000)))
        }
        try Task.checkCancellation()
        await pauseGate.waitIfPaused()
    }

    private func handleConnectionThrottle(for item: DownloadTaskItem, error: Error) {
        let family = SiteFamily.of(item.comic.site)
        notePacingThrottle(item.comic.site, reason: "连接被断开")
        connectionResetFailedIDs.insert(item.id)
        let streak = (connectionResetStreak[family] ?? 0) + 1
        connectionResetStreak[family] = streak
        guard streak >= 2 else { return }
        let cooldown = pacingState(for: family).pacing.throttleCooldown
        switch family {
        case .manhuaGui:
            guard manhuaGuiSoftCircuit == nil else { return }
            startManhuaGuiCooldown(after: item, cooldown: cooldown)
        case .other:
            var state = pacingState(for: family)
            state.postpone(until: Date().addingTimeInterval(cooldown))
            pacingStates[family] = state
            log("节奏：\(family.title) 连续 \(streak) 次连接被断开，暂停新章节约 \(Int(cooldown)) 秒")
        case .copy:
            break  // handled by the Copy soft circuit (`copyFailureOutcome`)
        }
    }

    private func startManhuaGuiCooldown(after item: DownloadTaskItem, cooldown: TimeInterval) {
        let resumeAt = Date().addingTimeInterval(cooldown)
        manhuaGuiSoftCircuit = ManhuaGuiSoftCircuit(
            statusCode: 0,
            host: item.comic.site.webBase.host?.lowercased() ?? "-",
            chapterTitle: "[\(item.chapter.volumeName)] \(item.chapter.displayName)",
            triggeredAt: Date(),
            autoResumeAt: resumeAt
        )
        // Chapters that only failed because of the throttle go back in line instead of staying failed.
        taskItems = taskItems.map { existing in
            var updated = existing
            guard isManhuaGuiItem(updated) else { return updated }
            if updated.state == .running { updated.state = .queued }
            if case .failed = updated.state, connectionResetFailedIDs.contains(updated.id) {
                updated.state = .queued
                updated.finishedAt = nil
            }
            return updated
        }
        connectionResetFailedIDs = connectionResetFailedIDs.filter { id in
            !taskItems.contains { $0.id == id && $0.state == .queued }
        }
        var state = pacingState(for: .manhuaGui)
        state.postpone(until: resumeAt)
        pacingStates[.manhuaGui] = state
        connectionResetStreak[.manhuaGui] = 0
        updateProgress()
        updateCurrentTaskTitle()
        message = manhuaGuiSoftCircuit?.message ?? message
        log("漫画柜限流：连续连接被断开，暂停漫画柜请求 \(Int(cooldown)) 秒，相关章节已回到队列，到点自动继续")
        scheduleAutoResume(after: cooldown)
    }

    /// Stops the automatic continue but keeps the cooldown clock running; when it ends the
    /// queue waits for a manual continue.
    func cancelAutoResume() {
        autoResumeTask?.cancel()
        autoResumeTask = nil
        manhuaGuiSoftCircuit?.autoResumeEnabled = false
        copySoftCircuit?.autoResumeEnabled = false
        message = manhuaGuiSoftCircuit?.message ?? copySoftCircuit?.message ?? message
        log("已取消冷却后自动继续，冷却计时仍在后台进行")
    }

    func restoreAutoResume() {
        manhuaGuiSoftCircuit?.autoResumeEnabled = true
        copySoftCircuit?.autoResumeEnabled = true
        let remaining = max(manhuaGuiSoftCircuit?.remainingSeconds ?? 0, copySoftCircuit?.remainingSeconds ?? 0)
        scheduleAutoResume(after: TimeInterval(remaining) + 1)
        message = manhuaGuiSoftCircuit?.message ?? copySoftCircuit?.message ?? message
        log("已恢复冷却后自动继续，约 \(remaining) 秒后继续")
    }

    /// Continue Copy downloads before its cooldown has ended (the user confirmed the risk).
    func forceClearCopySoftCircuit() {
        guard let circuit = copySoftCircuit else { return }
        copySoftCircuit = nil
        copySuspiciousChapterFailures = 0
        copyRecoveryProbeActive = true
        copyRecoverySuccessfulChapters = 0
        Task { await copyHostBudget.resetPenalty(key: Self.copyBudgetKey) }
        log("用户在冷却结束前继续拷贝漫画下载（剩余约 \(circuit.remainingSeconds) 秒），以单话探测速度恢复")
        updateCurrentTaskTitle()
    }

    /// Clears an expired cooldown and continues the queue without user action.
    private func scheduleAutoResume(after seconds: TimeInterval) {
        autoResumeTask?.cancel()
        autoResumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, seconds)))
            guard let self, !Task.isCancelled else { return }
            self.autoResumeTask = nil
            var cleared = false
            if self.manhuaGuiSoftCircuit?.isCooldown == true, self.manhuaGuiSoftCircuit?.autoResumeEnabled == true {
                self.manhuaGuiSoftCircuit = nil
                cleared = true
            }
            if self.copySoftCircuit?.autoResumeEnabled == true, self.clearCopySoftCircuitIfReady() {
                cleared = true
            }
            guard cleared else { return }
            self.log("冷却结束，自动继续下载")
            if self.isRunning {
                self.message = "冷却结束，继续下载。"
            } else if self.hasEligibleQueuedItems() {
                self.start()
            }
        }
    }

    @discardableResult
    func add(
        chapters: [ComicChapter],
        comic: ComicInfo,
        destination: URL,
        cookie: String?,
        existingFilePolicy: ExistingFilePolicy = .keepExisting,
        usesGroupFolder: Bool? = nil,
        resolvedImageURLsByChapterID: [String: [URL]] = [:],
        copyImageQuality: CopyImageQuality = .high,
        replacingFinished: Bool = false
    ) -> Int {
        if replacingFinished {
            let requestedIdentities = Set(chapters.map { chapter in
                DownloadTaskItem(
                    comic: comic,
                    chapter: chapter,
                    state: .queued,
                    destination: destination,
                    cookie: cookie
                ).queueIdentity
            })
            taskItems.removeAll { item in
                guard requestedIdentities.contains(item.queueIdentity) else { return false }
                return item.state != .queued && item.state != .running
            }
        }
        let existing = Set(taskItems.map(\.queueIdentity))
        let newItems = chapters.compactMap { chapter -> DownloadTaskItem? in
            let item = DownloadTaskItem(
                comic: comic,
                chapter: chapter,
                state: .queued,
                destination: destination,
                cookie: cookie,
                existingFilePolicy: existingFilePolicy,
                usesGroupFolder: usesGroupFolder,
                resolvedImageURLs: resolvedImageURLsByChapterID[chapter.id],
                copyImageQuality: copyImageQuality
            )
            return existing.contains(item.queueIdentity) ? nil : item
        }
        taskItems.append(contentsOf: newItems)
        updateCurrentTaskTitle()
        if newItems.isEmpty {
            message = "所选章节已在队列中。"
            log("添加任务跳过：\(comic.name) 所选章节均已在队列中")
            return 0
        }
        if isRunning {
            message = "已加入 \(newItems.count) 话，当前下载会自动继续。"
        } else {
            message = "队列共 \(taskItems.count) 话。"
        }
        log("添加任务：由 \(comic.name) 添加 \(newItems.count) 话，当前队列共 \(taskItems.count) 话")
        return newItems.count
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
        isRunning = false
        isPaused = false
        message = ""
        speedText = ""
        currentTaskTitle = ""
        lastCompletedOutputURL = nil
        manhuaGuiSoftCircuit = nil
        copySoftCircuit = nil
        manhuaGuiPreferredHost = nil
        chapterExpectedPages = [:]
        chapterCompletedPages = [:]
        chapterResolvedPageCounts = []
        explicitlyCanceledItemIDs = []
        progressRefreshTask?.cancel()
        progressRefreshTask = nil
        isCancelling = false
        stopSpeedTicker()
        autoResumeTask?.cancel()
        autoResumeTask = nil
        connectionResetStreak = [:]
        connectionResetFailedIDs = []
        protectionState.clear()
        copySuspiciousChapterFailures = 0
        copyRecoveryProbeActive = false
        copyRecoverySuccessfulChapters = 0
        resetSpeedEstimateState()
    }

    private func pruneProgressTracking() {
        let alive = Set(taskItems.map(\.id))
        chapterExpectedPages = chapterExpectedPages.filter { alive.contains($0.key) }
        chapterCompletedPages = chapterCompletedPages.filter { alive.contains($0.key) }
        chapterResolvedPageCounts = chapterResolvedPageCounts.intersection(alive)
        protectionState.prune(aliveIDs: alive)
    }

    func failedItems() -> [DownloadTaskItem] {
        taskItems.filter {
            switch $0.state {
            case .failed, .canceled: return true
            default: return false
            }
        }
    }

    /// `maxConcurrent` overrides the pacing-derived chapter concurrency (tests only).
    func start(maxConcurrent: Int? = nil) {
        guard !isRunning else {
            if hasEligibleQueuedItems() {
                message = "已加入队列，当前下载会自动继续。"
                log("启动跳过：已有下载任务运行中，新增排队项将自动接续")
            } else {
                log("启动跳过：已有下载任务运行中")
            }
            return
        }
        let pendingItems = taskItems.filter { isEligibleQueuedItem($0) }
        guard !pendingItems.isEmpty else {
            if manhuaGuiSoftCircuit != nil, hasQueuedManhuaGuiItems() {
                message = "漫画柜疑似触发风控，请确认后再继续下载。"
                log("启动暂停：漫画柜软熔断中，等待用户确认")
            } else if let circuit = copySoftCircuit, hasQueuedCopyItems() {
                message = circuit.message
                log("启动暂停：拷贝漫画软熔断冷却中")
            } else {
                message = "队列中没有等待下载的章节。"
                log("启动失败：队列为空")
            }
            return
        }

        isRunning = true
        isPaused = false
        isCancelling = false
        currentRunID = UUID()
        message = "下载开始..."
        updateCurrentTaskTitle()
        let effectiveMaxConcurrent = copyRecoveryProbeActive ? 1 : (maxConcurrent ?? desiredChapterConcurrency())
        log("下载开始：节奏「\(pacingMode.title)」，章节并发 \(effectiveMaxConcurrent)")
        for family in Set(pendingItems.map { SiteFamily.of($0.comic.site) }).sorted(by: { $0.rawValue < $1.rawValue }) {
            let state = pacingState(for: family)
            let pacing = state.pacing
            let images = family == .copy ? "全局图片并发 \(state.globalImageConcurrency)" : "每话图片并发 \(pacing.imageConcurrencyPerChapter)"
            let rest = pacing.restEveryChapters > 0 ? "，每 \(pacing.restEveryChapters) 话休息 \(pacing.restSeconds.lowerBound)–\(pacing.restSeconds.upperBound)s" : ""
            log("节奏：\(family.title) 章节并发 \(state.chapterConcurrency)，\(images)，图片间隔 \(pacing.imageSpacingMS.lowerBound)–\(pacing.imageSpacingMS.upperBound)ms，章节间隔 \(pacing.chapterGapMS.lowerBound / 1000)–\(Double(pacing.chapterGapMS.upperBound) / 1000)s\(rest)")
        }
        applySleepAssertion(active: true)
        // Speed and ETA describe this run only.
        downloadStartTime = Date()
        resetSpeedEstimateState(placeholder: "计算中...")
        startSpeedTicker()

        let runID = currentRunID
        masterTask = Task { [weak self] in
            guard let self else { return }
            await self.pauseGate.resume()

            await withTaskGroup(of: UUID?.self) { group in
                var inFlightItemIDs: Set<UUID> = []

                while inFlightItemIDs.count < effectiveMaxConcurrent {
                    guard !Task.isCancelled else { break }
                    if let item = await MainActor.run(body: {
                        self.nextQueuedItem(excluding: inFlightItemIDs)
                    }) {
                        inFlightItemIDs.insert(item.id)
                        group.addTask { [weak self] in
                            guard let self else { return nil }
                            if Task.isCancelled { return item.id }
                            await self.run(item: item, runID: runID)
                            return item.id
                        }
                    } else {
                        break
                    }
                }

                while let finishedID = await group.next() {
                    if let finishedID {
                        inFlightItemIDs.remove(finishedID)
                    }
                    if Task.isCancelled { continue }
                    let desiredConcurrency = await MainActor.run {
                        self.copyRecoveryProbeActive ? 1 : (maxConcurrent ?? self.desiredChapterConcurrency())
                    }
                    while inFlightItemIDs.count < desiredConcurrency {
                        if let item = await MainActor.run(body: {
                            self.nextQueuedItem(excluding: inFlightItemIDs)
                        }) {
                            inFlightItemIDs.insert(item.id)
                            group.addTask { [weak self] in
                                guard let self else { return nil }
                                if Task.isCancelled { return item.id }
                                await self.run(item: item, runID: runID)
                                return item.id
                            }
                        } else {
                            break
                        }
                    }
                }
            }

            await MainActor.run {
                guard self.currentRunID == runID else { return }
                self.isRunning = false
                self.isPaused = false
                self.isCancelling = false
                self.applySleepAssertion(active: false)
                self.stopSpeedTicker()
                self.resetSpeedEstimateState()
                self.updateCurrentTaskTitle()
                if let circuit = self.manhuaGuiSoftCircuit {
                    self.message = circuit.message
                    self.log("下载批次因 ManhuaGui 软熔断暂停：HTTP \(circuit.statusCode) host=\(circuit.host)")
                    return
                }
                if let circuit = self.copySoftCircuit {
                    self.message = circuit.message
                    self.log("下载批次因拷贝漫画软熔断暂停：\(circuit.reason) host=\(circuit.host)")
                    return
                }
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
        isCancelling = true
        currentRunID = UUID()
        masterTask?.cancel()
        Task { await pauseGate.resume() }
        Task { await copyHostBudget.wakeAll() }
        autoResumeTask?.cancel()
        autoResumeTask = nil
        progressRefreshTask?.cancel()
        progressRefreshTask = nil

        let canceledIDs = Set(taskItems.compactMap { item -> UUID? in
            switch item.state {
            case .queued, .running:
                return item.id
            default:
                return nil
            }
        })
        explicitlyCanceledItemIDs.formUnion(canceledIDs)
        taskItems = taskItems.map { item in
            var updated = item
            switch updated.state {
            case .queued, .running:
                updated.state = .canceled
            default:
                break
            }
            return updated
        }
        isRunning = false
        isPaused = false
        message = "已取消。"
        stopSpeedTicker()
        resetSpeedEstimateState()
        updateProgress()
        updateCurrentTaskTitle()
        applySleepAssertion(active: false)
        log("下载已取消")
    }

    func cancelAndClearAll() {
        log("收到取消并清空全部下载请求")
        isCancelling = true
        currentRunID = UUID()
        masterTask?.cancel()
        masterTask = nil
        Task { await pauseGate.resume() }
        Task { await copyHostBudget.wakeAll() }
        autoResumeTask?.cancel()
        autoResumeTask = nil
        progressRefreshTask?.cancel()
        progressRefreshTask = nil
        clearQueueState()
        message = "已取消并清空下载队列。"
        applySleepAssertion(active: false)
        log("已取消并清空全部下载队列")
    }

    func cancelItem(_ id: UUID) {
        explicitlyCanceledItemIDs.insert(id)
        if let idx = taskItems.firstIndex(where: { $0.id == id }) {
            switch taskItems[idx].state {
            case .queued, .running:
                taskItems[idx].state = .canceled
                scheduleProgressRefresh(force: true)
            default:
                break
            }
        }
    }

    func clearManhuaGuiSoftCircuit() {
        guard let circuit = manhuaGuiSoftCircuit else { return }
        manhuaGuiSoftCircuit = nil
        message = "已确认漫画柜网页可访问，可继续下载。"
        log("ManhuaGui 软熔断已由用户手动解除：HTTP \(circuit.statusCode) host=\(circuit.host)")
        updateCurrentTaskTitle()
    }

    @discardableResult
    func clearCopySoftCircuitIfReady() -> Bool {
        guard let circuit = copySoftCircuit else { return true }
        guard circuit.cooldownUntil <= Date() else {
            message = circuit.message
            return false
        }
        copySoftCircuit = nil
        copySuspiciousChapterFailures = 0
        copyRecoveryProbeActive = true
        copyRecoverySuccessfulChapters = 0
        Task { await copyHostBudget.resetPenalty(key: Self.copyBudgetKey) }
        message = "拷贝漫画冷却结束，可以继续下载。"
        log("拷贝漫画软熔断冷却结束：host=\(circuit.host)")
        updateCurrentTaskTitle()
        return true
    }

    private func noteCopyChapterRequestSuccess(for item: DownloadTaskItem) {
        guard isCopyFamily(item.comic.site) else { return }
        copySuspiciousChapterFailures = 0
    }

    private func noteCopyChapterCompleted(for item: DownloadTaskItem) {
        guard copyRecoveryProbeActive, isCopyFamily(item.comic.site) else { return }
        copyRecoverySuccessfulChapters += 1
        if copyRecoverySuccessfulChapters >= 3 {
            copyRecoveryProbeActive = false
            log("拷贝漫画恢复探测通过：连续完成 3 话，后续恢复章节并发 3")
        }
    }

    private func noteCopyChapterFailure(_ error: Error, for item: DownloadTaskItem) async {
        guard isCopyFamily(item.comic.site), let outcome = Self.copyFailureOutcome(error) else { return }
        copySuspiciousChapterFailures += 1
        let threshold = outcome.immediate ? 1 : 3
        guard copySuspiciousChapterFailures >= threshold, copySoftCircuit == nil else { return }

        let host = item.comic.site.webBase.host?.lowercased() ?? "-"
        copyRecoveryProbeActive = false
        copyRecoverySuccessfulChapters = 0
        copySoftCircuit = CopySoftCircuit(
            reason: outcome.reason,
            host: host,
            chapterTitle: "[\(item.chapter.volumeName)] \(item.chapter.displayName)",
            triggeredAt: Date(),
            cooldownUntil: Date().addingTimeInterval(outcome.cooldown)
        )
        taskItems = taskItems.map { existing in
            var updated = existing
            if isCopyFamily(updated.comic.site), updated.id != item.id, updated.state == .running {
                updated.state = .queued
            }
            return updated
        }
        updateProgress()
        updateCurrentTaskTitle()
        message = copySoftCircuit?.message ?? "拷贝漫画请求异常，已暂停当前批次。"
        log("拷贝漫画软熔断：\(outcome.reason) host=\(host)，已保留后续队列，冷却后自动继续")
        scheduleAutoResume(after: outcome.cooldown + 1)
    }

    static func copyFailureOutcome(_ error: Error) -> (reason: String, cooldown: TimeInterval, immediate: Bool)? {
        if let integrity = error as? DownloadIntegrityError {
            switch integrity {
            case .nonImagePayload:
                return ("连续收到非图片风控页面", 5 * 60, false)
            case .emptyPayload, .unsupportedImage, .incompleteChapter, .truncatedImage, .placeholderImage:
                return ("连续收到损坏或不完整页面", 5 * 60, false)
            }
        }
        guard let error = error as? CopyMangaError else { return nil }
        switch error {
        case .parseBlocked, .cooldown:
            return ("站点明确返回风控或冷却状态", 20 * 60, true)
        case .apiDetail(let detail) where detail.localizedCaseInsensitiveContains("ban") || detail.contains("风控"):
            return ("接口返回风控状态", 20 * 60, true)
        case .httpStatus(let code, _ ) where [403, 429, 503].contains(code):
            return ("HTTP \(code)", 20 * 60, true)
        case .httpStatus(let code, let body) where code == 404 && (body.localizedCaseInsensitiveContains("<html") || body.localizedCaseInsensitiveContains("<!doctype")):
            return ("连续收到 HTML 404 页面", 5 * 60, false)
        case .noImageInChapter:
            return ("连续未解析到章节图片", 5 * 60, false)
        case .invalidJSON(_, let snippet) where snippet.localizedCaseInsensitiveContains("<html"):
            return ("连续收到非预期网页", 5 * 60, false)
        case .allEndpoints404, .copyMirrorsUnavailable:
            return ("连续镜像或章节入口不可用", 5 * 60, false)
        case .connectionReset:
            return ("连续被站点断开连接（限流）", 10 * 60, false)
        default:
            return nil
        }
    }

    private static let copyBudgetKey = "copy-family"

    private func triggerManhuaGuiSoftCircuitIfNeeded(statusCode: Int, host: String?, itemID: UUID) {
        guard let idx = taskItems.firstIndex(where: { $0.id == itemID }) else { return }
        let item = taskItems[idx]
        guard isManhuaGuiItem(item) else { return }

        let hostText = host?.lowercased() ?? "-"
        let chapterTitle = "[\(item.chapter.volumeName)] \(item.chapter.displayName)"
        manhuaGuiSoftCircuit = ManhuaGuiSoftCircuit(
            statusCode: statusCode,
            host: hostText,
            chapterTitle: chapterTitle,
            triggeredAt: Date()
        )
        taskItems = taskItems.map { existing in
            var updated = existing
            if isManhuaGuiItem(updated), updated.state == .running {
                updated.state = .queued
            }
            return updated
        }
        updateProgress()
        updateCurrentTaskTitle()
        message = manhuaGuiSoftCircuit?.message ?? "漫画柜疑似触发风控，已停止当前批次。"
        log("ManhuaGui 软熔断：HTTP \(statusCode) host=\(hostText) chapter=\(chapterTitle)，已停止当前漫画柜批次并保留队列")
    }

    private func run(item: DownloadTaskItem, runID: UUID) async {
        if Task.isCancelled || !shouldContinue(runID: runID, itemID: item.id) {
            await MainActor.run {
                if self.currentRunID == runID {
                    self.setState(self.stoppedState(for: item), for: item.id)
                }
            }
            return
        }

        await pauseGate.waitIfPaused()
        if Task.isCancelled || !shouldContinue(runID: runID, itemID: item.id) {
            await MainActor.run {
                if self.currentRunID == runID {
                    self.setState(self.stoppedState(for: item), for: item.id)
                }
            }
            return
        }

        await MainActor.run {
            guard self.currentRunID == runID, !self.explicitlyCanceledItemIDs.contains(item.id) else { return }
            self.setState(.running, for: item.id)
            self.setChapterExpectedPages(1, for: item.id, resolved: false)
            self.setChapterCompletedPages(0, for: item.id)
            self.resetDownloadProtection(for: item.id)
            self.currentTaskTitle = "[\(item.chapter.volumeName)] \(item.chapter.displayName)"
            self.scheduleProgressRefresh()
        }
        log("开始章节：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName)")

        do {
            try await waitForChapterTurn(item)
            guard shouldContinue(runID: runID, itemID: item.id) else { throw CancellationError() }
            let imageFetchStart = Date()
            let (imageURLs, reusedResolvedURLs) = try await resolveImageURLs(for: item)
            try Task.checkCancellation()
            guard shouldContinue(runID: runID, itemID: item.id) else {
                throw CancellationError()
            }
            let imageFetchElapsed = Date().timeIntervalSince(imageFetchStart)
            await MainActor.run {
                guard self.currentRunID == runID, !self.explicitlyCanceledItemIDs.contains(item.id) else { return }
                self.setChapterExpectedPages(max(1, imageURLs.count), for: item.id, resolved: true)
                self.setChapterCompletedPages(min(self.chapterCompletedPages[item.id] ?? 0, max(1, imageURLs.count)), for: item.id)
                self.scheduleProgressRefresh()
            }
            if isCopyFamily(item.comic.site) {
                log(String(format: "拷贝漫画章节解析：[%@] %@ %@ %d 张图，耗时 %.2fs", item.chapter.volumeName, item.chapter.displayName, reusedResolvedURLs ? "复用" : "拿到", imageURLs.count, imageFetchElapsed))
            }
            try await downloadChapter(item: item, imageURLs: imageURLs, runID: runID)
            await MainActor.run {
                guard self.currentRunID == runID else { return }
                self.setState(.done, for: item.id)
                self.connectionResetStreak[SiteFamily.of(item.comic.site)] = 0
                self.lastCompletedOutputURL = self.chapterOutputFolder(for: item)
                self.markChapterFinished(for: item.id, succeeded: true)
                self.resetDownloadProtection(for: item.id)
                self.noteCopyChapterCompleted(for: item)
                self.scheduleProgressRefresh(force: true)
            }
            log("章节完成：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName)，共 \(imageURLs.count) 张")
        } catch is CancellationError {
            await MainActor.run {
                guard self.currentRunID == runID || self.explicitlyCanceledItemIDs.contains(item.id) else { return }
                self.setState(self.stoppedState(for: item), for: item.id)
                self.markChapterFinished(for: item.id, succeeded: false)
                self.resetDownloadProtection(for: item.id)
                self.scheduleProgressRefresh(force: true)
            }
            log("章节取消：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName)")
        } catch {
            await MainActor.run {
                guard self.currentRunID == runID else { return }
                self.setState(.failed(error.localizedDescription), for: item.id)
                if let index = self.taskItems.firstIndex(where: { $0.id == item.id }) {
                    self.taskItems[index].resolvedImageURLs = nil
                }
                self.markChapterFinished(for: item.id, succeeded: false)
                self.resetDownloadProtection(for: item.id)
                if Self.isConnectionThrottle(error) {
                    self.handleConnectionThrottle(for: item, error: error)
                }
                self.scheduleProgressRefresh(force: true)
            }
            await noteCopyChapterFailure(error, for: item)
            log("章节失败：[\(item.comic.name)] [\(item.chapter.volumeName)] \(item.chapter.displayName) - \(error.localizedDescription)")
        }
    }

    private func resolveImageURLs(for item: DownloadTaskItem) async throws -> ([URL], Bool) {
        if let cached = item.resolvedImageURLs, !cached.isEmpty {
            return (cached, true)
        }

        let chapterFolder = chapterOutputFolder(for: item)
        let recoverableFolder = await Self.recoverableChapterFolder(for: chapterFolder)
        // 漫画柜 image URLs carry an expiring signature (e=/m=); an old manifest would only earn 403s.
        let maxManifestAge: TimeInterval? = isManhuaGuiItem(item) ? 20 * 60 : nil
        if let persisted = await Self.persistedImageURLs(in: recoverableFolder, maxAge: maxManifestAge), !persisted.isEmpty {
            if let index = taskItems.firstIndex(where: { $0.id == item.id }) {
                taskItems[index].resolvedImageURLs = persisted
            }
            return (persisted, true)
        }

        let isCopy = isCopyFamily(item.comic.site)
        if isCopy {
            try await copyHostBudget.acquire(
                key: Self.copyBudgetKey,
                kind: .chapter,
                maxConcurrent: copyRecoveryProbeActive ? 1 : pacingState(for: .copy).chapterConcurrency,
                spacingMS: 200...400
            )
        }

        do {
            let urls = try await api.fetchImageURLs(
                slug: item.comic.slug,
                chapterUUID: item.chapter.uuid,
                chapterName: item.chapter.displayName,
                site: item.comic.site,
                preferredPrefix: item.comic.apiPathPrefix,
                preferredBaseURL: item.comic.apiBaseURL,
                cookie: item.cookie
            )
            if isCopy {
                await copyHostBudget.release(key: Self.copyBudgetKey, outcome: .success)
                noteCopyChapterRequestSuccess(for: item)
            }
            if let index = taskItems.firstIndex(where: { $0.id == item.id }) {
                taskItems[index].resolvedImageURLs = urls
            }
            return (urls, false)
        } catch {
            if isCopy {
                let throttled = Self.copyFailureOutcome(error) != nil
                await copyHostBudget.release(
                    key: Self.copyBudgetKey,
                    outcome: throttled ? .throttled : .failure
                )
            }
            throw error
        }
    }

    private func updateProgress() {
        progress = Self.chapterWeightedProgress(
            states: taskItems.map { item in
                (item.state, chapterResolvedPageCounts.contains(item.id),
                 chapterCompletedPages[item.id] ?? 0, chapterExpectedPages[item.id] ?? 1)
            }
        )
        updateCurrentTaskTitle()
        
        updateSpeedEstimate()
    }

    /// Every chapter weighs the same, so the percent never jumps when a chapter's real page count
    /// arrives. Failed chapters stay in the denominator at 0 (a run with failures can't read 100%);
    /// canceled chapters leave it.
    nonisolated static func chapterWeightedProgress(
        states: [(state: DownloadTaskItem.State, resolved: Bool, completedPages: Int, expectedPages: Int)]
    ) -> Double {
        var weight = 0.0
        var done = 0.0
        for entry in states {
            switch entry.state {
            case .canceled:
                continue
            case .done:
                weight += 1
                done += 1
            case .queued, .failed:
                weight += 1
            case .running:
                weight += 1
                // Small baseline while the image list is still being fetched.
                let fraction = entry.resolved
                    ? Double(min(entry.completedPages, max(1, entry.expectedPages))) / Double(max(1, entry.expectedPages))
                    : 0
                done += max(fraction, 0.03)
            }
        }
        return weight == 0 ? 0 : min(1, done / weight)
    }

    private func setState(_ state: DownloadTaskItem.State, for id: UUID) {
        guard let idx = taskItems.firstIndex(where: { $0.id == id }) else { return }
        let now = Date()
        switch state {
        case .running:
            if taskItems[idx].startedAt == nil {
                taskItems[idx].startedAt = now
            }
            taskItems[idx].finishedAt = nil
        case .done, .failed, .canceled:
            if taskItems[idx].startedAt == nil {
                taskItems[idx].startedAt = now
            }
            taskItems[idx].finishedAt = now
        case .queued:
            break
        }
        taskItems[idx].state = state
    }

    private func stoppedState(for item: DownloadTaskItem) -> DownloadTaskItem.State {
        if manhuaGuiSoftCircuit != nil, isManhuaGuiItem(item), !explicitlyCanceledItemIDs.contains(item.id) {
            return .queued
        }
        if copySoftCircuit != nil, isCopyFamily(item.comic.site), !explicitlyCanceledItemIDs.contains(item.id) {
            return .queued
        }
        return .canceled
    }

    private func downloadChapter(item: DownloadTaskItem, imageURLs: [URL], runID: UUID) async throws {
        let comicFolder = resolvedComicFolder(for: item)
        let groupName = canonicalGroupName(item.chapter.volumeName)
        let finalChapterFolder = chapterOutputFolder(for: item)
        let volumeFolder = finalChapterFolder.deletingLastPathComponent()

        try createDirIfNeeded(comicFolder)
        try createDirIfNeeded(volumeFolder)
        let chapterFolder = try await Self.prepareStagingFolder(
            for: finalChapterFolder,
            overwrite: item.existingFilePolicy == .overwrite
        )
        if item.existingFilePolicy == .overwrite {
            if let index = taskItems.firstIndex(where: { $0.id == item.id }) {
                taskItems[index].existingFilePolicy = .keepExisting
            }
            log("覆盖已有章节目录：[\(item.chapter.volumeName)] \(item.chapter.displayName)")
        }

        // Intra-chapter concurrency speeds up image downloading drastically
        // while the request pacer prevents API burst spikes and mitigates bans.
        let maxImageConcurrent = pacingState(for: SiteFamily.of(item.comic.site)).pacing.imageConcurrencyPerChapter
        if isCopyFamily(item.comic.site) {
            log("拷贝漫画进入图片下载：[\(item.chapter.volumeName)] \(item.chapter.displayName)，\(imageURLs.count) 张，并发 \(maxImageConcurrent)")
        }
        var verifiedPages: [VerifiedDownloadPage] = []
        do {
            try await withThrowingTaskGroup(of: VerifiedDownloadPage.self) { group in
            var iterator = imageURLs.enumerated().makeIterator()
            var completedCount = 0

            for _ in 0..<maxImageConcurrent {
                if let (index, imageURL) = iterator.next() {
                    group.addTask { [weak self] in
                        guard let self else { throw CancellationError() }
                        try Task.checkCancellation()
                        await self.pauseGate.waitIfPaused()
                        try Task.checkCancellation()
                        let shouldContinue = await MainActor.run {
                            self.shouldContinue(runID: runID, itemID: item.id)
                        }
                        guard shouldContinue else {
                            throw CancellationError()
                        }
                        return try await self.downloadImage(
                            url: imageURL,
                            to: chapterFolder,
                            fileName: self.fileName(comic: item.comic.name, volume: groupName, chapter: item.chapter.displayName, index: index + 1),
                            pageIndex: index + 1,
                            refererURL: self.api.imageRefererURL(slug: item.comic.slug, chapterUUID: item.chapter.uuid, site: item.comic.site),
                            site: item.comic.site,
                            copyImageQuality: item.copyImageQuality ?? .high,
                            comicKey: item.comic.slug,
                            cookie: item.cookie,
                            runID: runID,
                            itemID: item.id
                        )
                    }
                }
            }

            while let page = try await group.next() {
                try Task.checkCancellation()
                guard shouldContinue(runID: runID, itemID: item.id) else {
                    throw CancellationError()
                }
                completedCount += 1
                verifiedPages.append(page)
                if completedCount % 10 == 0 {
                    try await Self.writeChapterManifest(
                        item: item,
                        expectedPages: imageURLs.count,
                        imageURLs: imageURLs,
                        pages: verifiedPages,
                        complete: false,
                        folder: chapterFolder
                    )
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.currentRunID == runID, !self.explicitlyCanceledItemIDs.contains(item.id) else { return }
                    self.increaseCompletedPage(for: item.id)
                    self.scheduleProgressRefresh()
                }
                if completedCount % 20 == 0 || completedCount == imageURLs.count {
                    log("章节进度：[\(item.chapter.volumeName)] \(item.chapter.displayName) \(completedCount)/\(imageURLs.count)")
                }

                if let (index, imageURL) = iterator.next() {
                    group.addTask { [weak self] in
                        guard let self else { throw CancellationError() }
                        try Task.checkCancellation()
                        await self.pauseGate.waitIfPaused()
                        try Task.checkCancellation()
                        let shouldContinue = await MainActor.run {
                            self.shouldContinue(runID: runID, itemID: item.id)
                        }
                        guard shouldContinue else {
                            throw CancellationError()
                        }
                        return try await self.downloadImage(
                            url: imageURL,
                            to: chapterFolder,
                            fileName: self.fileName(comic: item.comic.name, volume: groupName, chapter: item.chapter.displayName, index: index + 1),
                            pageIndex: index + 1,
                            refererURL: self.api.imageRefererURL(slug: item.comic.slug, chapterUUID: item.chapter.uuid, site: item.comic.site),
                            site: item.comic.site,
                            copyImageQuality: item.copyImageQuality ?? .high,
                            comicKey: item.comic.slug,
                            cookie: item.cookie,
                            runID: runID,
                            itemID: item.id
                        )
                    }
                }
            }
            }
            let indexes = Set(verifiedPages.map(\.index))
            guard indexes.count == imageURLs.count else {
                throw DownloadIntegrityError.incompleteChapter(expected: imageURLs.count, verified: indexes.count)
            }
            try await Self.writeChapterManifest(
                item: item,
                expectedPages: imageURLs.count,
                imageURLs: imageURLs,
                pages: verifiedPages,
                complete: true,
                folder: chapterFolder
            )
            try await Self.publishStagingFolder(chapterFolder, as: finalChapterFolder)
            let standardCount = verifiedPages.filter { $0.standardQuality == true }.count
            standardQualityPages[item.id] = standardCount
            if standardCount > 0 {
                log("画质：[\(item.chapter.volumeName)] \(item.chapter.displayName) 有 \(standardCount)/\(imageURLs.count) 页为标准画质（高清不可用）")
            }
        } catch {
            try? await Self.writeChapterManifest(
                item: item,
                expectedPages: imageURLs.count,
                imageURLs: imageURLs,
                pages: verifiedPages,
                complete: false,
                folder: chapterFolder
            )
            throw error
        }
    }

    nonisolated private static func writeChapterManifest(
        item: DownloadTaskItem,
        expectedPages: Int,
        imageURLs: [URL],
        pages: [VerifiedDownloadPage],
        complete: Bool,
        folder: URL
    ) async throws {
        try await Task.detached(priority: .utility) {
            try DownloadIntegrity.writeManifest(
                chapterID: item.chapter.id,
                expectedPages: expectedPages,
                imageURLs: imageURLs,
                pages: pages,
                complete: complete,
                to: folder
            )
        }.value
    }

    nonisolated private static func persistedImageURLs(in folder: URL, maxAge: TimeInterval? = nil) async -> [URL]? {
        await Task.detached(priority: .utility) {
            guard let manifest = DownloadIntegrity.loadManifest(from: folder) else { return nil }
            if let maxAge, Date().timeIntervalSince(manifest.updatedAt) > maxAge { return nil }
            return manifest.imageURLs
        }.value
    }

    nonisolated private static func recoverableChapterFolder(for folder: URL) async -> URL {
        await Task.detached(priority: .utility) {
            DownloadOutputLayout.recoverableChapterFolder(for: folder)
        }.value
    }

    nonisolated private static func prepareStagingFolder(for folder: URL, overwrite: Bool) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try DownloadOutputLayout.prepareStagingFolder(for: folder, overwrite: overwrite)
        }.value
    }

    nonisolated private static func publishStagingFolder(_ staging: URL, as folder: URL) async throws {
        try await Task.detached(priority: .utility) {
            try DownloadOutputLayout.publishStagingFolder(staging, as: folder)
        }.value
    }

    private func chapterOutputFolder(for item: DownloadTaskItem) -> URL {
        let selectedKinds = Set(taskItems.filter {
            $0.comic.slug == item.comic.slug && $0.destination.standardizedFileURL == item.destination.standardizedFileURL
        }.map { canonicalGroupKey($0.chapter.volumeName) })
        return DownloadOutputLayout.chapterFolder(
            comic: item.comic,
            chapter: item.chapter,
            destination: item.destination,
            usesGroupFolder: item.usesGroupFolder ?? (selectedKinds.count > 1)
        )
    }

    private func resolvedComicFolder(for item: DownloadTaskItem) -> URL {
        DownloadOutputLayout.comicFolder(comic: item.comic, destination: item.destination)
    }

    private func downloadImage(
        url: URL,
        to folder: URL,
        fileName: String,
        pageIndex: Int,
        refererURL: URL?,
        site: MangaSiteConfig,
        copyImageQuality requestedQuality: CopyImageQuality,
        comicKey: String,
        cookie: String?,
        runID: UUID,
        itemID: UUID
    ) async throws -> VerifiedDownloadPage {
        let isCopySite = isCopyFamily(site)
        let copyImageQuality: CopyImageQuality = isCopySite && copyHighResUnavailable.contains(comicKey) ? .standard : requestedQuality
        let baseName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if let existing = await Task.detached(priority: .utility, operation: {
            DownloadIntegrity.existingPage(in: folder, baseName: baseName, index: pageIndex)
        }).value {
            return existing
        }

        let resolutionCandidates = Self.copyResolutionCandidates(
            for: url,
            quality: copyImageQuality,
            isCopy: isCopyFamily(site)
        )
        var candidateKeys: Set<String> = []
        let candidates = resolutionCandidates
            .flatMap { candidateImageURLs(for: $0, site: site) }
            .filter { candidateKeys.insert($0.absoluteString).inserted }
        var lastError: Error?
        if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
            let hosts = candidates.compactMap(\.host).joined(separator: " -> ")
            log("ManhuaGui 图片下载候选：\(hosts)")
        }

        for (index, candidate) in candidates.enumerated() {
            if let remaining = hostCooldownRemaining(for: candidate.host?.lowercased()) {
                if index + 1 < candidates.count {
                    log("图片 host 冷却中，跳过候选：\(candidate.host ?? "-")，剩余约 \(Int(remaining.rounded()))s")
                    continue
                }
                throw DownloadCircuitBreakError(message: "图片 host 风控冷却中，已暂停该章节请求。")
            }
            do {
                // Mirror hosts (漫画柜/包子) fail over on connection errors instead of retrying a dead host.
                let hasMirrorFallback = index + 1 < candidates.count
                    && (site == .baoziManga || site.webBase.host?.lowercased().contains("manhuagui.com") == true)
                let page = try await retrying(times: 3, failFastOnConnectionError: hasMirrorFallback) {
                    try Task.checkCancellation()
                    guard self.shouldContinue(runID: runID, itemID: itemID) else { throw CancellationError() }
                    let isCopy = self.isCopyFamily(site)
                    let pacer = self.pacer(for: site)
                    if isCopy {
                        try await self.copyHostBudget.acquire(
                            key: Self.copyBudgetKey,
                            kind: .image,
                            maxConcurrent: self.copyRecoveryProbeActive ? 1 : self.pacingState(for: .copy).globalImageConcurrency,
                            spacingMS: self.pacingState(for: .copy).pacing.imageSpacingMS
                        )
                    } else {
                        try await pacer.waitTurn()
                    }
                    guard !Task.isCancelled, self.shouldContinue(runID: runID, itemID: itemID) else {
                        if isCopy {
                            await self.copyHostBudget.release(key: Self.copyBudgetKey, outcome: .failure)
                        }
                        throw CancellationError()
                    }
                    var req = URLRequest(url: candidate)
                    req.setValue((refererURL ?? site.webBase).absoluteString, forHTTPHeaderField: "Referer")
                    req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                    if let cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        req.setValue(cookie, forHTTPHeaderField: "Cookie")
                    }
                    let data: Data
                    let response: URLResponse
                    do {
                        (data, response) = try await self.session.data(for: req)
                    } catch {
                        if isCopy {
                            await self.copyHostBudget.release(key: Self.copyBudgetKey, outcome: .failure)
                        }
                        throw error
                    }
                    guard !Task.isCancelled, self.shouldContinue(runID: runID, itemID: itemID) else {
                        if isCopy {
                            await self.copyHostBudget.release(key: Self.copyBudgetKey, outcome: .failure)
                        }
                        throw CancellationError()
                    }
                    guard let http = response as? HTTPURLResponse else {
                        if isCopy {
                            await self.copyHostBudget.release(key: Self.copyBudgetKey, outcome: .failure)
                        }
                        throw URLError(.badServerResponse)
                    }
                    guard (200...299).contains(http.statusCode) else {
                        if isCopy {
                            await self.copyHostBudget.release(
                                key: Self.copyBudgetKey,
                                outcome: [403, 429, 503].contains(http.statusCode) ? .throttled : .failure
                            )
                        }
                        if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
                            let hasSignature = candidate.query?.contains("e=") == true && candidate.query?.contains("m=") == true
                            self.log("ManhuaGui 图片请求失败：host=\(candidate.host ?? "-") status=\(http.statusCode) signed=\(hasSignature ? "是" : "否")")
                        }
                        if [403, 429, 503].contains(http.statusCode) {
                            self.notePacingThrottle(site, reason: "HTTP \(http.statusCode)")
                            if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
                                self.triggerManhuaGuiSoftCircuitIfNeeded(
                                    statusCode: http.statusCode,
                                    host: candidate.host,
                                    itemID: itemID
                                )
                            } else if !isCopy {
                                await pacer.markThrottled()
                            }
                            if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
                                throw DownloadCircuitBreakError(message: "漫画柜疑似触发风控（HTTP \(http.statusCode)），已停止当前批次。")
                            }
                            if let stopMessage = self.noteImageFailure(
                                itemID: itemID,
                                host: candidate.host?.lowercased(),
                                kind: .throttled
                            ) {
                                throw DownloadCircuitBreakError(message: stopMessage)
                            }
                        } else if http.statusCode == 404 {
                            if let stopMessage = self.noteImageFailure(itemID: itemID, host: candidate.host?.lowercased(), kind: .notFound) {
                                throw DownloadCircuitBreakError(message: stopMessage)
                            }
                        }
                        throw DownloadRequestError.httpStatus(http.statusCode, retryAfter: self.retryAfter(from: http))
                    }
                    let format: DownloadImageFormat
                    do {
                        // Decode-level validation runs off the main actor.
                        let mimeType = http.value(forHTTPHeaderField: "Content-Type")
                        let expectedLength = http.expectedContentLength
                        format = try await Task.detached(priority: .utility) {
                            try DownloadIntegrity.verify(data: data, mimeType: mimeType, expectedLength: expectedLength)
                        }.value
                    } catch {
                        if isCopy {
                            await self.copyHostBudget.release(key: Self.copyBudgetKey, outcome: .throttled)
                        }
                        if case DownloadIntegrityError.nonImagePayload = error {
                            self.notePacingThrottle(site, reason: "返回非图片页面")
                        }
                        throw error
                    }
                    if isCopy {
                        await self.copyHostBudget.release(key: Self.copyBudgetKey, outcome: .success)
                    } else {
                        await pacer.markSuccess()
                    }
                    self.noteImageSuccess(itemID: itemID, host: candidate.host?.lowercased())
                    self.notePacingSuccess(site)
                    self.noteNetworkPage(bytes: data.count)
                    let isHighResURL = candidate.absoluteString.localizedCaseInsensitiveContains("c1500x")
                    if isCopySite && isHighResURL { self.copyHighResMisses[comicKey] = 0 }
                    let outputURL = folder.appendingPathComponent("\(baseName).\(format.fileExtension)")
                    try await Task.detached(priority: .utility) {
                        try data.write(to: outputURL, options: .atomic)
                    }.value
                    self.rememberPreferredHost(from: candidate, site: site)
                    let fellBackToStandard = isCopySite && requestedQuality == .high
                        && !isHighResURL && url.absoluteString.localizedCaseInsensitiveContains("c800x")
                    return VerifiedDownloadPage(
                        index: pageIndex,
                        fileName: outputURL.lastPathComponent,
                        byteCount: data.count,
                        format: format,
                        standardQuality: fellBackToStandard ? true : nil
                    )
                }
                return page
            } catch let error as DownloadRequestError where error.statusCode == 404 && index + 1 < candidates.count {
                lastError = error
                if isCopySite, candidate.absoluteString.localizedCaseInsensitiveContains("c1500x") {
                    noteCopyHighResMiss(comicKey: comicKey)
                }
                log("图片 404，切换备用域名重试：\(candidate.host ?? "-") -> \(candidates[index + 1].host ?? "-")")
                continue
            } catch let error as URLError where Self.shouldTryNextBaoziImageHost(after: error) && index + 1 < candidates.count {
                lastError = error
                log("图片连接异常（\(error.code.rawValue)），切换备用域名：\(candidate.host ?? "-") -> \(candidates[index + 1].host ?? "-")")
                continue
            } catch let error as DownloadCircuitBreakError {
                throw error
            } catch {
                if site.webBase.host?.lowercased().contains("manhuagui.com") == true {
                    log("ManhuaGui 图片下载异常：host=\(candidate.host ?? "-") error=\(error.localizedDescription)")
                }
                if let urlError = error as? URLError, urlError.code == .timedOut {
                    notePacingThrottle(site, reason: "请求超时")
                    if site.webBase.host?.lowercased().contains("manhuagui.com") != true {
                        await self.pacer(for: site).markThrottled()
                    }
                    if let stopMessage = self.noteImageFailure(itemID: itemID, host: candidate.host?.lowercased(), kind: .timeout) {
                        throw DownloadCircuitBreakError(message: stopMessage)
                    }
                    log("图片请求超时，自动降速后重试：\(candidate.absoluteString)")
                }
                throw error
            }
        }

        throw lastError ?? DownloadRequestError.httpStatus(404, retryAfter: nil)
    }
    private func noteCopyHighResMiss(comicKey: String) {
        let misses = (copyHighResMisses[comicKey] ?? 0) + 1
        copyHighResMisses[comicKey] = misses
        if misses >= copyHighResMissThreshold, copyHighResUnavailable.insert(comicKey).inserted {
            log("拷贝漫画高清图不可用：\(comicKey) 连续 \(misses) 页 c1500x 返回 404，后续直接请求标准图")
        }
    }

    func standardQualityPageCount(for itemID: UUID) -> Int {
        standardQualityPages[itemID] ?? 0
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

    private func retrying<T>(
        times: Int,
        failFastOnConnectionError: Bool = false,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var backoffMS = 450
        for attempt in 1...times {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as DownloadRequestError {
                if error.statusCode == 404 {
                    throw error
                }
                lastError = error
                guard attempt < Self.retryLimit(for: error, default: times) else { throw error }
                do {
                    let serverWait = (error.retryAfter ?? 0) * 1000
                    let waitMS = max(Int(serverWait), backoffMS + Int.random(in: 120...420))
                    log("下载请求重试：第 \(attempt) 次失败（HTTP \(error.statusCode)），\(waitMS)ms 后重试")
                    try await Task.sleep(for: .milliseconds(waitMS))
                    backoffMS = min(backoffMS * 2, 5000)
                }
            } catch {
                lastError = error
                if failFastOnConnectionError, let urlError = error as? URLError,
                   Self.shouldTryNextBaoziImageHost(after: urlError) {
                    throw urlError
                }
                if attempt >= Self.retryLimit(for: error, default: times) {
                    throw error
                }
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

    /// Retry budget per failure kind. A 403 is a block, not a glitch: retrying only deepens it.
    /// Rate limits and non-image (challenge) pages get one more try; everything else keeps `times`.
    nonisolated static func retryLimit(for error: Error, default times: Int) -> Int {
        if let request = error as? DownloadRequestError {
            switch request.statusCode {
            case 403: return 1
            case 429, 503: return min(times, 2)
            default: return times
            }
        }
        if let integrity = error as? DownloadIntegrityError, case .nonImagePayload = integrity {
            return min(times, 2)
        }
        return times
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

    private func markChapterFinished(for id: UUID, succeeded: Bool) {
        guard succeeded else { return }
        let expected = max(1, chapterExpectedPages[id] ?? 1)
        chapterCompletedPages[id] = expected
    }

    private func resetSpeedEstimateState(placeholder: String = "") {
        speedText = placeholder
        networkPagesThisRun = 0
        networkBytesThisRun = 0
        lastNetworkPageAt = nil
        lastSpeedSampleTime = nil
        lastSpeedSamplePages = 0
        lastSpeedSampleBytes = 0
        smoothedPagesPerSecond = nil
        smoothedBytesPerSecond = nil
        lastSpeedDiagnosticTime = nil
    }

    private func noteNetworkPage(bytes: Int) {
        networkPagesThisRun += 1
        networkBytesThisRun += bytes
        lastNetworkPageAt = Date()
    }

    /// Refreshes speed once a second even when no page completes, so stalls become visible.
    private func startSpeedTicker() {
        speedTicker?.cancel()
        speedTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.updateSpeedEstimate()
            }
        }
    }

    private func stopSpeedTicker() {
        speedTicker?.cancel()
        speedTicker = nil
    }

    private func scheduleProgressRefresh(force: Bool = false) {
        if force {
            progressRefreshTask?.cancel()
            progressRefreshTask = nil
            updateProgress()
            return
        }
        guard !isCancelling, progressRefreshTask == nil else { return }
        progressRefreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            await MainActor.run {
                guard let self else { return }
                self.progressRefreshTask = nil
                guard !self.isCancelling else { return }
                self.updateProgress()
            }
        }
    }

    private func shouldContinue(runID: UUID, itemID: UUID) -> Bool {
        guard currentRunID == runID, !isCancelling, !explicitlyCanceledItemIDs.contains(itemID) else {
            return false
        }
        guard let item = taskItems.first(where: { $0.id == itemID }) else { return false }
        if manhuaGuiSoftCircuit != nil, isManhuaGuiItem(item) { return false }
        if copySoftCircuit != nil, isCopyFamily(item.comic.site) { return false }
        return true
    }

    private func hasEligibleQueuedItems() -> Bool {
        taskItems.contains { isEligibleQueuedItem($0) }
    }

    private func nextQueuedItem(excluding inFlightItemIDs: Set<UUID>) -> DownloadTaskItem? {
        taskItems.first {
            isEligibleQueuedItem($0) && !inFlightItemIDs.contains($0.id)
        }
    }

    private func isEligibleQueuedItem(_ item: DownloadTaskItem) -> Bool {
        item.state == .queued &&
            !(manhuaGuiSoftCircuit != nil && isManhuaGuiItem(item)) &&
            !(copySoftCircuit != nil && isCopyFamily(item.comic.site))
    }

    private func hasQueuedManhuaGuiItems() -> Bool {
        taskItems.contains { $0.state == .queued && isManhuaGuiItem($0) }
    }

    private func hasQueuedCopyItems() -> Bool {
        taskItems.contains { $0.state == .queued && isCopyFamily($0.comic.site) }
    }

    private func isManhuaGuiItem(_ item: DownloadTaskItem) -> Bool {
        item.comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true
    }

    private func updateSpeedEstimate() {
        guard isRunning, !isPaused, let start = downloadStartTime else { return }
        let now = Date()
        let elapsed = now.timeIntervalSince(start)
        let manhuaGuiActive = hasActiveManhuaGuiDownloads()
        let interval = manhuaGuiActive ? manhuaGuiSpeedSampleInterval : speedSampleInterval
        let alpha = manhuaGuiActive ? manhuaGuiSpeedSmoothingFactor : speedSmoothingFactor

        if let last = lastSpeedSampleTime {
            let dt = now.timeIntervalSince(last)
            if dt >= interval {
                let pageRate = Double(networkPagesThisRun - lastSpeedSamplePages) / dt
                let byteRate = Double(networkBytesThisRun - lastSpeedSampleBytes) / dt
                // Zero-progress samples are kept on purpose: the rate decays during stalls.
                smoothedPagesPerSecond = Self.ema(smoothedPagesPerSecond, pageRate, alpha: alpha)
                smoothedBytesPerSecond = Self.ema(smoothedBytesPerSecond, byteRate, alpha: alpha)
                lastSpeedSampleTime = now
                lastSpeedSamplePages = networkPagesThisRun
                lastSpeedSampleBytes = networkBytesThisRun
            }
        } else {
            lastSpeedSampleTime = now
            lastSpeedSamplePages = networkPagesThisRun
            lastSpeedSampleBytes = networkBytesThisRun
        }

        if lastSpeedDiagnosticTime.map({ now.timeIntervalSince($0) >= 10 }) ?? true, networkPagesThisRun > 0 {
            lastSpeedDiagnosticTime = now
            log(String(format: "速度：%@，%.2f 页/秒，本次网络下载 %d 页，已运行 %ds",
                       Self.formatByteRate(smoothedBytesPerSecond ?? 0), smoothedPagesPerSecond ?? 0,
                       networkPagesThisRun, Int(elapsed)))
        }

        guard networkPagesThisRun > 0, let pageRate = smoothedPagesPerSecond else {
            let resolvingOnly = !taskItems.contains { $0.state == .running && chapterResolvedPageCounts.contains($0.id) }
            speedText = resolvingOnly && taskItems.contains { $0.state == .running } ? "解析中" : "计算中..."
            return
        }
        if let lastPage = lastNetworkPageAt, now.timeIntervalSince(lastPage) >= stallThreshold {
            speedText = "等待中 · \(Int(now.timeIntervalSince(lastPage)))s 无新页面"
            return
        }

        var parts = [Self.formatByteRate(smoothedBytesPerSecond ?? 0), String(format: "%.1f 页/秒", pageRate)]
        let (knownExpectedPages, completedKnownPages, unresolvedChapters, resolvedCount) = estimateInputs()
        let canShowETA = elapsed >= etaWarmupDuration
            && networkPagesThisRun >= etaMinimumCompletedPages
            && pageRate > 0.05
            && knownExpectedPages > 0
            && (unresolvedChapters == 0 || resolvedCount >= etaResolvedChapterThreshold || knownExpectedPages >= etaKnownPageThreshold)
        if canShowETA {
            let averagePages = Double(knownExpectedPages) / Double(max(1, resolvedCount))
            let estimatedTotal = Double(knownExpectedPages) + averagePages * Double(unresolvedChapters)
            let remaining = max(0, estimatedTotal - Double(completedKnownPages)) / pageRate
            parts.append("剩余 " + Self.formatRemaining(remaining))
        }
        speedText = parts.joined(separator: " · ")
    }

    nonisolated static func ema(_ previous: Double?, _ value: Double, alpha: Double) -> Double {
        guard let previous else { return value }
        return previous * (1 - alpha) + value * alpha
    }

    nonisolated static func formatByteRate(_ bytesPerSecond: Double) -> String {
        if bytesPerSecond >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSecond / 1_048_576)
        }
        return String(format: "%.0f KB/s", bytesPerSecond / 1024)
    }

    nonisolated static func formatRemaining(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total >= 3600 {
            return String(format: "%d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func hasActiveManhuaGuiDownloads() -> Bool {
        taskItems.contains { item in
            guard item.comic.site.webBase.host?.lowercased().contains("manhuagui.com") == true else { return false }
            switch item.state {
            case .queued, .running:
                return true
            case .done, .failed, .canceled:
                return false
            }
        }
    }

    private func isCopyFamily(_ site: MangaSiteConfig) -> Bool {
        guard let host = site.webBase.host?.lowercased() else { return false }
        return CopyMangaMirror.mirror(for: host) != nil
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

    func comicDurationSummaries(now: Date = Date()) -> [ComicDurationSummary] {
        struct Bucket {
            var comicName = ""
            var totalTasks = 0
            var completedTasks = 0
            var failedOrCanceledTasks = 0
            var isRunning = false
            var startedAt: Date?
            var finishedAt: Date?
        }

        var buckets: [String: Bucket] = [:]

        for item in taskItems {
            let key = [
                item.comic.slug.lowercased(),
                item.destination.path.lowercased()
            ].joined(separator: "::")

            var bucket = buckets[key] ?? Bucket()
            bucket.comicName = item.comic.name
            bucket.totalTasks += 1

            switch item.state {
            case .running:
                bucket.isRunning = true
            case .done:
                bucket.completedTasks += 1
            case .failed, .canceled:
                bucket.failedOrCanceledTasks += 1
            case .queued:
                break
            }

            if let startedAt = item.startedAt {
                bucket.startedAt = bucket.startedAt.map { min($0, startedAt) } ?? startedAt
            }
            if let finishedAt = item.finishedAt {
                bucket.finishedAt = bucket.finishedAt.map { max($0, finishedAt) } ?? finishedAt
            }

            buckets[key] = bucket
        }

        return buckets.map { key, bucket in
            let hasOpenTasks = bucket.completedTasks + bucket.failedOrCanceledTasks < bucket.totalTasks
            let effectiveEnd: Date?
            if bucket.isRunning || hasOpenTasks {
                effectiveEnd = bucket.startedAt.map { _ in now }
            } else {
                effectiveEnd = bucket.finishedAt
            }

            let elapsed = max(0, effectiveEnd?.timeIntervalSince(bucket.startedAt ?? effectiveEnd ?? now) ?? 0)
            return ComicDurationSummary(
                id: key,
                comicName: bucket.comicName,
                totalTasks: bucket.totalTasks,
                completedTasks: bucket.completedTasks,
                failedOrCanceledTasks: bucket.failedOrCanceledTasks,
                isRunning: bucket.isRunning,
                startedAt: bucket.startedAt,
                finishedAt: bucket.isRunning || hasOpenTasks ? nil : bucket.finishedAt,
                elapsedSeconds: elapsed
            )
        }
        .filter { $0.startedAt != nil }
        .sorted { lhs, rhs in
            if lhs.isRunning != rhs.isRunning {
                return lhs.isRunning && !rhs.isRunning
            }
            let lhsDate = lhs.finishedAt ?? lhs.startedAt ?? .distantPast
            let rhsDate = rhs.finishedAt ?? rhs.startedAt ?? .distantPast
            if lhsDate != rhsDate {
                return lhsDate > rhsDate
            }
            return lhs.comicName.localizedStandardCompare(rhs.comicName) == .orderedAscending
        }
    }

    func durationText(for item: DownloadTaskItem, now: Date = Date()) -> String? {
        guard let startedAt = item.startedAt else { return nil }
        let effectiveEnd: Date
        switch item.state {
        case .done, .failed, .canceled:
            effectiveEnd = item.finishedAt ?? now
        case .queued, .running:
            effectiveEnd = now
        }
        return Self.formatDuration(max(0, effectiveEnd.timeIntervalSince(startedAt)))
    }

    nonisolated static func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func countsSummary() -> (queued: Int, running: Int, failed: Int, done: Int) {
        if let cachedCounts { return cachedCounts }
        let counts = taskItems.reduce(into: (queued: 0, running: 0, failed: 0, done: 0)) { partial, item in
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
        cachedCounts = counts
        return counts
    }

    /// `pagesKnown` is false until every chapter that still counts has a real page count;
    /// before that `totalPages` would only be a chapter count and must not be shown as pages.
    func progressSummary() -> (completedPages: Int, totalPages: Int, completedTasks: Int, totalTasks: Int, pagesKnown: Bool) {
        if let cachedProgressSummary { return cachedProgressSummary }
        let totalTasks = taskItems.count
        let completedTasks = taskItems.reduce(0) { partial, item in
            switch item.state {
            case .done:
                return partial + 1
            default:
                return partial
            }
        }
        let totalPages = taskItems.reduce(0) { partial, item in
            partial + max(1, chapterExpectedPages[item.id] ?? 1)
        }
        let completedPages = taskItems.reduce(0) { partial, item in
            let expected = max(1, chapterExpectedPages[item.id] ?? 1)
            let done = min(expected, max(0, chapterCompletedPages[item.id] ?? 0))
            switch item.state {
            case .done:
                return partial + expected
            case .queued:
                return partial
            case .running, .failed, .canceled:
                return partial + done
            }
        }
        let pagesKnown = taskItems.allSatisfy { item in
            switch item.state {
            case .failed, .canceled: return true
            default: return chapterResolvedPageCounts.contains(item.id)
            }
        }
        let summary = (completedPages: completedPages, totalPages: totalPages, completedTasks: completedTasks,
                       totalTasks: totalTasks, pagesKnown: pagesKnown)
        cachedProgressSummary = summary
        return summary
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
        if normalized.contains("章节页已返回") || normalized.contains("未解析到图片载荷") {
            return "章节取图失败"
        }
        if normalized.contains("图片请求失败") {
            return "图片下载失败"
        }
        if normalized.contains("图片链接已解析") || normalized.contains("下载链路失败") {
            return "图链下载失败"
        }
        if normalized.contains("403") || normalized.contains("429") || normalized.contains("503") || normalized.contains("风控") || normalized.contains("冷却") {
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
        if let queued = taskItems.first(where: { isEligibleQueuedItem($0) }) {
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

    nonisolated static func copyResolutionCandidates(
        for original: URL,
        quality: CopyImageQuality,
        isCopy: Bool = true
    ) -> [URL] {
        guard isCopy, quality == .high else { return [original] }
        let raw = original.absoluteString
        guard raw.localizedCaseInsensitiveContains("c800x") else { return [original] }
        let highRaw = raw.replacingOccurrences(
            of: "c800x",
            with: "c1500x",
            options: .caseInsensitive
        )
        guard let high = URL(string: highRaw), high != original else { return [original] }
        return [high, original]
    }

    private func candidateImageURLs(for original: URL, site: MangaSiteConfig) -> [URL] {
        if site == .baoziManga {
            return Self.baoziImageCandidates(for: original)
        }
        guard site.webBase.host?.lowercased().contains("manhuagui.com") == true else {
            return [original]
        }
        return Self.manhuaGuiImageCandidates(for: original, preferredHost: manhuaGuiPreferredHost)
    }

    /// Image mirrors for 漫画柜. `cf` comes first: in user networks the older i/eu/us hosts can be
    /// unreachable (TLS reset or timeout) while `cf` still serves the same signed paths.
    nonisolated static let manhuaGuiImageHosts = [
        "cf.hamreus.com", "i.hamreus.com", "eu.hamreus.com", "us.hamreus.com", "us2.hamreus.com", "eu2.hamreus.com"
    ]

    /// A host that already served images this session goes first, then the payload's own host, then mirrors.
    nonisolated static func manhuaGuiImageCandidates(for original: URL, preferredHost: String?) -> [URL] {
        guard let host = original.host?.lowercased(), host.contains("hamreus.com") else {
            return [original]
        }
        var urls: [URL] = []
        var seen: Set<String> = []
        func add(_ candidateHost: String) {
            guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else { return }
            components.host = candidateHost
            guard let url = components.url, seen.insert(url.absoluteString).inserted else { return }
            urls.append(url)
        }
        if let preferredHost { add(preferredHost) }
        add(host)
        manhuaGuiImageHosts.forEach(add)
        return urls
    }

    nonisolated static func baoziImageCandidates(for original: URL) -> [URL] {
        guard let originalHost = original.host?.lowercased(),
              originalHost.contains("bzcdn.net") || originalHost.contains("baozimh.com") else {
            return [original]
        }

        var candidates = [original]
        var seen: Set<String> = [original.absoluteString]
        for host in ["static-tw.baozimh.com", "s1.baozimh.com"] where host != originalHost {
            guard var components = URLComponents(url: original, resolvingAgainstBaseURL: false) else { continue }
            components.host = host
            guard let candidate = components.url, seen.insert(candidate.absoluteString).inserted else { continue }
            candidates.append(candidate)
        }
        return candidates
    }

    nonisolated static func shouldTryNextBaoziImageHost(after error: URLError) -> Bool {
        switch error.code {
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .networkConnectionLost,
             .timedOut:
            return true
        default:
            return false
        }
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

    private func resetDownloadProtection(for itemID: UUID) {
        protectionState.reset(itemID: itemID)
    }

    private func noteImageSuccess(itemID: UUID, host: String?) {
        protectionState.noteSuccess(itemID: itemID, host: host)
    }

    private func noteImageFailure(itemID: UUID, host: String?, kind: ImageFailureKind) -> String? {
        let outcome = protectionState.noteFailure(itemID: itemID, host: host, kind: kind)
        if let cooldownHost = outcome.cooldownHost {
            let seconds = kind == .timeout ? Int(hostTimeoutCooldownSeconds) : Int(hostThrottleCooldownSeconds)
            let reason = kind == .timeout ? "连续超时" : "连续风控"
            log("图片 host 进入冷却：\(cooldownHost) \(seconds)s（\(reason)）")
        }
        return outcome.message
    }

    private func hostCooldownRemaining(for host: String?) -> TimeInterval? {
        protectionState.cooldownRemaining(for: host)
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

struct DownloadRequestError: LocalizedError {
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

private struct DownloadCircuitBreakError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

actor RequestPacer {
    private var minDelayMS: Int
    private var maxDelayMS: Int
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

    func waitTurn() async throws {
        try Task.checkCancellation()
        let spacingMS = Int.random(in: minDelayMS...maxDelayMS) + penaltyMS
        let now = Date()
        let scheduled = max(now, nextAllowedAt)
        nextAllowedAt = scheduled.addingTimeInterval(Double(spacingMS) / 1000.0)
        let waitMS = Int(max(0, scheduled.timeIntervalSince(now) * 1000))
        if waitMS > 0 {
            try await Task.sleep(for: .milliseconds(waitMS))
        }
        try Task.checkCancellation()
    }

    func markThrottled() {
        penaltyMS = min(maxPenaltyMS, penaltyMS + throttleStepMS)
    }

    func setDelayRange(_ range: ClosedRange<Int>) {
        minDelayMS = range.lowerBound
        maxDelayMS = max(range.upperBound, range.lowerBound)
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
