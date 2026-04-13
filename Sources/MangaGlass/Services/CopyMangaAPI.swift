import Foundation
import JavaScriptCore
import CommonCrypto

enum CopyMangaError: LocalizedError {
    case invalidURL
    case invalidComicPath
    case unexpectedPayload
    case noImageInChapter(String)
    case httpStatus(Int, String)
    case invalidJSON(contentType: String, snippet: String)
    case allEndpoints404([String])
    case payloadShape([String])
    case apiDetail(String)
    case parseBlocked(String)
    case cooldown(Int)
    case htmlParse(String)
    case copyMirrorsUnavailable([String])

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "链接无效。"
        case .invalidComicPath:
            return "无法从链接中解析漫画 path_word。"
        case .unexpectedPayload:
            return "接口返回结构已变化，请更新解析逻辑。"
        case .noImageInChapter(let chapter):
            return "章节 \(chapter) 未发现图片地址。"
        case .httpStatus(let status, let body):
            return "请求失败（HTTP \(status)）。\(body)"
        case .invalidJSON(let contentType, let snippet):
            return "接口返回非 JSON（Content-Type: \(contentType)）。响应片段：\(snippet)"
        case .allEndpoints404(let urls):
            return "接口全部返回 404。已尝试：\(urls.joined(separator: " | "))"
        case .payloadShape(let keys):
            return "接口返回结构已变化（顶层 keys: \(keys.joined(separator: ", "))）"
        case .apiDetail(let detail):
            return "接口返回详情：\(detail)"
        case .parseBlocked(let detail):
            return "疑似触发站点风控：\(detail)"
        case .cooldown(let seconds):
            return "疑似触发风控，已进入冷却期，请 \(seconds) 秒后再试。"
        case .htmlParse(let detail):
            return "页面解析失败：\(detail)"
        case .copyMirrorsUnavailable(let attempts):
            return "拷贝漫画镜像均未返回有效目录。已尝试：\(attempts.joined(separator: " | "))"
        }
    }
}

struct ResolvedAPI {
    let baseURL: URL
    let pathPrefix: String
}

private struct CopyWebFetchResult {
    let info: ComicInfo
    let expectedCounts: (volumes: Int?, chapters: Int?)
    let usedSingleShareFallback: Bool
}

private struct CopyCatalogEvaluation {
    let isAcceptable: Bool
    let canUseAsLastResort: Bool
    let reason: String
}

private struct CopyDetailProbeResult {
    let volumes: [ComicVolume]
    let requestCount: Int
}

private struct SiteParserAdapter {
    let supports: (MangaSiteConfig) -> Bool
    let resolveTarget: (URL, [String]) -> String?
    let fetchComic: (String, MangaSiteConfig, String?) async throws -> ComicInfo
    let fetchImageURLs: (String, String, String, MangaSiteConfig, String?) async throws -> [URL]
    let imageRefererURL: (String, String, MangaSiteConfig) -> URL
}

