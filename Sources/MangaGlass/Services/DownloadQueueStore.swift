import Foundation

struct DownloadQueueSnapshot: Codable, Sendable {
    static let currentVersion = 1

    struct Item: Codable, Sendable {
        let id: UUID
        let comicIndex: Int
        let chapter: ComicChapter
        let state: DownloadTaskItem.State
        let destination: URL
        let cookie: String?
        let startedAt: Date?
        let finishedAt: Date?
        let existingFilePolicy: ExistingFilePolicy?
        let usesGroupFolder: Bool?
    }

    let version: Int
    let comics: [ComicInfo]
    let items: [Item]

    init(taskItems: [DownloadTaskItem]) {
        var comics: [ComicInfo] = []
        var comicIndexes: [String: Int] = [:]
        var items: [Item] = []
        items.reserveCapacity(taskItems.count)

        for task in taskItems {
            let comicKey = [
                task.comic.site.webBase.host?.lowercased() ?? "",
                task.comic.slug.lowercased(),
                task.comic.apiPathPrefix,
                task.comic.apiBaseURL.absoluteString
            ].joined(separator: "::")
            let comicIndex: Int
            if let existing = comicIndexes[comicKey] {
                comicIndex = existing
            } else {
                comicIndex = comics.count
                comicIndexes[comicKey] = comicIndex
                comics.append(task.comic)
            }
            items.append(Item(
                id: task.id,
                comicIndex: comicIndex,
                chapter: task.chapter,
                state: task.state,
                destination: task.destination,
                cookie: task.cookie,
                startedAt: task.startedAt,
                finishedAt: task.finishedAt,
                existingFilePolicy: task.existingFilePolicy,
                usesGroupFolder: task.usesGroupFolder
            ))
        }

        self.version = Self.currentVersion
        self.comics = comics
        self.items = items
    }

    func restoredTaskItems() -> [DownloadTaskItem]? {
        guard version == Self.currentVersion else { return nil }
        var restored: [DownloadTaskItem] = []
        restored.reserveCapacity(items.count)
        for item in items {
            guard comics.indices.contains(item.comicIndex) else { return nil }
            restored.append(DownloadTaskItem(
                id: item.id,
                comic: comics[item.comicIndex],
                chapter: item.chapter,
                state: item.state,
                destination: item.destination,
                cookie: item.cookie,
                startedAt: item.startedAt,
                finishedAt: item.finishedAt,
                existingFilePolicy: item.existingFilePolicy,
                usesGroupFolder: item.usesGroupFolder
            ))
        }
        return restored
    }
}

final class DownloadQueueStore: @unchecked Sendable {
    private let fileURL: URL
    private let backupURL: URL
    private let ioQueue = DispatchQueue(label: "com.mangaglass.download-queue-store", qos: .utility)

    init(fileURL: URL? = nil) {
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
        } else {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            resolvedURL = root
                .appendingPathComponent("MangaGlass", isDirectory: true)
                .appendingPathComponent("download-queue-v1.json")
        }
        self.fileURL = resolvedURL
        self.backupURL = resolvedURL.appendingPathExtension("backup")
    }

    func save(_ items: [DownloadTaskItem]) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            _ = self.write(DownloadQueueSnapshot(taskItems: items))
        }
    }

    @discardableResult
    func saveSynchronously(_ items: [DownloadTaskItem]) -> Bool {
        return ioQueue.sync {
            return write(DownloadQueueSnapshot(taskItems: items))
        }
    }

    /// `nil` means no durable snapshot exists. An empty array is a valid saved queue.
    func load() -> [DownloadTaskItem]? {
        ioQueue.sync {
            if let items = decodeItems(at: fileURL) {
                return items
            }
            return decodeItems(at: backupURL)
        }
    }

    private func write(_ snapshot: DownloadQueueSnapshot) -> Bool {
        do {
            let manager = FileManager.default
            try manager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if decodeItems(at: fileURL) != nil {
                try? manager.removeItem(at: backupURL)
                try? manager.copyItem(at: fileURL, to: backupURL)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    private func decodeItems(at url: URL) -> [DownloadTaskItem]? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(DownloadQueueSnapshot.self, from: data) else {
            return nil
        }
        return snapshot.restoredTaskItems()
    }

}
