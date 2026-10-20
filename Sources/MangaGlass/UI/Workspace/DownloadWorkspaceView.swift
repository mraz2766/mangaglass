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
    @State private var showCategories = false
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

    var body: some View {
        GeometryReader { proxy in
            let contentWidth = proxy.size.width
            let coverWidth: CGFloat = contentWidth >= 900 ? 260 : (contentWidth >= 720 ? 220 : 180)
            let coverHeight: CGFloat = contentWidth >= 900 ? 364 : (contentWidth >= 720 ? 308 : 250)
            VStack(spacing: 16) {
                homeToolbar
                HStack(alignment: .top, spacing: MGSpacing.lg) {
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: MGSpacing.sm) {
                linkInput.frame(minWidth: 240)
                toolbarActions
            }
            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    toolbarActions
                }
                linkInput
            }
        }
        .frame(minHeight: 36)
    }

    private var linkInput: some View {
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
                    showCategories = false
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
            .mgQuietTextField()
            .overlay { RoundedRectangle(cornerRadius: 6).stroke(linkFocused ? MGTheme.accent : .clear, lineWidth: 2) }
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
                }.frame(width: 28)
            }
            .buttonStyle(MGActionButtonStyle(variant: .primary))
            .disabled(vm.isLoading || vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel(vm.isLoading ? "正在解析" : "解析")
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
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("在浏览器中打开支持站点")
            Button { showLogs = true } label: { Image(systemName: "doc.text").frame(width: 28, height: 28) }
                .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
                .help("活动日志").accessibilityLabel("活动日志")
        }
    }

    private func comicInspector(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showCover = true } label: {
                coverImage.frame(maxWidth: .infinity).frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain).disabled(vm.comic?.coverURL == nil)
            .help("查看大图").accessibilityLabel("查看漫画封面大图")
            Text(vm.comic?.name ?? "添加一部漫画")
                .font(.system(size: 15, weight: .semibold)).lineLimit(3).textSelection(.enabled)
                .padding(.top, 4)
            if let comic = vm.comic {
                Text("\(comic.site.displayName) · \(comic.volumes.count) 类 · \(vm.totalChapterCount) 话")
                    .font(MGFont.caption).foregroundStyle(.secondary)
            } else {
                Text("输入链接，解析后选择卷与章节。").font(MGFont.caption).foregroundStyle(.secondary)
            }
            Button { vm.chooseDestination() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                    Text(vm.destinationFolder.lastPathComponent)
                        .lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("下载到 \(vm.destinationFolder.path)，点按更改")
            .accessibilityLabel("下载目录：\(vm.destinationFolder.lastPathComponent)，点按更改")
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
        VStack(spacing: 8) {
            chapterToolbar
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
                    LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(vm.filteredVolumeSections.filter { !$0.chapters.isEmpty }) { section in
                            Section {
                                if !vm.collapsedVolumeIDs.contains(section.id) {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 136), spacing: 4)], spacing: 4) {
                                        ForEach(section.chapters) { chapter in chapterCell(chapter) }
                                    }
                                    .padding(.horizontal, 2)
                                    .padding(.bottom, 8)
                                    .contentShape(Rectangle())
                                    .gesture(chapterDragGesture)
                                }
                            } header: { sectionHeader(section) }
                        }
                    }.padding(.bottom, 4)
                }
                .coordinateSpace(name: "chapter-canvas")
                .onPreferenceChange(ChapterFrameKey.self) { chapterFrameStore.frames = $0 }
                .overlay(DragRectOverlay(rect: dragRect))
            }
            selectionBar
                .padding(.top, 8)
                .overlay(alignment: .top) { MGHairlineDivider() }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chapterToolbar: some View {
        VStack(spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    chapterTitle
                    MGSearchField(title: "搜索章节", text: $vm.chapterSearchQuery, quiet: true).frame(minWidth: 100)
                    sortPicker
                }
                HStack(spacing: 8) {
                    MGSearchField(title: "搜索章节", text: $vm.chapterSearchQuery, quiet: true)
                    sortPicker
                }
            }
            HStack(spacing: 6) {
                Button { showCategories.toggle() } label: {
                    Label(vm.selectedVolumeIDs.count == vm.displayVolumes.count ? "分类：全部" : "分类：\(vm.selectedVolumeIDs.count)",
                          systemImage: "line.3.horizontal.decrease")
                }
                .buttonStyle(MGActionButtonStyle(variant: .ghost))
                .popover(isPresented: $showCategories, arrowEdge: .bottom) { categoryPopover }
                Spacer(minLength: 0)
                Button("全选可见") { vm.selectAllVisible() }
                    .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    .disabled(vm.visibleChapterCount == 0)
                Button("清除选择") { vm.clearChapterSelection() }.buttonStyle(MGActionButtonStyle(variant: .ghost))
                    .disabled(vm.selectedChapters.isEmpty)
            }
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
        let selectedCount = section.chapters.reduce(into: 0) { count, chapter in
            if vm.selectedChapterIDs.contains(chapter.id) { count += 1 }
        }
        let selectionState: MGSelectionState = selectedCount == section.chapterCount && section.chapterCount > 0
            ? .all
            : (selectedCount > 0 ? .partial : .none)
        return HStack(spacing: 6) {
            Button {
                if vm.collapsedVolumeIDs.contains(section.id) {
                    vm.collapsedVolumeIDs.remove(section.id)
                } else {
                    vm.collapsedVolumeIDs.insert(section.id)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(vm.collapsedVolumeIDs.contains(section.id) ? 0 : 90))
                        .animation(reduceMotion ? nil : MGMotion.fast, value: vm.collapsedVolumeIDs.contains(section.id))
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
                .accessibilityLabel("\(vm.collapsedVolumeIDs.contains(section.id) ? "展开" : "折叠")\(section.volumeName)")
            MGGroupSelectionButton(title: section.volumeName,
                                   state: selectionState) {
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
        Text("已选 \(vm.selectedChapterCount) 话" + (vm.hiddenSelectedChapterCount > 0 ? " · 隐藏 \(vm.hiddenSelectedChapterCount) 话" : ""))
            .font(MGFont.bodyStrong).monospacedDigit().foregroundStyle(vm.selectedChapterCount == 0 ? .secondary : .primary)
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
            .buttonStyle(MGActionButtonStyle(variant: .primary))
            .disabled(enqueueFeedback == nil && !isCheckingExistingFiles && (vm.selectedChapterCount == 0 || vm.isLoading || !vm.errorText.isEmpty))
            .allowsHitTesting(enqueueFeedback == nil && !isCheckingExistingFiles)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
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
