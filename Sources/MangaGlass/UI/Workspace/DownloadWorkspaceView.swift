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
    @State private var expandVolumeFilters = false
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
            let compact = proxy.size.width < 820
            let short = proxy.size.height < 640
            VStack(alignment: .leading, spacing: MGSpacing.xs) {
                pageHeader(showSubtitle: !short)
                linkWorkspace
                if compact {
                    comicSummary(short: short)
                    chapterWorkspace
                } else {
                    HStack(alignment: .top, spacing: MGSpacing.content) {
                        comicInspector
                            .frame(width: 200)
                        chapterWorkspace
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

    private func pageHeader(showSubtitle: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("下载")
                    .font(MGFont.title)
                if showSubtitle {
                    Text("解析目录并选择要保存到本地的章节。")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
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
        .frame(minHeight: 48)
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
                            .help(mirror.webBaseURL.host ?? mirror.displayName)
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
                if vm.isLoading {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text(vm.parseLiveText.isEmpty ? "解析中" : vm.parseLiveText)
                    }
                    .font(MGFont.caption)
                    .foregroundStyle(MGTheme.accent)
                } else if vm.showParseDone {
                    Label(vm.parseDoneText, systemImage: "checkmark.circle.fill")
                        .font(MGFont.caption)
                        .foregroundStyle(MGTheme.success)
                } else if !vm.statusText.isEmpty {
                    Text(vm.statusText)
                        .font(MGFont.caption)
                        .foregroundStyle(vm.errorText.isEmpty ? .secondary : MGTheme.danger)
                        .lineLimit(1)
                }
            }

            if !vm.errorText.isEmpty {
                HStack(alignment: .top, spacing: MGSpacing.xs) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MGTheme.danger)
                    Text(vm.errorText)
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    if let suggestion = vm.lastMirrorSuggestion {
                        Button("切换到\(suggestion.displayName)") { vm.applySuggestedMirrorAndReload() }
                            .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    }
                    Button("复制错误") { vm.copyCurrentError() }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    Button("查看日志") { showLogs = true }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
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
                .frame(height: 224)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 5) {
                Text(vm.comic?.name ?? "等待解析")
                    .font(MGFont.section)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(vm.comic?.site.displayName ?? "粘贴链接以开始")
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

        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func comicSummary(short: Bool) -> some View {
        HStack(spacing: MGSpacing.xs) {
            coverView
                .frame(width: short ? 36 : 40, height: short ? 48 : 54)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.comic?.name ?? "等待解析")
                    .font(MGFont.section)
                    .lineLimit(1)
                Text(vm.comic?.site.displayName ?? "粘贴链接以开始")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                if let comic = vm.comic {
                    Text("分类 \(comic.volumes.count) · 章节 \(vm.totalChapterCount) · 已选 \(selectedCount)")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 56)
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
                        AnimatedCoverImage(image: image, reduceMotion: reduceMotion)
                            .id(cover)
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
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            chapterToolbar
            volumeFilters

            if let empty = emptyState {
                MGEmptyState(title: empty.title, systemImage: empty.image, detail: empty.detail)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    chapterSections
                        .padding(.vertical, MGSpacing.xs)
                }
                .coordinateSpace(name: "chapter-canvas")
                .gesture(chapterDragGesture)
                .onPreferenceChange(ChapterFrameKey.self) { chapterFrames = $0 }
                .overlay(DragRectOverlay(rect: dragRect))
            }

            Divider()
            selectedActionBar
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
                Button("清除章节选择") { vm.deselectAllVisible() }
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

                Picker("排序", selection: $vm.chapterSortDirection) {
                    ForEach(SortDirection.allCases) { direction in Text(direction.rawValue).tag(direction) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 112)
            }
        }
    }

    private var volumeFilters: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                        showVolumeFilters.toggle()
                    }
                } label: {
                    Label("显示分类", systemImage: showVolumeFilters ? "chevron.down" : "chevron.right")
                }
                .buttonStyle(MGActionButtonStyle(variant: .ghost))
                Text("\(selectedVolumeCount)/\(vm.displayVolumes.count)")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if showVolumeFilters {
                    Button("全部显示") { vm.selectAllVolumes() }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    Button("全部隐藏") { vm.deselectAllVolumes() }
                        .buttonStyle(MGActionButtonStyle(variant: .ghost))
                }
            }

            if showVolumeFilters {
                if expandVolumeFilters {
                    ScrollView {
                        volumeFilterGrid(Array(vm.displayVolumes))
                    }
                    .frame(maxHeight: 96, alignment: .top)
                } else {
                    volumeFilterGrid(Array(vm.displayVolumes.prefix(6)))
                }

                if vm.displayVolumes.count > 6 {
                    Button(expandVolumeFilters ? "收起分类" : "展开分类") {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                            expandVolumeFilters.toggle()
                        }
                    }
                    .buttonStyle(MGActionButtonStyle(variant: .ghost))
                }
            }
        }
    }

    private func volumeFilterGrid(_ volumes: [ComicVolume]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(volumes) { volume in
                let visible = vm.selectedVolumeIDs.contains(volume.id)
                let matching = volume.chapters.filter(matchesCurrentSearch).count
                Button {
                    vm.toggleVolume(volume.id)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: visible ? "eye.fill" : "eye.slash")
                        Text(volume.displayName)
                        Text("· \(matching)").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(MGSelectionButtonStyle(selected: visible, horizontalPadding: 8, verticalPadding: 4))
                .help(visible ? "隐藏该分类" : "显示该分类")
                .disabled(!vm.chapterSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && matching == 0)
            }
        }
    }

    private var chapterSections: some View {
        LazyVStack(alignment: .leading, spacing: MGSpacing.md) {
            ForEach(vm.filteredVolumeSections) { section in
                VStack(alignment: .leading, spacing: MGSpacing.xs) {
                    HStack {
                        Text(section.volumeName)
                            .font(MGFont.section)
                        Text("已选 \(vm.selectedChapterCount(in: section.id)) / 共 \(section.chapterCount)")
                            .font(MGFont.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let allSelected = vm.areAllChaptersSelected(in: section.id)
                        let partiallySelected = vm.isVolumeChapterSelectionPartial(volumeID: section.id)
                        Button {
                            vm.toggleVolumeChapterSelection(volumeID: section.id)
                        } label: {
                            Label(
                                allSelected ? "取消本组选择" : "全选本组",
                                systemImage: allSelected ? "checkmark.square.fill" : (partiallySelected ? "minus.square.fill" : "square")
                            )
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: MGSpacing.xs)], spacing: MGSpacing.xs) {
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
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? MGTheme.accent : .secondary)
                Text(chapter.displayName)
                    .font(MGFont.body)
                    .foregroundStyle(.primary.opacity(0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(ChapterCellButtonStyle(selected: selected))
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: ChapterFrameKey.self, value: [chapter.id: proxy.frame(in: .named("chapter-canvas"))])
            }
        )
        .accessibilityValue(selected ? "已选择" : "未选择")
        .help(chapter.displayName)
    }

    private var selectedActionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MGSpacing.xs) {
                selectionStatus
                Spacer()
                selectionActions
            }
            VStack(alignment: .leading, spacing: 4) {
                selectionStatus
                HStack {
                    Spacer()
                    selectionActions
                }
            }
        }
        .frame(minHeight: 44, maxHeight: 64)
    }

    private var selectionStatus: some View {
        Label(selectionSummary, systemImage: "checkmark.square.fill")
            .font(MGFont.bodyStrong)
            .foregroundStyle(vm.selectedVisibleChapterCount == 0 ? .secondary : MGTheme.accent)
    }

    private var selectionActions: some View {
        HStack(spacing: MGSpacing.xs) {
            Button("清除选择") { vm.deselectAllVisible() }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
                .disabled(vm.selectedVisibleChapterCount == 0)
            Button("加入队列 \(vm.selectedVisibleChapterCount)", action: requestStartDownload)
                .buttonStyle(MGActionButtonStyle(variant: .primary))
                .disabled(vm.selectedVisibleChapterCount == 0)
                .help(vm.selectedVisibleChapterCount == 0 ? "请选择章节" : "将所选章节加入下载队列")
        }
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

    private var selectionSummary: String {
        let total = selectedCount
        let visible = vm.selectedVisibleChapterCount
        return total == visible ? "已选 \(total) 话" : "已选 \(total) 话，当前可见 \(visible) 话"
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

private struct ChapterCellButtonStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ChapterCellButtonBody(configuration: configuration, selected: selected)
    }
}

