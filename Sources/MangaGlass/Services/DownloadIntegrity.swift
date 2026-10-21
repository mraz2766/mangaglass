import Foundation
import ImageIO

enum DownloadImageFormat: String, Codable, CaseIterable, Sendable {
    case jpeg = "jpg"
    case png
    case gif
    case webp
    case avif

    var fileExtension: String { rawValue }
}

struct VerifiedDownloadPage: Codable, Equatable, Sendable {
    let index: Int
    let fileName: String
    let byteCount: Int
    let format: DownloadImageFormat
    /// True when high resolution was requested but only the standard image was available.
    var standardQuality: Bool? = nil
}

struct ChapterDownloadManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let fileName = ".mangaglass-manifest.json"

    let version: Int
    let chapterID: String
    let expectedPages: Int
    let imageURLs: [URL]?
    let pages: [VerifiedDownloadPage]
    let isComplete: Bool
    let updatedAt: Date

    init(
        chapterID: String,
        expectedPages: Int,
        imageURLs: [URL]? = nil,
        pages: [VerifiedDownloadPage],
        isComplete: Bool,
        updatedAt: Date = Date()
    ) {
        self.version = Self.currentVersion
        self.chapterID = chapterID
        self.expectedPages = expectedPages
        self.imageURLs = imageURLs
        self.pages = pages.sorted { $0.index < $1.index }
        self.isComplete = isComplete
        self.updatedAt = updatedAt
    }
}

enum DownloadIntegrityError: LocalizedError, Equatable {
    case emptyPayload
    case nonImagePayload(String)
    case unsupportedImage
    case incompleteChapter(expected: Int, verified: Int)
    case truncatedImage
    case placeholderImage(width: Int, height: Int)

    var errorDescription: String? {
        switch self {
        case .emptyPayload:
            return "图片响应为空，未写入文件。"
        case .nonImagePayload(let detail):
            return "图片地址返回了非图片内容（\(detail)），可能是风控页面。"
        case .unsupportedImage:
            return "响应内容不是可识别的 JPEG、PNG、GIF、WebP 或 AVIF 图片。"
        case .incompleteChapter(let expected, let verified):
            return "章节完整性检查失败：预期 \(expected) 页，已验证 \(verified) 页。"
        case .truncatedImage:
            return "图片数据不完整（下载中断或被截断），已丢弃并重试。"
        case .placeholderImage(let width, let height):
            return "收到 \(width)×\(height) 的占位小图，不是正常漫画页。"
        }
    }
}

enum DownloadIntegrity {
    static let minimumImageBytes = 32

    static func detectFormat(data: Data, mimeType: String? = nil) throws -> DownloadImageFormat {
        guard data.count >= minimumImageBytes else {
            throw DownloadIntegrityError.emptyPayload
        }

        let normalizedMIME = mimeType?.lowercased() ?? ""
        if normalizedMIME.contains("text/html") || normalizedMIME.contains("application/json") || normalizedMIME.contains("text/plain") {
            throw DownloadIntegrityError.nonImagePayload(normalizedMIME.isEmpty ? "非图片响应" : normalizedMIME)
        }

        let bytes = [UInt8](data.prefix(16))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if bytes.starts(with: Array("GIF87a".utf8)) || bytes.starts(with: Array("GIF89a".utf8)) { return .gif }
        if bytes.starts(with: Array("RIFF".utf8)), bytes.count >= 12,
           Array(bytes[8..<12]) == Array("WEBP".utf8) { return .webp }
        if bytes.count >= 12, Array(bytes[4..<8]) == Array("ftyp".utf8) {
            let brand = String(bytes: bytes[8..<12], encoding: .ascii)?.lowercased() ?? ""
            if ["avif", "avis", "mif1", "miaf"].contains(brand) { return .avif }
        }
        throw DownloadIntegrityError.unsupportedImage
    }

    /// Smallest edge accepted for a manga page; CDN placeholders are typically 1×1 to a few dozen px.
    static let minimumPageDimension = 64

    /// Detects the format, then checks the payload is a whole, decodable page:
    /// declared length matches, the format's end marker is present, and ImageIO reads a real size.
    static func verify(data: Data, mimeType: String? = nil, expectedLength: Int64? = nil) throws -> DownloadImageFormat {
        let format = try detectFormat(data: data, mimeType: mimeType)
        if let expectedLength, expectedLength > 0, Int64(data.count) < expectedLength {
            throw DownloadIntegrityError.truncatedImage
        }
        guard hasEndMarker(data: data, format: format) else {
            throw DownloadIntegrityError.truncatedImage
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw DownloadIntegrityError.unsupportedImage
        }
        guard width >= minimumPageDimension, height >= minimumPageDimension else {
            throw DownloadIntegrityError.placeholderImage(width: width, height: height)
        }
        return format
    }

