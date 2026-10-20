import AppKit
import SwiftUI

struct DownloadWorkspaceView: View {
    private enum EnqueueFeedback: Equatable {
        case added(Int)
        case alreadyQueued
    }

    @ObservedObject var vm: MainViewModel
    @Binding var showLogs: Bool
    let openQueue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var categoryQuery = ""
    @State private var showCover = false
    @StateObject private var chapterFrameStore = ChapterFrameStore()
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragAdditive = false
    @State private var dragStartChapterID: String?
    @State private var dragLastChapterID: String?
    @State private var dragChapterOrder: [String] = []
    @State private var dragChapterIDs: Set<String> = []
    @State private var enqueueFeedback: EnqueueFeedback?
    @State private var enqueuePulse = false
    @State private var enqueueFeedbackTask: Task<Void, Never>?
    @State private var enqueuePreparationTask: Task<Void, Never>?
    @State private var isCheckingExistingFiles = false
    @State private var preparedDownload: MainViewModel.PreparedDownload?
    @State private var linkUndoStack: [String] = []
    @State private var previousLinkText = ""
    @State private var isApplyingLinkUndo = false
    @FocusState private var linkFocused: Bool
    @Namespace private var heroSpace
    @State private var enqueueButtonCenter: CGPoint = .zero
    @Environment(\.mgFlyToQueue) private var flyToQueue

    private var isEmptyHome: Bool {
        vm.comic == nil && !vm.isLoading && vm.errorText.isEmpty
    }

    private var heroSpring: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if isEmptyHome {
                emptyHome
                    .transition(.opacity)
            } else {
                VStack(spacing: 16) {
                    homeToolbar
                    comicHeader
                    chapterWorkspace
                }
                .transition(.opacity)
            }
            if !isEmptyHome && vm.selectedChapterCount > 0 {
                selectionCapsule
                    .padding(.bottom, 4)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(heroSpring, value: isEmptyHome)
        .animation(heroSpring, value: vm.selectedChapterCount > 0)
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
        .onChange(of: vm.comic?.slug) { slug in
            vm.collapsedVolumeIDs.removeAll()
            if slug != nil { MGRevealClock.mark() }
        }
        .onDisappear {
            enqueueFeedbackTask?.cancel()
            enqueuePreparationTask?.cancel()
        }
        .alert("发现已有下载文件", isPresented: existingFilesConfirmationBinding, presenting: preparedDownload) { prepared in
            Button("保留并补全") {
                startPreparedDownload(prepared, policy: .keepExisting)
            }
            Button("覆盖重新下载", role: .destructive) {
                startPreparedDownload(prepared, policy: .overwrite)
            }
            Button("取消", role: .cancel) {}
        } message: { prepared in
            Text(prepared.conflictMessage)
        }
    }

    private var homeToolbar: some View {
        HStack(spacing: 10) {
            linkInput(large: false).frame(minWidth: 240)
            toolbarActions
        }
        .frame(minHeight: 36)
    }

