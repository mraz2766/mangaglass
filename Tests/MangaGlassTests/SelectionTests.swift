import AppKit
import Combine
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
        XCTAssertEqual(vm.enqueueSelectedChapters(), .added(3))
        XCTAssertEqual(Set(vm.downloader.taskItems.map(\.chapter.id)), ["0", "1", "2"])
        XCTAssertTrue(vm.selectedChapterIDs.isEmpty)
        vm.selectedChapterIDs = ["0", "1", "2"]
        XCTAssertEqual(vm.enqueueSelectedChapters(), .alreadyQueued)
        XCTAssertEqual(vm.downloader.taskItems.count, 3)
        XCTAssertEqual(vm.selectedChapters.count, 3)
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
        // Folding only hides tiles: the selection still counts as visible.
        XCTAssertEqual(vm.hiddenSelectedChapterCount, 0)
        vm.collapsedVolumeIDs = ["g0", "g1"]
        XCTAssertTrue(vm.hasAnyMatchingChapters, "全部折叠后仍须显示可展开的分组标题")
        XCTAssertEqual(vm.visibleChapterCount, 34, "折叠后「下载全部可见」仍覆盖当前分类")
        XCTAssertTrue(vm.expandedChapters.isEmpty)
        vm.collapsedVolumeIDs = ["g0"]
        vm.chapterSortDirection = .descending
        vm.deselectAllVolumes()
        XCTAssertEqual(vm.selectedChapterIDs, ["0", "1"])
        vm.selectAllVolumes()
        vm.selectAllVisible()
        XCTAssertEqual(vm.selectedChapters.count, 34)
        XCTAssertTrue(vm.selectedChapterIDs.contains("0"))
    }

    func testChapterSearchSupportsMultipleTermsAndWidthFolding() {
        let vm = model()
        vm.chapterSearchQuery = "０６ 章节标题"
        XCTAssertEqual(vm.visibleChapters.map(\.id), ["5"])
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

    func testNewComicFoldsGroupsExceptALoneOne() async {
        let vm = model()
        XCTAssertEqual(vm.collapsedVolumeIDs, ["g0", "g1"])
        let single = Self.fixture(chapterCount: 10, groups: 1)
        let lone = ComicInfo(slug: "lone", name: "单组", coverURL: nil, volumes: single.volumes,
                             site: single.site, apiPathPrefix: "", apiBaseURL: single.apiBaseURL)
        vm.applyFetchedComic(lone, final: true, sourceText: "测试")
        XCTAssertTrue(vm.collapsedVolumeIDs.isEmpty)
    }

    func testClickShiftCommandAndDrag() async {
        let vm = model()
        vm.collapsedVolumeIDs = []
        let chapters = vm.expandedChapters
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

    func testRepeatedDragSelectionDoesNotRepublishIdenticalState() async {
        let vm = model()
        var publishedSelections = 0
        let observation = vm.$selectedChapterIDs
            .dropFirst()
            .sink { _ in publishedSelections += 1 }
        vm.applyDragSelection(["1", "3"], additive: false)
        vm.applyDragSelection(["1", "3"], additive: false)
        vm.applyDragSelection(["1"], additive: true)
        XCTAssertEqual(publishedSelections, 1)
        withExtendedLifetime(observation) {}
    }

    func testDownloadProgressDoesNotRefreshWholeHomeViewModel() async {
        let vm = model()
        var wholeViewModelRefreshes = 0
        let observation = vm.objectWillChange.sink { wholeViewModelRefreshes += 1 }
        vm.downloader.progress = 0.5
        vm.downloader.speedText = "8.0 页/秒"
        XCTAssertEqual(wholeViewModelRefreshes, 0)
        withExtendedLifetime(observation) {}
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
        XCTAssertEqual(vm.collapsedVolumeIDs, ["g0", "g1"], "新漫画默认折叠全部分组")
    }

    func testClearHomeResetsOnlyCurrentWorkspace() async {
        let vm = model()
        vm.inputURL = "https://www.mangacopy.com/comic/test-fixture"
        vm.authCookie = "test-only-cookie"
        vm.recentRecords = [RecentComicRecord(title: "保留历史", input: vm.inputURL, siteName: "主站")]
        vm.selectAllVisible()
        vm.enqueueSelectedChapters()
        let destination = vm.destinationFolder
        vm.chapterSearchQuery = "03"
        vm.collapsedVolumeIDs = ["g0"]
        vm.chapterSortDirection = .descending
        vm.errorText = "测试错误"
        vm.lastMirrorSuggestion = .copy4000
        vm.lastFailedInput = "old"
        vm.clearHome()
        XCTAssertFalse(vm.hasHomeContent)
        XCTAssertNil(vm.comic)
        XCTAssertTrue(vm.selectedChapterIDs.isEmpty)
        XCTAssertTrue(vm.selectedVolumeIDs.isEmpty)
        XCTAssertTrue(vm.collapsedVolumeIDs.isEmpty)
        XCTAssertEqual(vm.chapterSortDirection, .ascending)
        XCTAssertTrue(vm.parseDoneText.isEmpty)
        XCTAssertTrue(vm.parseLiveText.isEmpty)
        XCTAssertFalse(vm.showParseDone)
        XCTAssertNil(vm.lastMirrorSuggestion)
        XCTAssertTrue(vm.lastFailedInput.isEmpty)
        XCTAssertEqual(vm.downloader.taskItems.count, 34)
        XCTAssertEqual(vm.recentRecords.count, 1)
        XCTAssertEqual(vm.authCookie, "test-only-cookie")
        XCTAssertEqual(vm.destinationFolder, destination)
    }

    func testClearCancelsPendingParseBeforeItStarts() async {
        let vm = model()
        vm.inputURL = "test-fixture"
        vm.loadComic(fetch: { _, _, _ in
            XCTFail("清除后不应启动旧请求")
            return Self.fixture()
        })
        vm.clearHome()
        await Task.yield()
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.hasHomeContent)
        XCTAssertNil(vm.comic)
    }

    func testLateCanceledResultCannotOverwriteNewParse() async {
        let vm = MainViewModel(persistsState: false)
        var oldCompletion: CheckedContinuation<ComicInfo, Never>?
        vm.inputURL = "test-fixture"
        vm.loadComic(fetch: { _, _, _ in
            await withCheckedContinuation { oldCompletion = $0 }
        })
        // Wait until the simulated request is actually in flight.
        for _ in 0..<100 where oldCompletion == nil { await Task.yield() }
        XCTAssertNotNil(oldCompletion)
        vm.clearHome()
        vm.inputURL = "new-fixture"
        let original = Self.fixture()
        let newer = ComicInfo(slug: "new-fixture", name: "新结果", coverURL: nil, volumes: original.volumes,
                              site: original.site, apiPathPrefix: "", apiBaseURL: original.apiBaseURL)
        vm.loadComic(fetch: { _, _, _ in newer })
        for _ in 0..<100 where vm.isLoading { await Task.yield() }
        XCTAssertEqual(vm.comic?.slug, "new-fixture")
        oldCompletion?.resume(returning: original)
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(vm.comic?.slug, "new-fixture")
        XCTAssertEqual(vm.inputURL, "new-fixture")
        XCTAssertTrue(vm.errorText.isEmpty)
        XCTAssertFalse(vm.isLoading)
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