    /// Cheap structural completeness check per format (a cut-off download loses its tail).
    static func hasEndMarker(data: Data, format: DownloadImageFormat) -> Bool {
        // Search a tail window rather than the last bytes: some CDNs/encoders append padding or metadata.
        let tail = [UInt8](data.suffix(1024))
        switch format {
        case .jpeg:
            return zip(tail, tail.dropFirst()).contains { $0 == 0xFF && $1 == 0xD9 }
        case .png:
            return data.suffix(1024).range(of: Data("IEND".utf8)) != nil
        case .gif:
            return tail.suffix(64).contains(0x3B)
        case .webp:
            guard data.count >= 12 else { return false }
            let size = data.subdata(in: 4..<8).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            return Int(UInt32(littleEndian: size)) + 8 <= data.count
        case .avif:
            return true
        }
    }

    static func existingPage(
        in folder: URL,
        baseName: String,
        index: Int,
        manager: FileManager = .default
    ) -> VerifiedDownloadPage? {
        for format in DownloadImageFormat.allCases {
            let url = folder.appendingPathComponent("\(baseName).\(format.fileExtension)")
            guard manager.fileExists(atPath: url.path) else { continue }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  let detected = try? verify(data: data) else {
                try? manager.removeItem(at: url)
                continue
            }
            return VerifiedDownloadPage(index: index, fileName: url.lastPathComponent, byteCount: data.count, format: detected)
        }
        return nil
    }

    static func writeManifest(
        chapterID: String,
        expectedPages: Int,
        imageURLs: [URL]? = nil,
        pages: [VerifiedDownloadPage],
        complete: Bool,
        to folder: URL
    ) throws {
        let unique = Dictionary(pages.map { ($0.index, $0) }, uniquingKeysWith: { _, latest in latest })
        let ordered = unique.values.sorted { $0.index < $1.index }
        let manifest = ChapterDownloadManifest(
            chapterID: chapterID,
            expectedPages: expectedPages,
            imageURLs: imageURLs,
            pages: ordered,
            isComplete: complete && ordered.count == expectedPages
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        try encoder.encode(manifest).write(
            to: folder.appendingPathComponent(ChapterDownloadManifest.fileName),
            options: [.atomic]
        )
    }

    static func loadManifest(from folder: URL) -> ChapterDownloadManifest? {
        let url = folder.appendingPathComponent(ChapterDownloadManifest.fileName)
        guard let data = try? Data(contentsOf: url),
              let manifest = try? JSONDecoder().decode(ChapterDownloadManifest.self, from: data),
              manifest.version == ChapterDownloadManifest.currentVersion else { return nil }
        return manifest
    }
}

actor HostRequestBudget {
    enum RequestKind: Sendable {
        case chapter
        case image
    }

    enum Outcome: Sendable {
        case success
        case failure
        case throttled
    }

    private struct State {
        var active = 0
        var nextAllowedAt = Date.distantPast
        var penaltyMS = 0
    }

    private var states: [String: State] = [:]
    /// Tasks waiting for a free slot; woken one at a time by `release` instead of polling.
    private var waiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private let maxPenaltyMS = 10_000

    func acquire(key: String, kind: RequestKind, maxConcurrent: Int, spacingMS: ClosedRange<Int>? = nil) async throws {
        let limit = max(1, maxConcurrent)
        while (states[key]?.active ?? 0) >= limit {
            await withCheckedContinuation { continuation in
                waiters[key, default: []].append(continuation)
            }
            if Task.isCancelled {
                // Pass the wake-up on so a cancelled waiter never swallows a free slot.
                wakeNext(key: key)
                throw CancellationError()
            }
        }

        var state = states[key] ?? State()
        let range: ClosedRange<Int> = spacingMS ?? (kind == .chapter ? 650...1050 : 80...180)
        let spacingMS = Int.random(in: range) + state.penaltyMS
        let now = Date()
        let scheduled = max(now, state.nextAllowedAt)
        state.nextAllowedAt = scheduled.addingTimeInterval(Double(spacingMS) / 1000)
        state.active += 1
        states[key] = state

        do {
            let waitMS = Int(max(0, scheduled.timeIntervalSince(now) * 1000))
            if waitMS > 0 { try await Task.sleep(for: .milliseconds(waitMS)) }
            try Task.checkCancellation()
        } catch {
            release(key: key, outcome: .failure)
            throw error
        }
    }

    private func wakeNext(key: String) {
        guard var queue = waiters[key], !queue.isEmpty else { return }
        let next = queue.removeFirst()
        waiters[key] = queue
        next.resume()
    }

    /// Wakes every waiter (used when a run is cancelled so nobody sleeps forever).
    func wakeAll() {
        let all = waiters.values.flatMap { $0 }
        waiters.removeAll()
        all.forEach { $0.resume() }
    }

    func release(key: String, outcome: Outcome) {
        defer { wakeNext(key: key) }
        var state = states[key] ?? State()
        state.active = max(0, state.active - 1)
        switch outcome {
        case .success:
            state.penaltyMS = max(0, state.penaltyMS - 120)
        case .failure:
            break
        case .throttled:
            state.penaltyMS = min(maxPenaltyMS, state.penaltyMS + 1_400)
        }
        states[key] = state
    }

    func resetPenalty(key: String) {
        var state = states[key] ?? State()
        state.penaltyMS = 0
        states[key] = state
    }

    func activeCount(key: String) -> Int {
        states[key]?.active ?? 0
    }
}
