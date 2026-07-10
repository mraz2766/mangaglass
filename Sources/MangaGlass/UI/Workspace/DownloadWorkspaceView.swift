import AppKit
import SwiftUI

struct DownloadWorkspaceView: View {
    private enum DownloadConfirmation: Identifiable {
        case addAllVisible(Int)

        var id: String { "add-all-visible" }
    }

    @ObservedObject var vm: MainViewModel
    @Binding var showLogs: Bool
    let openQueue: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showVolumeFilters = true
    @State private var chapterFrames: [String: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragAdditive = false
    @State private var dragStartChapterID: String?
    @State private var dragLastChapterID: String?
    @State private var confirmation: DownloadConfirmation?

    private var selectedCount: Int { vm.selectedChapterIDs.count }
    private var selectedVolumeCount: Int { vm.selectedVolumeIDs.count }

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 760
            VStack(alignment: .leading, spacing: MGSpacing.sm) {
                pageHeader
                linkWorkspace
                if compact {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MGSpacing.sm) {
                            comicInspector
                            chapterWorkspace(columns: 2)
                                .frame(minHeight: 420)
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: MGSpacing.sm) {
                        comicInspector
                            .frame(width: min(max(proxy.size.width * 0.25, 220), 272))
                        chapterWorkspace(columns: proxy.size.width > 1180 ? 5 : 4)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .alert("加入全部可见章节？", isPresented: confirmationBinding, presenting: confirmation) { _ in
            Button("加入队列") { vm.startDownload() }
            Button("取消", role: .cancel) {}
        } message: { confirmation in
            switch confirmation {
            case .addAllVisible(let count):
                Text("当前未单独选择章节，将把搜索与分类筛选后的全部 \(count) 话加入队列。")
            }
        }
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("下载")
                    .font(MGFont.title)
                Text("解析目录并选择要保存到本地的章节。")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.showParseDone {
                Label(vm.parseDoneText, systemImage: "checkmark.circle.fill")
                    .mgStatusTag(tint: MGTheme.success)
            } else if vm.isLoading {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text(vm.parseLiveText.isEmpty ? "正在解析" : vm.parseLiveText)
                }
                .mgStatusTag(tint: MGTheme.accent)
            }
            Button {
                showLogs = true
            } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost))
            .help("活动日志")
            Button(action: openQueue) {
                Image(systemName: "tray.full")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost))
            .help("打开队列")
        }
    }

    private var linkWorkspace: some View {
        VStack(spacing: MGSpacing.xs) {
            HStack(spacing: MGSpacing.xs) {
                Image(systemName: "link")
                    .foregroundStyle(MGTheme.accent)
                TextField("粘贴漫画链接或 path_word", text: $vm.inputURL)
                    .mgTextField()
                    .submitLabel(.go)
                    .onSubmit { vm.loadComic() }
                Button(vm.isLoading ? "解析中" : "解析") {
                    vm.loadComic()
                }
                .buttonStyle(MGActionButtonStyle(variant: .primary))
                .disabled(vm.isLoading || vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: MGSpacing.xs) {
                Menu {
                    Section("拷贝漫画") {
                        ForEach(CopyMangaMirror.allCases) { mirror in
                            Button(mirror.displayName) {
                                openInBrowser(mirror.webBaseURL.absoluteString)
                            }
                        }
                    }
                    Section("其他站点") {
                        Button("漫画柜") { openInBrowser("https://www.manhuagui.com") }
                    }
                } label: {
                    Label("站点入口", systemImage: "safari")
                }
                .menuStyle(.borderlessButton)

                Button {
                    vm.chooseDestination()
                } label: {
                    Label(destinationName, systemImage: "folder")
                        .lineLimit(1)
                }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
                .help(vm.destinationFolder.path)

                Spacer(minLength: 0)
                if !vm.statusText.isEmpty && !vm.showParseDone && !vm.isLoading {
                    Text(vm.statusText)
                        .font(MGFont.caption)
                        .foregroundStyle(vm.errorText.isEmpty ? .secondary : MGTheme.danger)
                        .lineLimit(1)
                }
            }
        }
        .padding(MGSpacing.sm)
        .mgSurface(elevated: true)
    }

    private var comicInspector: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            coverView
                .frame(maxWidth: .infinity)
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(vm.comic?.name ?? "等待解析")
                    .font(MGFont.section)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(inspectorSubtitle)
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let comic = vm.comic {
                HStack(spacing: MGSpacing.xs) {
                    metadata("分类", "\(comic.volumes.count)")
                    metadata("章节", "\(vm.totalChapterCount)")
                    metadata("已选", "\(selectedCount)")
                }
                .padding(.top, 2)
            }

            if !vm.errorText.isEmpty {
                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    Label("解析失败", systemImage: "exclamationmark.triangle.fill")
                        .font(MGFont.captionStrong)
                        .foregroundStyle(MGTheme.danger)
                    Text(vm.errorText)
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let suggestion = vm.lastMirrorSuggestion {
                        Button("切换到 \(suggestion.displayName) 重试") {
                            vm.applySuggestedMirrorAndReload()
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    }
                    HStack(spacing: MGSpacing.xs) {
                        Button("复制错误") { vm.copyCurrentError() }
                            .buttonStyle(MGActionButtonStyle(variant: .ghost))
                        Button("查看日志") { showLogs = true }
                            .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    }
                }
                .padding(MGSpacing.xs)
                .mgInset()
            }

            Spacer(minLength: 0)
            Text(vm.destinationFolder.path)
                .font(MGFont.mono)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(MGSpacing.sm)
        .mgSurface()
    }

    private func metadata(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(MGFont.number)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var coverView: some View {
        Group {
            if let cover = vm.comic?.coverURL {
                AsyncImage(url: cover) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(MGSpacing.xs)
                    case .empty:
                        ZStack { placeholderCover; ProgressView() }
                    default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
        .background(MGTheme.inset(for: colorScheme))
    }

    private var placeholderCover: some View {
        VStack(spacing: MGSpacing.xs) {
            BrandMarkView(size: 44)
            Text("封面预览")
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var chapterWorkspace: some View {
        chapterWorkspace(columns: 4)
    }

    private func chapterWorkspace(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            chapterToolbar
            volumeFilters

            if let empty = emptyState {
                MGEmptyState(title: empty.title, systemImage: empty.image, detail: empty.detail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mgInset()
            } else {
                ZStack(alignment: .bottom) {
                    ScrollView {
                        chapterSections(columns: columns)
                            .padding(MGSpacing.sm)
                    }
                    .coordinateSpace(name: "chapter-canvas")
                    .gesture(chapterDragGesture)
                    .onPreferenceChange(ChapterFrameKey.self) { chapterFrames = $0 }
                    .overlay(DragRectOverlay(rect: dragRect))

                    if vm.selectedVisibleChapterCount > 0 {
                        selectedActionBar
                            .padding(MGSpacing.sm)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selectedCount)
                .mgInset()
            }
        }
        .padding(MGSpacing.sm)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mgSurface()
    }

    private var chapterToolbar: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("章节")
                        .font(MGFont.section)
                    Text("可见 \(vm.visibleChapterCount) · 已选 \(vm.selectedVisibleChapterCount)")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("全选") { vm.selectAllVisible() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
                Button("清空") { vm.deselectAllVisible() }
                    .buttonStyle(MGActionButtonStyle(variant: .ghost))
            }

            HStack(spacing: MGSpacing.xs) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索章节", text: $vm.chapterSearchQuery)
                        .textFieldStyle(.plain)
                        .font(MGFont.body)
                    if !vm.chapterSearchQuery.isEmpty {
                        Button {
                            vm.chapterSearchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 7)
                .mgInset()

                HStack(spacing: 3) {
                    ForEach(SortDirection.allCases) { direction in
                        Button(direction.rawValue) { vm.chapterSortDirection = direction }
                            .buttonStyle(MGSelectionButtonStyle(selected: vm.chapterSortDirection == direction, horizontalPadding: 8, verticalPadding: 6))
                    }
                }
            }
        }
    }

    private var volumeFilters: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        showVolumeFilters.toggle()
                    }
                } label: {
                    Label(showVolumeFilters ? "隐藏分类" : "显示分类", systemImage: "square.grid.2x2")
                }
                .buttonStyle(MGActionButtonStyle(variant: .ghost))
                Text("\(selectedVolumeCount)/\(vm.displayVolumes.count)")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if showVolumeFilters {
                    Button("全部") { vm.selectAllVolumes() }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    Button("清空") { vm.deselectAllVolumes() }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
                }
            }

            if showVolumeFilters {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(vm.displayVolumes) { volume in
                            let selected = vm.selectedVolumeIDs.contains(volume.id)
                            let matching = volume.chapters.filter(matchesCurrentSearch).count
                            Button {
                                vm.toggleVolume(volume.id)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    Text(volume.displayName)
                                    Text("\(vm.selectedChapterCount(in: volume.id))/\(matching)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(MGSelectionButtonStyle(selected: selected, horizontalPadding: 8, verticalPadding: 6))
                            .disabled(!vm.chapterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && matching == 0)
                        }
                    }
                }
            }
        }
    }

    private func chapterSections(columns: Int) -> some View {
        LazyVStack(alignment: .leading, spacing: MGSpacing.md) {
            ForEach(vm.filteredVolumeSections) { section in
                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.volumeName)
                                .font(MGFont.bodyStrong)
                            Text("\(section.chapterCount) 话 · 已选 \(vm.selectedChapterCount(in: section.id))")
                                .font(MGFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(vm.areAllChaptersSelected(in: section.id) ? "清空本组" : "选择本组") {
                            vm.toggleVolumeChapterSelection(volumeID: section.id)
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 126), spacing: MGSpacing.xs), count: columns), spacing: MGSpacing.xs) {
                        ForEach(section.chapters) { chapter in
                            chapterCell(chapter)
                        }
                    }
                }
            }
        }
    }

    private func chapterCell(_ chapter: ComicChapter) -> some View {
        let selected = vm.selectedChapterIDs.contains(chapter.id)
        return Button {
            vm.selectChapter(chapter, modifiers: NSEvent.modifierFlags)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? MGTheme.accent : .secondary)
                Text(chapter.displayName)
                    .font(MGFont.body)
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? MGTheme.accent.opacity(colorScheme == .dark ? 0.23 : 0.11) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? MGTheme.accent.opacity(0.52) : MGTheme.divider(for: colorScheme).opacity(0.54), lineWidth: 0.8)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ChapterFrameKey.self, value: [chapter.id: proxy.frame(in: .named("chapter-canvas"))])
                }
            )
        }
        .buttonStyle(.plain)
        .help(chapter.displayName)
    }

    private var selectedActionBar: some View {
        HStack(spacing: MGSpacing.xs) {
            Label("当前可见已选 \(vm.selectedVisibleChapterCount) 话", systemImage: "checkmark.circle.fill")
                .font(MGFont.bodyStrong)
                .foregroundStyle(MGTheme.accent)
            Spacer()
            Button("清空") { vm.deselectAllVisible() }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
            Button("加入队列", action: requestStartDownload)
                .buttonStyle(MGActionButtonStyle(variant: .primary))
        }
        .padding(MGSpacing.xs)
        .mgSurface(elevated: true, radius: 10)
    }

    private var emptyState: (title: String, detail: String, image: String)? {
        if vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, vm.comic == nil {
            return ("输入链接后开始解析", "支持详情页、章节页链接与 path_word。", "link.badge.plus")
        }
        if vm.isLoading {
            return ("正在解析目录", vm.parseLiveText.isEmpty ? "请稍候，章节完成后会显示在此处。" : vm.parseLiveText, "hourglass")
        }
        if !vm.errorText.isEmpty {
            return ("无法解析此链接", "请查看左侧的错误详情或活动日志。", "exclamationmark.triangle")
        }
        if vm.comic != nil && selectedVolumeCount == 0 {
            return ("先选择分类", "选择至少一个分类后即可浏览和批量选择章节。", "square.grid.2x2")
        }
        if vm.comic != nil && !vm.chapterSearchQuery.isEmpty && !vm.hasAnyMatchingChapters {
            return ("没有匹配章节", "尝试修改搜索关键词，已选章节不会因此改变。", "magnifyingglass")
        }
        if vm.comic != nil && !vm.hasAnyParsedChapters {
            return ("暂无可下载章节", "当前漫画没有可用章节。", "tray")
        }
        return nil
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

    private func matchesCurrentSearch(_ chapter: ComicChapter) -> Bool {
        let query = vm.chapterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || chapter.displayName.localizedCaseInsensitiveContains(query)
    }

    private var destinationName: String {
        let name = vm.destinationFolder.lastPathComponent
        return name.isEmpty ? vm.destinationFolder.path : name
    }

    private var inspectorSubtitle: String {
        if vm.isLoading { return vm.parseLiveText.isEmpty ? "正在解析…" : vm.parseLiveText }
        return vm.statusText
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private func requestStartDownload() {
        guard vm.comic != nil else {
            vm.startDownload()
            return
        }
        if vm.selectedVisibleChapterCount > 0 {
            vm.startDownload()
        } else if vm.visibleChapterCount > 0 {
            confirmation = .addAllVisible(vm.visibleChapterCount)
        }
    }

    private func openInBrowser(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
