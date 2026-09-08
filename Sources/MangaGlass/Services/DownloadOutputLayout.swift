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
            guard let enumerator = manager.enumerator(
                at: folder,
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
