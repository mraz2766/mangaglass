import Foundation

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
                  let detected = try? detectFormat(data: data) else {
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
    private let maxPenaltyMS = 10_000

    func acquire(key: String, kind: RequestKind, maxConcurrent: Int) async throws {
        let limit = max(1, maxConcurrent)
        while (states[key]?.active ?? 0) >= limit {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(25))
        }

        var state = states[key] ?? State()
        let range: ClosedRange<Int> = kind == .chapter ? 650...1050 : 80...180
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

    func release(key: String, outcome: Outcome) {
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