final class CopyMangaAPI: @unchecked Sendable {
    private var session: URLSession
    private let endpointCache = EndpointCache()
    private let comicInfoCache = ComicInfoCache()
    private let siteHeuristics = SiteHeuristicsCache()
    private let copyMirrorCache = CopyMirrorHealthCache()
    private let copyScriptCache = TextAssetCache(ttl: 6 * 60 * 60)
    private let chapterImageURLCache = ChapterImageURLCache(ttl: 45 * 60)
    private let antiBanGuard = AntiBanGuard()
    private let apiPacer = RequestPacer(
        minDelayMS: 420,
        maxDelayMS: 820,
        maxPenaltyMS: 0,
        throttleStepMS: 1,
        relaxStepMS: 1
    )
    private let copyBanCooldownSeconds = 180
    private var logger: ((String) -> Void)?
    private var intermediateComicHandler: ((ComicInfo) -> Void)?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            self.session = ProxySessionFactory.makeSession(
                timeoutRequest: 20,
                timeoutResource: 60,
                maxConnections: 10
            )
        }
    }

    func setLogger(_ logger: @escaping (String) -> Void) {
        self.logger = logger
    }

    func setIntermediateComicHandler(_ handler: @escaping (ComicInfo) -> Void) {
        self.intermediateComicHandler = handler
    }

    func resolveTarget(from input: String) throws -> (slug: String, site: MangaSiteConfig) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            guard let url = URL(string: trimmed) else { throw CopyMangaError.invalidURL }
            let host = url.host?.lowercased()
            let isSupportedHost =
                (host?.contains("manhuagui.com") == true) ||
                (CopyMangaMirror.mirror(for: host) != nil)
            guard isSupportedHost else { throw CopyMangaError.invalidComicPath }
            let site = siteConfig(for: url.host)
            let parts = url.pathComponents.filter { $0 != "/" }
            if let adapter = parserAdapter(for: site),
               let resolved = adapter.resolveTarget(url, parts) {
                return (resolved, site)
            }
            throw CopyMangaError.invalidComicPath
        }
        if !trimmed.isEmpty {
            return (trimmed, CopyMangaMirror.mangacopy.siteConfig())
        }
        throw CopyMangaError.invalidComicPath
    }

    func parseSlug(from input: String) throws -> String {
        try resolveTarget(from: input).slug
    }

    func cachedComic(slug: String, site: MangaSiteConfig) async -> ComicInfo? {
        await comicInfoCache.get(slug: slug, site: site)
    }

    func clearCaches() async {
        await endpointCache.clear()
        await comicInfoCache.clear()
        await siteHeuristics.clear()
        await copyMirrorCache.clear()
        await copyScriptCache.clear()
        await chapterImageURLCache.clear()
        await antiBanGuard.clear()
        log("已清空解析缓存与镜像冷却状态")
    }

    private func siteConfig(for host: String?) -> MangaSiteConfig {
        guard let host = host?.lowercased() else { return CopyMangaMirror.mangacopy.siteConfig() }
        if host.contains("manhuagui.com") {
            return .manhuaGui
        }

        if let mirror = CopyMangaMirror.mirror(for: host) {
            return mirror.siteConfig(preferredHost: host)
        }

        return CopyMangaMirror.mangacopy.siteConfig()
    }

    func fetchComic(slug: String, site: MangaSiteConfig, cookie: String?, preferCache: Bool = true) async throws -> ComicInfo {
        log("加载漫画：\(slug) @ \(site.displayName)")
        if preferCache, let cached = await comicInfoCache.get(slug: slug, site: site) {
            log("加载漫画：命中缓存 \(slug)")
            return cached
        }
        if let adapter = parserAdapter(for: site) {
            do {
                let info = try await adapter.fetchComic(slug, site, cookie)
                let normalized = normalizeComicInfoVolumes(info)
                await comicInfoCache.set(normalized, slug: normalized.slug, site: normalized.site)
                if normalized.slug != slug {
                    await comicInfoCache.set(normalized, slug: slug, site: normalized.site)
                }
                return normalized
            } catch {
                throw normalizeSiteError(error, site: site, phase: "漫画解析")
            }
        }

        log("使用 API 解析分支：\(site.displayName)")
        let resolved = try await resolveAPI(slug: slug, site: site, cookie: cookie, forceRefresh: false)
        let meta = try await getJSON(path: "\(resolved.pathPrefix)/\(slug)", site: site, cookie: cookie, baseURL: resolved.baseURL)
        let results = try primaryObject(from: meta)

        let comicName = JSONNavigator.string(results, keys: ["name", "title"]) ?? slug
        let coverRaw = JSONNavigator.string(results, keys: ["cover", "cover_url", "image"])
        let coverURL = normalizedURL(coverRaw, site: site)

        let groups = parseGroups(from: results)
        var volumes: [ComicVolume] = []

        if !groups.isEmpty {
            let limiter = APIConcurrencyLimiter(limit: 2)
            await withTaskGroup(of: ComicVolume?.self) { group in
                for g in groups {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        await limiter.acquire()
                        defer { Task { await limiter.release() } }
                        return try? await self.fetchVolume(
                            slug: slug,
                            groupPathWord: g.pathWord,
                            fallbackName: g.name,
                            cookie: cookie,
                            site: site,
                            resolved: resolved
                        )
                    }
                }
                for await volume in group {
                    if let volume {
                        volumes.append(volume)
                    }
                }
            }
            volumes.sort { $0.displayName < $1.displayName }
        }

        if volumes.isEmpty, let inline = parseInlineVolume(from: results) {
            volumes = [inline]
        }

        if volumes.isEmpty {
            throw CopyMangaError.payloadShape(Array(results.keys).sorted())
        }

        let info = ComicInfo(
            slug: slug,
            name: comicName,
            coverURL: coverURL,
            volumes: volumes,
            site: site,
            apiPathPrefix: resolved.pathPrefix,
            apiBaseURL: resolved.baseURL
        )
        let normalized = normalizeComicInfoVolumes(info)
        await comicInfoCache.set(normalized, slug: slug, site: normalized.site)
        return normalized
    }

    private func normalizeComicInfoVolumes(_ info: ComicInfo) -> ComicInfo {
        let normalized = normalizeVolumes(info.volumes)
        return ComicInfo(
            slug: info.slug,
            name: info.name,
            coverURL: info.coverURL,
            volumes: normalized,
            site: info.site,
            apiPathPrefix: info.apiPathPrefix,
            apiBaseURL: info.apiBaseURL
        )
    }

    private func normalizeVolumes(_ volumes: [ComicVolume]) -> [ComicVolume] {
        struct Bucket {
            var displayName: String
            var pathWord: String
            var chapters: [ComicChapter] = []
            var seenUUIDs: Set<String> = []
            var order: Int
        }

        var buckets: [String: Bucket] = [:]
        var nextGroupOrder = 0
        for volume in volumes {
            let rawVolumeName = volume.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            for chapter in volume.chapters {
                // When source volume name is generic (e.g. "默认卷"), keep chapter-level
                // grouping info collected from rendered DOM/API instead of overriding it.
                var sourceGroupName: String
                if rawVolumeName.isEmpty || isDefaultVolumeName(rawVolumeName) {
                    sourceGroupName = chapter.volumeName
                } else {
                    sourceGroupName = rawVolumeName
                }
                if isDefaultVolumeName(sourceGroupName),
                   let inferred = inferGroupNameFromChapterTitle(chapter.displayName) {
                    sourceGroupName = inferred
                }

                let displayName = canonicalGroupName(sourceGroupName)
                let key = canonicalGroupKey(displayName)

                if buckets[key] == nil {
                    buckets[key] = Bucket(
                        displayName: displayName,
                        pathWord: volume.pathWord,
                        chapters: [],
                        seenUUIDs: [],
                        order: nextGroupOrder
                    )
                    nextGroupOrder += 1
                } else {
                    if isDefaultVolumeName(buckets[key]!.displayName), !isDefaultVolumeName(displayName) {
                        buckets[key]!.displayName = displayName
                    }
                    let currentPathWord = buckets[key]!.pathWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    let incomingPathWord = volume.pathWord.trimmingCharacters(in: .whitespacesAndNewlines)
                    if currentPathWord.isEmpty || isDefaultVolumeName(currentPathWord) {
                        if !incomingPathWord.isEmpty {
                            buckets[key]!.pathWord = incomingPathWord
                        }
                    }
                }

                let chapterUUID = chapter.uuid.trimmingCharacters(in: .whitespacesAndNewlines)
                let chapterIDRaw = chapter.id.trimmingCharacters(in: .whitespacesAndNewlines)
                let fallbackID: String = {
                    if let range = chapterIDRaw.range(of: "::", options: .backwards) {
                        return String(chapterIDRaw[range.upperBound...])
                    }
                    return chapterIDRaw
                }()
                let uniqueBase = chapterUUID.isEmpty ? fallbackID : chapterUUID
                if !uniqueBase.isEmpty {
                    if !buckets[key]!.seenUUIDs.insert(uniqueBase).inserted {
                        continue
                    }
                }

                let chapterID = "\(key)::\(uniqueBase)"
                let rewritten = ComicChapter(
                    id: chapterID,
                    uuid: uniqueBase,
                    displayName: chapter.displayName,
                    order: chapter.order,
                    volumeID: key,
                    volumeName: buckets[key]!.displayName
                )
                buckets[key]!.chapters.append(rewritten)
            }
        }

        let ordered = buckets.sorted { lhs, rhs in
            if lhs.value.order == rhs.value.order {
                return lhs.value.displayName.localizedCompare(rhs.value.displayName) == .orderedAscending
            }
            return lhs.value.order < rhs.value.order
        }

        let result: [ComicVolume] = ordered.map { key, bucket in
            let sortedChapters = bucket.chapters.sorted { lhs, rhs in
                let left = lhs.order
                let right = rhs.order
                if left == right {
                    return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
                }
                return left < right
            }
            return ComicVolume(
                id: key,
                displayName: bucket.displayName,
                pathWord: bucket.pathWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? key : bucket.pathWord,
                chapters: sortedChapters
            )
        }

        return result
    }

    private func inferGroupNameFromChapterTitle(_ title: String) -> String? {
        let text = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale.current)
        guard !text.isEmpty else { return nil }

        if text.contains("番外") || text.contains("外传") || text.contains("外傳") ||
            text.contains("特別") || text.contains("特别") || text.contains("附录") || text.contains("附錄") ||
            text.contains("sp") {
            return "番外"
        }
        if text.contains("卷") || text.contains("冊") || text.contains("册") {
            return "卷"
        }
        if text.contains("话") || text.contains("話") {
            return "话"
        }
        return nil
    }

    func fetchImageURLs(slug: String, chapterUUID: String, chapterName: String, site: MangaSiteConfig, preferredPrefix: String, preferredBaseURL: URL, cookie: String?) async throws -> [URL] {
        if let cached = await chapterImageURLCache.get(slug: slug, chapterID: chapterUUID, site: site) {
            log("章节图片解析：命中 URL 缓存 \(chapterName)（\(cached.count) 张）")
            return cached
        }

        let urls: [URL]
        if let adapter = parserAdapter(for: site) {
            do {
                urls = try await adapter.fetchImageURLs(slug, chapterUUID, chapterName, site, cookie)
            } catch {
                throw normalizeSiteError(error, site: site, phase: "章节取图")
            }
        } else {
            var candidatePaths: [String] = [
                "\(preferredPrefix)/\(slug)/chapter2/\(chapterUUID)",
                "\(preferredPrefix)/\(slug)/chapter/\(chapterUUID)"
            ]
            if preferredPrefix == "comic" {
                candidatePaths.append("comic2/\(slug)/chapter2/\(chapterUUID)")
            } else {
                candidatePaths.append("comic/\(slug)/chapter2/\(chapterUUID)")
            }

            let payload = try await getJSON(paths: candidatePaths, site: site, cookie: cookie, preferredBaseURL: preferredBaseURL)
            let results = try primaryObject(from: payload)

            let chapterNode = (results["chapter"] as? [String: Any]) ?? results
            let contents =
                JSONNavigator.array(chapterNode, keys: ["contents", "images", "pages"]) ??
                JSONNavigator.array(results, keys: ["contents", "images", "pages"]) ??
                []

            urls = contents.compactMap { item in
                if let raw = item as? String, let url = normalizedURL(raw, site: site) {
                    return url
                }
                guard let dict = item as? [String: Any] else { return nil }
                let candidates = ["url", "image", "src", "origin", "raw", "image_url", "file"]
                for key in candidates {
                    if let value = dict[key] as? String, let url = normalizedURL(value, site: site) {
                        return url
                    }
                }
                return nil
            }
        }

        if urls.isEmpty {
            throw CopyMangaError.noImageInChapter(chapterName)
        }
        await chapterImageURLCache.set(urls, slug: slug, chapterID: chapterUUID, site: site)
        return urls
    }

    func imageRefererURL(slug: String, chapterUUID: String, site: MangaSiteConfig) -> URL {
        parserAdapter(for: site)?.imageRefererURL(slug, chapterUUID, site) ?? site.webBase
    }

    private func isManhuaGui(_ site: MangaSiteConfig) -> Bool {
        site.webBase.host?.lowercased().contains("manhuagui.com") == true
    }

    private func isCopyFamily(_ site: MangaSiteConfig) -> Bool {
        guard let host = site.webBase.host?.lowercased() else { return false }
        for mirror in CopyMangaMirror.allCases {
            if host.contains(mirror.rawValue) {
                return true
            }
        }
        return false
    }

    private var copyParserAdapter: SiteParserAdapter {
        SiteParserAdapter(
            supports: { [weak self] site in self?.isCopyFamily(site) == true },
            resolveTarget: { _, parts in
                if let comicIndex = parts.firstIndex(of: "comic"), parts.count > comicIndex + 1 {
                    return parts[comicIndex + 1]
                }
                return parts.last
            },
            fetchComic: { [weak self] slug, site, cookie in
                guard let self else { throw CopyMangaError.unexpectedPayload }
                self.log("使用网页解析分支：Copy 家族")
                return try await self.fetchComicFromCopyMirrors(slug: slug, requestedSite: site, cookie: cookie)
            },
            fetchImageURLs: { [weak self] slug, chapterUUID, chapterName, site, cookie in
                guard let self else { throw CopyMangaError.unexpectedPayload }
                self.log("章节图片解析：Copy 网页模式 \(chapterName)")
                return try await self.fetchImageURLsFromCopyWeb(
                    slug: slug,
                    chapterID: chapterUUID,
                    chapterName: chapterName,
                    site: site,
                    cookie: cookie
                )
            },
            imageRefererURL: { _, _, site in
                site.webBase
            }
        )
    }

    private var manhuaGuiParserAdapter: SiteParserAdapter {
        SiteParserAdapter(
            supports: { [weak self] site in self?.isManhuaGui(site) == true },
            resolveTarget: { _, parts in
                if let comicIndex = parts.firstIndex(of: "comic"), parts.count > comicIndex + 1 {
                    return parts[comicIndex + 1]
                }
                return parts.last
            },
            fetchComic: { [weak self] slug, site, cookie in
                guard let self else { throw CopyMangaError.unexpectedPayload }
                self.log("使用网页解析分支：ManhuaGui")
                return try await self.fetchComicFromManhuaGui(slug: slug, site: site, cookie: cookie)
            },
            fetchImageURLs: { [weak self] slug, chapterUUID, chapterName, site, cookie in
                guard let self else { throw CopyMangaError.unexpectedPayload }
                self.log("章节图片解析：网页模式 \(chapterName)")
                return try await self.fetchImageURLsFromManhuaGui(
                    slug: slug,
                    chapterID: chapterUUID,
                    chapterName: chapterName,
                    site: site,
                    cookie: cookie
                )
            },
            imageRefererURL: { _, _, site in
                site.webBase
            }
        )
    }

    private var siteParserAdapters: [SiteParserAdapter] {
        [copyParserAdapter, manhuaGuiParserAdapter]
    }

    private func parserAdapter(for site: MangaSiteConfig) -> SiteParserAdapter? {
        siteParserAdapters.first { $0.supports(site) }
    }

    private func normalizeSiteError(_ error: Error, site: MangaSiteConfig, phase: String) -> CopyMangaError {
        if let known = error as? CopyMangaError {
            return known
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .htmlParse("\(site.displayName)\(phase)超时。")
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return .htmlParse("\(site.displayName)\(phase)网络连接失败。")
            default:
                return .htmlParse("\(site.displayName)\(phase)失败：\(urlError.localizedDescription)")
            }
        }
        return .htmlParse("\(site.displayName)\(phase)失败：\(error.localizedDescription)")
    }

    private func copyMirrorCandidateSites(for requestedSite: MangaSiteConfig) -> [MangaSiteConfig] {
        CopyMangaMirror.fallbackSiteConfigs(startingFrom: requestedSite.webBase.host)
    }

    private func describeCopySite(_ site: MangaSiteConfig) -> String {
        site.webBase.host?.lowercased() ?? site.webBase.absoluteString
    }

    private func evaluateCopyCatalog(_ result: CopyWebFetchResult) -> CopyCatalogEvaluation {
        let info = result.info
        let chapters = info.volumes.reduce(0) { $0 + $1.chapters.count }
        let groups = info.volumes.count
        let expectedChapters = result.expectedCounts.chapters ?? 0
        let hasNonDefaultGroup = info.volumes.contains { !isDefaultVolumeName($0.displayName) }
        let nearExpected = expectedChapters > 0 && chapters + 3 >= expectedChapters
        let singleShareFallback = result.usedSingleShareFallback ||
            (groups == 1 && info.volumes.first?.id == "single")

        if chapters == 0 {
            return CopyCatalogEvaluation(isAcceptable: false, canUseAsLastResort: false, reason: "未识别到可用目录")
        }
        if chapters > 1 && (expectedChapters == 0 || nearExpected || hasNonDefaultGroup || groups > 1 || chapters >= 20) {
            let expectedSuffix = expectedChapters > 0 ? "，页面约 \(expectedChapters) 话" : ""
            return CopyCatalogEvaluation(isAcceptable: true, canUseAsLastResort: false, reason: "目录有效（章节 \(chapters)\(expectedSuffix)）")
        }
        if expectedChapters > 1 {
            return CopyCatalogEvaluation(
                isAcceptable: false,
                canUseAsLastResort: false,
                reason: singleShareFallback
                    ? "仅识别到单话入口（章节 \(chapters)，页面约 \(expectedChapters) 话）"
                    : "目录不完整（章节 \(chapters)，页面约 \(expectedChapters) 话）"
            )
        }
        if singleShareFallback {
            return CopyCatalogEvaluation(
                isAcceptable: expectedChapters == 1,
                canUseAsLastResort: true,
                reason: expectedChapters == 1 ? "识别为单话作品" : "仅识别到单话入口"
            )
        }
        if chapters == 1 {
            return CopyCatalogEvaluation(
                isAcceptable: expectedChapters == 1,
                canUseAsLastResort: false,
                reason: expectedChapters == 1 ? "识别为单话作品" : "仅识别到 1 话"
            )
        }
        return CopyCatalogEvaluation(
            isAcceptable: false,
            canUseAsLastResort: false,
            reason: "目录不完整（章节 \(chapters)）"
        )
    }

    private func fetchComicFromCopyMirrors(slug: String, requestedSite: MangaSiteConfig, cookie: String?) async throws -> ComicInfo {
        let candidates = await copyMirrorCache.prioritize(
            copyMirrorCandidateSites(for: requestedSite),
            requestedSite: requestedSite
        )
        let requestedHost = describeCopySite(requestedSite)
        let requestedMirror = CopyMangaMirror.mirror(for: requestedSite.webBase.host)
        var fallbackResult: CopyWebFetchResult?
        var attemptMessages: [String] = []

        for candidate in candidates {
            let host = describeCopySite(candidate)
            if host == requestedHost {
                log("Copy 镜像尝试：主镜像 \(host)")
            } else if CopyMangaMirror.mirror(for: candidate.webBase.host) == requestedMirror {
                log("Copy 镜像尝试：同镜像 host 回退 \(host)")
            } else {
                log("Copy 镜像尝试：跨镜像回退 \(host)")
            }

            do {
                let result = try await fetchComicFromCopyWeb(slug: slug, site: candidate, cookie: cookie)
                let evaluation = evaluateCopyCatalog(result)
                if evaluation.isAcceptable {
                    await copyMirrorCache.markSuccess(site: candidate)
                    log("Copy 镜像最终采用：\(host)（\(evaluation.reason)）")
                    return result.info
                }

                attemptMessages.append("\(host) \(evaluation.reason)")
                await copyMirrorCache.markFailure(site: candidate, seconds: copyMirrorCooldown(for: evaluation))
                log("Copy 镜像回退：\(host) \(evaluation.reason)")
                if evaluation.canUseAsLastResort, fallbackResult == nil {
                    fallbackResult = result
                }
            } catch let error as CopyMangaError where isBlockingCopyError(error) {
                attemptMessages.append("\(host) \(error.localizedDescription)")
                await copyMirrorCache.markFailure(site: candidate, seconds: copyMirrorCooldown(for: error))
                log("Copy 镜像停止探测：\(host) \(error.localizedDescription)")
                throw error
            } catch {
                attemptMessages.append("\(host) \(error.localizedDescription)")
                await copyMirrorCache.markFailure(site: candidate, seconds: copyMirrorCooldown(for: error))
                log("Copy 镜像回退：\(host) 请求失败 \(error.localizedDescription)")
            }
        }

        if let fallbackResult {
            let fallbackHost = describeCopySite(fallbackResult.info.site)
            log("Copy 镜像全部失败，采用最后单话兜底：\(fallbackHost)")
            return fallbackResult.info
        }

        throw CopyMangaError.copyMirrorsUnavailable(attemptMessages)
    }

    private func copyMirrorCooldown(for evaluation: CopyCatalogEvaluation) -> Int {
        if evaluation.canUseAsLastResort {
            return 120
        }
        return 300
    }

    private func copyMirrorCooldown(for error: Error) -> Int {
        if let error = error as? CopyMangaError {
            switch error {
            case .parseBlocked:
                return 20 * 60
            case .cooldown(let seconds):
                return max(seconds, 20 * 60)
            case .httpStatus(let code, _):
                return [403, 429, 503].contains(code) ? 20 * 60 : 5 * 60
            case .apiDetail(let detail):
                return isBanDetail(detail) ? 20 * 60 : 5 * 60
            default:
                return 5 * 60
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost:
                return 5 * 60
            default:
                return 3 * 60
            }
        }
        return 3 * 60
    }

    private func isBlockingCopyError(_ error: CopyMangaError) -> Bool {
        switch error {
        case .parseBlocked, .cooldown:
            return true
        case .apiDetail(let detail):
            return isBanDetail(detail)
        case .httpStatus(let code, _):
            return [403, 429, 503].contains(code)
        default:
            return false
        }
    }

    private func fetchComicFromCopyWeb(slug: String, site: MangaSiteConfig, cookie: String?) async throws -> CopyWebFetchResult {
        let comicURL = site.webBase.appendingPathComponent("comic/\(slug)")
        let html = try await getHTML(url: comicURL, cookie: cookie, site: site, retryTimes: 1)
        let expected = parseCopyExpectedCounts(html: html)
        var usedPaths: [String] = ["html"]
        var probeRequestCount = 1

        let titleFromMeta = firstMatch(
            in: html,
            pattern: #"(?is)<meta\s+property\s*=\s*["']og:title["']\s+content\s*=\s*["'](.*?)["']"#
        )
        let titleFromH1 = firstMatch(
            in: html,
            pattern: #"(?is)<h1[^>]*>(.*?)</h1>"#
        )
        let titleFromH6Attr = firstMatch(
            in: html,
            pattern: #"(?is)<h6[^>]*title\s*=\s*["'](.*?)["']"#
        )
        let titleFromH6 = firstMatch(
            in: html,
            pattern: #"(?is)<h6[^>]*>(.*?)</h6>"#
        )
        let rawName = titleFromH6Attr ?? titleFromH6 ?? titleFromMeta ?? titleFromH1 ?? slug
        let comicName = normalizeCopyComicName(rawName, fallback: slug)
        var coverURL = extractCoverURL(from: html, site: site)
        var usedSingleShareFallback = false

        var volumes: [ComicVolume] = []
        let htmlVolumes = parseCopyVolumesFromHTML(html: html, slug: slug)
        if !htmlVolumes.isEmpty {
            volumes = htmlVolumes
            log("Copy 网页解析：使用 HTML 章节提取，章节总数 \(htmlVolumes.reduce(0) { $0 + $1.chapters.count })")
        }

        let htmlCount = htmlVolumes.reduce(0) { $0 + $1.chapters.count }
        let expectedChapters = expected.chapters ?? 0
        let shouldProbeDetail =
            htmlCount == 0 ||
            (expectedChapters > 0 && htmlCount + 3 < expectedChapters) ||
            htmlCount < 20
        let detailProbe = shouldProbeDetail
            ? try await fetchCopyVolumesFromDetailEndpoint(slug: slug, html: html, site: site, cookie: cookie)
            : nil
        if shouldProbeDetail {
            usedPaths.append("comicdetail")
            probeRequestCount += detailProbe?.requestCount ?? 0
        } else {
            log("Copy 网页解析：HTML 章节已足够，跳过 comicdetail 探测（章节 \(htmlCount)）")
        }
        let detailCandidate = detailProbe?.volumes

        if let fromDetail = detailCandidate, !fromDetail.isEmpty {
            let localCount = volumes.reduce(0) { $0 + $1.chapters.count }
            let detailCount = fromDetail.reduce(0) { $0 + $1.chapters.count }
            if detailCount >= localCount {
                volumes = fromDetail
                log("Copy 网页解析：使用 comicdetail 接口，章节总数 \(detailCount)")
                log("Copy 网页解析：comicdetail 最终分组 \(volumesSummary(fromDetail))")
            } else {
                log("Copy 网页解析：保留 HTML 结果（\(localCount)）优于 comicdetail（\(detailCount)）")
            }
        }

        let staticAnchorCount = countCopyChapterAnchors(in: html, slug: slug)
        if let blockedReason = copyCatalogBlockedReason(
            html: html,
            slug: slug,
            expectedChapters: expected.chapters,
            currentCount: volumes.reduce(0) { $0 + $1.chapters.count },
            detailCount: detailCandidate?.reduce(0) { $0 + $1.chapters.count } ?? 0,
            staticAnchorCount: staticAnchorCount
        ) {
            await apiPacer.markThrottled()
            await antiBanGuard.block(site: site, seconds: banCooldownSeconds(for: site))
            log("Copy 网页解析：疑似风控页，停止后续探测（\(blockedReason)）")
            throw CopyMangaError.parseBlocked(blockedReason)
        }

        emitIntermediateComic(
            slug: slug,
            name: comicName,
            coverURL: coverURL,
            volumes: volumes,
            site: site
        )

        let currentCount = volumes.reduce(0) { $0 + $1.chapters.count }
        if expectedChapters > 0, currentCount > 0, currentCount + 8 < expectedChapters {
            usedPaths.append("api-groups")
            probeRequestCount += 1
            log("Copy 网页解析：检测到章节缺口（当前 \(currentCount)，页面约 \(expectedChapters)），尝试 API 分组补齐")
            if let enriched = try await fetchCopyVolumesFromAPIGroups(slug: slug, site: site, cookie: cookie),
               !enriched.isEmpty {
                let merged = mergeVolumes(volumes, with: enriched)
                let mergedCount = merged.reduce(0) { $0 + $1.chapters.count }
                if mergedCount > currentCount {
                    volumes = merged
                    log("Copy 网页解析：API 补齐成功，章节数 \(currentCount) -> \(mergedCount)")
                } else {
                    log("Copy 网页解析：API 补齐无新增章节")
                }
            }
        }

        // Copy family often renders full chapter list only after JS runtime finishes.
        // Trigger rendered-DOM fallback only when static HTML is clearly sparse.
        let renderedBaseline = volumes.reduce(0) { $0 + $1.chapters.count }
        let preferRenderedDOM = await siteHeuristics.preferRenderedDOM(for: site)
        let hasNonDefaultGroup = volumes.contains { !isDefaultVolumeName($0.displayName) }
        let groupedEnough = (volumes.count > 1 || hasNonDefaultGroup) && renderedBaseline >= 30
        let nearExpected = expectedChapters > 0 && renderedBaseline + 3 >= expectedChapters
        let enoughChapters = renderedBaseline > 0 && (nearExpected || (expectedChapters == 0 && renderedBaseline >= 20))
        let detailLooksSufficient = detailCandidate?.isEmpty == false && (enoughChapters || groupedEnough)
        let renderedDOMSignals =
            preferRenderedDOM ||
            html.contains("章節加載中") ||
            html.contains("章节加載中") ||
            staticAnchorCount < 20 ||
            renderedBaseline <= max(1, staticAnchorCount)
        let skipRenderedDOM = enoughChapters || (groupedEnough && staticAnchorCount >= 20)
        let shouldUseRenderedDOM = !skipRenderedDOM && !detailLooksSufficient && renderedDOMSignals
        if skipRenderedDOM {
            log("Copy 网页解析：当前分类/章节已足够，跳过渲染 DOM（分类 \(volumes.count)，章节 \(renderedBaseline)）")
        } else if detailLooksSufficient {
            log("Copy 网页解析：comicdetail 已提供可用结果，跳过渲染 DOM（分类 \(volumes.count)，章节 \(renderedBaseline)）")
        }
        if shouldUseRenderedDOM {
            usedPaths.append("rendered-dom")
            probeRequestCount += 1
            log("Copy 网页解析：尝试渲染 DOM 补齐（静态锚点 \(staticAnchorCount)，当前章节 \(renderedBaseline)）")
        }
        if shouldUseRenderedDOM,
           let rendered = await fetchCopyVolumesFromRenderedDOM(slug: slug, site: site, cookie: cookie, baselineCount: renderedBaseline) {
            let merged = mergeVolumes(volumes, with: rendered)
            let mergedCount = merged.reduce(0) { $0 + $1.chapters.count }
            let betterGrouping = hasBetterSiteGrouping(candidate: merged, than: volumes)
            if mergedCount > renderedBaseline || (mergedCount == renderedBaseline && betterGrouping) {
                volumes = merged
                if mergedCount > renderedBaseline {
                    log("Copy 网页解析：渲染 DOM 补齐成功，章节数 \(renderedBaseline) -> \(mergedCount)")
                } else {
                    log("Copy 网页解析：渲染 DOM 采用网站原分类（章节数 \(mergedCount)）")
                }
                log("Copy 网页解析：渲染后分组 \(volumesSummary(volumes))")
                await siteHeuristics.markPreferRenderedDOM(for: site)
            } else {
                log("Copy 网页解析：渲染 DOM 未新增章节")
            }
        }

        volumes = stripPseudoShareVolumes(volumes, slug: slug)
        if volumes.isEmpty {
            let fallback = parseCopyChaptersFromJSONScripts(html: html, slug: slug)
            if !fallback.isEmpty {
                log("Copy 网页解析：使用 JSON 脚本兜底，章节数 \(fallback.count)")
                volumes = [
                    ComicVolume(id: "default", displayName: "默认卷", pathWord: "default", chapters: fallback)
                ]
            }
        }
        volumes = stripPseudoShareVolumes(volumes, slug: slug)
        if volumes.isEmpty {
            let fallback = parseCopyChaptersFromLooseURLPatterns(source: html, slug: slug)
            if !fallback.isEmpty {
                log("Copy 网页解析：使用 URL 扫描兜底，章节数 \(fallback.count)")
                volumes = [
                    ComicVolume(id: "default", displayName: "默认卷", pathWord: "default", chapters: fallback)
                ]
            }
        }
        volumes = stripPseudoShareVolumes(volumes, slug: slug)
        if volumes.isEmpty, let shareEntry = parseCopyShareEntryChapter(html: html, slug: slug, site: site) {
            usedPaths.append("next-links")
            probeRequestCount += 1
            log("Copy 网页解析：识别到“开始阅读”入口，尝试通过章节链恢复")
            if let entryURL = URL(string: String(shareEntry.id.dropFirst(5))) {
                let crawled = try await crawlCopyChaptersByNextLinks(
                    from: entryURL,
                    slug: slug,
                    site: site,
                    cookie: cookie
                )
                if !crawled.isEmpty {
                    log("Copy 网页解析：通过“下一话”链路恢复章节 \(crawled.count) 话")
                    volumes = [
                        ComicVolume(
                            id: "default",
                            displayName: "默认卷",
                            pathWord: "default",
                            chapters: crawled
                        )
                    ]
                }
            }
        }
        // Only run next-link scan when current list is obviously incomplete.
        if let shareEntry = parseCopyShareEntryChapter(html: html, slug: slug, site: site),
           let entryURL = URL(string: String(shareEntry.id.dropFirst(5))),
           volumes.reduce(0, { $0 + $1.chapters.count }) < 20 {
            if !usedPaths.contains("next-links") {
                usedPaths.append("next-links")
                probeRequestCount += 1
            }
            let crawled = try await crawlCopyChaptersByNextLinks(
                from: entryURL,
                slug: slug,
                site: site,
                cookie: cookie
            )
            let currentCount = volumes.reduce(0) { $0 + $1.chapters.count }
            if crawled.count > max(1, currentCount) {
                log("Copy 网页解析：章节链路结果更完整，采用 \(crawled.count) 话（原 \(currentCount)）")
                volumes = [
                    ComicVolume(
                        id: "default",
                        displayName: "默认卷",
                        pathWord: "default",
                        chapters: crawled
                    )
                ]
            }
        }
        if volumes.isEmpty {
            let directImages = parseCopyImageURLs(html: html, site: site, slugHint: slug)
            if !directImages.isEmpty {
                usedSingleShareFallback = true
                log("Copy 网页解析：识别为单话分享页，图片数 \(directImages.count)")
                volumes = [
                    ComicVolume(
                        id: "single",
                        displayName: "单话",
                        pathWord: "single",
                        chapters: [
                            ComicChapter(
                                id: "__single_share__",
                                uuid: "__single_share__",
                                displayName: "单话",
                                order: 0,
                                volumeID: "single",
                                volumeName: "单话"
                            )
                        ]
                    )
                ]
                if coverURL == nil {
                    coverURL = directImages.first
                }
            }
        }
        if volumes.isEmpty {
            throw CopyMangaError.htmlParse("网页中未找到可用章节")
        }

        log("Copy 网页解析：host \(describeCopySite(site))，路径 \(usedPaths.joined(separator: " -> "))，探测请求约 \(probeRequestCount) 次，锚点 \(staticAnchorCount)，最终章节 \(volumes.reduce(0) { $0 + $1.chapters.count })")

        return CopyWebFetchResult(
            info: ComicInfo(
                slug: slug,
                name: comicName,
                coverURL: coverURL,
                volumes: volumes,
                site: site,
                apiPathPrefix: "web",
                apiBaseURL: site.webBase
            ),
            expectedCounts: expected,
            usedSingleShareFallback: usedSingleShareFallback
        )
    }

    private func emitIntermediateComic(
        slug: String,
        name: String,
        coverURL: URL?,
        volumes: [ComicVolume],
        site: MangaSiteConfig
    ) {
        guard !volumes.isEmpty else { return }
        guard let handler = intermediateComicHandler else { return }
        let snapshot = normalizeComicInfoVolumes(
            ComicInfo(
                slug: slug,
                name: name,
                coverURL: coverURL,
                volumes: volumes,
                site: site,
                apiPathPrefix: "web",
                apiBaseURL: site.webBase
            )
        )
        handler(snapshot)
    }

    private func parseCopyExpectedCounts(html: String) -> (volumes: Int?, chapters: Int?) {
        let text = cleanHTMLText(html)
        let volumeMatch = firstMatch(in: text, pattern: #"(\d{1,4})\s*[卷冊册]"#).flatMap { Int($0) }
        let chapterPatterns = [
            #"(\d{1,5})\s*[话話]"#,
            #"共\s*(\d{1,5})\s*[话話]"#,
            #"chapter[s]?\s*(\d{1,5})"#
        ]
        var chapterCount: Int?
        for pattern in chapterPatterns {
            if let value = firstMatch(in: text, pattern: pattern).flatMap({ Int($0) }) {
                chapterCount = max(chapterCount ?? 0, value)
            }
        }
        return (volumeMatch, chapterCount)
    }

    private func hasBetterSiteGrouping(candidate: [ComicVolume], than baseline: [ComicVolume]) -> Bool {
        let genericNames = Set(["全部", "all", "話", "话", "卷", "番外", "番外篇"])

        func groupNames(from volumes: [ComicVolume]) -> Set<String> {
            var names: Set<String> = []
            for volume in volumes {
                let name = canonicalGroupName(volume.displayName)
                if isDefaultVolumeName(name) {
                    for chapter in volume.chapters {
                        let group = canonicalGroupName(chapter.volumeName)
                        if !isDefaultVolumeName(group) {
                            names.insert(group)
                        }
                    }
                } else {
                    names.insert(name)
                }
            }
            return names
        }

        func customCount(_ names: Set<String>) -> Int {
            names.reduce(into: 0) { count, raw in
                let normalized = raw.folding(
                    options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                    locale: Locale.current
                )
                if !genericNames.contains(normalized) {
                    count += 1
                }
            }
        }

        let baselineNames = groupNames(from: baseline)
        let candidateNames = groupNames(from: candidate)
        let baselineCustom = customCount(baselineNames)
        let candidateCustom = customCount(candidateNames)
        if candidateCustom != baselineCustom {
            return candidateCustom > baselineCustom
        }
        return candidateNames.count > baselineNames.count
    }

    private func countCopyChapterAnchors(in html: String, slug: String) -> Int {
        let slugPattern = NSRegularExpression.escapedPattern(for: slug)
        let patterns = [
            #"(?is)<a[^>]*(?:href|data-href|data-url|data-path)\s*=\s*["'](?:https?://[^/"']+)?/comic/\#(slugPattern)/chapter/([^/"'#?]+)(?:/|\.html)?(?:\?[^"']*)?["']"#,
            #"(?is)<a[^>]*(?:href|data-href|data-url|data-path)\s*=\s*["'](?:https?://[^/"']+)?/comic/\#(slugPattern)/([^/"'#?]+)\.html(?:\?[^"']*)?["']"#
        ]
        var seen: Set<String> = []
        for pattern in patterns {
            for match in matches(in: html, pattern: pattern) {
                guard let raw = substring(in: html, nsRange: match.range(at: 1)) else { continue }
                let id = normalizedChapterID(raw)
                if !id.isEmpty {
                    seen.insert(id)
                }
            }
        }
        return seen.count
    }

    private func fetchCopyVolumesFromAPIGroups(slug: String, site: MangaSiteConfig, cookie: String?) async throws -> [ComicVolume]? {
        do {
            let resolved = try await resolveAPI(slug: slug, site: site, cookie: cookie, forceRefresh: false)
            let meta = try await getJSON(path: "\(resolved.pathPrefix)/\(slug)", site: site, cookie: cookie, baseURL: resolved.baseURL, retryTimes: 1)
            guard let results = primaryObjectOrNil(from: meta) else { return nil }
            let groups = parseGroups(from: results)
            guard !groups.isEmpty else { return nil }

            var volumes: [ComicVolume] = []
            let limiter = APIConcurrencyLimiter(limit: 2)
            await withTaskGroup(of: ComicVolume?.self) { group in
                for g in groups {
                    group.addTask { [weak self] in
                        guard let self else { return nil }
                        await limiter.acquire()
                        defer { Task { await limiter.release() } }
                        return try? await self.fetchVolume(
                            slug: slug,
                            groupPathWord: g.pathWord,
                            fallbackName: g.name,
                            cookie: cookie,
                            site: site,
                            resolved: resolved
                        )
                    }
                }
                for await volume in group {
                    if let volume {
                        volumes.append(volume)
                    }
                }
            }
            return volumes.isEmpty ? nil : volumes
        } catch {
            log("Copy 网页解析：API 分组补齐失败 \(error.localizedDescription)")
            return nil
        }
    }

    private func fetchCopyVolumesFromRenderedDOM(
        slug: String,
        site: MangaSiteConfig,
        cookie: String?,
        baselineCount: Int
    ) async -> [ComicVolume]? {
        let comicURL = site.webBase.appendingPathComponent("comic/\(slug)")
        let chapters = await CopyRenderedDOMExtractor.shared.fetchChapters(
            comicURL: comicURL,
            slug: slug,
            cookie: cookie,
            baselineCount: baselineCount
        )
        guard !chapters.isEmpty else { return nil }
        return [ComicVolume(id: "rendered", displayName: "默认卷", pathWord: "rendered", chapters: chapters)]
    }

    private func normalizeCopyComicName(_ raw: String, fallback: String) -> String {
        let cleaned = cleanHTMLText(raw)
        guard !cleaned.isEmpty else { return fallback }

        let separators = ["-", "—", "–", "_", "|"]
        for sep in separators {
            if let idx = cleaned.firstIndex(of: Character(sep)) {
                let head = String(cleaned[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !head.isEmpty, !head.lowercased().contains("copy"), !head.lowercased().contains("拷貝漫畫"), !head.lowercased().contains("拷贝漫画") {
                    return head
                }
            }
        }
        return cleaned
    }

    private func fetchCopyVolumesFromDetailEndpoint(
        slug: String,
        html: String,
        site: MangaSiteConfig,
        cookie: String?
    ) async throws -> CopyDetailProbeResult? {
        guard isCopyFamily(site) else { return nil }
        guard let ccz = firstMatch(in: html, pattern: #"(?is)\bvar\s+ccz\s*=\s*['"]([^'"]+)['"]"#) else {
            return nil
        }
        let dnts = firstMatch(in: html, pattern: #"(?is)id\s*=\s*["']dnt["'][^>]*value\s*=\s*["']([^"']+)["']"#) ?? "3"
        let expectedChapters = parseCopyExpectedCounts(html: html).chapters
        let endpointCandidates = [
            "comicdetail/\(slug)/chapters",
            "comicdetail/\(slug)/chapters?limit=500&offset=0",
            "comicdetail/\(slug)/chapters?limit=500&page=1"
        ]
        var merged: [ComicVolume] = []
        var requestCount = 0

        for endpoint in endpointCandidates {
            let url = URL(string: endpoint, relativeTo: site.webBase)?.absoluteURL
                ?? site.webBase.appendingPathComponent(endpoint)
            do {
                requestCount += 1
                let text = try await getText(
                    url: url,
                    cookie: cookie,
                    site: site,
                    retryTimes: 1,
                    extraHeaders: ["dnts": dnts]
                )
                if let volumes = parseCopyDetailVolumesPayload(text: text, ccz: ccz), !volumes.isEmpty {
                    merged = mergeVolumes(merged, with: volumes)
                    let mergedCount = merged.reduce(0, { $0 + $1.chapters.count })
                    log("Copy 网页解析：comicdetail \(endpoint) 分组 \(volumesSummary(volumes))，累计 \(mergedCount) 话")
                    if !shouldContinueCopyDetailProbe(volumes: merged, expectedChapters: expectedChapters) {
                        log("Copy 网页解析：comicdetail 已足够，停止继续探测（累计 \(mergedCount) 话）")
                        break
                    }
                }
            } catch let error as CopyMangaError {
                if case .httpStatus(let code, _) = error, code == 404 {
                    continue
                }
            } catch {
                continue
            }
        }
        guard !merged.isEmpty else { return nil }
        return CopyDetailProbeResult(volumes: merged, requestCount: requestCount)
    }

    private func shouldContinueCopyDetailProbe(volumes: [ComicVolume], expectedChapters: Int?) -> Bool {
        let currentCount = volumes.reduce(0) { $0 + $1.chapters.count }
        guard currentCount > 0 else { return true }

        if let expectedChapters, expectedChapters > 0 {
            let tolerance = expectedChapters >= 120 ? 8 : 3
            return currentCount + tolerance < expectedChapters
        }

        let hasCustomGrouping = volumes.count > 1 || volumes.contains { !isDefaultVolumeName($0.displayName) }
        let enoughWithoutExpected = hasCustomGrouping ? 20 : 24
        return currentCount < enoughWithoutExpected
    }

    private func mergeVolumes(_ base: [ComicVolume], with incoming: [ComicVolume]) -> [ComicVolume] {
        var map: [String: ComicVolume] = [:]
        for v in base {
            map[v.id] = v
        }
        for v in incoming {
            if let existing = map[v.id] {
                var seen = Set(existing.chapters.map(\.id))
                var mergedChapters = existing.chapters
                for c in v.chapters where seen.insert(c.id).inserted {
                    mergedChapters.append(c)
                }
                mergedChapters.sort { lhs, rhs in
                    if lhs.order == rhs.order {
                        return lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
                    }
                    return lhs.order < rhs.order
                }
                map[v.id] = ComicVolume(id: existing.id, displayName: existing.displayName, pathWord: existing.pathWord, chapters: mergedChapters)
            } else {
                map[v.id] = v
            }
        }
        return map.values.sorted { lhs, rhs in
            lhs.displayName.localizedCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func volumesSummary(_ volumes: [ComicVolume]) -> String {
        if volumes.isEmpty { return "0 组" }
        let detail = volumes
            .map { "\($0.displayName)(\($0.chapters.count))" }
            .joined(separator: ", ")
        return "\(volumes.count) 组 [\(detail)]"
    }

    private func parseCopyDetailVolumesPayload(text: String, ccz: String) -> [ComicVolume]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let data = trimmed.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let results = root["results"] as? [String: Any] {
                return parseCopyDetailVolumes(from: results)
            }
            if let resultsText = root["results"] as? String,
               let decoded = decryptCopyDetailResults(resultsText, ccz: ccz),
               let decodedData = decoded.data(using: .utf8),
               let decodedRoot = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any] {
                return parseCopyDetailVolumes(from: decodedRoot)
            }
        }
        if let decoded = decryptCopyDetailResults(trimmed, ccz: ccz),
           let decodedData = decoded.data(using: .utf8),
           let decodedRoot = try? JSONSerialization.jsonObject(with: decodedData) as? [String: Any] {
            return parseCopyDetailVolumes(from: decodedRoot)
        }
        return nil
    }

    private func decryptCopyDetailResults(_ raw: String, ccz: String) -> String? {
        let compact = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Newer Copy payload format:
        // iv = results.prefix(16) (raw UTF-8), cipher = hex string.
        if compact.count > 16 {
            let ivString = String(compact.prefix(16))
            let cipherHex = String(compact.dropFirst(16))
            if let cipherData = Data(hexString: cipherHex),
               let plainData = aesCBCDecrypt(
                   cipherData: cipherData,
                   key: Data(ccz.utf8),
                   iv: Data(ivString.utf8)
               ),
               let text = String(data: plainData, encoding: .utf8),
               text.contains("{") && text.contains("}") {
                return text
            }
        }

        // Legacy Copy payload format:
        // ivHex + cipherBase64.
        let splitCandidates = [16, 24, 32]
        for prefix in splitCandidates where compact.count > prefix {
            let ivHex = String(compact.prefix(prefix))
            let cipherBase64 = String(compact.dropFirst(prefix))
            guard let iv = Data(hexString: ivHex),
                  let cipherData = Data(base64Encoded: cipherBase64) else {
                continue
            }
            var normalizedIV = iv
            if normalizedIV.count < kCCBlockSizeAES128 {
                normalizedIV.append(Data(repeating: 0, count: kCCBlockSizeAES128 - normalizedIV.count))
            } else if normalizedIV.count > kCCBlockSizeAES128 {
                normalizedIV = normalizedIV.prefix(kCCBlockSizeAES128)
            }
            if let plainData = aesCBCDecrypt(cipherData: cipherData, key: Data(ccz.utf8), iv: normalizedIV),
               let text = String(data: plainData, encoding: .utf8),
               text.contains("{") && text.contains("}") {
                return text
            }
        }
        return nil
    }

    private func parseCopyDetailVolumes(from root: [String: Any]) -> [ComicVolume] {
        var volumes: [ComicVolume] = []
        let typeNameMap = copyTypeNameMap(from: root)
        if let groups = root["groups"] as? [String: Any] {
            for (groupKey, value) in groups {
                guard let group = value as? [String: Any] else { continue }
                volumes.append(
                    contentsOf: makeCopyVolumesFromGroup(
                        group,
                        fallbackKey: groupKey,
                        typeNameMap: typeNameMap
                    )
                )
            }
        } else if let groups = root["groups"] as? [[String: Any]] {
            for (idx, group) in groups.enumerated() {
                volumes.append(
                    contentsOf: makeCopyVolumesFromGroup(
                        group,
                        fallbackKey: "g\(idx)",
                        typeNameMap: typeNameMap
                    )
                )
            }
        }
        return volumes
    }

    private func copyTypeNameMap(from root: [String: Any]) -> [Int: String] {
        var mapping: [Int: String] = [
            1: "话",
            2: "卷",
            3: "番外"
        ]
        guard let build = root["build"] as? [String: Any],
              let types = build["type"] as? [[String: Any]] else {
            return mapping
        }
        for entry in types {
            if let idRaw = JSONNavigator.number(entry, keys: ["id", "type"]),
               let id = Int(exactly: idRaw),
               let name = JSONNavigator.string(entry, keys: ["name", "title"]),
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mapping[id] = name
            }
        }
        return mapping
    }

    private func makeCopyVolumesFromGroup(
        _ group: [String: Any],
        fallbackKey: String,
        typeNameMap: [Int: String]
    ) -> [ComicVolume] {
        let name = JSONNavigator.string(group, keys: ["name", "title"]) ?? fallbackKey
        let pathWord = JSONNavigator.string(group, keys: ["path_word", "pathWord", "id"]) ?? fallbackKey
        let chapterNodes = (
            JSONNavigator.array(group, keys: ["chapters", "chapter", "list", "items"]) ?? []
        ).compactMap { $0 as? [String: Any] }
        if chapterNodes.isEmpty { return [] }

        var parsed: [(index: Int, chapter: ComicChapter, type: Int?)] = []
        parsed.reserveCapacity(chapterNodes.count)
        for (idx, node) in chapterNodes.enumerated() {
            guard let id = chapterIdentifier(from: node).map(normalizedChapterID), !id.isEmpty else { continue }
            let title = JSONNavigator.string(node, keys: ["name", "title", "chapter_name", "chapter_title"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let display = (title?.isEmpty == false) ? title! : id
            let chapterType = JSONNavigator.number(node, keys: ["type", "chapter_type"]).flatMap { Int(exactly: $0) }
            parsed.append((idx, ComicChapter(
                id: id,
                uuid: id,
                displayName: display,
                order: Double(idx),
                volumeID: pathWord,
                volumeName: name
            ), chapterType))
        }
        if parsed.isEmpty { return [] }

        let distinctTypes = Set(parsed.compactMap(\.type))
        // 2026copy may return a single "default" group while chapter.type carries
        // the true category (话/卷/番外). Split whenever default-group semantics
        // and multiple chapter types are detected.
        let defaultLikeGroup =
            isDefaultVolumeName(name) ||
            pathWord.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "default" ||
            fallbackKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "default"
        let shouldSplitByType = defaultLikeGroup && distinctTypes.count > 1

        if shouldSplitByType {
            var buckets: [Int: [ComicChapter]] = [:]
            var noType: [ComicChapter] = []
            for item in parsed {
                guard let t = item.type else {
                    noType.append(item.chapter)
                    continue
                }
                var chapter = item.chapter
                let groupName = typeNameMap[t] ?? "分类\(t)"
                chapter = ComicChapter(
                    id: chapter.id,
                    uuid: chapter.uuid,
                    displayName: chapter.displayName,
                    order: chapter.order,
                    volumeID: "\(pathWord)-t\(t)",
                    volumeName: groupName
                )
                buckets[t, default: []].append(chapter)
            }

            var result: [ComicVolume] = []
            for typeID in buckets.keys.sorted() {
                guard let chapters = buckets[typeID], !chapters.isEmpty else { continue }
                let displayName = typeNameMap[typeID] ?? "分类\(typeID)"
                result.append(
                    ComicVolume(
                        id: "\(pathWord)-t\(typeID)",
                        displayName: displayName,
                        pathWord: "\(pathWord)-t\(typeID)",
                        chapters: chapters
                    )
                )
            }
            if !noType.isEmpty {
                result.append(
                    ComicVolume(
                        id: pathWord,
                        displayName: name,
                        pathWord: pathWord,
                        chapters: noType
                    )
                )
            }
            if !result.isEmpty {
                return result
            }
        }

        let chapters = parsed.map(\.chapter)
        return [ComicVolume(id: pathWord, displayName: name, pathWord: pathWord, chapters: chapters)]
    }

    private func parseCopyVolumesFromHTML(html: String, slug: String) -> [ComicVolume] {
        var seenChapterIDs: Set<String> = []
        var volumes: [ComicVolume] = []

        let headingMatches = matches(
            in: html,
            pattern: #"(?is)<h[2-5][^>]*>(.*?)</h[2-5]>"#
        )
        if !headingMatches.isEmpty {
            for (index, match) in headingMatches.enumerated() {
                guard let headingRange = range(of: match.range(at: 1), in: html) else { continue }
                let sectionStart = match.range.location
                let sectionEnd: Int
                if index + 1 < headingMatches.count {
                    sectionEnd = headingMatches[index + 1].range.location
                } else {
                    sectionEnd = (html as NSString).length
                }
                let sectionRange = NSRange(location: sectionStart, length: max(0, sectionEnd - sectionStart))
                guard let sectionText = substring(in: html, nsRange: sectionRange) else { continue }
                let volumeName = cleanHTMLText(String(html[headingRange]))
                if volumeName.isEmpty || isGenericSectionTitle(volumeName) { continue }
                let chapters = parseCopyChaptersFromAnchors(
                    in: sectionText,
                    slug: slug,
                    volumeID: "h\(index)",
                    volumeName: volumeName,
                    seenChapterIDs: &seenChapterIDs
                )
                if !chapters.isEmpty {
                    volumes.append(
                        ComicVolume(
                            id: "h\(index)",
                            displayName: volumeName,
                            pathWord: "h\(index)",
                            chapters: chapters
                        )
                    )
                }
            }
        }

        var fallbackSeen: Set<String> = []
        let fallback = parseCopyChaptersFromAnchors(
            in: html,
            slug: slug,
            volumeID: "default",
            volumeName: "默认卷",
            seenChapterIDs: &fallbackSeen
        )
        let currentCount = volumes.reduce(0) { $0 + $1.chapters.count }
        if !fallback.isEmpty, (volumes.isEmpty || fallback.count > currentCount) {
            volumes = [
                ComicVolume(id: "default", displayName: "默认卷", pathWord: "default", chapters: fallback)
            ]
        }

        return volumes
    }

    private func parseCopyChaptersFromAnchors(
        in sourceHTML: String,
        slug: String,
        volumeID: String,
        volumeName: String,
        seenChapterIDs: inout Set<String>
    ) -> [ComicChapter] {
        let slugPattern = NSRegularExpression.escapedPattern(for: slug)
        let strictPattern = #"(?is)<a[^>]*(?:href|data-href|data-url|data-path)\s*=\s*["']((?:https?://[^/"']+)?/comic/\#(slugPattern)/chapter/([^/"'#?]+)(?:/|\.html)?(?:\?[^"']*)?)["'][^>]*>(.*?)</a>"#
        var anchorMatches = matches(in: sourceHTML, pattern: strictPattern)
        if anchorMatches.isEmpty {
            let loosePattern = #"(?is)<a[^>]*(?:href|data-href|data-url|data-path)\s*=\s*["']((?:https?://[^/"']+)?/comic/\#(slugPattern)/([^/"'#?]+)(?:/|\.html)?(?:\?[^"']*)?)["'][^>]*>(.*?)</a>"#
            anchorMatches = matches(in: sourceHTML, pattern: loosePattern)
        }

        let blacklist: Set<String> = ["comic", "comments", "comment", "author", "cover", "status", "intro"]
        var chapters: [ComicChapter] = []
        var order = 0

        for match in anchorMatches {
            guard let rawID = substring(in: sourceHTML, nsRange: match.range(at: 2)) else { continue }
            let chapterID = normalizedChapterID(rawID)
            if chapterID.isEmpty || blacklist.contains(chapterID.lowercased()) { continue }
            if !isLikelyChapterID(chapterID) { continue }
            if seenChapterIDs.contains(chapterID) { continue }
            seenChapterIDs.insert(chapterID)

            let chapterName = cleanHTMLText(substring(in: sourceHTML, nsRange: match.range(at: 3)) ?? chapterID)
            if isPseudoShareEntry(chapterID: chapterID, chapterName: chapterName, slug: slug) {
                continue
            }
            chapters.append(
                ComicChapter(
                    id: chapterID,
                    uuid: chapterID,
                    displayName: chapterName.isEmpty ? chapterID : chapterName,
                    order: Double(order),
                    volumeID: volumeID,
                    volumeName: volumeName
                )
            )
            order += 1
        }
        return chapters
    }

    private func parseCopyChaptersFromJSONScripts(html: String, slug: String) -> [ComicChapter] {
        let jsonScripts = scriptJSONBodies(from: html)
        guard !jsonScripts.isEmpty else { return [] }

        var seen: Set<String> = []
        var chapters: [ComicChapter] = []

        for jsonText in jsonScripts {
            guard let data = jsonText.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }
            collectChaptersFromJSONNode(
                node: json,
                slug: slug,
                volumeID: "default",
                volumeName: "默认卷",
                seenIDs: &seen,
                output: &chapters
            )
        }

        // Keep source order and normalize display ordering.
        return chapters.enumerated().map { idx, chapter in
            ComicChapter(
                id: chapter.id,
                uuid: chapter.uuid,
                displayName: chapter.displayName,
                order: Double(idx),
                volumeID: chapter.volumeID,
                volumeName: chapter.volumeName
            )
        }
    }

    private func parseCopyChaptersFromLooseURLPatterns(source: String, slug: String) -> [ComicChapter] {
        let slugPattern = NSRegularExpression.escapedPattern(for: slug)
        let patterns = [
            #"(?is)(?:https?:)?//[^"'\s]+/comic/\#(slugPattern)/chapter/([A-Za-z0-9_-]+)"#,
            #"(?is)/comic/\#(slugPattern)/chapter/([A-Za-z0-9_-]+)"#,
            #"(?is)(?:https?:)?//[^"'\s]+/comic/\#(slugPattern)/([A-Za-z0-9_-]+)\.html"#,
            #"(?is)/comic/\#(slugPattern)/([A-Za-z0-9_-]+)\.html"#
        ]
        let blacklist: Set<String> = ["comic", "comments", "comment", "author", "cover", "status", "intro"]
        var ids: [String] = []
        var seen: Set<String> = []

        for pattern in patterns {
            for match in matches(in: source, pattern: pattern) {
                guard let rawID = substring(in: source, nsRange: match.range(at: 1)) else { continue }
                let chapterID = normalizedChapterID(rawID)
                if chapterID.isEmpty || blacklist.contains(chapterID.lowercased()) { continue }
                if !isLikelyChapterID(chapterID) { continue }
                if isPseudoShareEntry(chapterID: chapterID, chapterName: chapterID, slug: slug) { continue }
                if seen.insert(chapterID).inserted {
                    ids.append(chapterID)
                }
            }
        }

        return ids.enumerated().map { idx, id in
            ComicChapter(
                id: id,
                uuid: id,
                displayName: id,
                order: Double(idx),
                volumeID: "default",
                volumeName: "默认卷"
            )
        }
    }

    private func collectChaptersFromJSONNode(
        node: Any,
        slug: String,
        volumeID: String,
        volumeName: String,
        seenIDs: inout Set<String>,
        output: inout [ComicChapter]
    ) {
        if let dict = node as? [String: Any] {
            let chapterID = chapterIdentifier(from: dict).map(normalizedChapterID)
            let chapterName = JSONNavigator.string(dict, keys: ["name", "title", "chapter_name", "chapter_title", "display_name"])
            let comicPathWord = JSONNavigator.string(dict, keys: ["comic_path_word", "comicPathWord", "path_word"])
            let slugMatches = comicPathWord == nil || comicPathWord == slug
            let hasChapterSignal = !Set(dict.keys).intersection([
                "chapter_uuid", "chapter_id", "index", "sort", "order", "is_lock", "chapter"
            ]).isEmpty
            let looseSignal = dict.keys.contains("id") && dict.keys.contains("name")
            if let chapterID, !chapterID.isEmpty, hasChapterSignal, isLikelyChapterID(chapterID),
               let chapterName, !chapterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, slugMatches {
                if !seenIDs.contains(chapterID) {
                    seenIDs.insert(chapterID)
                    output.append(
                        ComicChapter(
                            id: chapterID,
                            uuid: chapterID,
                            displayName: chapterName,
                            order: Double(output.count),
                            volumeID: volumeID,
                            volumeName: volumeName
                        )
                    )
                }
            } else if let chapterID, !chapterID.isEmpty, looseSignal, isLikelyChapterID(chapterID),
                      let chapterName, !chapterName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, slugMatches {
                if !seenIDs.contains(chapterID) {
                    seenIDs.insert(chapterID)
                    output.append(
                        ComicChapter(
                            id: chapterID,
                            uuid: chapterID,
                            displayName: chapterName,
                            order: Double(output.count),
                            volumeID: volumeID,
                            volumeName: volumeName
                        )
                    )
                }
            }
            for value in dict.values {
                collectChaptersFromJSONNode(
                    node: value,
                    slug: slug,
                    volumeID: volumeID,
                    volumeName: volumeName,
                    seenIDs: &seenIDs,
                    output: &output
                )
            }
            return
        }

        if let array = node as? [Any] {
            for item in array {
                collectChaptersFromJSONNode(
                    node: item,
                    slug: slug,
                    volumeID: volumeID,
                    volumeName: volumeName,
                    seenIDs: &seenIDs,
                    output: &output
                )
            }
        }
    }

    private func fetchImageURLsFromCopyWeb(
        slug: String,
        chapterID: String,
        chapterName: String,
        site: MangaSiteConfig,
        cookie: String?
    ) async throws -> [URL] {
        if chapterID.hasPrefix("url::") {
            let raw = String(chapterID.dropFirst(5))
            if let directURL = URL(string: raw) {
                log("Copy 图片解析：使用分享入口页面 \(directURL.absoluteString)")
                let html = try await getHTML(url: directURL, cookie: cookie, site: site, retryTimes: 1)
                let urls = parseCopyImageURLs(html: html, site: site, slugHint: slug)
                if urls.count >= 3 {
                    log("Copy 图片解析：分享入口提取到 \(urls.count) 张")
                    return urls
                }
            }
            throw CopyMangaError.noImageInChapter(chapterName)
        }

        if chapterID == "__single_share__" {
            let singleURL = site.webBase.appendingPathComponent("comic/\(slug)")
            log("Copy 图片解析：使用单话分享页 \(singleURL.absoluteString)")
            let html = try await getHTML(url: singleURL, cookie: cookie, site: site, retryTimes: 1)
            let urls = parseCopyImageURLs(html: html, site: site, slugHint: slug)
            if urls.count >= 3 {
                log("Copy 图片解析：单话分享页提取到 \(urls.count) 张")
                return urls
            }
            throw CopyMangaError.noImageInChapter(chapterName)
        }

        let normalizedID = normalizedChapterID(chapterID)
        let chapterURL = site.webBase.appendingPathComponent("comic/\(slug)/chapter/\(normalizedID)")
        log("Copy 图片解析：章节页 \(chapterURL.absoluteString)")
        let html = try await getHTML(url: chapterURL, cookie: cookie, site: site, retryTimes: 1)

        var urls = parseCopyImageURLs(html: html, site: site, slugHint: slug)
        if urls.isEmpty {
            let decrypted = try await parseCopyImageURLsFromEncryptedChapterHTML(html: html, site: site, cookie: cookie, slugHint: slug)
            if !decrypted.isEmpty {
                log("Copy 图片解析：章节页 JS 解密提取到 \(decrypted.count) 张")
                urls = decrypted
            }
        }
        if urls.isEmpty {
            // Some mirrors use /comic/{slug}/{chapterID}.html for reading pages.
            let fallbackURL = site.webBase.appendingPathComponent("comic/\(slug)/\(normalizedID).html")
            log("Copy 图片解析：章节页无图，回退 \(fallbackURL.absoluteString)")
            let fallbackHTML = try await getHTML(url: fallbackURL, cookie: cookie, site: site, retryTimes: 1)
            urls = parseCopyImageURLs(html: fallbackHTML, site: site, slugHint: slug)
            if urls.isEmpty {
                let decrypted = try await parseCopyImageURLsFromEncryptedChapterHTML(html: fallbackHTML, site: site, cookie: cookie, slugHint: slug)
                if !decrypted.isEmpty {
                    log("Copy 图片解析：回退章节页 JS 解密提取到 \(decrypted.count) 张")
                    urls = decrypted
                }
            }
        }
        if urls.isEmpty {
            throw CopyMangaError.noImageInChapter(chapterName)
        }
        log("Copy 图片解析：章节提取到 \(urls.count) 张")
        return urls
    }

    private func parseCopyImageURLsFromEncryptedChapterHTML(
        html: String,
        site: MangaSiteConfig,
        cookie: String?,
        slugHint: String?
    ) async throws -> [URL] {
        guard isCopyFamily(site) else { return [] }
        guard let cct = firstMatch(in: html, pattern: #"(?is)\bvar\s+cct\s*=\s*['"]([^'"]+)['"]"#),
              let contentKey = firstMatch(in: html, pattern: #"(?is)\bvar\s+contentKey\s*=\s*['"]([^'"]+)['"]"#) else {
            return []
        }

        let fastDecoded = decryptCopyImageURLs(cct: cct, contentKey: contentKey, site: site, slugHint: slugHint)
        if !fastDecoded.isEmpty {
            log("Copy 图片解析：AES 直解成功，提取到 \(fastDecoded.count) 张")
            return fastDecoded
        }

        guard let bundleScriptRaw = firstMatch(in: html, pattern: #"(?is)<script[^>]+src\s*=\s*["']([^"']*bundle[^"']*\.js)["']"#),
              let passScriptRaw = firstMatch(in: html, pattern: #"(?is)<script[^>]+src\s*=\s*["']([^"']*comic_content_pass[^"']*\.js)["']"#),
              let bundleURL = normalizedURL(bundleScriptRaw.replacingOccurrences(of: "\\/", with: "/"), site: site),
              let passURL = normalizedURL(passScriptRaw.replacingOccurrences(of: "\\/", with: "/"), site: site) else {
            log("Copy 图片解析：检测到 contentKey，但未找到解密脚本 URL")
            return []
        }

        log("Copy 图片解析：进入 JS 解密兜底")
        log("Copy 图片解析：bundle=\(bundleURL.absoluteString)")
        log("Copy 图片解析：pass=\(passURL.absoluteString)")

        let bundleJS = try await getCachedCopyScript(url: bundleURL, cookie: cookie, site: site)
        let passJS = try await getCachedCopyScript(url: passURL, cookie: cookie, site: site)

        let context = JSContext()
        var exceptionText = ""
        context?.exceptionHandler = { _, exception in
            if let text = exception?.toString(), !text.isEmpty {
                exceptionText = text
            }
        }

        _ = context?.evaluateScript(copyWebViewRuntimeShim)
        _ = context?.evaluateScript("var cct = \(javaScriptLiteral(cct)); var contentKey = \(javaScriptLiteral(contentKey)); var URL_LOADING = contentKey;")
        _ = context?.evaluateScript(bundleJS)
        _ = context?.evaluateScript(passJS)

        if !exceptionText.isEmpty {
            log("Copy 图片解析：JS 解密运行异常 \(exceptionText)")
        }

        guard let itemsJSON = context?.evaluateScript("JSON.stringify(__MG_APPENDED || [])")?.toString(),
              let data = itemsJSON.data(using: .utf8),
              let htmlItems = try? JSONSerialization.jsonObject(with: data) as? [String],
              !htmlItems.isEmpty else {
            log("Copy 图片解析：JS 解密未产出图片节点")
            return []
        }

        var urls: [URL] = []
        var seen: Set<String> = []
        for itemHTML in htmlItems {
            for raw in regexImageURLCandidates(in: itemHTML) {
                if let url = normalizedURL(raw, site: site),
                   shouldKeepCopyImageURL(url, slugHint: slugHint),
                   seen.insert(url.absoluteString).inserted {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private func getCachedCopyScript(url: URL, cookie: String?, site: MangaSiteConfig) async throws -> String {
        if let cached = await copyScriptCache.get(url: url) {
            log("Copy 图片解析：脚本缓存命中 \(url.lastPathComponent)")
            return cached
        }
        let text = try await getHTML(url: url, cookie: cookie, site: site, retryTimes: 1)
        await copyScriptCache.set(text, for: url)
        return text
    }

    private func decryptCopyImageURLs(cct: String, contentKey: String, site: MangaSiteConfig, slugHint: String?) -> [URL] {
        // Observed on Copy read pages:
        // iv = contentKey.prefix(16), cipherHex = contentKey.dropFirst(16), key = cct(utf8), AES-CBC-PKCS7
        guard contentKey.count > 16 else { return [] }
        let ivString = String(contentKey.prefix(16))
        let cipherHex = String(contentKey.dropFirst(16))
        guard let cipherData = Data(hexString: cipherHex) else { return [] }
        guard let plainData = aesCBCDecrypt(cipherData: cipherData, key: Data(cct.utf8), iv: Data(ivString.utf8)),
              let plainText = String(data: plainData, encoding: .utf8),
              let jsonData = plainText.data(using: .utf8) else {
            return []
        }

        var urls: [URL] = []
        var seen: Set<String> = []

        if let array = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            for item in array {
                let keys = ["url", "image", "src", "origin", "raw", "image_url", "file"]
                for key in keys {
                    if let raw = item[key] as? String,
                       let url = normalizedURL(raw, site: site),
                       shouldKeepCopyImageURL(url, slugHint: slugHint),
                       seen.insert(url.absoluteString).inserted {
                        urls.append(url)
                    }
                }
            }
        } else if let array = try? JSONSerialization.jsonObject(with: jsonData) as? [String] {
            for raw in array {
                if let url = normalizedURL(raw, site: site),
                   shouldKeepCopyImageURL(url, slugHint: slugHint),
                   seen.insert(url.absoluteString).inserted {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    private func aesCBCDecrypt(cipherData: Data, key: Data, iv: Data) -> Data? {
        guard [kCCKeySizeAES128, kCCKeySizeAES192, kCCKeySizeAES256].contains(key.count),
              iv.count == kCCBlockSizeAES128 else {
            return nil
        }
        var outLength = 0
        let outCapacity = cipherData.count + kCCBlockSizeAES128
        var outData = Data(count: outCapacity)
        let status = outData.withUnsafeMutableBytes { outBytes in
            cipherData.withUnsafeBytes { cipherBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            cipherBytes.baseAddress, cipherData.count,
                            outBytes.baseAddress, outCapacity,
                            &outLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        outData.count = outLength
        return outData
    }

    private func parseCopyImageURLs(html: String, site: MangaSiteConfig, slugHint: String?) -> [URL] {
        var urls: [URL] = []
        var seen: Set<String> = []

        for jsonBody in scriptJSONBodies(from: html) {
            if let data = jsonBody.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) {
                collectImageURLs(from: json, site: site, output: &urls, seen: &seen, slugHint: slugHint)
            }
        }
        if !urls.isEmpty {
            return urls
        }

        let scripts = scriptContents(from: html)
        for script in scripts {
            if let object = captureImageDataObject(from: script) {
                for url in imageURLs(fromImagePayload: object, site: site) {
                    if seen.insert(url.absoluteString).inserted {
                        urls.append(url)
                    }
                }
            }
            if let decoded = decodePackedScript(from: script) {
                let fromLoose = imageURLsFromLoosePattern(in: decoded, site: site)
                if !fromLoose.isEmpty {
                    for url in fromLoose where shouldKeepCopyImageURL(url, slugHint: slugHint) && seen.insert(url.absoluteString).inserted {
                        urls.append(url)
                    }
                }
                if let data = decoded.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    collectImageURLs(from: json, site: site, output: &urls, seen: &seen, slugHint: slugHint)
                }
            }
        }
        if !urls.isEmpty {
            return urls
        }

        // Final fallback: scan full HTML for escaped or plain image URLs.
        for raw in regexImageURLCandidates(in: html) {
            if let url = normalizedURL(raw, site: site),
               shouldKeepCopyImageURL(url, slugHint: slugHint),
               seen.insert(url.absoluteString).inserted {
                urls.append(url)
            }
        }
        return urls
    }

    private func collectImageURLs(from node: Any, site: MangaSiteConfig, output: inout [URL], seen: inout Set<String>, slugHint: String?) {
        if let dict = node as? [String: Any] {
            if let imagePayloadURLs = imageURLs(fromImagePayload: dict, site: site) as [URL]? {
                for url in imagePayloadURLs where shouldKeepCopyImageURL(url, slugHint: slugHint) && seen.insert(url.absoluteString).inserted {
                    output.append(url)
                }
            }
            if let list = JSONNavigator.array(dict, keys: ["contents", "images", "pages"]) {
                for item in list {
                    if let raw = item as? String,
                       let url = normalizedURL(raw, site: site),
                       shouldKeepCopyImageURL(url, slugHint: slugHint),
                       seen.insert(url.absoluteString).inserted {
                        output.append(url)
                    } else if let itemDict = item as? [String: Any] {
                        let keys = ["url", "image", "src", "origin", "raw", "image_url", "file"]
                        for key in keys {
                            if let raw = itemDict[key] as? String,
                               let url = normalizedURL(raw, site: site),
                               shouldKeepCopyImageURL(url, slugHint: slugHint),
                               seen.insert(url.absoluteString).inserted {
                                output.append(url)
                            }
                        }
                    }
                }
            }
            for value in dict.values {
                collectImageURLs(from: value, site: site, output: &output, seen: &seen, slugHint: slugHint)
            }
            return
        }

        if let array = node as? [Any] {
            for item in array {
                collectImageURLs(from: item, site: site, output: &output, seen: &seen, slugHint: slugHint)
            }
            return
        }

        if let raw = node as? String,
           looksLikeImageURL(raw),
           let url = normalizedURL(raw, site: site),
           shouldKeepCopyImageURL(url, slugHint: slugHint),
           seen.insert(url.absoluteString).inserted {
            output.append(url)
        }
    }

    private func scriptJSONBodies(from html: String) -> [String] {
        let jsonScriptMatches = matches(
            in: html,
            pattern: #"(?is)<script[^>]*type\s*=\s*["']application/json["'][^>]*>(.*?)</script>"#
        )
        return jsonScriptMatches.compactMap { match in
            guard let body = substring(in: html, nsRange: match.range(at: 1)) else { return nil }
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func regexImageURLCandidates(in source: String) -> [String] {
        let patterns = [
            #"(?is)(https?:\\?/\\?/[^"'\s]+?\.(?:jpg|jpeg|png|webp|gif)(?:\?[^"'\s]*)?)"#,
            #"(?is)(//[^"'\s]+?\.(?:jpg|jpeg|png|webp|gif)(?:\?[^"'\s]*)?)"#
        ]
        var results: [String] = []
        var seen: Set<String> = []
        for pattern in patterns {
            for match in matches(in: source, pattern: pattern) {
                guard let raw = substring(in: source, nsRange: match.range(at: 1)) else { continue }
                let cleaned = raw
                    .replacingOccurrences(of: "\\/", with: "/")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                if seen.insert(cleaned).inserted {
                    results.append(cleaned)
                }
            }
        }
        return results
    }

    private func looksLikeImageURL(_ raw: String) -> Bool {
        let text = raw.lowercased()
        if text.hasPrefix("data:") {
            return false
        }
        if !(text.contains("http://") || text.contains("https://") || text.hasPrefix("//") || text.contains("/")) {
            return false
        }
        return text.contains(".jpg") || text.contains(".jpeg") || text.contains(".png") || text.contains(".webp") || text.contains(".gif")
    }

    private func shouldKeepCopyImageURL(_ url: URL, slugHint: String?) -> Bool {
        let full = url.absoluteString.lowercased()
        let path = url.path.lowercased()

        // Drop obvious non-content assets from copy-family mirrors.
        let blockedSegments = [
            "/static/", "/assets/", "/images/", "/img/", "/icon/",
            "/logo", "/favicon", "/cover/", "/banner/", "/avatar/",
            "/ad/", "/ads/", "/advert", "/loading", "/placeholder"
        ]
        if blockedSegments.contains(where: { full.contains($0) || path.contains($0) }) {
            return false
        }

        // Keep only likely image CDN/content hosts when possible.
        let allowedHostHints = ["mangafun", "cdn77", "copymanga", "mangacopy", "2026copy", "2025copy"]
        if let host = url.host?.lowercased(), !host.isEmpty {
            let hostLooksRelated = allowedHostHints.contains(where: { host.contains($0) })
            if !hostLooksRelated && !path.contains("/comic/") && !path.contains("/chapter/") {
                return false
            }
        }

        if let slug = slugHint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !slug.isEmpty {
            let normalizedSlug = slug.replacingOccurrences(of: " ", with: "")
            if !path.contains("/\(normalizedSlug)/") && !full.contains("/\(normalizedSlug)/") {
                // For copy pages, real chapter images almost always contain comic slug in path.
                // If it does not, keep only when path has explicit chapter-like marker.
                let chapterLike = path.contains("/chapter/") || path.contains("/comic/")
                if !chapterLike {
                    return false
                }
            }
        }
        return true
    }

    private func isGenericSectionTitle(_ raw: String) -> Bool {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.isEmpty { return true }
        let generic = [
            "分组", "group", "章节", "章節", "目录", "目錄", "chapter", "chapters",
            "连载", "連載", "更新", "最新", "漫畫", "漫画", "manga", "detail"
        ]
        return generic.contains { text == $0 || text.hasPrefix($0) }
    }

    private func normalizedChapterID(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: ".html", with: "")
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func isLikelyChapterID(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= 160 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return raw.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func isPseudoShareEntry(chapterID: String, chapterName: String, slug: String) -> Bool {
        let id = chapterID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let title = chapterName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        let slugLower = slug.lowercased()

        let badIDs: Set<String> = [
            "start", "read", "reader", "detail", "index", "home", "undefined", "null", "nan", slugLower
        ]
        if badIDs.contains(id) {
            return true
        }
        let badTitleKeywords = [
            "开始阅读", "開始閱讀", "立即阅读", "立即閱讀", "readnow", "startreading", "漫画分享", "漫畫分享", "mangashare"
        ]
        if badTitleKeywords.contains(where: { title.contains($0.lowercased()) }) {
            return true
        }
        if (id == "1" || id == "01") && badTitleKeywords.contains(where: { title.contains($0.lowercased()) }) {
            return true
        }
        return false
    }

    private func stripPseudoShareVolumes(_ volumes: [ComicVolume], slug: String) -> [ComicVolume] {
        var filtered: [ComicVolume] = []
        var removed = 0
        for volume in volumes {
            let chapters = volume.chapters.filter { chapter in
                let pseudo = isPseudoShareEntry(chapterID: chapter.id, chapterName: chapter.displayName, slug: slug)
                if pseudo { removed += 1 }
                return !pseudo
            }
            if !chapters.isEmpty {
                filtered.append(
                    ComicVolume(
                        id: volume.id,
                        displayName: volume.displayName,
                        pathWord: volume.pathWord,
                        chapters: chapters
                    )
                )
            }
        }
        if removed > 0 {
            log("Copy 网页解析：剔除伪章节 \(removed) 条（分享入口/开始阅读）")
        }
        return filtered
    }

    private func parseCopyShareEntryChapter(html: String, slug: String, site: MangaSiteConfig) -> ComicChapter? {
        let anchorMatches = matches(
            in: html,
            pattern: #"(?is)<a[^>]*href\s*=\s*["'](.*?)["'][^>]*>(.*?)</a>"#
        )
        if anchorMatches.isEmpty { return nil }

        let titleKeywords = ["开始阅读", "開始閱讀", "立即阅读", "立即閱讀", "read", "start"]
        let slugNeedle = "/comic/\(slug.lowercased())"

        for match in anchorMatches {
            guard let hrefRaw = substring(in: html, nsRange: match.range(at: 1)),
                  let titleRaw = substring(in: html, nsRange: match.range(at: 2)) else {
                continue
            }
            let title = cleanHTMLText(titleRaw)
            let titleLower = title.lowercased()
            guard titleKeywords.contains(where: { titleLower.contains($0.lowercased()) }) else {
                continue
            }

            let cleanedHref = hrefRaw
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedHref.isEmpty,
                  let url = normalizedURL(cleanedHref, site: site) else {
                continue
            }
            let absLower = url.absoluteString.lowercased()
            guard absLower.contains(slugNeedle) else {
                continue
            }

            return ComicChapter(
                id: "url::\(url.absoluteString)",
                uuid: "url::\(url.absoluteString)",
                displayName: title.isEmpty ? "开始阅读" : title,
                order: 0,
                volumeID: "share-entry",
                volumeName: "漫画分享"
            )
        }
        return nil
    }

    private func crawlCopyChaptersByNextLinks(
        from startURL: URL,
        slug: String,
        site: MangaSiteConfig,
        cookie: String?
    ) async throws -> [ComicChapter] {
        guard isCopyFamily(site) else { return [] }

        var chapters: [ComicChapter] = []
        var seenIDs: Set<String> = []
        var currentURL: URL? = startURL
        var expectedTotal: Int?
        let maxScan = 220

        for step in 0..<maxScan {
            guard let url = currentURL else { break }
            let html = try await getHTML(url: url, cookie: cookie, site: site, retryTimes: 1)
            let (chapterID, chapterName) = parseCopyChapterIdentity(from: html, fallbackURL: url)
            if !chapterID.isEmpty, !seenIDs.contains(chapterID) {
                seenIDs.insert(chapterID)
                chapters.append(
                    ComicChapter(
                        id: chapterID,
                        uuid: chapterID,
                        displayName: chapterName.isEmpty ? chapterID : chapterName,
                        order: Double(chapters.count),
                        volumeID: "default",
                        volumeName: "默认卷"
                    )
                )
            }

            if expectedTotal == nil,
               let totalRaw = firstMatch(in: html, pattern: #"(?is)第\s*\d+\s*/\s*(\d+)\s*[话話]"#),
               let total = Int(totalRaw), total > 0 {
                expectedTotal = total
                log("Copy 网页解析：章节总数提示 \(total)")
            }

            if let total = expectedTotal, chapters.count >= total {
                break
            }

            guard let nextURL = parseCopyNextChapterURL(from: html, site: site) else { break }
            let nextID = chapterIDFromChapterURL(nextURL)
            if nextID.isEmpty || seenIDs.contains(nextID) { break }
            currentURL = nextURL

            if step % 12 == 0 {
                log("Copy 网页解析：章节链路扫描进度 \(chapters.count) 话")
            }
            try await Task.sleep(for: .milliseconds(Int.random(in: 90...180)))
        }

        return chapters
    }

    private func parseCopyChapterIdentity(from html: String, fallbackURL: URL) -> (id: String, name: String) {
        let id = chapterIDFromChapterURL(fallbackURL)
        let title = firstMatch(in: html, pattern: #"(?is)<h4[^>]*class\s*=\s*["'][^"']*header[^"']*["'][^>]*>(.*?)</h4>"#)
        let cleanedTitle = cleanHTMLText(title ?? "")
        if let slash = cleanedTitle.lastIndex(of: "/") {
            let name = String(cleanedTitle[cleanedTitle.index(after: slash)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (id, name)
        }
        return (id, cleanedTitle)
    }

    private func parseCopyNextChapterURL(from html: String, site: MangaSiteConfig) -> URL? {
        guard let raw = firstMatch(
            in: html,
            pattern: #"(?is)<div[^>]*class\s*=\s*["'][^"']*comicContent-next[^"']*["'][^>]*>.*?<a[^>]*href\s*=\s*["'](.*?)["']"#
        ) else {
            return nil
        }
        let cleaned = raw
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned != "#", cleaned != "/" else { return nil }
        return normalizedURL(cleaned, site: site)
    }

    private func chapterIDFromChapterURL(_ url: URL) -> String {
        let path = url.path
        guard let range = path.range(of: #"/chapter/([^/?#]+)"#, options: .regularExpression) else {
            return ""
        }
        let part = String(path[range])
        return normalizedChapterID(part.replacingOccurrences(of: "/chapter/", with: ""))
    }

    private func fetchComicFromManhuaGui(slug: String, site: MangaSiteConfig, cookie: String?) async throws -> ComicInfo {
        let comicURL = site.webBase.appendingPathComponent("comic/\(slug)/")
        let html = try await getHTML(url: comicURL, cookie: cookie, site: site, retryTimes: 1)

        let titleFromMeta = firstMatch(
            in: html,
            pattern: #"(?is)<meta\s+property\s*=\s*["']og:title["']\s+content\s*=\s*["'](.*?)["']"#
        )
        let titleFromH1 = firstMatch(
            in: html,
            pattern: #"(?is)<h1[^>]*>(.*?)</h1>"#
        )
        let comicName = cleanHTMLText(titleFromMeta ?? titleFromH1 ?? slug)
        let coverURL = extractCoverURL(from: html, site: site)

        let volumes = parseManhuaGuiVolumes(html: html, slug: slug)
        if volumes.isEmpty {
            throw CopyMangaError.htmlParse("未找到章节列表")
        }

        return ComicInfo(
            slug: slug,
            name: comicName,
            coverURL: coverURL,
            volumes: volumes,
            site: site,
            apiPathPrefix: "html",
            apiBaseURL: site.webBase
        )
    }

    private func parseManhuaGuiVolumes(html: String, slug: String) -> [ComicVolume] {
        var seenChapterIDs: Set<String> = []
        var volumes: [ComicVolume] = []
        if let chapterSectionHTML = extractManhuaGuiChapterSection(from: html) {
            let subgroupMatches = matches(
                in: chapterSectionHTML,
                pattern: #"(?is)<h([4-6])[^>]*>(.*?)</h\1>"#
            )
            if !subgroupMatches.isEmpty {
                for (index, match) in subgroupMatches.enumerated() {
                    guard let headingRaw = substring(in: chapterSectionHTML, nsRange: match.range(at: 2)) else { continue }
                    let volumeName = cleanHTMLText(headingRaw)
                    if !isManhuaGuiVolumeHeading(volumeName) { continue }

                    let sectionStart = match.range.location
                    let sectionEnd: Int
                    if index + 1 < subgroupMatches.count {
                        sectionEnd = subgroupMatches[index + 1].range.location
                    } else {
                        sectionEnd = (chapterSectionHTML as NSString).length
                    }
                    let sectionRange = NSRange(location: sectionStart, length: max(0, sectionEnd - sectionStart))
                    guard let sectionText = substring(in: chapterSectionHTML, nsRange: sectionRange) else { continue }

                    let chapters = parseManhuaGuiChapters(
                        in: sectionText,
                        slug: slug,
                        volumeID: "h\(index)",
                        volumeName: volumeName,
                        seenChapterIDs: &seenChapterIDs
                    )
                    if !chapters.isEmpty {
                        volumes.append(
                            ComicVolume(
                                id: "h\(index)",
                                displayName: volumeName,
                                pathWord: "h\(index)",
                                chapters: chapters
                            )
                        )
                    }
                }
            }

            if volumes.isEmpty {
                var sectionSeen: Set<String> = []
                let sectionChapters = parseManhuaGuiChapters(
                    in: chapterSectionHTML,
                    slug: slug,
                    volumeID: "default",
                    volumeName: "默认卷",
                    seenChapterIDs: &sectionSeen
                )
                if !sectionChapters.isEmpty {
                    volumes = [
                        ComicVolume(id: "default", displayName: "默认卷", pathWord: "default", chapters: sectionChapters)
                    ]
                }
            }
        }

        if volumes.isEmpty {
            var fallbackSeen: Set<String> = []
            let fallbackChapters = parseManhuaGuiChapters(
                in: html,
                slug: slug,
                volumeID: "default",
                volumeName: "默认卷",
                seenChapterIDs: &fallbackSeen
            )
            if !fallbackChapters.isEmpty {
                volumes = [
                    ComicVolume(id: "default", displayName: "默认卷", pathWord: "default", chapters: fallbackChapters)
                ]
            }
        }

        return volumes
    }

    private func extractManhuaGuiChapterSection(from html: String) -> String? {
        let headingMatches = matches(
            in: html,
            pattern: #"(?is)<h([2-6])[^>]*>(.*?)</h\1>"#
        )
        guard !headingMatches.isEmpty else { return nil }

        for (index, match) in headingMatches.enumerated() {
            guard let levelText = substring(in: html, nsRange: match.range(at: 1)),
                  let level = Int(levelText),
                  let headingText = substring(in: html, nsRange: match.range(at: 2)) else {
                continue
            }
            let cleaned = cleanHTMLText(headingText)
            guard cleaned.contains("章节全集") || cleaned.contains("章節全集") else { continue }

            let sectionStart = match.range.location
            var sectionEnd = (html as NSString).length

            for nextMatch in headingMatches.dropFirst(index + 1) {
                guard let nextLevelText = substring(in: html, nsRange: nextMatch.range(at: 1)),
                      let nextLevel = Int(nextLevelText) else {
                    continue
                }
                if nextLevel <= level {
                    sectionEnd = nextMatch.range.location
                    break
                }
            }

            let sectionRange = NSRange(location: sectionStart, length: max(0, sectionEnd - sectionStart))
            return substring(in: html, nsRange: sectionRange)
        }

        return nil
    }

    private func isManhuaGuiVolumeHeading(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, !isGenericSectionTitle(cleaned) else { return false }
        return !isLikelyManhuaGuiChapterTitle(cleaned)
    }

    private func isLikelyManhuaGuiChapterTitle(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return false }
        if cleaned.contains("总编集") || cleaned.contains("總編集") {
            return true
        }
        if cleaned.contains("完整版第") {
            return true
        }
        if cleaned.contains("第"), (cleaned.contains("卷") || cleaned.contains("话") || cleaned.contains("話")) {
            return true
        }
        return false
    }

    private func parseManhuaGuiChapters(
        in sourceHTML: String,
        slug: String,
        volumeID: String,
        volumeName: String,
        seenChapterIDs: inout Set<String>
    ) -> [ComicChapter] {
        let slugPattern = NSRegularExpression.escapedPattern(for: slug)
        let anchorPattern = #"(?is)<a[^>]*href\s*=\s*["']((?:https?://[^/"']+)?/comic/\#(slugPattern)/([^/"'#?]+)(?:\.html)?/?(?:\?[^"']*)?)["'][^>]*>(.*?)</a>"#
        let anchorMatches = matches(in: sourceHTML, pattern: anchorPattern)

        var chapters: [ComicChapter] = []
        var order = 0

        for match in anchorMatches {
            guard let chapterRaw = substring(in: sourceHTML, nsRange: match.range(at: 2)) else { continue }
            var chapterID = chapterRaw
                .replacingOccurrences(of: ".html", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if chapterID.isEmpty { continue }
            chapterID = chapterID.replacingOccurrences(of: "\\/", with: "/")
            if chapterID.contains("/") { continue }
            if seenChapterIDs.contains(chapterID) { continue }
            seenChapterIDs.insert(chapterID)

            let anchorHTML = substring(in: sourceHTML, nsRange: match.range(at: 0)) ?? ""
            let titleFromAttr = firstMatch(in: anchorHTML, pattern: #"(?is)\btitle\s*=\s*["'](.*?)["']"#).map(cleanHTMLText)
            let titleFromInner = substring(in: sourceHTML, nsRange: match.range(at: 3)).map(cleanHTMLText) ?? ""
            var title = titleFromAttr?.isEmpty == false ? titleFromAttr! : titleFromInner
            if title.isEmpty || isPseudoReadButtonTitle(title) {
                if let inferred = inferFriendlyChapterName(fromID: chapterID) {
                    title = inferred
                } else {
                    title = chapterID
                }
            }

            chapters.append(
                ComicChapter(
                    id: chapterID,
                    uuid: chapterID,
                    displayName: title,
                    order: Double(order),
                    volumeID: volumeID,
                    volumeName: volumeName
                )
            )
            order += 1
        }

        return chapters
    }

    private func isPseudoReadButtonTitle(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        if normalized.isEmpty { return true }
        let bad = ["开始阅读", "開始閱讀", "立即阅读", "立即閱讀", "readnow", "startreading", "开始", "閱讀"]
        return bad.contains { normalized.contains($0.lowercased()) }
    }

    private func inferFriendlyChapterName(fromID id: String) -> String? {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let digits = trimmed.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        if digits.count <= 3 {
            return "第\(digits)话"
        }
        return nil
    }

    private func fetchImageURLsFromManhuaGui(
        slug: String,
        chapterID: String,
        chapterName: String,
        site: MangaSiteConfig,
        cookie: String?
    ) async throws -> [URL] {
        // Stagger chapter HTML fetches slightly to reduce burst pressure on ManhuaGui.
        try await Task.sleep(for: .milliseconds(Int.random(in: 120...260)))
        let chapterPath: String
        if chapterID.hasSuffix(".html") {
            chapterPath = chapterID
        } else {
            chapterPath = "\(chapterID).html"
        }
        let chapterURL = site.webBase.appendingPathComponent("comic/\(slug)/\(chapterPath)")
        let html = try await getHTML(url: chapterURL, cookie: cookie, site: site, retryTimes: 1)
        log("ManhuaGui 章节页已返回：\(chapterURL.absoluteString)（\(html.count) 字符）")

        let urls = parseManhuaGuiImageURLs(html: html, site: site)
        if urls.isEmpty {
            log("ManhuaGui 章节取图失败：未从章节页提取到图片载荷")
            throw CopyMangaError.htmlParse("漫画柜章节页已返回，但未解析到图片载荷")
        }
        log("ManhuaGui 章节取图成功：\(chapterName) 共 \(urls.count) 张")
        return urls
    }

    private func parseManhuaGuiImageURLs(html: String, site: MangaSiteConfig) -> [URL] {
        let direct = imageURLsFromLoosePattern(in: html, site: site)
        if !direct.isEmpty {
            if isManhuaGui(site) {
                log("ManhuaGui 图片解析：命中直链/宽松脚本提取 \(direct.count) 张")
            }
            return direct
        }

        let scripts = scriptContents(from: html)
        for script in scripts {
            if let object = captureImageDataObject(from: script) {
                let urls = imageURLs(fromImagePayload: object, source: script, site: site)
                if !urls.isEmpty {
                    if isManhuaGui(site) {
                        log("ManhuaGui 图片解析：命中 JS 对象载荷 \(urls.count) 张")
                    }
                    return urls
                }
            }

            if let decoded = decodePackedScript(from: script) {
                if let object = captureImageDataObject(from: decoded) {
                    let urls = imageURLs(fromImagePayload: object, source: decoded, site: site)
                    if !urls.isEmpty {
                        if isManhuaGui(site) {
                            log("ManhuaGui 图片解析：命中解包脚本载荷 \(urls.count) 张")
                        }
                        return urls
                    }
                }

                let fallback = imageURLsFromLoosePattern(in: decoded, site: site)
                if !fallback.isEmpty {
                    if isManhuaGui(site) {
                        log("ManhuaGui 图片解析：命中解包脚本宽松提取 \(fallback.count) 张")
                    }
                    return fallback
                }
            }
        }

        return []
    }

    private func imageURLs(fromImagePayload payload: [String: Any], source: String? = nil, site: MangaSiteConfig) -> [URL] {
        let files = extractFiles(from: payload)
        if files.isEmpty {
            return []
        }

        let path = extractPayloadString(
            keys: ["path", "imgpath", "chapterPath", "img_path", "chapter_path"],
            from: payload
        ) ?? source.flatMap {
            firstMatch(
                in: $0,
                pattern: #"(?is)["'](?:path|imgpath|chapterPath|img_path|chapter_path)["']\s*:\s*["'](.*?)["']"#
            )
        }
        let host = extractPayloadString(
            keys: ["domain", "host", "imgHost", "cdn", "imgDomain", "img_host"],
            from: payload
        ) ?? source.flatMap {
            firstMatch(
                in: $0,
                pattern: #"(?is)["'](?:domain|host|imgHost|cdn|imgDomain|img_host)["']\s*:\s*["'](.*?)["']"#
            )
        }
        let signature = manhuaGuiSignature(from: payload) ?? source.flatMap(manhuaGuiSignature(from:))

        if isManhuaGui(site) {
            log("ManhuaGui 图片载荷：files=\(files.count), path=\(path ?? "-"), host=\(host ?? "-"), sl=\(signature == nil ? "无" : "有")")
        }

        return buildImageURLs(files: files, path: path, host: host, site: site, signature: signature)
    }

    private func extractFiles(from payload: [String: Any]) -> [String] {
        if let direct = directFiles(in: payload), !direct.isEmpty {
            return direct
        }
        for nested in nestedPayloadObjects(in: payload) {
            if let files = directFiles(in: nested), !files.isEmpty {
                return files
            }
        }
        return []
    }

    private func directFiles(in payload: [String: Any]) -> [String]? {
        let candidateKeys = ["files", "images", "imgs", "imgs_url", "imgsUrl"]
        for key in candidateKeys {
            if let files = payload[key] as? [String], !files.isEmpty {
                return files
            }
            if let list = payload[key] as? [Any] {
                let files = list.compactMap { $0 as? String }
                if !files.isEmpty {
                    return files
                }
            }
        }
        return nil
    }

    private func extractPayloadString(keys: [String], from payload: [String: Any]) -> String? {
        for key in keys {
            if let value = payload[key] as? String, !value.isEmpty {
                return value
            }
        }
        for nested in nestedPayloadObjects(in: payload) {
            for key in keys {
                if let value = nested[key] as? String, !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private func nestedPayloadObjects(in payload: [String: Any]) -> [[String: Any]] {
        var results: [[String: Any]] = []

        func collect(from value: Any) {
            if let dict = value as? [String: Any] {
                results.append(dict)
                for nested in dict.values {
                    collect(from: nested)
                }
            } else if let array = value as? [Any] {
                for element in array {
                    collect(from: element)
                }
            }
        }

        for value in payload.values {
            collect(from: value)
        }
        return results
    }

    private func imageURLsFromLoosePattern(in source: String, site: MangaSiteConfig) -> [URL] {
        guard let filesSegment = firstMatch(
            in: source,
            pattern: #"(?is)["']files["']\s*:\s*\[(.*?)\]"#
        ) else {
            return []
        }
        let files = quotedStrings(in: filesSegment)
        if files.isEmpty {
            return []
        }

        let path = firstMatch(
            in: source,
            pattern: #"(?is)["'](?:path|imgpath|chapterPath)["']\s*:\s*["'](.*?)["']"#
        )
        let host = firstMatch(
            in: source,
            pattern: #"(?is)["'](?:domain|host|imgHost|cdn)["']\s*:\s*["'](.*?)["']"#
        )
        let signature = manhuaGuiSignature(from: source)
        return buildImageURLs(files: files, path: path, host: host, site: site, signature: signature)
    }

    private func buildImageURLs(
        files: [String],
        path: String?,
        host: String?,
        site: MangaSiteConfig,
        signature: ManhuaGuiSignature? = nil
    ) -> [URL] {
        let normalizedHost = normalizedHostURL(host)
        let normalizedPath = normalizePath(path)
        let defaultHost = manhuaGuiFallbackHost(site: site, path: normalizedPath)
        let effectiveHost = normalizedHost ?? defaultHost
        var urls: [URL] = []
        var seen: Set<String> = []

        for rawFile in files {
            let file = rawFile
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if file.isEmpty {
                continue
            }

            let url: URL?
            if file.hasPrefix("http://") || file.hasPrefix("https://") || file.hasPrefix("//") {
                url = normalizedURL(file, site: site)
            } else if let effectiveHost {
                let prefix = normalizedPath.isEmpty ? "" : "/\(normalizedPath)"
                url = URL(string: "\(effectiveHost)\(prefix)/\(file)")
            } else {
                var combined = normalizedPath
                if !combined.isEmpty {
                    combined += "/"
                }
                combined += file
                let cleaned = combined.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                url = normalizedURL("/\(cleaned)", site: site)
            }

            if let url {
                let finalURL = withManhuaGuiSignature(signature, url: url)
                if seen.insert(finalURL.absoluteString).inserted {
                    urls.append(finalURL)
                }
            }
        }

        if isManhuaGui(site), urls.isEmpty == false {
            let sample = urls.prefix(2).map(\.absoluteString).joined(separator: " | ")
            log("ManhuaGui 图片链接组装：\(urls.count) 张，示例 \(sample)")
        }

        return urls
    }

    private func normalizedHostURL(_ raw: String?) -> String? {
        guard var host = raw?
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            return nil
        }
        if host.hasPrefix("//") {
            host = "https:\(host)"
        } else if !host.hasPrefix("http://") && !host.hasPrefix("https://") {
            host = "https://\(host)"
        }
        return host.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func normalizePath(_ raw: String?) -> String {
        guard let raw else { return "" }
        return raw
            .replacingOccurrences(of: "\\/", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private struct ManhuaGuiSignature {
        let e: String
        let m: String
    }

    private func manhuaGuiSignature(from payload: [String: Any]) -> ManhuaGuiSignature? {
        if let sl = payload["sl"] as? [String: Any] {
            return manhuaGuiSignatureFromDict(sl)
        }
        if let sl = payload["signature"] as? [String: Any] {
            return manhuaGuiSignatureFromDict(sl)
        }
        return manhuaGuiSignatureFromDict(payload)
    }

    private func manhuaGuiSignature(from source: String) -> ManhuaGuiSignature? {
        let patterns = [
            #"(?is)["'](?:sl|signature)["']\s*:\s*\{(.*?)\}"#,
            #"(?is)(?:sl|signature)\s*=\s*\{(.*?)\}"#
        ]
        for pattern in patterns {
            guard let body = firstMatch(in: source, pattern: pattern) else { continue }
            let e = firstMatch(in: body, pattern: #"(?is)["']?e["']?\s*:\s*["']?([0-9]+)["']?"#)
            let m = firstMatch(in: body, pattern: #"(?is)["']?m["']?\s*:\s*["']([^"']+)["']"#)
            if let e, let m, !e.isEmpty, !m.isEmpty {
                return ManhuaGuiSignature(e: e, m: m)
            }
        }
        return nil
    }

    private func manhuaGuiSignatureFromDict(_ dict: [String: Any]) -> ManhuaGuiSignature? {
        let e: String?
        if let value = dict["e"] as? String, !value.isEmpty {
            e = value
        } else if let value = dict["e"] as? Int {
            e = String(value)
        } else if let value = dict["e"] as? Double {
            e = String(Int(value))
        } else {
            e = nil
        }

        let m = dict["m"] as? String
        guard let e, let m, !m.isEmpty else { return nil }
        return ManhuaGuiSignature(e: e, m: m)
    }

    private func withManhuaGuiSignature(_ signature: ManhuaGuiSignature?, url: URL) -> URL {
        guard let signature else { return url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var queryItems = components.queryItems ?? []
        if !queryItems.contains(where: { $0.name == "e" }) {
            queryItems.append(URLQueryItem(name: "e", value: signature.e))
        }
        if !queryItems.contains(where: { $0.name == "m" }) {
            queryItems.append(URLQueryItem(name: "m", value: signature.m))
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    private func manhuaGuiFallbackHost(site: MangaSiteConfig, path: String) -> String? {
        guard isManhuaGui(site), !path.isEmpty else { return nil }
        return "https://i.hamreus.com"
    }

    private func scriptContents(from html: String) -> [String] {
        let scriptMatches = matches(in: html, pattern: #"(?is)<script[^>]*>(.*?)</script>"#)
        return scriptMatches.compactMap { match in
            guard let script = substring(in: html, nsRange: match.range(at: 1)) else { return nil }
            let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private func captureImageDataObject(from script: String) -> [String: Any]? {
        let context = JSContext()
        context?.exceptionHandler = { _, _ in }
        _ = context?.evaluateScript(manhuaGuiSplicShim)
        _ = context?.evaluateScript(
            """
            var __imgData = null;
            var window = this;
            var SMH = { imgData: function(data){ __imgData = data; }, chapter: function(data){ __imgData = data; } };
            var C_DATA = null;
            var DATA = null;
            var cInfo = null;
            var chapterData = null;
            """
        )
        _ = context?.evaluateScript(script)

        let candidates = ["__imgData", "C_DATA", "DATA", "cInfo", "chapterData"]
        for key in candidates {
            guard let json = context?.evaluateScript("typeof \(key) === 'undefined' || \(key) === null ? '' : JSON.stringify(\(key));")?.toString() else {
                continue
            }
            if json.isEmpty || json == "undefined" || json == "null" {
                continue
            }
            guard let data = json.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if !object.isEmpty {
                return object
            }
        }
        return nil
    }

    private func decodePackedScript(from script: String) -> String? {
        let lowered = script.lowercased()
        guard lowered.contains("eval(") || lowered.contains("\\x65\\x76\\x61\\x6c") else {
            return nil
        }

        let context = JSContext()
        context?.exceptionHandler = { _, _ in }
        _ = context?.evaluateScript(manhuaGuiSplicShim)
        let scriptLiteral = javaScriptLiteral(script)
        let decodeScript =
            """
            var __decoded = "";
            var window = this;
            window.eval = function(v){ __decoded = String(v); return v; };
            window["\\x65\\x76\\x61\\x6c"] = window.eval;
            this.eval = window.eval;
            try {
                (new Function(\(scriptLiteral)))();
            } catch (e) {}
            __decoded;
            """
        guard let decoded = context?.evaluateScript(decodeScript)?.toString() else {
            return nil
        }
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var manhuaGuiSplicShim: String {
        #"""
        var LZString=(function(){var f=String.fromCharCode;var keyStrBase64="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";var baseReverseDic={};function getBaseValue(alphabet,character){if(!baseReverseDic[alphabet]){baseReverseDic[alphabet]={};for(var i=0;i<alphabet.length;i++){baseReverseDic[alphabet][alphabet.charAt(i)]=i}}return baseReverseDic[alphabet][character]}var LZString={decompressFromBase64:function(input){if(input==null)return"";if(input=="")return null;return LZString._0(input.length,32,function(index){return getBaseValue(keyStrBase64,input.charAt(index))})},_0:function(length,resetValue,getNextValue){var dictionary=[],next,enlargeIn=4,dictSize=4,numBits=3,entry="",result=[],i,w,bits,resb,maxpower,power,c,data={val:getNextValue(0),position:resetValue,index:1};for(i=0;i<3;i+=1){dictionary[i]=i}bits=0;maxpower=Math.pow(2,2);power=1;while(power!=maxpower){resb=data.val&data.position;data.position>>=1;if(data.position==0){data.position=resetValue;data.val=getNextValue(data.index++)}bits|=(resb>0?1:0)*power;power<<=1}switch(next=bits){case 0:bits=0;maxpower=Math.pow(2,8);power=1;while(power!=maxpower){resb=data.val&data.position;data.position>>=1;if(data.position==0){data.position=resetValue;data.val=getNextValue(data.index++)}bits|=(resb>0?1:0)*power;power<<=1}c=f(bits);break;case 1:bits=0;maxpower=Math.pow(2,16);power=1;while(power!=maxpower){resb=data.val&data.position;data.position>>=1;if(data.position==0){data.position=resetValue;data.val=getNextValue(data.index++)}bits|=(resb>0?1:0)*power;power<<=1}c=f(bits);break;case 2:return""}dictionary[3]=c;w=c;result.push(c);while(true){if(data.index>length){return""}bits=0;maxpower=Math.pow(2,numBits);power=1;while(power!=maxpower){resb=data.val&data.position;data.position>>=1;if(data.position==0){data.position=resetValue;data.val=getNextValue(data.index++)}bits|=(resb>0?1:0)*power;power<<=1}switch(c=bits){case 0:bits=0;maxpower=Math.pow(2,8);power=1;while(power!=maxpower){resb=data.val&data.position;data.position>>=1;if(data.position==0){data.position=resetValue;data.val=getNextValue(data.index++)}bits|=(resb>0?1:0)*power;power<<=1}dictionary[dictSize++]=f(bits);c=dictSize-1;enlargeIn--;break;case 1:bits=0;maxpower=Math.pow(2,16);power=1;while(power!=maxpower){resb=data.val&data.position;data.position>>=1;if(data.position==0){data.position=resetValue;data.val=getNextValue(data.index++)}bits|=(resb>0?1:0)*power;power<<=1}dictionary[dictSize++]=f(bits);c=dictSize-1;enlargeIn--;break;case 2:return result.join('')}if(enlargeIn==0){enlargeIn=Math.pow(2,numBits);numBits++}if(dictionary[c]){entry=dictionary[c]}else{if(c===dictSize){entry=w+w.charAt(0)}else{return null}}result.push(entry);dictionary[dictSize++]=w+entry.charAt(0);enlargeIn--;w=entry;if(enlargeIn==0){enlargeIn=Math.pow(2,numBits);numBits++}}}};return LZString})();String.prototype.splic=function(f){var d=LZString.decompressFromBase64(this);return (d==null?String(this):d).split(f)};
        """#
    }

    private func javaScriptLiteral(_ value: String) -> String {
        var escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "\"", with: "\\\"")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        escaped = escaped.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        escaped = escaped.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "\"\(escaped)\""
    }

    private var copyWebViewRuntimeShim: String {
        #"""
        var __MG_APPENDED = [];
        var window = this;
        window.scrollTo = function(){};
        window.onscroll = null;
        var setTimeout = function(fn){ try { if (typeof fn === "function") fn(); } catch (e) {} return 0; };
        var clearTimeout = function(){};
        var location = { href: "", host: "", protocol: "https:" };
        var navigator = { userAgent: "Mozilla/5.0" };
        var document = {
            body: { onmouseup: function(){} },
            querySelector: function(sel){
                if (sel === ".comicContent-list") {
                    return {
                        offsetHeight: 0,
                        append: function(node){
                            try {
                                if (node && typeof node.innerHTML === "string" && node.innerHTML.length > 0) {
                                    __MG_APPENDED.push(node.innerHTML);
                                }
                            } catch (e) {}
                        }
                    };
                }
                if (sel === ".comicIndex" || sel === ".comicCount") {
                    return { innerText: "0", offsetHeight: 0 };
                }
                return { innerText: "", offsetHeight: 0, append: function(){}, onmouseup: function(){} };
            },
            querySelectorAll: function(){ return []; },
            createElement: function(){ return { innerHTML: "", offsetTop: 0 }; }
        };
        var $ = function(v){
            if (typeof v === "function") {
                try { v(); } catch (e) {}
                return {};
            }
            return { click: function(){}, on: function(){}, ready: function(fn){ if (typeof fn === "function") { try { fn(); } catch (e) {} } } };
        };
        var jQuery = $;
        """#
    }

    private func quotedStrings(in source: String) -> [String] {
        let matches = matches(in: source, pattern: #"(?is)["'](.*?)["']"#)
        return matches.compactMap { match in
            guard let text = substring(in: source, nsRange: match.range(at: 1)) else { return nil }
            let cleaned = text
                .replacingOccurrences(of: "\\/", with: "/")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private func fetchVolume(slug: String, groupPathWord: String, fallbackName: String, cookie: String?, site: MangaSiteConfig, resolved: ResolvedAPI) async throws -> ComicVolume? {
        let paths = [
            "\(resolved.pathPrefix)/\(slug)/group/\(groupPathWord)/chapters",
            "\(resolved.pathPrefix)/\(slug)/groups/\(groupPathWord)/chapters"
        ]
        let payload = try await getJSON(paths: paths, site: site, cookie: cookie, preferredBaseURL: resolved.baseURL)

        let (results, chapterNodesFromArray): ([String: Any], [Any]?) = {
            if let dict = primaryObjectOrNil(from: payload) {
                return (dict, nil)
            }
            if let arr = primaryArray(from: payload) {
                return ([:], arr)
            }
            return ([:], nil)
        }()

        let chapterNodes = chapterNodesFromArray ?? JSONNavigator.array(results, keys: ["list", "chapters", "items", "results"]) ?? []
        if chapterNodes.isEmpty {
            return nil
        }

        let displayName = JSONNavigator.string(results, keys: ["name", "title"]) ?? fallbackName

        var chapters: [ComicChapter] = chapterNodes.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            guard let uuid = chapterIdentifier(from: dict) else { return nil }
            let chapterName = JSONNavigator.string(dict, keys: ["name", "title"]) ?? uuid
            let order = JSONNavigator.number(dict, keys: ["index", "order", "sort", "chapter_id", "sequence"]) ?? 0
            return ComicChapter(id: uuid, uuid: uuid, displayName: chapterName, order: order, volumeID: groupPathWord, volumeName: displayName)
        }

        chapters.sort { lhs, rhs in
            if lhs.order == rhs.order { return lhs.displayName < rhs.displayName }
            return lhs.order < rhs.order
        }
        if chapters.isEmpty { return nil }

        return ComicVolume(id: groupPathWord, displayName: displayName, pathWord: groupPathWord, chapters: chapters)
    }

    private func resolveAPI(slug: String, site: MangaSiteConfig, cookie: String?, forceRefresh: Bool) async throws -> ResolvedAPI {
        try await antiBanGuard.check(site: site)
        if !forceRefresh, let cached = await endpointCache.get(for: site) {
            return cached
        }

        var tried: [String] = []
        var lastDetail: String?
        let prefixes = ["comic", "comic2"]
        for prefix in prefixes {
            for base in site.apiBaseURLs {
                let path = "\(prefix)/\(slug)"
                let url = base.appendingPathComponent(path)
                tried.append(url.absoluteString)
                do {
                    let payload = try await getJSON(path: path, site: site, cookie: cookie, baseURL: base, retryTimes: 1)
                    if primaryObjectOrNil(from: payload) == nil {
                        if let detail = apiDetailMessage(from: payload) {
                            lastDetail = detail
                            if isBanDetail(detail) {
                                await antiBanGuard.block(site: site, seconds: 15)
                                throw CopyMangaError.apiDetail(detail)
                            }
                            continue
                        }
                        continue
                    }
                    let resolved = ResolvedAPI(baseURL: base, pathPrefix: prefix)
                    await endpointCache.set(resolved, for: site)
                    return resolved
                } catch let error as CopyMangaError {
                    if case .httpStatus(let code, _) = error, code == 404 { continue }
                    if case .apiDetail(let detail) = error {
                        lastDetail = detail
                        if isBanDetail(detail) {
                            await antiBanGuard.block(site: site, seconds: 15)
                            throw error
                        }
                        continue
                    }
                    throw error
                }
            }
        }
        if let lastDetail {
            throw CopyMangaError.apiDetail(lastDetail)
        }
        throw CopyMangaError.allEndpoints404(tried)
    }

    private func parseGroups(from results: [String: Any]) -> [(pathWord: String, name: String)] {
        if let groups = results["groups"] as? [String: Any] {
            let parsed = groups.compactMap { key, value -> (String, String)? in
                if let name = value as? String { return (key, name) }
                if let obj = value as? [String: Any] {
                    let path = JSONNavigator.string(obj, keys: ["path_word", "path", "id"]) ?? key
                    let name = JSONNavigator.string(obj, keys: ["name", "title"]) ?? key
                    return (path, name)
                }
                return (key, key)
            }
            if !parsed.isEmpty { return parsed }
        }

        if let groups = results["groups"] as? [[String: Any]] {
            let parsed = groups.compactMap { group -> (String, String)? in
                let path = JSONNavigator.string(group, keys: ["path_word", "path", "id"])
                let name = JSONNavigator.string(group, keys: ["name", "title"]) ?? path
                if let path, let name { return (path, name) }
                return nil
            }
            if !parsed.isEmpty { return parsed }
        }

        if let groups = results["groups"] as? [String], !groups.isEmpty {
            return groups.map { ($0, $0) }
        }

        return []
    }

    private func parseInlineVolume(from results: [String: Any]) -> ComicVolume? {
        let chapterNodes = JSONNavigator.array(results, keys: ["chapters", "list", "items", "chapter_list"]) ?? []
        if chapterNodes.isEmpty { return nil }

        var chapters: [ComicChapter] = chapterNodes.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            guard let uuid = chapterIdentifier(from: dict) else { return nil }
            let chapterName = JSONNavigator.string(dict, keys: ["name", "title"]) ?? uuid
            let order = JSONNavigator.number(dict, keys: ["index", "order", "sort", "chapter_id", "sequence"]) ?? 0
            return ComicChapter(id: uuid, uuid: uuid, displayName: chapterName, order: order, volumeID: "default", volumeName: "默认卷")
        }

        chapters.sort { lhs, rhs in
            if lhs.order == rhs.order { return lhs.displayName < rhs.displayName }
            return lhs.order < rhs.order
        }
        if chapters.isEmpty { return nil }
        return ComicVolume(id: "default", displayName: "默认卷", pathWord: "default", chapters: chapters)
    }

    private func primaryObject(from payload: [String: Any]) throws -> [String: Any] {
        if let dict = primaryObjectOrNil(from: payload) { return dict }
        throw CopyMangaError.payloadShape(Array(payload.keys).sorted())
    }

    private func primaryObjectOrNil(from payload: [String: Any]) -> [String: Any]? {
        if let results = payload["results"] as? [String: Any] { return results }
        if let data = payload["data"] as? [String: Any] { return data }
        if let result = payload["result"] as? [String: Any] { return result }
        if let comic = payload["comic"] as? [String: Any] { return comic }
        if let response = payload["response"] as? [String: Any] { return response }
        if let arr = payload["results"] as? [[String: Any]], let first = arr.first { return first }
        if let arr = payload["data"] as? [[String: Any]], let first = arr.first { return first }
        if isLikelyPayloadObject(payload) {
            return payload
        }
        return nil
    }

    private func primaryArray(from payload: [String: Any]) -> [Any]? {
        if let arr = payload["results"] as? [Any] { return arr }
        if let arr = payload["data"] as? [Any] { return arr }
        if let arr = payload["items"] as? [Any] { return arr }
        if let arr = payload["list"] as? [Any] { return arr }
        return nil
    }

    private func chapterIdentifier(from dict: [String: Any]) -> String? {
        if let id = JSONNavigator.string(dict, keys: ["uuid", "id", "chapter_uuid", "chapterId", "chapter_id"]) {
            return id
        }
        if let numeric = dict["id"] as? Int { return String(numeric) }
        if let numeric = dict["chapter_id"] as? Int { return String(numeric) }
        return nil
    }

    private func getJSON(path: String, site: MangaSiteConfig, cookie: String?, baseURL: URL) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(path)
        return try await getJSON(url: url, cookie: cookie, site: site)
    }

    private func getJSON(paths: [String], site: MangaSiteConfig, cookie: String?, preferredBaseURL: URL) async throws -> [String: Any] {
        var triedURLs: [String] = []

        for path in paths {
            let preferredURL = preferredBaseURL.appendingPathComponent(path)
            triedURLs.append(preferredURL.absoluteString)
            do {
                return try await getJSON(url: preferredURL, cookie: cookie, site: site)
            } catch let error as CopyMangaError {
                if case .httpStatus(let code, _) = error, code == 404 {
                    continue
                }
                throw error
            }
        }

        throw CopyMangaError.allEndpoints404(triedURLs)
    }

    private func getJSON(path: String, site: MangaSiteConfig, cookie: String?, baseURL: URL, retryTimes: Int) async throws -> [String: Any] {
        let url = baseURL.appendingPathComponent(path)
        return try await getJSON(url: url, cookie: cookie, site: site, retryTimes: retryTimes)
    }

    private func getJSON(url: URL, cookie: String?, site: MangaSiteConfig) async throws -> [String: Any] {
        try await getJSON(url: url, cookie: cookie, site: site, retryTimes: 2)
    }

    private func getJSON(url: URL, cookie: String?, site: MangaSiteConfig, retryTimes: Int) async throws -> [String: Any] {
        return try await retrying(times: retryTimes) {
            try await self.antiBanGuard.check(site: site)
            try await self.apiPacer.waitTurn()
            self.log("GET JSON: \(url.absoluteString)")
            let request = self.baseRequest(url: url, cookie: cookie, site: site)
            let (data, response) = try await self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CopyMangaError.unexpectedPayload
            }
            guard (200...299).contains(http.statusCode) else {
                if [403, 429, 503].contains(http.statusCode) {
                    await self.antiBanGuard.block(site: site, seconds: self.banCooldownSeconds(for: site))
                }
                throw CopyMangaError.httpStatus(http.statusCode, self.snippet(from: data))
            }
            do {
                let payload = try JSONNavigator.object(data: data)
                if let detail = self.apiDetailMessage(from: payload) {
                    if self.isBanDetail(detail) {
                        await self.antiBanGuard.block(site: site, seconds: self.banCooldownSeconds(for: site))
                        throw CopyMangaError.parseBlocked(detail)
                    }
                    throw CopyMangaError.apiDetail(detail)
                }
                await self.apiPacer.markSuccess()
                return payload
            } catch {
                if let error = error as? CopyMangaError {
                    throw error
                }
                let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "unknown"
                throw CopyMangaError.invalidJSON(contentType: contentType, snippet: self.snippet(from: data))
            }
        }
    }

    private func getHTML(url: URL, cookie: String?, site: MangaSiteConfig, retryTimes: Int) async throws -> String {
        return try await retrying(times: retryTimes) {
            try await self.antiBanGuard.check(site: site)
            try await self.apiPacer.waitTurn()
            self.log("GET HTML: \(url.absoluteString)")
            let request = self.baseRequest(url: url, cookie: cookie, site: site)
            let (data, response) = try await self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CopyMangaError.unexpectedPayload
            }
            guard (200...299).contains(http.statusCode) else {
                if [403, 429, 503].contains(http.statusCode) {
                    await self.antiBanGuard.block(site: site, seconds: self.banCooldownSeconds(for: site))
                }
                throw CopyMangaError.httpStatus(http.statusCode, self.snippet(from: data))
            }

            guard let text = self.decodeResponseText(data) else {
                throw CopyMangaError.unexpectedPayload
            }
            if let blockedReason = self.banReason(in: text) {
                await self.antiBanGuard.block(site: site, seconds: self.banCooldownSeconds(for: site))
                throw CopyMangaError.parseBlocked(blockedReason)
            } else {
                await self.apiPacer.markSuccess()
            }
            return text
        }
    }

    private func getText(
        url: URL,
        cookie: String?,
        site: MangaSiteConfig,
        retryTimes: Int,
        extraHeaders: [String: String]
    ) async throws -> String {
        return try await retrying(times: retryTimes) {
            try await self.antiBanGuard.check(site: site)
            try await self.apiPacer.waitTurn()
            self.log("GET TEXT: \(url.absoluteString)")
            var request = self.baseRequest(url: url, cookie: cookie, site: site)
            for (k, v) in extraHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            let (data, response) = try await self.session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw CopyMangaError.unexpectedPayload
            }
            guard (200...299).contains(http.statusCode) else {
                if [403, 429, 503].contains(http.statusCode) {
                    await self.antiBanGuard.block(site: site, seconds: self.banCooldownSeconds(for: site))
                }
                throw CopyMangaError.httpStatus(http.statusCode, self.snippet(from: data))
            }
            guard let text = self.decodeResponseText(data) else {
                throw CopyMangaError.unexpectedPayload
            }
            if let blockedReason = self.banReason(in: text) {
                await self.antiBanGuard.block(site: site, seconds: self.banCooldownSeconds(for: site))
                throw CopyMangaError.parseBlocked(blockedReason)
            }
            await self.apiPacer.markSuccess()
            return text
        }
    }

    private func baseRequest(url: URL, cookie: String?, site: MangaSiteConfig) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(site.webBase.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
        if let cookie, !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func decodeResponseText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let text = String(data: data, encoding: gb18030), !text.isEmpty {
            return text
        }
        if let latin = String(data: data, encoding: .isoLatin1), !latin.isEmpty {
            return latin
        }
        return nil
    }

    private func extractCoverURL(from html: String, site: MangaSiteConfig) -> URL? {
        let patterns = [
            #"(?is)<meta\s+property\s*=\s*["']og:image["']\s+content\s*=\s*["'](.*?)["']"#,
            #"(?is)<meta\s+name\s*=\s*["']twitter:image["']\s+content\s*=\s*["'](.*?)["']"#,
            #"(?is)<p[^>]*class\s*=\s*["'][^"']*hcover[^"']*["'][^>]*>.*?<img[^>]+(?:data-src|src)\s*=\s*["'](.*?)["']"#,
            #"(?is)<img[^>]+(?:data-src|src)\s*=\s*["'](//[^"']*?/cpic/h/[^"']+)["']"#,
            #"(?is)<img[^>]+(?:id|class)\s*=\s*["'][^"']*(?:cover|comic|book-cover|hcover)[^"']*["'][^>]+(?:data-src|src)\s*=\s*["'](.*?)["']"#,
            #"(?is)["'](?:cover|cover_url|comic_cover|banner|image|img)["']\s*:\s*["'](https?:\\?/\\?/[^"']+\.(?:jpg|jpeg|png|webp))["']"#,
            #"(?is)["'](?:cover|cover_url|comic_cover|banner|image|img)["']\s*:\s*["'](\\?/\\?/[^"']+\.(?:jpg|jpeg|png|webp))["']"#
        ]
        for pattern in patterns {
            if let raw = firstMatch(in: html, pattern: pattern) {
                let cleaned = raw.replacingOccurrences(of: "\\/", with: "/")
                if let url = normalizedURL(cleaned, site: site) {
                    return url
                }
            }
        }

        for script in scriptContents(from: html) {
            if let raw = firstMatch(
                in: script,
                pattern: #"(?is)["'](?:cover|cover_url|comic_cover|banner|image|img)["']\s*:\s*["'](.*?)["']"#
            ) {
                let cleaned = raw.replacingOccurrences(of: "\\/", with: "/")
                if let url = normalizedURL(cleaned, site: site), looksLikeImageURL(cleaned) {
                    return url
                }
            }
        }

        for raw in regexImageURLCandidates(in: html) {
            if raw.contains("/cover") || raw.contains("/cpic/") || raw.lowercased().contains("cover"),
               let url = normalizedURL(raw, site: site) {
                return url
            }
        }
        return nil
    }

    private func normalizedURL(_ raw: String?, site: MangaSiteConfig) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("/") { return URL(string: site.webBase.absoluteString + raw) }
        return URL(string: raw)
    }

    private func retrying<T>(times: Int, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        for attempt in 1...times {
            do {
                return try await operation()
            } catch let error as CopyMangaError {
                if case .httpStatus(let code, _) = error, code == 404 {
                    throw error
                }
                if case .httpStatus(let code, _) = error, [403, 429, 503].contains(code) {
                    throw error
                }
                if case .apiDetail = error {
                    throw error
                }
                if case .parseBlocked = error {
                    throw error
                }
                if case .cooldown = error {
                    throw error
                }
                lastError = error
                if attempt < times {
                    try await Task.sleep(for: .milliseconds(220 * attempt))
                }
            } catch {
                lastError = error
                if attempt < times {
                    try await Task.sleep(for: .milliseconds(220 * attempt))
                }
            }
        }
        throw lastError ?? CopyMangaError.unexpectedPayload
    }

    private func snippet(from data: Data, maxLength: Int = 120) -> String {
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        let trimmed = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        if trimmed.count <= maxLength { return trimmed }
        let end = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return "\(trimmed[..<end])..."
    }

    private func isLikelyPayloadObject(_ payload: [String: Any]) -> Bool {
        let markerKeys: Set<String> = [
            "name", "title", "groups", "chapters", "chapter_list", "contents", "images", "pages", "chapter", "list", "items"
        ]
        return !Set(payload.keys).intersection(markerKeys).isEmpty
    }

    private func matches(in text: String, pattern: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let nsText = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
    }

    private func firstMatch(in text: String, pattern: String, group: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, options: [], range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > group else {
            return nil
        }
        return substring(in: text, nsRange: match.range(at: group))
    }

    private func substring(in text: String, nsRange: NSRange) -> String? {
        guard let range = range(of: nsRange, in: text) else { return nil }
        return String(text[range])
    }

    private func range(of nsRange: NSRange, in text: String) -> Range<String.Index>? {
        guard nsRange.location != NSNotFound,
              let range = Range(nsRange, in: text) else {
            return nil
        }
        return range
    }

    private func cleanHTMLText(_ text: String) -> String {
        let stripped = text.replacingOccurrences(
            of: #"(?is)<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        let decoded = decodeHTMLEntities(stripped)
        return decoded.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func decodeHTMLEntities(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let attr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
              ) else {
            return text
        }
        return attr.string
    }

    private func apiDetailMessage(from payload: [String: Any]) -> String? {
        // Many anti-bot / gateway responses come back as {"detail":"..."} with HTTP 200.
        if let detail = payload["detail"] as? String {
            return detail
        }
        if let detailObj = payload["detail"] as? [String: Any] {
            if let message = detailObj["message"] as? String {
                return message
            }
            if let message = detailObj["detail"] as? String {
                return message
            }
            if let code = detailObj["code"] {
                return "detail code: \(code)"
            }
            return "detail object"
        }
        return nil
    }

    private func isBanDetail(_ detail: String) -> Bool {
        let text = detail.lowercased()
        let keywords = [
            "forbidden", "access denied", "too many", "rate limit", "captcha", "challenge",
            "blocked", "ban", "cloudflare", "频繁", "风控", "限制", "稍后", "拦截"
        ]
        return keywords.contains { text.contains($0) }
    }

    private func banReason(in text: String) -> String? {
        let normalized = text.lowercased()
        let keywords = [
            "captcha", "cloudflare", "challenge", "access denied", "forbidden",
            "访问过于频繁", "访问受限", "频繁", "风控", "限制", "稍后", "拦截"
        ]
        guard let matched = keywords.first(where: { normalized.contains($0.lowercased()) }) else {
            return nil
        }
        return "命中风控关键词：\(matched)"
    }

    private func copyCatalogBlockedReason(
        html: String,
        slug: String,
        expectedChapters: Int?,
        currentCount: Int,
        detailCount: Int,
        staticAnchorCount: Int
    ) -> String? {
        if let direct = banReason(in: html) {
            return direct
        }
        guard currentCount == 0, detailCount == 0, staticAnchorCount == 0 else {
            return nil
        }
        let text = cleanHTMLText(html)
        let hasReadEntry = text.contains("开始阅读") || text.contains("開始閱讀")
        let hasCatalogHints = text.contains("章节") || text.contains("章節") || html.contains("comicdetail/")
        if let expectedChapters, expectedChapters >= 10, !hasReadEntry {
            return "页面声明约 \(expectedChapters) 话，但目录锚点与探测结果均为空"
        }
        if html.contains("comicDetailAds") && !hasReadEntry && !hasCatalogHints {
            return "页面仅返回空壳结构，未发现目录骨架"
        }
        return nil
    }

    private func banCooldownSeconds(for site: MangaSiteConfig) -> Int {
        isCopyFamily(site) ? copyBanCooldownSeconds : 15
    }

    private func log(_ message: String) {
        logger?("[接口] \(message)")
    }
}

actor APIConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        running += 1
    }

    func release() {
        running = max(0, running - 1)
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}

private extension Data {
    init?(hexString: String) {
        let text = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count % 2 == 0 else { return nil }
        var data = Data(capacity: text.count / 2)
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2)
            let byteText = text[index..<next]
            guard let value = UInt8(byteText, radix: 16) else { return nil }
            data.append(value)
            index = next
        }
        self = data
    }
}

actor EndpointCache {
    private var store: [String: ResolvedAPI] = [:]
    private let defaults = UserDefaults.standard
    private let prefix = "mg.endpoint."

    func get(for site: MangaSiteConfig) -> ResolvedAPI? {
        let key = key(for: site)
        if let inMemory = store[key] {
            return inMemory
        }
        guard let saved = defaults.string(forKey: "\(prefix)\(key)") else {
            return nil
        }
        let comps = saved.split(separator: "|", maxSplits: 1).map(String.init)
        guard comps.count == 2, let url = URL(string: comps[0]) else { return nil }
        let resolved = ResolvedAPI(baseURL: url, pathPrefix: comps[1])
        store[key] = resolved
        return resolved
    }

    func set(_ value: ResolvedAPI, for site: MangaSiteConfig) {
        let key = key(for: site)
        store[key] = value
        defaults.set("\(value.baseURL.absoluteString)|\(value.pathPrefix)", forKey: "\(prefix)\(key)")
    }

    func clear() {
        store.removeAll()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func key(for site: MangaSiteConfig) -> String {
        site.webBase.host?.lowercased() ?? site.displayName.lowercased()
    }
}

actor SiteHeuristicsCache {
    private var preferRenderedDOMHosts: Set<String> = []
    private let defaults = UserDefaults.standard
    private let key = "mg.preferRenderedDOMHosts"

    init() {
        if let list = defaults.array(forKey: key) as? [String] {
            preferRenderedDOMHosts = Set(list)
        }
    }

    func preferRenderedDOM(for site: MangaSiteConfig) -> Bool {
        let host = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        return preferRenderedDOMHosts.contains(host)
    }

    func markPreferRenderedDOM(for site: MangaSiteConfig) {
        let host = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        if preferRenderedDOMHosts.insert(host).inserted {
            defaults.set(Array(preferRenderedDOMHosts).sorted(), forKey: key)
        }
    }

    func clear() {
        preferRenderedDOMHosts.removeAll()
        defaults.removeObject(forKey: key)
    }
}

actor ComicInfoCache {
    private struct Entry {
        let value: ComicInfo
        let expiresAt: Date
    }

    private var store: [String: Entry] = [:]
    private let ttl: TimeInterval = 15 * 60

    func get(slug: String, site: MangaSiteConfig) -> ComicInfo? {
        let key = cacheKey(slug: slug, site: site)
        guard let entry = store[key] else { return nil }
        if entry.expiresAt > Date() {
            return entry.value
        }
        store.removeValue(forKey: key)
        return nil
    }

    func set(_ info: ComicInfo, slug: String, site: MangaSiteConfig) {
        let key = cacheKey(slug: slug, site: site)
        store[key] = Entry(value: info, expiresAt: Date().addingTimeInterval(ttl))
    }

    func clear() {
        store.removeAll()
    }

    private func cacheKey(slug: String, site: MangaSiteConfig) -> String {
        let host = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        return "\(host)::\(slug.lowercased())"
    }
}

actor CopyMirrorHealthCache {
    private var preferredHosts: [String: String] = [:]
    private var cooldownUntil: [String: Date] = [:]
    private let defaults = UserDefaults.standard
    private let preferredKey = "mg.copy.preferredHosts"
    private let cooldownKey = "mg.copy.cooldownUntil"

    init() {
        if let savedPreferred = defaults.dictionary(forKey: preferredKey) as? [String: String] {
            preferredHosts = savedPreferred
        }
        if let savedCooldowns = defaults.dictionary(forKey: cooldownKey) as? [String: Double] {
            let now = Date()
            cooldownUntil = savedCooldowns.reduce(into: [:]) { partial, item in
                let until = Date(timeIntervalSince1970: item.value)
                if until > now {
                    partial[item.key] = until
                }
            }
        }
    }

    func prioritize(_ candidates: [MangaSiteConfig], requestedSite: MangaSiteConfig) -> [MangaSiteConfig] {
        pruneExpired(now: Date())
        let requestedHost = requestedSite.webBase.host?.lowercased()
        return candidates.enumerated().sorted { lhs, rhs in
            rank(lhs.element, index: lhs.offset, requestedHost: requestedHost) <
            rank(rhs.element, index: rhs.offset, requestedHost: requestedHost)
        }.map(\.element)
    }

    func markSuccess(site: MangaSiteConfig) {
        let now = Date()
        pruneExpired(now: now)
        guard let host = site.webBase.host?.lowercased() else { return }
        cooldownUntil.removeValue(forKey: host)
        if let mirror = CopyMangaMirror.mirror(for: host) {
            preferredHosts[mirror.rawValue] = host
        }
        persist()
    }

    func markFailure(site: MangaSiteConfig, seconds: Int) {
        let now = Date()
        pruneExpired(now: now)
        guard let host = site.webBase.host?.lowercased() else { return }
        let until = now.addingTimeInterval(TimeInterval(max(30, seconds)))
        if let existing = cooldownUntil[host], existing > until {
            return
        }
        cooldownUntil[host] = until
        persist()
    }

    func clear() {
        preferredHosts.removeAll()
        cooldownUntil.removeAll()
        defaults.removeObject(forKey: preferredKey)
        defaults.removeObject(forKey: cooldownKey)
    }

    private func rank(_ site: MangaSiteConfig, index: Int, requestedHost: String?) -> (Int, Int, Int, Int) {
        let host = site.webBase.host?.lowercased()
        let cooling = host.flatMap { cooldownUntil[$0] }.map { $0 > Date() } == true ? 1 : 0
        let requested = host == requestedHost ? 0 : 1
        let preferred: Int = {
            guard let host,
                  let mirror = CopyMangaMirror.mirror(for: host),
                  preferredHosts[mirror.rawValue] == host else {
                return 1
            }
            return 0
        }()
        return (cooling, requested, preferred, index)
    }

    private func pruneExpired(now: Date) {
        cooldownUntil = cooldownUntil.filter { $0.value > now }
    }

    private func persist() {
        defaults.set(preferredHosts, forKey: preferredKey)
        let encodedCooldowns = cooldownUntil.mapValues { $0.timeIntervalSince1970 }
        defaults.set(encodedCooldowns, forKey: cooldownKey)
    }
}

actor TextAssetCache {
    private struct Entry {
        let text: String
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private var store: [String: Entry] = [:]

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func get(url: URL) -> String? {
        let key = url.absoluteString
        guard let entry = store[key] else { return nil }
        if entry.expiresAt > Date() {
            return entry.text
        }
        store.removeValue(forKey: key)
        return nil
    }

    func set(_ text: String, for url: URL) {
        store[url.absoluteString] = Entry(
            text: text,
            expiresAt: Date().addingTimeInterval(ttl)
        )
    }

    func clear() {
        store.removeAll()
    }
}

actor ChapterImageURLCache {
    private struct Entry {
        let urls: [URL]
        let expiresAt: Date
    }

    private let ttl: TimeInterval
    private var store: [String: Entry] = [:]

    init(ttl: TimeInterval) {
        self.ttl = ttl
    }

    func get(slug: String, chapterID: String, site: MangaSiteConfig) -> [URL]? {
        let key = cacheKey(slug: slug, chapterID: chapterID, site: site)
        guard let entry = store[key] else { return nil }
        if entry.expiresAt > Date() {
            return entry.urls
        }
        store.removeValue(forKey: key)
        return nil
    }

    func set(_ urls: [URL], slug: String, chapterID: String, site: MangaSiteConfig) {
        let key = cacheKey(slug: slug, chapterID: chapterID, site: site)
        store[key] = Entry(urls: urls, expiresAt: Date().addingTimeInterval(ttl))
    }

    func clear() {
        store.removeAll()
    }

    private func cacheKey(slug: String, chapterID: String, site: MangaSiteConfig) -> String {
        let host = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        return "\(host)::\(slug.lowercased())::\(chapterID.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
}

actor AntiBanGuard {
    private var blockedUntil: [String: Date] = [:]

    func check(site: MangaSiteConfig) async throws {
        let key = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        while let until = blockedUntil[key], until > Date() {
            let remaining = until.timeIntervalSinceNow
            if remaining > 60 {
                // If the block is huge, still throw to fail fast rather than deadlocking the user forever
                throw CopyMangaError.cooldown(Int(ceil(remaining)))
            }
            if remaining > 0 {
                try await Task.sleep(for: .milliseconds(Int(remaining * 1000)))
            }
        }
    }

    func block(site: MangaSiteConfig, seconds: Int) {
        let key = site.webBase.host?.lowercased() ?? site.displayName.lowercased()
        let until = Date().addingTimeInterval(TimeInterval(seconds))
        if let existing = blockedUntil[key], existing > until {
            return
        }
        blockedUntil[key] = until
    }

    func clear() {
        blockedUntil.removeAll()
    }
}
