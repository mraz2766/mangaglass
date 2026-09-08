import AppKit
import XCTest
@testable import MangaGlass

@MainActor
final class SelectionTests: XCTestCase {
    static func fixture(chapterCount: Int = 34, groups: Int = 2) -> ComicInfo {
        let volumes = (0..<groups).map { group in
            let chapters = (0..<chapterCount).filter { $0 % groups == group }.map { index in
                ComicChapter(id: "\(index)", uuid: "\(index)", displayName: index == 5 ? "第 06 话 — 一个很长的章节标题用于验证截断和完整提示" : String(format: "第 %02d 话", index + 1),
                             order: Double(index), volumeID: "g\(group)", volumeName: "第 \(group + 1) 卷")
            }
            return ComicVolume(id: "g\(group)", displayName: "第 \(group + 1) 卷", pathWord: "g\(group)", chapters: chapters)
        }
        return ComicInfo(slug: "test-fixture", name: "测试漫画：跨分类选择与章节网格", coverURL: nil, volumes: volumes,
                         site: .mangaCopy, apiPathPrefix: "", apiBaseURL: MangaSiteConfig.mangaCopy.apiBaseURLs[0])
    }

    func model() -> MainViewModel {
        let vm = MainViewModel(persistsState: false)
        vm.applyFetchedComic(Self.fixture(), final: true, sourceText: "测试")
        return vm
    }

    func testHiddenSelectionEnqueuesAllAndDeduplicates() async {
        let vm = model()
        vm.selectedChapterIDs = ["0", "1", "2"]
        vm.toggleVolume("g0")
        XCTAssertEqual(vm.hiddenSelectedChapterCount, 2)
        vm.chapterSearchQuery = "不存在"
        XCTAssertEqual(vm.hiddenSelectedChapterCount, 3)
        vm.enqueueSelectedChapters()
        XCTAssertEqual(Set(vm.downloader.taskItems.map(\.chapter.id)), ["0", "1", "2"])
        vm.enqueueSelectedChapters()
        XCTAssertEqual(vm.downloader.taskItems.count, 3)
        vm.clearChapterSelection()
        XCTAssertEqual(vm.selectedChapters.count, 0)
        XCTAssertEqual(vm.downloader.taskItems.count, 3)
    }

    func testQueueStartDoesNotAddHomeSelection() async {
        let vm = model()
        vm.selectAllVisible()
        vm.startQueuedDownloads()
        XCTAssertTrue(vm.downloader.taskItems.isEmpty)
        XCTAssertEqual(vm.selectedChapters.count, 34)
    }

    func testFilteringCollapseAndSortPreserveSelection() async {
        let vm = model()
        vm.selectedChapterIDs = ["0", "1"]
        vm.collapsedVolumeIDs = ["g0"]
        XCTAssertEqual(vm.hiddenSelectedChapterCount, 1)
        vm.collapsedVolumeIDs = ["g0", "g1"]
        XCTAssertTrue(vm.hasAnyMatchingChapters, "全部折叠后仍须显示可展开的分组标题")
        XCTAssertEqual(vm.visibleChapterCount, 0)
        vm.collapsedVolumeIDs = ["g0"]
        vm.chapterSortDirection = .descending
        vm.deselectAllVolumes()
        XCTAssertEqual(vm.selectedChapterIDs, ["0", "1"])
        vm.selectAllVolumes()
        vm.selectAllVisible()
        XCTAssertEqual(vm.selectedChapters.count, 18)
        XCTAssertTrue(vm.selectedChapterIDs.contains("0"))
    }

    func testGroupSelectionHonorsSearchAndPartialState() async {
        let vm = model()
        vm.selectedChapterIDs = ["0"]
        XCTAssertFalse(vm.areAllChaptersSelected(in: "g0"))
        XCTAssertEqual(vm.selectedChapterCount(in: "g0"), 1)
        vm.chapterSearchQuery = "03"
        vm.toggleVolumeChapterSelection(volumeID: "g0")
        XCTAssertEqual(vm.selectedChapterIDs, ["0", "2"])
        vm.toggleVolumeChapterSelection(volumeID: "g0")
        XCTAssertEqual(vm.selectedChapterIDs, ["0"])
    }

    func testClickShiftCommandAndDrag() async {
        let vm = model()
        let chapters = vm.visibleChapters
        vm.selectChapter(chapters[0], modifiers: [])
        vm.selectChapter(chapters[2], modifiers: .shift)
        XCTAssertEqual(vm.selectedChapterIDs, Set(chapters[0...2].map(\.id)))
        vm.selectChapter(chapters[5], modifiers: .command)
        XCTAssertEqual(vm.selectedChapters.count, 4)
        vm.applyDragSelection(["1", "3"], additive: true)
        XCTAssertEqual(vm.selectedChapters.count, 6)
        vm.applyDragSelection(["7", "9"], additive: false)
        XCTAssertEqual(vm.selectedChapterIDs, ["7", "9"])
    }

    func testSameComicRefreshPreservesSelectionNewComicClears() async {
        let vm = model()
        vm.selectedChapterIDs = ["0"]
        vm.collapsedVolumeIDs = ["g1"]
        vm.applyFetchedComic(Self.fixture(), final: true, sourceText: "测试")
        XCTAssertEqual(vm.selectedChapterIDs, ["0"])
        XCTAssertEqual(vm.collapsedVolumeIDs, ["g1"])
        let previous = Self.fixture()
        let next = ComicInfo(slug: "another", name: "另一部漫画", coverURL: nil, volumes: previous.volumes,
                             site: previous.site, apiPathPrefix: "", apiBaseURL: previous.apiBaseURL)
        vm.applyFetchedComic(next, final: true, sourceText: "测试")
        XCTAssertTrue(vm.selectedChapterIDs.isEmpty)
        XCTAssertTrue(vm.collapsedVolumeIDs.isEmpty)
    }

    func testRetiredComicCannotEnqueue() async {
        let vm = model()
        let original = Self.fixture()
        vm.comic = ComicInfo(slug: original.slug, name: original.name, coverURL: nil, volumes: original.volumes,
                            site: MangaSiteConfig(displayName: "旧站", webBase: URL(string: "https://www.2025copy.com")!, apiBaseURLs: []),
                            apiPathPrefix: "", apiBaseURL: original.apiBaseURL)
        vm.selectAllVisible()
        vm.enqueueSelectedChapters()
        XCTAssertTrue(vm.downloader.taskItems.isEmpty)
        XCTAssertEqual(vm.errorText, CopyMangaMirror.retiredMessage)
        vm.errorText = ""
        vm.startDownload()
        XCTAssertTrue(vm.downloader.taskItems.isEmpty)
        XCTAssertEqual(vm.errorText, CopyMangaMirror.retiredMessage)
    }
}
