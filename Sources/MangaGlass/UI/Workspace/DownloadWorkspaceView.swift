import AppKit
import SwiftUI

struct DownloadWorkspaceView: View {
    @ObservedObject var vm: MainViewModel
    @Binding var showLogs: Bool
    let openQueue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showCategories = false
    @State private var categoryQuery = ""
    @State private var showCover = false
    @State private var chapterFrames: [String: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragAdditive = false
    @State private var dragStartChapterID: String?
    @State private var dragLastChapterID: String?
    @FocusState private var linkFocused: Bool

    var body: some View {
        GeometryReader { proxy in
            let windowWidth = proxy.size.width + 97
            let coverWidth: CGFloat = windowWidth >= 1100 ? 280 : (windowWidth >= 900 ? 240 : 180)
            let coverHeight: CGFloat = windowWidth >= 1100 ? 390 : (windowWidth >= 900 ? 340 : 250)
            VStack(spacing: 12) {
                homeToolbar
                Divider()
                HStack(alignment: .top, spacing: 20) {
                    ScrollView {
                        comicInspector(height: min(coverHeight, max(180, proxy.size.height - 220)))
                    }
                    .frame(width: coverWidth)
                    chapterWorkspace
                }
                .frame(maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showCover) {
            VStack(spacing: 12) {
                HStack {
                    Text(vm.comic?.name ?? "封面预览").font(MGFont.section)
                    Spacer()
                    Button("关闭") { showCover = false }
                        .buttonStyle(MGActionButtonStyle(variant: .secondary))
                        .keyboardShortcut(.cancelAction)
                }
                coverImage.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(20)
            .frame(minWidth: 360, idealWidth: 520, maxWidth: 700, minHeight: 400, idealHeight: 620, maxHeight: 800)
        }
        .onChange(of: vm.comic?.slug) { _ in vm.collapsedVolumeIDs.removeAll() }
    }

    private var homeToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text("首页").font(.system(size: 18, weight: .semibold))
                linkInput.frame(minWidth: 240)
                toolbarActions
            }
            VStack(spacing: 8) {
                HStack {
                    Text("首页").font(.system(size: 18, weight: .semibold))
                    Spacer()
                    toolbarActions
                }
                linkInput
            }
        }
        .frame(minHeight: 44)
    }

    private var linkInput: some View {
        HStack(spacing: 8) {
            TextField("粘贴漫画链接或 path_word", text: $vm.inputURL)
                .mgTextField().focused($linkFocused)
                .onSubmit { vm.loadComic() }
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(linkFocused ? MGTheme.accent : .clear, lineWidth: 2) }
            Button { vm.loadComic() } label: {
                ZStack {
                    Text("解析").opacity(vm.isLoading ? 0 : 1)
                    if vm.isLoading { ProgressView().controlSize(.small) }
                }.frame(width: 28)
            }
            .buttonStyle(MGActionButtonStyle(variant: .primary))
            .disabled(vm.isLoading || vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(vm.isLoading ? "正在解析" : "解析")
        }
    }

    private var toolbarActions: some View {
        HStack(spacing: 8) {
            Menu {
                Section("拷贝漫画") {
                    ForEach(CopyMangaMirror.allCases) { mirror in
                        Button(mirror.displayName) { NSWorkspace.shared.open(mirror.webBaseURL) }
                    }
                }
                Button("漫画柜") { NSWorkspace.shared.open(MangaSiteConfig.manhuaGui.webBase) }
            } label: { Label("站点", systemImage: "globe") }
                .fixedSize()
            Button { showLogs = true } label: { Image(systemName: "doc.text").frame(width: 28, height: 28) }
                .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
                .help("活动日志").accessibilityLabel("活动日志")
        }
    }

    private func comicInspector(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { showCover = true } label: {
                coverImage.frame(maxWidth: .infinity).frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(vm.comic?.coverURL == nil)
            .help("查看大图").accessibilityLabel("查看漫画封面大图")
            Text(vm.comic?.name ?? "添加一部漫画")
                .font(.system(size: 16, weight: .semibold)).lineLimit(3).textSelection(.enabled)
            if let comic = vm.comic {
                Text("\(comic.site.displayName) · \(comic.volumes.count) 类 · \(vm.totalChapterCount) 话")
                    .font(MGFont.caption).foregroundStyle(.secondary)
            } else {
                Text("输入链接，解析后选择卷与章节。").font(MGFont.caption).foregroundStyle(.secondary)
            }
            Divider()
            Button { vm.chooseDestination() } label: {
                Label("下载到：\(vm.destinationFolder.lastPathComponent)", systemImage: "folder")
                    .lineLimit(1).truncationMode(.middle)
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost)).help(vm.destinationFolder.path)
            parseStatus
        }.padding(.bottom, 8)
    }