private struct ChapterCellButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var background: Color {
        if selected {
            return MGTheme.accent.opacity(colorScheme == .dark ? 0.22 : 0.11)
        }
        if configuration.isPressed {
            return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.075)
        }
        if hovering {
            return colorScheme == .dark ? Color.white.opacity(0.075) : Color.black.opacity(0.055)
        }
        return colorScheme == .dark ? Color.white.opacity(0.045) : Color.black.opacity(0.025)
    }

    private var border: Color {
        if selected {
            return MGTheme.accent.opacity(colorScheme == .dark ? 0.78 : 0.62)
        }
        return MGTheme.divider(for: colorScheme).opacity(hovering ? 1 : 0.72)
    }

    var body: some View {
        configuration.label
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(border, lineWidth: selected ? 1 : 0.7)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = isEnabled && $0 }
            .animation(.easeOut(duration: 0.1), value: hovering)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct AnimatedCoverImage: View {
    let image: Image
    let reduceMotion: Bool
    @State private var isVisible = false

    var body: some View {
        image
            .resizable()
            .scaledToFit()
            .padding(MGSpacing.xs)
            .opacity(reduceMotion || isVisible ? 1 : 0)
            .scaleEffect(reduceMotion || isVisible ? 1 : 0.98)
            .onAppear {
                guard !isVisible else { return }
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isVisible = true
                    }
                }
            }
    }
}
