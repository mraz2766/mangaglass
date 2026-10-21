import Foundation

/// How hard downloads lean on a site. `smart` adapts between the other two.
enum DownloadPacingMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case smart
    case efficient
    case safe

    static let storageKey = "downloadPacingMode"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "智能"
        case .efficient: return "偏效率"
        case .safe: return "偏稳妥"
        }
    }

    var detail: String {
        switch self {
        case .smart:
            return "从中等速度开始，顺利时逐步提速，遇到限流立即降速并冷却后自动继续。"
        case .efficient:
            return "并发更高、间隔更短，适合站点状态良好、想尽快下完时使用；仍会在限流时降速。"
        case .safe:
            return "单话或少量并发、更长间隔并定时休息，适合大批量下载或刚被限流过。"
        }
    }
}

/// Sites that share limits; pacing is tracked per family.
enum SiteFamily: String, CaseIterable, Sendable {
    case copy
    case manhuaGui
    case other

    static func of(_ site: MangaSiteConfig) -> SiteFamily {
        let host = site.webBase.host?.lowercased() ?? ""
        if host.contains("manhuagui.com") { return .manhuaGui }
        if CopyMangaMirror.mirror(for: host) != nil { return .copy }
        return .other
    }

    var title: String {
        switch self {
        case .copy: return "拷贝漫画"
        case .manhuaGui: return "漫画柜"
        case .other: return "包子漫画"
        }
    }
}

/// One family's limits under one mode. Ranges are inclusive; `smart` moves within them.
struct SitePacing: Equatable, Sendable {
    /// Chapters downloading at the same time.
    var chapterConcurrency: ClosedRange<Int>
    /// Images in flight within one chapter.
    var imageConcurrencyPerChapter: Int
    /// Copy only: image slots shared by all chapters.
    var globalImageConcurrency: ClosedRange<Int>
    /// Random spacing between image requests on the site's shared pacer.
    var imageSpacingMS: ClosedRange<Int>
    /// Minimum spacing between two chapters starting (each start fetches a chapter page).
    var chapterGapMS: ClosedRange<Int>
    /// After this many chapters, pause new chapters for `restSeconds` (0 = never).
    var restEveryChapters: Int
    var restSeconds: ClosedRange<Int>
    /// Whole-site pause after a confirmed rate limit; resumes on its own.
    var throttleCooldown: TimeInterval
    /// Consecutive successful images before stepping up one level (0 = fixed pace).
    var successesToStepUp: Int
    /// Level the run starts at (0 = lower bounds).
    var startLevel: Int

    var maxLevel: Int {
        max(chapterConcurrency.upperBound - chapterConcurrency.lowerBound,
            globalImageConcurrency.upperBound - globalImageConcurrency.lowerBound)
    }