    private var coverImage: some View {
        Group {
            if let url = vm.comic?.coverURL, !CopyMangaMirror.isRetired(url.host) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    case .empty: ZStack { coverPlaceholder; ProgressView().controlSize(.small) }
                    default: coverPlaceholder
                    }
                }
            } else { coverPlaceholder }
        }
    }

    private var coverPlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed").font(.system(size: 40, weight: .light))
            Text("封面预览").font(MGFont.caption)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var parseStatus: some View {
        if vm.isLoading {
            Label(vm.parseLiveText.isEmpty ? "正在解析" : vm.parseLiveText, systemImage: "arrow.triangle.2.circlepath")
                .font(MGFont.caption).foregroundStyle(MGTheme.accent)
        } else if !vm.errorText.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("解析失败", systemImage: "exclamationmark.triangle").foregroundStyle(MGTheme.danger)
                Text(vm.errorText).foregroundStyle(.secondary).textSelection(.enabled)
                if let mirror = vm.lastMirrorSuggestion {
                    Button("切换到\(mirror.displayName)") { vm.applySuggestedMirrorAndReload() }
                        .buttonStyle(MGActionButtonStyle(variant: .secondary))
                }
                Button("复制错误") { vm.copyCurrentError() }.buttonStyle(MGActionButtonStyle(variant: .ghost))
            }.font(MGFont.caption)
        } else if vm.showParseDone {
            Label("目录已就绪", systemImage: "checkmark.circle").font(MGFont.caption).foregroundStyle(.secondary)
        }
    }

    private var chapterWorkspace: some View {
        VStack(spacing: 8) {
            chapterToolbar
            Divider()
            if vm.isLoading {
                MGEmptyState(title: "正在解析目录", systemImage: "hourglass", detail: "目录就绪后即可选择章节。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.errorText.isEmpty {
                MGEmptyState(title: "无法解析此链接", systemImage: "exclamationmark.triangle", detail: "请查看左侧错误详情或活动日志。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.hasAnyMatchingChapters {
                MGEmptyState(title: vm.comic == nil ? "卷与章节" : "没有可见章节", systemImage: "square.grid.2x2",
                             detail: vm.comic == nil ? "解析漫画链接后，章节会显示在这里。" : "调整搜索或分类；已有选择会保留。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(vm.filteredVolumeSections.filter { !$0.chapters.isEmpty }) { section in
                            Section {
                                if !vm.collapsedVolumeIDs.contains(section.id) {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 8)], spacing: 8) {
                                        ForEach(section.chapters) { chapter in chapterCell(chapter) }
                                    }.padding(.horizontal, 2)
                                }
                            } header: { sectionHeader(section) }
                        }
                    }.padding(.bottom, 4)
                }
                .coordinateSpace(name: "chapter-canvas")
                .gesture(chapterDragGesture)
                .onPreferenceChange(ChapterFrameKey.self) { chapterFrames = $0 }
                .overlay(DragRectOverlay(rect: dragRect))
            }
            Divider()
            selectionBar
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chapterToolbar: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    Text("卷与章节 \(vm.totalChapterCount)").font(MGFont.section).fixedSize()
                    MGSearchField(title: "搜索章节", text: $vm.chapterSearchQuery).frame(minWidth: 100)
                    sortPicker
                }
                HStack(spacing: 8) {
                    MGSearchField(title: "搜索章节", text: $vm.chapterSearchQuery)
                    sortPicker
                }
            }
            HStack(spacing: 6) {
                Button { showCategories.toggle() } label: {
                    Label(vm.selectedVolumeIDs.count == vm.displayVolumes.count ? "分类：全部" : "分类：\(vm.selectedVolumeIDs.count)",
                          systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
                .popover(isPresented: $showCategories, arrowEdge: .bottom) { categoryPopover }
                Spacer(minLength: 0)
                Button("全选可见") { vm.selectAllVisible() }.buttonStyle(MGActionButtonStyle(variant: .secondary))
                    .disabled(vm.visibleChapterCount == 0)
                Button("清除选择") { vm.clearChapterSelection() }.buttonStyle(MGActionButtonStyle(variant: .ghost))
                    .disabled(vm.selectedChapters.isEmpty)
            }
        }
    }

    private var sortPicker: some View {
        Picker("排序", selection: $vm.chapterSortDirection) {
            ForEach(SortDirection.allCases) { Text($0.rawValue).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 100)
    }

    private var categoryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("显示分类").font(MGFont.section)
            MGSearchField(title: "搜索分类", text: $categoryQuery)
            HStack {
                Button("全部显示") { vm.selectAllVolumes() }
                Button("全部隐藏") { vm.deselectAllVolumes() }
            }.buttonStyle(MGActionButtonStyle(variant: .secondary))
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(vm.displayVolumes.filter { categoryQuery.isEmpty || $0.displayName.localizedCaseInsensitiveContains(categoryQuery) }) { volume in
                        Toggle(isOn: Binding(get: { vm.selectedVolumeIDs.contains(volume.id) },
                                             set: { _ in vm.toggleVolume(volume.id) })) {
                            HStack {
                                Text(volume.displayName)
                                Spacer()
                                Text("\(volume.chapters.count)").foregroundStyle(.secondary)
                            }
                        }.toggleStyle(.checkbox).font(MGFont.body).padding(8)
                    }
                }
            }.frame(height: min(260, CGFloat(max(1, vm.displayVolumes.count)) * 36))
            Text("仅影响显示，已选章节会保留。").font(MGFont.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 280)
    }

    private func sectionHeader(_ section: MainViewModel.FilteredVolumeSection) -> some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(reduceMotion ? nil : MGMotion.regular) {
                    if vm.collapsedVolumeIDs.contains(section.id) { vm.collapsedVolumeIDs.remove(section.id) } else { vm.collapsedVolumeIDs.insert(section.id) }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: vm.collapsedVolumeIDs.contains(section.id) ? "chevron.right" : "chevron.down").font(.system(size: 10, weight: .semibold))
                    Text(section.volumeName).font(MGFont.section).lineLimit(1)
                }
            }.buttonStyle(.plain)
                .accessibilityLabel("\(vm.collapsedVolumeIDs.contains(section.id) ? "展开" : "折叠")\(section.volumeName)")
            Text("已选 \(vm.selectedChapterCount(in: section.id)) / \(section.chapterCount)")
                .font(MGFont.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            Spacer(minLength: 0)
            MGGroupSelectionButton(title: section.volumeName,
                                   state: vm.areAllChaptersSelected(in: section.id) ? .all :
                                    (vm.isVolumeChapterSelectionPartial(volumeID: section.id) ? .partial : .none)) {
                vm.toggleVolumeChapterSelection(volumeID: section.id)
            }
        }.padding(.horizontal, 2).frame(height: 32).background(MGTheme.background(for: colorScheme))
    }

    private func chapterCell(_ chapter: ComicChapter) -> some View {
        let selected = vm.selectedChapterIDs.contains(chapter.id)
        return MGChapterSelectionCell(title: chapter.displayName, selected: selected) {
            vm.selectChapter(chapter, modifiers: NSEvent.modifierFlags)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ChapterFrameKey.self, value: [chapter.id: proxy.frame(in: .named("chapter-canvas"))])
            }
        }
        .help(chapter.displayName).accessibilityValue(selected ? "已选择" : "未选择")
    }

    private var selectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack {
                selectionSummary.fixedSize()
                Spacer(minLength: 8)
                enqueueButton
            }
            VStack(alignment: .leading, spacing: 4) {
                selectionSummary
                HStack { Spacer(); enqueueButton }
            }
        }.frame(minHeight: 44)
    }

    private var selectionSummary: some View {
        Text("已选 \(vm.selectedChapters.count) 话" + (vm.hiddenSelectedChapterCount > 0 ? " · 隐藏 \(vm.hiddenSelectedChapterCount) 话" : ""))
            .font(MGFont.bodyStrong).foregroundStyle(vm.selectedChapters.isEmpty ? .secondary : MGTheme.accent)
    }

    private var enqueueButton: some View {
        Button("加入队列 \(vm.selectedChapters.count)") { vm.startDownload() }
            .buttonStyle(MGActionButtonStyle(variant: .primary))
            .disabled(vm.selectedChapters.isEmpty || vm.isLoading || !vm.errorText.isEmpty)
            .help(vm.selectedChapters.isEmpty ? "请选择章节" : "加入全部已选章节，包含隐藏的选择")
    }

    private var dragRect: CGRect? {
        guard let dragStart, let dragCurrent else { return nil }
        return CGRect(
            x: min(dragStart.x, dragCurrent.x),
            y: min(dragStart.y, dragCurrent.y),
            width: abs(dragStart.x - dragCurrent.x),
            height: abs(dragStart.y - dragCurrent.y)
        )
    }

    private var chapterDragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    dragAdditive = NSEvent.modifierFlags.contains(.command)
                    dragStartChapterID = chapterID(at: value.startLocation)
                    dragLastChapterID = dragStartChapterID
                }
                dragCurrent = value.location
                updateDragSelection()
            }
            .onEnded { _ in
                dragStart = nil
                dragCurrent = nil
                dragAdditive = false
                dragStartChapterID = nil
                dragLastChapterID = nil
            }
    }

    private func updateDragSelection() {
        guard let rect = dragRect else { return }
        let hitIDs = Set(chapterFrames.compactMap { id, frame in frame.intersects(rect) ? id : nil })
        if hitIDs.isEmpty, let start = dragStartChapterID {
            let target = chapterID(at: dragCurrent ?? .zero) ?? dragLastChapterID ?? start
            dragLastChapterID = target
            let ids = chapterRange(from: start, to: target)
            vm.applyDragSelection(ids, additive: dragAdditive)
        } else if !hitIDs.isEmpty {
            vm.applyDragSelection(hitIDs, additive: dragAdditive)
        }
    }

    private func chapterID(at point: CGPoint) -> String? {
        chapterFrames.first { $0.value.contains(point) }?.key
    }

    private func chapterRange(from startID: String, to endID: String) -> Set<String> {
        let ids = vm.visibleChapters.map(\.id)
        guard let start = ids.firstIndex(of: startID), let end = ids.firstIndex(of: endID) else { return [startID] }
        return Set(ids[min(start, end)...max(start, end)])
    }


}