    /// First screen: one big field, recent covers, and site shortcuts.
    private var emptyHome: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                toolbarActions
            }
            Spacer(minLength: 24)
            VStack(spacing: 14) {
                Text("今天想下载哪一部？")
                    .font(.system(size: 28, weight: .semibold))
                Text("粘贴拷贝漫画、漫画柜或包子漫画的链接，回车即可解析。")
                    .font(MGFont.body)
                    .foregroundStyle(.secondary)
                linkInput(large: true)
                    .frame(maxWidth: 560)
                    .padding(.top, 8)
            }
            if !vm.recentRecords.isEmpty {
                VStack(spacing: 12) {
                    Text("继续上次").font(MGFont.captionStrong).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(Array(vm.recentRecords.sorted { $0.updatedAt > $1.updatedAt }.prefix(6).enumerated()), id: \.element.id) { index, record in
                            Button { vm.applyRecentRecord(record) } label: {
                                VStack(spacing: 6) {
                                    MGBookCover(url: record.coverURL, title: record.title)
                                        .frame(width: 72, height: 100)
                                        .mgHoverLift()
                                    Text(record.title).font(MGFont.caption).lineLimit(1).frame(width: 80)
                                }
                            }
                            .buttonStyle(.plain)
                            .help("继续：\(record.title)")
                            .mgStaggerAppear(index: index * 3)
                        }
                    }
                }
                .padding(.top, 40)
            }
            Spacer(minLength: 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { MGRevealClock.mark() }
    }

    private func linkInput(large: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                TextField("粘贴漫画链接或 path_word", text: $vm.inputURL)
                    .focused($linkFocused)
                    .onSubmit { vm.loadComic() }
                    .onAppear { previousLinkText = vm.inputURL }
                    .onChange(of: vm.inputURL) { newValue in
                        if isApplyingLinkUndo {
                            isApplyingLinkUndo = false
                        } else if previousLinkText != newValue {
                            linkUndoStack.append(previousLinkText)
                            if linkUndoStack.count > 50 {
                                linkUndoStack.removeFirst(linkUndoStack.count - 50)
                            }
                        }
                        previousLinkText = newValue
                    }
                Button {
                    vm.clearHome()
                    categoryQuery = ""
                    showCover = false
                    dragStart = nil
                    dragCurrent = nil
                    chapterFrameStore.frames = [:]
                    linkFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
                .disabled(!vm.hasHomeContent)
                .help("清除链接、封面、卷与章节及解析状态")
                .accessibilityLabel("清除首页搜索数据和状态")
            }
            .font(large ? .system(size: 15) : MGFont.body)
            .mgQuietTextField()
            .frame(height: large ? 44 : 32)
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(linkFocused ? MGTheme.accent : .clear, lineWidth: 2) }
            .matchedGeometryEffect(id: "link-field", in: heroSpace)
            .background {
                Button(action: undoLinkInput) { Color.clear.frame(width: 1, height: 1) }
                    .keyboardShortcut("z", modifiers: .control)
                    .disabled(!linkFocused || linkUndoStack.isEmpty)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            Button { vm.loadComic() } label: {
                ZStack {
                    Text("解析").opacity(vm.isLoading ? 0 : 1)
                    if vm.isLoading { ProgressView().controlSize(.small) }
                }.frame(width: large ? 44 : 28, height: large ? 30 : nil)
            }
            .buttonStyle(MGActionButtonStyle(variant: MGTheme.style == .classic ? .primary : .emphasis))
            .disabled(vm.isLoading || vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(vm.isLoading ? "正在解析" : "解析")
            .matchedGeometryEffect(id: "link-button", in: heroSpace)
        }
    }

    private func undoLinkInput() {
        guard linkFocused, let previous = linkUndoStack.popLast() else { return }
        isApplyingLinkUndo = true
        vm.inputURL = previous
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
                Button("包子漫画") { NSWorkspace.shared.open(MangaSiteConfig.baoziManga.webBase) }
            } label: { Label("站点", systemImage: "globe") }
                .fixedSize()
            Button { showLogs = true } label: { Image(systemName: "doc.text").frame(width: 28, height: 28) }
                .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
                .help("活动日志").accessibilityLabel("活动日志")
        }
    }

    /// Cover, title, meta and category chips in one band above the grid.
    private var comicHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            Button { showCover = true } label: {
                Group {
                    if vm.isLoading && vm.comic == nil {
                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(MGTheme.palette.cell)
                    } else {
                        coverImage
                    }
                }
                .frame(width: 92, height: 128)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(vm.comic?.coverURL == nil)
            .help("查看大图").accessibilityLabel("查看漫画封面大图")

            VStack(alignment: .leading, spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack(spacing: 10) {
                    if let comic = vm.comic {
                        Text("\(comic.site.displayName) · \(vm.totalChapterCount) 话")
                            .font(MGFont.caption).foregroundStyle(.secondary)
                    }
                    Button { vm.chooseDestination() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("下载到 \(vm.destinationFolder.lastPathComponent)").lineLimit(1).truncationMode(.middle)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(vm.destinationFolder.path)
                }
                parseStatus
                if vm.comic != nil {
                    HStack(spacing: 10) {
                        if vm.displayVolumes.count > 1 {
                            categoryChips
                        }
                        Spacer(minLength: 8)
                        MGSearchField(title: "搜索章节", text: $vm.chapterSearchQuery, quiet: true)
                            .frame(minWidth: 120, maxWidth: 220)
                        sortPicker
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 128, alignment: .top)
    }

    private var headerTitle: String {
        if let name = vm.comic?.name { return name }
        if vm.isLoading { return "正在解析…" }
        return "无法解析此链接"
    }

    private var categoryChips: some View {
        let allSelected = vm.selectedVolumeIDs.count == vm.displayVolumes.count
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                MGChip(title: "全部", count: vm.totalChapterCount, selected: allSelected) { vm.selectAllVolumes() }
                ForEach(vm.displayVolumes) { volume in
                    let on = !allSelected && vm.selectedVolumeIDs.contains(volume.id)
                    MGChip(title: volume.displayName, count: volume.chapters.count, selected: on) {
                        if allSelected {
                            // From "全部", tapping a category focuses on it alone.
                            vm.deselectAllVolumes()
                            vm.toggleVolume(volume.id)
                        } else if vm.selectedVolumeIDs == [volume.id] {
                            vm.selectAllVolumes()
                        } else {
                            vm.toggleVolume(volume.id)
                        }
                    }
                }
            }
            .padding(.vertical, 1)
        }
        .help("仅影响显示，已选章节会保留")
    }

    private var coverImage: some View {
        Group {
            if let url = vm.comic?.coverURL, !CopyMangaMirror.isRetired(url.host) {
                CachedCoverImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        Image(nsImage: image).resizable().scaledToFill()
                            .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    case .loading: ZStack { coverPlaceholder; ProgressView().controlSize(.small) }
                    case .failure: coverPlaceholder
                    }
                }
            } else { coverPlaceholder }
        }
    }

    private var coverPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "book.closed").font(.system(size: 26, weight: .light))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MGTheme.quietSurface(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        VStack(spacing: 10) {
            if vm.isLoading {
                MGSkeletonGrid()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity)
            } else if !vm.errorText.isEmpty {
                MGEmptyState(title: "无法解析此链接", systemImage: "exclamationmark.triangle", detail: "检查链接，或在上方切换镜像后重试。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !vm.hasAnyMatchingChapters {
                MGEmptyState(title: "没有可见章节", systemImage: "square.grid.2x2",
                             detail: "调整搜索或分类；已有选择会保留。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    ChapterGridContent(
                        vm: vm,
                        sections: vm.filteredVolumeSections.filter { !$0.chapters.isEmpty },
                        selectedChapterIDs: vm.selectedChapterIDs,
                        collapsedVolumeIDs: vm.collapsedVolumeIDs,
                        frameStore: chapterFrameStore,
                        dragGesture: chapterDragGesture
                    )
                    .equatable()
                    .padding(.bottom, vm.selectedChapterCount > 0 ? 72 : 8)
                }
                .coordinateSpace(name: "chapter-canvas")
                .overlay(DragRectOverlay(rect: dragRect))
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : MGMotion.panel, value: vm.isLoading)
    }

    private var chapterToolbar: some View {
        HStack(spacing: 10) {
            chapterTitle
            Spacer(minLength: 8)
            MGSearchField(title: "搜索章节", text: $vm.chapterSearchQuery, quiet: true)
                .frame(minWidth: 120, maxWidth: 240)
            sortPicker
        }
    }

    private var chapterTitle: some View {
        HStack(spacing: 5) {
            Text("卷与章节").font(MGFont.section)
            Text("\(vm.totalChapterCount)")
                .font(MGFont.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }

    private var sortPicker: some View {
        Picker("排序", selection: $vm.chapterSortDirection) {
            ForEach(SortDirection.allCases) { Text($0.rawValue).tag($0) }
        }.labelsHidden().pickerStyle(.segmented).frame(width: 100)
    }

    /// Floats over the grid while anything is selected.
    private var selectionCapsule: some View {
        let palette = MGTheme.palette
        let text = palette.capsuleText
        return HStack(spacing: 14) {
            HStack(spacing: 4) {
                Text("已选")
                Text("\(vm.selectedChapterCount)")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: vm.selectedChapterCount)
                Text("话")
                if vm.hiddenSelectedChapterCount > 0 {
                    Text("· 隐藏 \(vm.hiddenSelectedChapterCount)").opacity(0.7)
                }
            }
            .font(MGFont.body)
            .foregroundStyle(text)
            Button("全选可见") { vm.selectAllVisible() }
                .buttonStyle(.plain).font(MGFont.body).foregroundStyle(text.opacity(0.7))
                .disabled(vm.visibleChapterCount == 0)
            Button("清除") { vm.clearChapterSelection() }
                .buttonStyle(.plain).font(MGFont.body).foregroundStyle(text.opacity(0.7))
            enqueueButton
        }
        .padding(.leading, 20)
        .padding(.trailing, 6)
        .frame(height: 48)
        .background {
            if let fill = palette.capsuleFill {
                Capsule().fill(fill)
            } else {
                Capsule().fill(.regularMaterial)
                Capsule().stroke(palette.glass ? palette.cellStroke : palette.divider, lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }

    private var enqueueButton: some View {
        Button(action: enqueueSelection) {
            ZStack {
                Text("加入队列 \(vm.selectedChapterCount)")
                    .opacity(enqueueFeedback == nil && !isCheckingExistingFiles ? 1 : 0)
                if isCheckingExistingFiles {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text("检查文件")
                    }
                }
                if let enqueueFeedback {
                    HStack(spacing: 6) {
                        Image(systemName: feedbackIcon(for: enqueueFeedback))
                        Text(feedbackTitle(for: enqueueFeedback))
                    }
                    .transition(.opacity)
                }
            }
            .frame(minWidth: 112)
        }
            .buttonStyle(MGActionButtonStyle(variant: .primary, capsule: true))
            .background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .named(MGRootSpace))
                    Color.clear
                        .onAppear { enqueueButtonCenter = CGPoint(x: frame.midX, y: frame.midY) }
                        .onChange(of: frame) { enqueueButtonCenter = CGPoint(x: $0.midX, y: $0.midY) }
                }
            }
            .disabled(enqueueFeedback == nil && !isCheckingExistingFiles && (vm.selectedChapterCount == 0 || vm.isLoading || !vm.errorText.isEmpty))
            .allowsHitTesting(enqueueFeedback == nil && !isCheckingExistingFiles)
            .overlay {
                Capsule()
                    .stroke(MGTheme.accent.opacity(enqueuePulse ? 0 : 0.55), lineWidth: 2)
                    .scaleEffect(enqueuePulse ? 1.08 : 1)
                    .opacity(reduceMotion || enqueueFeedback == nil ? 0 : 1)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(enqueueAccessibilityTitle)
            .help(vm.selectedChapterCount == 0 ? "请选择章节" : "加入全部已选章节，包含隐藏的选择")
    }

    private var enqueueAccessibilityTitle: String {
        if isCheckingExistingFiles { return "正在检查已有下载文件" }
        guard let enqueueFeedback else { return "加入队列 \(vm.selectedChapterCount) 话" }
        return feedbackTitle(for: enqueueFeedback)
    }

    private func enqueueSelection() {
        enqueuePreparationTask?.cancel()
        isCheckingExistingFiles = true
        enqueuePreparationTask = Task { @MainActor in
            guard let prepared = await vm.prepareSelectedDownload(), !Task.isCancelled else {
                isCheckingExistingFiles = false
                return
            }
            isCheckingExistingFiles = false
            if prepared.existingOutput.hasExistingFiles {
                preparedDownload = prepared
            } else {
                startPreparedDownload(prepared, policy: .keepExisting)
            }
        }
    }

    private func startPreparedDownload(_ prepared: MainViewModel.PreparedDownload, policy: ExistingFilePolicy) {
        preparedDownload = nil
        presentEnqueueResult(vm.startPreparedDownload(prepared, existingFilePolicy: policy))
    }

    private func presentEnqueueResult(_ result: EnqueueResult) {
        switch result {
        case .added(let count):
            showEnqueueFeedback(.added(count))
            flyToQueue(count, enqueueButtonCenter)
        case .alreadyQueued:
            showEnqueueFeedback(.alreadyQueued)
        case .unavailable:
            break
        }
    }

    private var existingFilesConfirmationBinding: Binding<Bool> {
        Binding(
            get: { preparedDownload != nil },
            set: { presented in
                if !presented { preparedDownload = nil }
            }
        )
    }

    private func showEnqueueFeedback(_ feedback: EnqueueFeedback) {
        enqueueFeedbackTask?.cancel()
        enqueueFeedback = feedback
        enqueuePulse = false
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.36)) {
                enqueuePulse = true
            }
        }
        enqueueFeedbackTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_400))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : MGMotion.regular) {
                enqueueFeedback = nil
                enqueuePulse = false
            }
        }
    }

    private func feedbackIcon(for feedback: EnqueueFeedback) -> String {
        switch feedback {
        case .added: return "checkmark"
        case .alreadyQueued: return "tray.full"
        }
    }

    private func feedbackTitle(for feedback: EnqueueFeedback) -> String {
        switch feedback {
        case .added(let count): return "已加入 \(count) 话"
        case .alreadyQueued: return "已在队列中"
        }
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
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = value.startLocation
                    dragAdditive = NSEvent.modifierFlags.contains(.command)
                    dragChapterOrder = vm.visibleChapters.map(\.id)
                    dragChapterIDs = Set(dragChapterOrder)
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
                dragChapterOrder = []
                dragChapterIDs = []
            }
    }

    private func updateDragSelection() {
        guard let rect = dragRect else { return }
        let hitIDs = Set(chapterFrameStore.frames.compactMap { id, frame in
            dragChapterIDs.contains(id) && frame.intersects(rect) ? id : nil
        })
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
        chapterFrameStore.frames.first { id, frame in
            (dragChapterIDs.isEmpty || dragChapterIDs.contains(id)) && frame.contains(point)
        }?.key
    }

    private func chapterRange(from startID: String, to endID: String) -> Set<String> {
        let ids = dragChapterOrder.isEmpty ? vm.visibleChapters.map(\.id) : dragChapterOrder
        guard let start = ids.firstIndex(of: startID), let end = ids.firstIndex(of: endID) else { return [startID] }
        return Set(ids[min(start, end)...max(start, end)])
    }


}

