import Foundation

struct MangaSiteConfig: Hashable, Codable {
    let displayName: String
    let webBase: URL
    let apiBaseURLs: [URL]

    static let mangaCopy = MangaSiteConfig(
        displayName: "拷贝漫画",
        webBase: URL(string: "https://www.mangacopy.com")!,
        apiBaseURLs: [
            URL(string: "https://api.mangacopy.com/api/v3")!,
            URL(string: "https://www.mangacopy.com/api/v3")!
        ]
    )

    static let manhuaGui = MangaSiteConfig(
        displayName: "漫画柜",
        webBase: URL(string: "https://www.manhuagui.com")!,
        apiBaseURLs: [
            URL(string: "https://www.manhuagui.com")!
        ]
    )
}

enum CopyMangaMirror: String, CaseIterable, Identifiable {
    case mangacopy = "mangacopy.com"
    case copy2025 = "2025copy.com"
    case copy2026 = "2026copy.com"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .mangacopy: return "主站 (mangacopy)"
        case .copy2025: return "备用一 (2025)"
        case .copy2026: return "备用二 (2026)"
        }
    }

    var bareHost: String { rawValue }

    var wwwHost: String { "www.\(rawValue)" }

    var webBaseURL: URL { URL(string: "https://\(wwwHost)")! }

    func hostCandidates(prioritizing requestedHost: String? = nil) -> [String] {
        let normalizedHost = requestedHost?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let prefersBare = normalizedHost.map { !$0.hasPrefix("www.") } ?? false
        let baseline = prefersBare ? [bareHost, wwwHost] : [wwwHost, bareHost]
        if let normalizedHost, normalizedHost.contains(rawValue) {
            return CopyMangaMirror.dedupedHosts([normalizedHost] + baseline)
        }
        return baseline
    }

    func siteConfig(preferredHost: String? = nil) -> MangaSiteConfig {
        let hostOrder = hostCandidates(prioritizing: preferredHost)
        let webHost = hostOrder.first ?? wwwHost

        var apiBaseURLs: [URL] = []
        for host in CopyMangaMirror.dedupedHosts(["api.\(rawValue)"] + hostOrder + hostCandidates()) {
            if let url = URL(string: "https://\(host)/api/v3") {
                apiBaseURLs.append(url)
            }
        }

        return MangaSiteConfig(
            displayName: "拷贝漫画",
            webBase: URL(string: "https://\(webHost)")!,
            apiBaseURLs: apiBaseURLs
        )
    }

    static func mirror(for host: String?) -> CopyMangaMirror? {
        guard let normalizedHost = host?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() else {
            return nil
        }
        return allCases.first { normalizedHost.contains($0.rawValue) }
    }

    static func fallbackSiteConfigs(startingFrom requestedHost: String?) -> [MangaSiteConfig] {
        let normalizedHost = requestedHost?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let preferredMirror = mirror(for: normalizedHost) ?? .mangacopy
        let prefersBare = normalizedHost.map { !$0.hasPrefix("www.") } ?? false
        let mirrorOrder = [preferredMirror] + allCases.filter { $0 != preferredMirror }

        var seenHosts: Set<String> = []
        var configs: [MangaSiteConfig] = []

        for mirror in mirrorOrder {
            let preferredHost: String?
            if mirror == preferredMirror {
                preferredHost = normalizedHost
            } else {
                preferredHost = prefersBare ? mirror.bareHost : mirror.wwwHost
            }

            for host in mirror.hostCandidates(prioritizing: preferredHost) {
                if seenHosts.insert(host).inserted {
                    configs.append(mirror.siteConfig(preferredHost: host))
                }
            }
        }

        return configs
    }

    private static func dedupedHosts(_ hosts: [String]) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for host in hosts {
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            if seen.insert(normalized).inserted {
                ordered.append(normalized)
            }
        }
        return ordered
    }
}

struct ComicVolume: Identifiable, Hashable, Codable {
    let id: String
    let displayName: String
    let pathWord: String
    let chapters: [ComicChapter]
}

struct ComicChapter: Identifiable, Hashable, Codable {
    let id: String
    let uuid: String
    let displayName: String
    let order: Double
    let volumeID: String
    let volumeName: String
}

func isDefaultVolumeName(_ name: String) -> Bool {
    let text = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if text.isEmpty { return true }
    let defaults = [
        "默认卷", "默认", "默認卷", "默認", "default",
        "volume", "volumes", "group",
        "章节", "章節", "目录", "目錄",
        "all", "全部"
    ]
    return defaults.contains(text)
}

func canonicalGroupName(_ raw: String) -> String {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return text.isEmpty ? "默认" : text
}

func canonicalGroupKey(_ raw: String) -> String {
    canonicalGroupName(raw).folding(
        options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
        locale: Locale.current
    )
}

struct ComicInfo: Codable {
    let slug: String
    let name: String
    let coverURL: URL?
    let volumes: [ComicVolume]
    let site: MangaSiteConfig
    let apiPathPrefix: String
    let apiBaseURL: URL
}

struct DownloadTaskItem: Identifiable, Codable {
    enum State: Equatable, Codable {
        case queued
        case running
        case done
        case canceled
        case failed(String)
    }

    let id: UUID
    let comic: ComicInfo
    let chapter: ComicChapter
    var state: State
    let destination: URL
    let cookie: String?

    init(id: UUID = UUID(), comic: ComicInfo, chapter: ComicChapter, state: State, destination: URL, cookie: String?) {
        self.id = id
        self.comic = comic
        self.chapter = chapter
        self.state = state
        self.destination = destination
        self.cookie = cookie
    }

    var queueIdentity: String {
        [
            comic.slug.lowercased(),
            chapter.id.lowercased(),
            destination.path.lowercased()
        ].joined(separator: "::")
    }
}

struct RecentComicRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let title: String
    let input: String
    let siteName: String
    let updatedAt: Date

    init(id: UUID = UUID(), title: String, input: String, siteName: String, updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.input = input
        self.siteName = siteName
        self.updatedAt = updatedAt
    }
}