    static func make(mode: DownloadPacingMode, family: SiteFamily) -> SitePacing {
        switch (family, mode) {
        // 漫画柜: the old fixed pace (4 chapters, 240–460ms, no rests) is now "efficient".
        case (.manhuaGui, .safe):
            return SitePacing(chapterConcurrency: 1...1, imageConcurrencyPerChapter: 2, globalImageConcurrency: 1...1,
                              imageSpacingMS: 500...900, chapterGapMS: 5000...8000,
                              restEveryChapters: 10, restSeconds: 90...150, throttleCooldown: 15 * 60,
                              successesToStepUp: 0, startLevel: 0)
        case (.manhuaGui, .smart):
            return SitePacing(chapterConcurrency: 1...3, imageConcurrencyPerChapter: 2, globalImageConcurrency: 1...1,
                              imageSpacingMS: 320...600, chapterGapMS: 2500...4500,
                              restEveryChapters: 20, restSeconds: 45...90, throttleCooldown: 8 * 60,
                              successesToStepUp: 60, startLevel: 1)
        case (.manhuaGui, .efficient):
            return SitePacing(chapterConcurrency: 2...4, imageConcurrencyPerChapter: 2, globalImageConcurrency: 1...1,
                              imageSpacingMS: 240...460, chapterGapMS: 1000...2000,
                              restEveryChapters: 40, restSeconds: 20...40, throttleCooldown: 4 * 60,
                              successesToStepUp: 30, startLevel: 2)
        case (.copy, .safe):
            return SitePacing(chapterConcurrency: 2...2, imageConcurrencyPerChapter: 2, globalImageConcurrency: 3...3,
                              imageSpacingMS: 150...300, chapterGapMS: 1500...2500,
                              restEveryChapters: 15, restSeconds: 30...60, throttleCooldown: 20 * 60,
                              successesToStepUp: 0, startLevel: 0)
        case (.copy, .smart):
            return SitePacing(chapterConcurrency: 2...3, imageConcurrencyPerChapter: 3, globalImageConcurrency: 4...6,
                              imageSpacingMS: 80...180, chapterGapMS: 650...1050,
                              restEveryChapters: 30, restSeconds: 20...40, throttleCooldown: 20 * 60,
                              successesToStepUp: 80, startLevel: 1)
        case (.copy, .efficient):
            return SitePacing(chapterConcurrency: 3...3, imageConcurrencyPerChapter: 3, globalImageConcurrency: 6...8,
                              imageSpacingMS: 60...140, chapterGapMS: 400...800,
                              restEveryChapters: 60, restSeconds: 10...20, throttleCooldown: 20 * 60,
                              successesToStepUp: 40, startLevel: 2)
        case (.other, .safe):
            return SitePacing(chapterConcurrency: 2...2, imageConcurrencyPerChapter: 2, globalImageConcurrency: 1...1,
                              imageSpacingMS: 200...400, chapterGapMS: 1000...2000,
                              restEveryChapters: 20, restSeconds: 30...60, throttleCooldown: 10 * 60,
                              successesToStepUp: 0, startLevel: 0)
        case (.other, .smart):
            return SitePacing(chapterConcurrency: 3...5, imageConcurrencyPerChapter: 3, globalImageConcurrency: 1...1,
                              imageSpacingMS: 80...180, chapterGapMS: 400...800,
                              restEveryChapters: 40, restSeconds: 15...30, throttleCooldown: 5 * 60,
                              successesToStepUp: 80, startLevel: 1)
        case (.other, .efficient):
            return SitePacing(chapterConcurrency: 5...5, imageConcurrencyPerChapter: 3, globalImageConcurrency: 1...1,
                              imageSpacingMS: 60...140, chapterGapMS: 200...500,
                              restEveryChapters: 80, restSeconds: 10...15, throttleCooldown: 3 * 60,
                              successesToStepUp: 40, startLevel: 2)
        }
    }
}

/// Live pacing for one site family: additive increase on sustained success,
/// drop to the floor on any rate-limit signal, plus chapter-start scheduling with rests.
struct AdaptivePacingState: Equatable, Sendable {
    let pacing: SitePacing
    private(set) var level: Int
    private(set) var successStreak = 0
    private(set) var chaptersSinceRest = 0
    private(set) var nextChapterAt: Date = .distantPast

    init(pacing: SitePacing) {
        self.pacing = pacing
        self.level = min(pacing.startLevel, pacing.maxLevel)
    }

    var chapterConcurrency: Int {
        min(pacing.chapterConcurrency.upperBound, pacing.chapterConcurrency.lowerBound + level)
    }

    var globalImageConcurrency: Int {
        min(pacing.globalImageConcurrency.upperBound, pacing.globalImageConcurrency.lowerBound + level)
    }

    /// Returns true when the level went up.
    mutating func noteSuccess() -> Bool {
        guard pacing.successesToStepUp > 0 else { return false }
        successStreak += 1
        guard successStreak >= pacing.successesToStepUp, level < pacing.maxLevel else { return false }
        level += 1
        successStreak = 0
        return true
    }

    /// Returns true when the level went down.
    mutating func noteThrottle() -> Bool {
        successStreak = 0
        guard level > 0 else { return false }
        level = 0
        return true
    }

    /// Reserves the next chapter start. Slots are handed out in order, `gap` apart, with a
    /// `rest` inserted every `restEveryChapters` chapters. Returns how long the caller must wait.
    mutating func reserveChapterSlot(now: Date, gap: TimeInterval, rest: TimeInterval) -> (wait: TimeInterval, rested: Bool) {
        var start = max(now, nextChapterAt)
        var rested = false
        if pacing.restEveryChapters > 0, chaptersSinceRest >= pacing.restEveryChapters {
            start = start.addingTimeInterval(rest)
            chaptersSinceRest = 0
            rested = true
        }
        chaptersSinceRest += 1
        nextChapterAt = start.addingTimeInterval(gap)
        return (start.timeIntervalSince(now), rested)
    }

    /// Pushes the next chapter start out (used for whole-site cooldowns).
    mutating func postpone(until date: Date) {
        nextChapterAt = max(nextChapterAt, date)
    }
}