/// The chapter grid only depends on these inputs; `Equatable` lets SwiftUI skip re-evaluating
/// every cell when unrelated model state (link text, parse status, logs) changes.
private struct ChapterGridContent<DragGestureType: Gesture>: View, @preconcurrency Equatable {
    let vm: MainViewModel
    let sections: [MainViewModel.FilteredVolumeSection]
    let selectedChapterIDs: Set<String>
    let collapsedVolumeIDs: Set<String>
    let frameStore: ChapterFrameStore
    let dragGesture: DragGestureType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sections == rhs.sections
            && lhs.selectedChapterIDs == rhs.selectedChapterIDs
            && lhs.collapsedVolumeIDs == rhs.collapsedVolumeIDs
    }

    var body: some View {
        LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { sectionIndex, section in
                Section {
                    if !collapsedVolumeIDs.contains(section.id) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 8)], spacing: 8) {
                            ForEach(Array(section.chapters.enumerated()), id: \.element.id) { index, chapter in
                                chapterCell(chapter)
                                    .mgStaggerAppear(index: sectionIndex * 12 + index)
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .padding(.horizontal, 2)
                        .contentShape(Rectangle())
                        .gesture(dragGesture)
                    }
                } header: { sectionHeader(section) }
            }
        }.padding(.bottom, 4)
    }

    private func sectionHeader(_ section: MainViewModel.FilteredVolumeSection) -> some View {
        let selectedCount = section.chapters.reduce(into: 0) { count, chapter in
            if selectedChapterIDs.contains(chapter.id) { count += 1 }
        }
        let selectionState: MGSelectionState = selectedCount == section.chapterCount && section.chapterCount > 0
            ? .all
            : (selectedCount > 0 ? .partial : .none)
        return HStack(spacing: 6) {
            Button {
                if collapsedVolumeIDs.contains(section.id) {
                    vm.collapsedVolumeIDs.remove(section.id)
                } else {
                    vm.collapsedVolumeIDs.insert(section.id)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(collapsedVolumeIDs.contains(section.id) ? 0 : 90))
                        .animation(reduceMotion ? nil : MGMotion.fast, value: collapsedVolumeIDs.contains(section.id))
                    Text(section.volumeName).font(MGFont.section).lineLimit(1)
                    Text("已选 \(selectedCount) / \(section.chapterCount)")
                        .font(MGFont.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
                .mgHoverBackground(radius: 5)
                .accessibilityLabel("\(collapsedVolumeIDs.contains(section.id) ? "展开" : "折叠")\(section.volumeName)")
            MGGroupSelectionButton(title: section.volumeName,
                                   state: selectionState) {
                vm.toggleVolumeChapterSelection(volumeID: section.id)
            }
        }
        .padding(.horizontal, 2).frame(height: 34)
        .background {
            if MGTheme.palette.glass {
                Rectangle().fill(.regularMaterial)
            } else {
                MGTheme.background(for: colorScheme)
            }
        }
    }

    private func chapterCell(_ chapter: ComicChapter) -> some View {
        let selected = selectedChapterIDs.contains(chapter.id)
        return MGChapterSelectionCell(title: chapter.displayName, selected: selected) {
            vm.selectChapter(chapter, modifiers: NSEvent.modifierFlags)
        }
        .background {
            ChapterFrameReporter(id: chapter.id, store: frameStore)
        }
        .help(chapter.displayName).accessibilityValue(selected ? "已选择" : "未选择")
    }

}
