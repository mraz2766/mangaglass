import Foundation

struct ExistingOutputSummary: Equatable, Sendable {
    let chapterCount: Int
    let fileCount: Int

    var hasExistingFiles: Bool { fileCount > 0 }
}

enum DownloadOutputLayout {
    static func comicFolder(comic: ComicInfo, destination: URL) -> URL {
        if matchesComicFolderName(destination, comicName: comic.name) {
            return destination
        }
        return destination.appendingPathComponent(sanitize(comic.name), isDirectory: true)
    }

    static func chapterFolder(
        comic: ComicInfo,
        chapter: ComicChapter,
        destination: URL,
        usesGroupFolder: Bool
    ) -> URL {
        let comicFolder = comicFolder(comic: comic, destination: destination)
        let parent = usesGroupFolder
            ? comicFolder.appendingPathComponent(sanitize(canonicalGroupName(chapter.volumeName)), isDirectory: true)
            : comicFolder
        return parent.appendingPathComponent(sanitize(chapter.displayName), isDirectory: true)
    }

    /// Chapters whose final folder already exists in either layout (with or without a group folder).
    /// Read-only; staging folders (`.下载中-…`) don't count.
    static func downloadedChapterIDs(comic: ComicInfo, destination: URL, manager: FileManager = .default) -> Set<String> {
        var ids: Set<String> = []
        for volume in comic.volumes {
            for chapter in volume.chapters {
                for grouped in [true, false] {
                    let folder = chapterFolder(comic: comic, chapter: chapter, destination: destination, usesGroupFolder: grouped)
                    var isDirectory: ObjCBool = false
                    if manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue {
                        ids.insert(chapter.id)
                        break
                    }
                }
            }
        }
        return ids
    }

    static func stagingChapterFolder(for chapterFolder: URL) -> URL {
        chapterFolder.deletingLastPathComponent().appendingPathComponent(
            ".下载中-\(chapterFolder.lastPathComponent)",
            isDirectory: true
        )
    }

    static func recoverableChapterFolder(for chapterFolder: URL, manager: FileManager = .default) -> URL {
        let staging = stagingChapterFolder(for: chapterFolder)
        return manager.fileExists(atPath: staging.path) ? staging : chapterFolder
    }

    static func prepareStagingFolder(
        for chapterFolder: URL,
        overwrite: Bool,
        manager: FileManager = .default
    ) throws -> URL {
        let staging = stagingChapterFolder(for: chapterFolder)
        if overwrite {
            if manager.fileExists(atPath: staging.path) { try manager.removeItem(at: staging) }
        } else if !manager.fileExists(atPath: staging.path), manager.fileExists(atPath: chapterFolder.path) {
            try manager.copyItem(at: chapterFolder, to: staging)
        }
        if !manager.fileExists(atPath: staging.path) {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
        }
        return staging
    }

    static func publishStagingFolder(
        _ staging: URL,
        as chapterFolder: URL,
        manager: FileManager = .default
    ) throws {
        guard manager.fileExists(atPath: staging.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let manifest = DownloadIntegrity.loadManifest(from: staging)
        guard let manifest,
              manifest.isComplete,
              manifest.pages.count == manifest.expectedPages else {
            throw DownloadIntegrityError.incompleteChapter(
                expected: manifest?.expectedPages ?? 1,
                verified: manifest?.pages.count ?? 0
            )
        }
        if manager.fileExists(atPath: chapterFolder.path) {
            _ = try manager.replaceItemAt(
                chapterFolder,
                withItemAt: staging,
                backupItemName: nil,
                options: []
            )
        } else {
            try manager.moveItem(at: staging, to: chapterFolder)
        }
    }

    static func inspectExistingFiles(
        comic: ComicInfo,
        chapters: [ComicChapter],
        destination: URL,
        usesGroupFolder: Bool
    ) -> ExistingOutputSummary {
        let manager = FileManager.default
        var chaptersWithFiles = 0
        var files = 0

        for chapter in chapters {
            let folder = chapterFolder(
                comic: comic,
                chapter: chapter,
                destination: destination,
                usesGroupFolder: usesGroupFolder
            )
            let recoverableFolder = recoverableChapterFolder(for: folder, manager: manager)
            guard let enumerator = manager.enumerator(
                at: recoverableFolder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            var chapterFiles = 0
            for case let fileURL as URL in enumerator {
                if (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                    chapterFiles += 1
                }
            }
            if chapterFiles > 0 {
                chaptersWithFiles += 1
                files += chapterFiles
            }
        }

        return ExistingOutputSummary(chapterCount: chaptersWithFiles, fileCount: files)
    }

    static func removeChapterFolder(at folder: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: folder.path) {
            try manager.removeItem(at: folder)
        }
    }

    static func sanitize(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return value
            .components(separatedBy: forbidden)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func matchesComicFolderName(_ folderURL: URL, comicName: String) -> Bool {
        let folderName = folderURL.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let comicFolderName = sanitize(comicName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderName.isEmpty, !comicFolderName.isEmpty else { return false }
        return sanitize(folderName).lowercased() == comicFolderName.lowercased()
    }
}
