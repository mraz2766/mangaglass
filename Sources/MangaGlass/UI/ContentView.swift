import AppKit
import SwiftUI

@MainActor
private func brandNSImage() -> NSImage {
    if let url = Bundle.module.url(forResource: "logo", withExtension: "png"),
       let image = NSImage(contentsOf: url) {
        return image
    }
    return NSApp.applicationIconImage
}

struct ContentView: View {
    private struct CompactMetaItem {
        let title: String
        let value: String
    }

    private enum LayoutSizeClass {
        case narrow
        case regular
        case wide
    }

    private struct LayoutMetrics {
        let sizeClass: LayoutSizeClass
        let width: CGFloat

        var isNarrow: Bool { sizeClass == .narrow }
        var isWide: Bool { sizeClass == .wide }

        var pagePadding: CGFloat {
            switch sizeClass {
            case .narrow: return 10
            case .regular: return 12
            case .wide: return 16
            }
        }

        var sectionSpacing: CGFloat {
            switch sizeClass {
            case .narrow: return 10
            case .regular: return 12
            case .wide: return 14
            }
        }

        var sidePanelWidth: CGFloat {
            min(max(width * 0.235, 230), isWide ? 296 : 272)
        }

        var coverWidth: CGFloat {
            switch sizeClass {
            case .narrow: return min(max(width * 0.15, 108), 132)
            case .regular: return 118
            case .wide: return 128
            }
        }

        var coverHeight: CGFloat {
            switch sizeClass {
            case .narrow: return coverWidth * 1.38
            case .regular: return 184
            case .wide: return 198
            }
        }

        var chapterColumns: Int {
            switch sizeClass {
            case .narrow:
                return width < 760 ? 1 : 2
            case .regular:
                return width < 1180 ? 5 : 6
            case .wide:
                return width < 1500 ? 6 : 7
            }
        }

        var sortControlWidth: CGFloat {
            switch sizeClass {
            case .narrow: return 102
            case .regular: return 114
            case .wide: return 126
            }
        }

        var toolbarLeadingWidth: CGFloat {
            switch sizeClass {
            case .narrow: return width
            case .regular: return 278
            case .wide: return 308
            }
        }

        var toolbarActionWidth: CGFloat {
            switch sizeClass {
            case .narrow: return width
            case .regular: return 188
            case .wide: return 212
            }
        }
    }

    @StateObject private var vm = MainViewModel()
    @State private var chapterFrames: [String: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragAdditive = false
    @State private var dragStartChapterID: String?
    @State private var dragLastChapterID: String?
    @State private var showLogPanel = false
    @State private var expandComicTitle = false
    @State private var showDownloadManager = false
    @State private var showSiteEntryPanel = false
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }
    private var subduedPanelFill: Color { MGTheme.insetFill(for: colorScheme, prominence: 0.72) }
    private var settingsBackgroundFill: Color { isDarkMode ? Color(red: 0.12, green: 0.15, blue: 0.20).opacity(0.96) : Color.white.opacity(0.92) }

    private var dragRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(start.x - current.x),
            height: abs(start.y - current.y)
        )
    }

    private var selectedCount: Int { vm.selectedChapterIDs.count }
    private var selectedVolumeCount: Int { vm.selectedVolumeIDs.count }
    private var failedCount: Int {
        vm.downloader.taskItems.reduce(into: 0) { partial, item in
            if case .failed = item.state { partial += 1 }
            if case .canceled = item.state { partial += 1 }
        }
    }
    private var toolbarIcon: Image {
        Image(nsImage: brandNSImage())
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size.width)

            ZStack {
                background

                VStack(spacing: metrics.sectionSpacing) {
                    toolbar(metrics: metrics)

                    Group {
                        if metrics.isNarrow {
                            VStack(spacing: metrics.sectionSpacing) {
                                sidePanel(metrics: metrics)
                                chapterPanel(metrics: metrics)
                            }
                        } else {
                            HStack(alignment: .top, spacing: metrics.sectionSpacing) {
                                sidePanel(metrics: metrics)
                                chapterPanel(metrics: metrics)
                            }
                        }
                    }
                    .layoutPriority(1)

                    simplifiedDownloadPanel(metrics: metrics)
                }
                .padding(metrics.pagePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .preferredColorScheme(vm.preferredColorScheme)
    }

    private var background: some View {
        ZStack {
            MGTheme.appBackground(for: colorScheme)
            .ignoresSafeArea()

            LinearGradient(
                colors: colorScheme == .dark
                    ? [MGTheme.accent.opacity(0.10), .clear]
                    : [MGTheme.accent.opacity(0.08), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    private func toolbar(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            if metrics.isNarrow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        toolbarBrand(size: metrics.isWide ? 34 : 30)
                        Spacer(minLength: 0)
                        toolbarSecondaryMenu
                    }

                    HStack(spacing: 8) {
                        toolbarURLField
                        Button(vm.isLoading ? "加载中" : "加载") {
                            vm.loadComic()
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .primary))
                        .disabled(vm.isLoading)
                        .keyboardShortcut(.defaultAction)
                    }

                    HStack(spacing: 8) {
                        siteEntryMenu(compact: true)
                        Button("选择目录") { vm.chooseDestination() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        Spacer(minLength: 0)
                        parseStatusChip
                    }

                    directoryStatusBar
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    toolbarBrand(size: metrics.isWide ? 34 : 30)
                        .frame(width: metrics.toolbarLeadingWidth, alignment: .leading)

                    toolbarURLField

                    Button(vm.isLoading ? "加载中" : "加载") {
                        vm.loadComic()
                    }
                    .buttonStyle(MGActionButtonStyle(variant: .primary))
                    .disabled(vm.isLoading)
                    .keyboardShortcut(.defaultAction)
                    .frame(width: metrics.toolbarActionWidth, alignment: .trailing)
                }

                HStack(alignment: .center, spacing: 8) {
                    siteEntryMenu(compact: false)
                    Button("选择目录") { vm.chooseDestination() }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))
                    directoryStatusBar
                    Spacer(minLength: 0)
                    parseStatusChip
                    toolbarSecondaryMenu
                }
            }
        }
        .padding(12)
        .mgPanel(cornerRadius: 12, prominence: 0.92)
        .sheet(isPresented: $showDownloadManager) {
            DownloadManagerView(vm: vm)
        }
    }

    private var toolbarURLField: some View {
        TextField("输入漫画链接或 path_word", text: $vm.inputURL)
            .textFieldStyle(.roundedBorder)
            .font(MGFont.body)
            .submitLabel(.go)
            .onSubmit { vm.loadComic() }
    }

    @ViewBuilder
    private func sidePanel(metrics: LayoutMetrics) -> some View {
        if metrics.isNarrow {
            HStack(alignment: .top, spacing: 14) {
                coverView
                    .frame(width: metrics.coverWidth, height: metrics.coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                detailsColumn(metrics: metrics)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .mgPanel()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                coverView
                    .frame(height: metrics.coverHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                ScrollView(showsIndicators: false) {
                    detailsColumn(metrics: metrics)
                }

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: metrics.sidePanelWidth)
            .mgPanel()
        }
    }

    private func detailsColumn(metrics: LayoutMetrics) -> some View {
        let comicName = vm.comic?.name ?? "未加载漫画"
        let titleIsLong = vm.comic != nil && comicName.count > 20

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(comicName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(expandComicTitle ? nil : (metrics.isWide ? 2 : 1))
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .help(comicName)

                if titleIsLong {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                expandComicTitle.toggle()
                            }
                        } label: {
                            Label(expandComicTitle ? "收起标题" : "展开标题", systemImage: expandComicTitle ? "chevron.up" : "chevron.down")
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))

                        Text(expandComicTitle ? "已展开" : "已折叠")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(vm.statusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(vm.errorText.isEmpty ? 1 : 2)
                .fixedSize(horizontal: false, vertical: true)

            if !vm.errorText.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(vm.errorText)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.indigo)
                    if let suggestion = vm.lastMirrorSuggestion {
                        Button("切换到 \(suggestion.displayName) 重试") {
                            vm.applySuggestedMirrorAndReload()
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))
                    }
                }
            }

            compactMetaSection
        }
    }

    private var coverView: some View {
        Group {
            if let cover = vm.comic?.coverURL {
                AsyncImage(url: cover) { phase in
                    switch phase {
                    case .empty:
                        ZStack { placeholderCover; ProgressView() }
                    case .success(let image):
                        ZStack {
                            Color.white.opacity(0.7)
                            image
                                .resizable()
                                .scaledToFit()
                                .padding(8)
                        }
                    case .failure:
                        placeholderCover
                    @unknown default:
                        placeholderCover
                    }
                }
            } else {
                placeholderCover
            }
        }
    }

    private var compactMetaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                statItem("分类", "\(selectedVolumeCount)")
                statItem("章节", "\(selectedCount)")
            }
        }
        .padding(8)
        .mgInsetPanel()
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MGFont.micro)
                .foregroundStyle(.secondary)
            Text(value)
                .font(MGFont.number)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .mgInsetPanel(cornerRadius: 8, prominence: 0.7)
    }

    private func compactMetaRow(_ left: CompactMetaItem, _ right: CompactMetaItem) -> some View {
        HStack(spacing: 8) {
            compactMetaCell(left)
            compactMetaCell(right)
        }
    }

    private func compactMetaCell(_ item: CompactMetaItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(item.value)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.86))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .mgInsetPanel(cornerRadius: 8, prominence: 0.72)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    private func statusLine(_ label: String, _ value: String, multiline: Bool = false) -> some View {
        HStack(alignment: multiline ? .top : .center, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(multiline ? 3 : 1)
                .truncationMode(multiline ? .middle : .tail)
                .fixedSize(horizontal: false, vertical: multiline)
            Spacer(minLength: 0)
        }
    }

    private var parseStatusChip: some View {
        Group {
            if vm.showParseDone {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                    Text(vm.parseDoneText)
                }
                .mgStatusPill(tint: MGTheme.accent, selected: true)
            } else if vm.isLoading, !vm.parseLiveText.isEmpty {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(vm.parseLiveText)
                }
                .mgStatusPill(tint: MGTheme.cyanAction, selected: true)
            }
        }
    }

    private var toolbarSecondaryMenu: some View {
        Menu {
            Menu("主题") {
                ForEach(AppThemeMode.allCases) { mode in
                    Button {
                        vm.themeMode = mode
                    } label: {
                        HStack {
                            Text(mode.title)
                            Spacer()
                            if vm.themeMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Button("打开下载目录") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.destinationFolder.path)
            }
            Button("清缓存") { vm.clearCaches() }
            if !vm.recentRecords.isEmpty {
                Divider()
                Text("最近打开")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Menu("加载历史") {
                    ForEach(vm.recentRecords) { record in
                        Button(historyMenuTitle(for: record)) {
                            vm.applyRecentRecord(record)
                        }
                    }
                }
                Menu("删除单条历史") {
                    ForEach(vm.recentRecords) { record in
                        Button(historyMenuTitle(for: record), role: .destructive) {
                            vm.removeRecentRecord(record)
                        }
                    }
                }
                Button("清空历史", role: .destructive) {
                    vm.clearRecentRecords()
                }
            }
        } label: {
            Label("更多", systemImage: "ellipsis.circle")
        }
        .buttonStyle(MGActionButtonStyle(variant: .ghost))
    }

    private func historyMenuTitle(for record: RecentComicRecord) -> String {
        "\(record.title) · \(record.siteName)"
    }

    private var directoryStatusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MGTheme.accent)
            Text(vm.destinationFolder.path)
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .mgInsetPanel(cornerRadius: 9, prominence: 0.82)
    }

    private func toolbarBrand(size: CGFloat) -> some View {
        HStack(spacing: 8) {
            toolbarIcon
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .padding(5)
                .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.58), lineWidth: 0.8)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                Text("MangaGlass")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("输入链接、解析目录、批量下载")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func siteEntryMenu(compact: Bool) -> some View {
        Button {
            showSiteEntryPanel.toggle()
        } label: {
            HStack(spacing: 6) {
                Text(compact ? "站点" : "站点入口")
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
            }
        }
        .buttonStyle(MGActionButtonStyle(variant: .ghost))
        .popover(isPresented: $showSiteEntryPanel, arrowEdge: .bottom) {
            siteEntryPopover
        }
    }

    private var siteEntryPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("站点入口")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text(currentSiteHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("拷贝漫画")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                VStack(spacing: 6) {
                    ForEach(CopyMangaMirror.allCases) { mirror in
                        Button {
                            showSiteEntryPanel = false
                            openInBrowser(mirror.webBaseURL.absoluteString)
                        } label: {
                            HStack {
                                Text(mirror.displayName)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                Spacer()
                                if currentCopyMirrorHost == mirror.webBaseURL.host?.lowercased() {
                                    Text("当前")
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 0.86))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(subduedPanelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("其他站点")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)

                Button {
                    showSiteEntryPanel = false
                    openInBrowser("https://www.manhuagui.com")
                } label: {
                    HStack {
                        Text("漫画柜")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                        Spacer()
                        if currentSiteHost?.contains("manhuagui.com") == true {
                            Text("当前")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(Color(red: 0.29, green: 0.56, blue: 0.86))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(subduedPanelFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 260)
        .background(settingsBackgroundFill)
    }

    private var currentSiteHost: String? {
        URL(string: vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased()
    }

    private var currentCopyMirrorHost: String? {
        guard let host = currentSiteHost else { return nil }
        return CopyMangaMirror.mirror(for: host)?.webBaseURL.host?.lowercased()
    }

    private var currentSiteHint: String {
        if let host = currentSiteHost {
            if host.contains("manhuagui.com") {
                return "当前来源：漫画柜"
            }
            if let mirror = CopyMangaMirror.mirror(for: host) {
                return "当前来源：\(mirror.displayName)"
            }
        }
        return "点击后直接打开站点或镜像，不再使用系统级子菜单。"
    }

    private func queueStat(_ title: String, _ value: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func compactDownloadInline(
        counts: (queued: Int, running: Int, failed: Int, done: Int),
        failures: [(reason: String, count: Int)]
    ) -> some View {
        let progressSummary = vm.downloader.progressSummary()
        return HStack(spacing: 10) {
            inlineStat("进行中", counts.running, tint: .blue, suffix: "话")
            inlineStat("排队", counts.queued, tint: .secondary, suffix: "话")
            inlineStat("失败", counts.failed, tint: .red, suffix: "话")
            inlineStat("完成", counts.done, tint: .green, suffix: "话")

            Divider()
                .frame(height: 14)
            Text("已下载 \(progressSummary.completedPages)/\(progressSummary.totalPages) 页 · 完成 \(progressSummary.completedTasks)/\(progressSummary.totalTasks) 话")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !vm.downloader.currentTaskTitle.isEmpty {
                Divider()
                    .frame(height: 14)
                Text(vm.downloader.currentTaskTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if let firstFailure = failures.first {
                Divider()
                    .frame(height: 14)
                Text("\(firstFailure.reason) · \(firstFailure.count) 话")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    private func inlineStat(_ title: String, _ value: Int, tint: Color, suffix: String = "") -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)\(suffix)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.24), in: Capsule())
    }

    private var volumeSelectionStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedVolumeCount == 0 ? "浏览分类" : "已选分类")
                    .font(MGFont.captionStrong)
                Text(selectedVolumeCount == 0 ? "先选分类再批量挑章节" : "\(selectedVolumeCount) 个分类已激活")
                    .font(MGFont.micro)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("全选") {
                    vm.selectAllVolumes()
                }
                .buttonStyle(MGActionButtonStyle(variant: .neutral))
                Button("清空") {
                    vm.deselectAllVolumes()
                }
                .buttonStyle(MGActionButtonStyle(variant: .neutral))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.displayVolumes) { volume in
                        let selected = vm.selectedVolumeIDs.contains(volume.id)
                        Button {
                            vm.toggleVolume(volume.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? MGTheme.accentStrong : .secondary)
                                Text(volume.displayName)
                                    .font(selected ? MGFont.captionStrong : MGFont.caption)
                                    .lineLimit(1)
                                Text("\(volume.chapters.count)")
                                    .font(MGFont.micro)
                                    .foregroundStyle(.secondary.opacity(0.82))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .mgStatusPill(tint: MGTheme.accentStrong, selected: selected)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyStateContent: (title: String, detail: String, systemImage: String)? {
        if vm.inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, vm.comic == nil {
            return ("输入链接后开始解析", "支持完整链接或 path_word。", "link.badge.plus")
        }
        if vm.isLoading {
            return ("正在解析漫画目录", vm.parseLiveText.isEmpty ? "请稍候，解析完成后会自动展示章节。" : vm.parseLiveText, "hourglass")
        }
        if !vm.errorText.isEmpty {
            return ("解析失败", vm.errorText, "exclamationmark.triangle")
        }
        if vm.comic != nil && vm.selectedVolumeIDs.isEmpty {
            return ("未选择分类", "先选择至少一个分类，再批量挑选章节。", "square.grid.2x2")
        }
        if vm.comic != nil && vm.hasAnyParsedChapters && !vm.hasAnyMatchingChapters {
            return ("章节展示异常", "已拿到目录数据，但当前分组下没有可展示章节。", "rectangle.stack.badge.exclamationmark")
        }
        if vm.comic != nil && !vm.hasAnyParsedChapters {
            return ("暂无可显示话", "当前漫画还没有可用章节。", "square.grid.2x2")
        }
        return nil
    }

    private func emptyStateCard(title: String, detail: String, systemImage: String) -> some View {
        VStack(spacing: 8) {
            if systemImage == "hourglass" {
                BrandMarkView(size: 42, elevated: false)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if systemImage == "hourglass" {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chapterPanel(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if metrics.isNarrow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        chapterPanelTitle
                        Spacer(minLength: 0)
                        chapterSelectionPill
                        sortPicker(width: metrics.sortControlWidth)
                    }
                    HStack(spacing: 8) {
                        Button("全选") { vm.selectAllVisible() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        Button("清空") { vm.deselectAllVisible() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        Button("加入队列") { vm.startDownload() }
                            .buttonStyle(MGActionButtonStyle(variant: .accent))
                            .disabled(vm.comic == nil && vm.downloader.taskItems.isEmpty)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        chapterPanelTitle
                        Spacer()
                        chapterSelectionPill
                    }

                    HStack(spacing: 8) {
                        sortPicker(width: metrics.sortControlWidth)
                        Button("全选") { vm.selectAllVisible() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        Button("清空") { vm.deselectAllVisible() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        Button("加入队列") { vm.startDownload() }
                            .buttonStyle(MGActionButtonStyle(variant: .accent))
                            .disabled(vm.comic == nil && vm.downloader.taskItems.isEmpty)
                        Spacer(minLength: 0)
                    }
                }
            }

            volumeSelectionStrip

            if let emptyState = emptyStateContent {
                emptyStateCard(title: emptyState.title, detail: emptyState.detail, systemImage: emptyState.systemImage)
            } else {
                ScrollView {
                    chapterSections(metrics: metrics)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            vm.deselectAllVisible()
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: vm.visibleChapters.count)
                }
                .coordinateSpace(name: "chapter-canvas")
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            if dragStart == nil {
                                dragStart = value.startLocation
                                dragAdditive = currentModifiers().contains(.command)
                                dragStartChapterID = chapterID(at: value.startLocation)
                                dragLastChapterID = dragStartChapterID
                            }
                            dragCurrent = value.location
                            updateDragSelection()
                        }
                        .onEnded { value in
                            if let start = dragStart {
                                let dx = value.location.x - start.x
                                let dy = value.location.y - start.y
                                let distance = hypot(dx, dy)
                                if distance < 6,
                                   !dragAdditive,
                                   dragStartChapterID == nil,
                                   chapterID(at: value.location) == nil {
                                    vm.deselectAllVisible()
                                }
                            }
                            dragStart = nil
                            dragCurrent = nil
                            dragAdditive = false
                            dragStartChapterID = nil
                            dragLastChapterID = nil
                        }
                )
                .overlay(DragRectOverlay(rect: dragRect))
                .onPreferenceChange(ChapterFrameKey.self) { frames in
                    chapterFrames = frames
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mgPanel()
    }

    private var chapterPanelTitle: some View {
        let selecting = selectedCount > 0 || selectedVolumeCount > 0
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("分类 / 章节")
                    .font(MGFont.title)
                Text(selecting ? "选择模式 · 批量操作已激活" : "浏览模式 · 支持多选 / 框选")
                    .font(MGFont.micro)
                    .foregroundStyle(.secondary.opacity(0.85))
            }

            Text(selecting ? "选择中" : "浏览中")
                .mgStatusPill(tint: MGTheme.accentStrong, selected: selecting)
        }
    }

    private var chapterSelectionPill: some View {
        Text(selectedCount > 0 ? "已选 \(selectedCount) 话" : "分类 \(selectedVolumeCount) · 章节 \(selectedCount)")
            .mgStatusPill(tint: MGTheme.accentStrong, selected: selectedCount > 0 || selectedVolumeCount > 0)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private func sortPicker(width: CGFloat) -> some View {
        Picker("排序", selection: $vm.chapterSortDirection) {
            ForEach(SortDirection.allCases) { direction in
                Text(direction.rawValue).tag(direction)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: width)
    }

    private func simplifiedDownloadPanel(metrics: LayoutMetrics) -> some View {
        let counts = vm.downloader.countsSummary()
        let failures = vm.downloader.failureSummary()
        let progressSummary = vm.downloader.progressSummary()
        let hasQueue = vm.downloader.isRunning || !vm.downloader.taskItems.isEmpty
        let stateText = vm.downloader.isRunning ? "队列执行中" : (vm.downloader.taskItems.isEmpty ? "队列空闲" : "队列已暂停")
        let detailText: String = {
            if !vm.downloader.currentTaskTitle.isEmpty {
                return vm.downloader.currentTaskTitle
            }
            if let firstFailure = failures.first {
                return "\(firstFailure.reason) · \(firstFailure.count) 话"
            }
            return "排队 \(counts.queued) · 进行中 \(counts.running) · 失败 \(counts.failed) · 完成 \(counts.done)"
        }()

        return VStack(alignment: .leading, spacing: 7) {
            if metrics.isNarrow {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(stateText, systemImage: vm.downloader.isRunning ? "arrow.down.circle.fill" : "tray")
                            .font(MGFont.bodyStrong)
                            .foregroundStyle(vm.downloader.isRunning ? MGTheme.accentStrong : .secondary)
                        Spacer(minLength: 0)
                        if !vm.downloader.speedText.isEmpty {
                            Text(vm.downloader.speedText)
                                .font(MGFont.number)
                                .foregroundStyle(MGTheme.accentStrong)
                        }
                    }

                    if hasQueue {
                        HStack(spacing: 8) {
                            ProgressView(value: vm.downloader.progress)
                                .progressViewStyle(.linear)
                                .scaleEffect(y: 1.45)
                            Text("\(progressSummary.completedPages)/\(progressSummary.totalPages) 页")
                                .font(MGFont.captionStrong)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(detailText)
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        inlineStat("排队", counts.queued, tint: MGTheme.queued, suffix: "话")
                        inlineStat("失败", counts.failed, tint: MGTheme.danger, suffix: "话")
                        inlineStat("完成", counts.done, tint: MGTheme.success, suffix: "话")
                        Spacer(minLength: 0)
                        Button(action: { showDownloadManager = true }) {
                            Label("下载管理", systemImage: "list.bullet.rectangle.portrait")
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .accent))
                        Button(showLogPanel ? "隐藏日志" : "显示日志") {
                            showLogPanel.toggle()
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))
                    }
                }
            } else {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(stateText, systemImage: vm.downloader.isRunning ? "arrow.down.circle.fill" : "tray")
                            .font(MGFont.bodyStrong)
                            .foregroundStyle(vm.downloader.isRunning ? MGTheme.accentStrong : .secondary)
                        Text(detailText)
                            .font(MGFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 220, alignment: .leading)

                    inlineStat("排队", counts.queued, tint: MGTheme.queued, suffix: "话")
                    inlineStat("进行中", counts.running, tint: MGTheme.accentStrong, suffix: "话")
                    inlineStat("失败", counts.failed, tint: MGTheme.danger, suffix: "话")
                    inlineStat("完成", counts.done, tint: MGTheme.success, suffix: "话")

                    Spacer(minLength: 0)

                    if hasQueue {
                        ProgressView(value: vm.downloader.progress)
                            .progressViewStyle(.linear)
                            .scaleEffect(y: 1.35)
                            .frame(width: metrics.isWide ? 190 : 150)
                        Text("\(progressSummary.completedPages)/\(progressSummary.totalPages) 页")
                            .font(MGFont.captionStrong)
                            .foregroundStyle(.secondary)
                    }

                    if !vm.downloader.speedText.isEmpty {
                        Text(vm.downloader.speedText)
                            .font(MGFont.number)
                            .foregroundStyle(MGTheme.accentStrong)
                    }

                    Button(action: { showDownloadManager = true }) {
                        Label("下载管理", systemImage: "list.bullet.rectangle.portrait")
                    }
                    .buttonStyle(MGActionButtonStyle(variant: .accent))

                    Button(showLogPanel ? "隐藏日志" : "显示日志") {
                        showLogPanel.toggle()
                    }
                    .buttonStyle(MGActionButtonStyle(variant: .neutral))
                }
            }

            if showLogPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("只看错误", isOn: $vm.showOnlyErrorLogs)
                            .toggleStyle(.checkbox)
                            .font(MGFont.caption)
                        Spacer()
                        Button("复制最近 50 条") {
                            vm.copyRecentLogs()
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        Button("清空日志") {
                            vm.clearLogs()
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            if vm.filteredLogLines.isEmpty {
                            Text("暂无日志，加载/下载后会实时显示。")
                                .font(MGFont.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {
                                ForEach(Array(vm.filteredLogLines.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }
                    .frame(minHeight: 88, maxHeight: 128)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .mgInsetPanel(cornerRadius: 8, prominence: 0.72)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .mgPanel(cornerRadius: 10, shadow: false)
    }

    private var placeholderCover: some View {
        LinearGradient(
            colors: [Color(red: 0.52, green: 0.70, blue: 0.93), Color(red: 0.45, green: 0.80, blue: 0.90)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            VStack(spacing: 6) {
                Image(systemName: "photo")
                    .font(.system(size: 24, weight: .semibold))
                Text("封面预览")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
        )
    }

    private func color(for state: DownloadTaskItem.State) -> Color {
        switch state {
        case .queued: return Color.secondary.opacity(0.3)
        case .running: return .blue
        case .done: return .cyan
        case .canceled: return .indigo
        case .failed: return .purple
        }
    }

    private func statusText(for state: DownloadTaskItem.State) -> String {
        switch state {
        case .queued: return "排队"
        case .running: return "下载中"
        case .done: return "完成"
        case .canceled: return "已取消"
        case .failed(let reason): return "失败: \(reason)"
        }
    }

    private func updateDragSelection() {
        guard let rect = dragRect else { return }
        let hits: Set<String>
        if let startID = dragStartChapterID {
            let currentID = chapterID(at: dragCurrent ?? .zero) ?? chapterIDIntersecting(rect)
            let targetID = currentID ?? dragLastChapterID ?? startID
            dragLastChapterID = targetID
            hits = chapterRangeSelection(from: startID, to: targetID)
        } else {
            hits = Set(chapterFrames.compactMap { key, frame in
                frame.intersects(rect) ? key : nil
            })
        }
        vm.applyDragSelection(hits, additive: dragAdditive)
    }

    private func chapterID(at point: CGPoint) -> String? {
        for (id, frame) in chapterFrames where frame.contains(point) {
            return id
        }
        return nil
    }

    private func chapterIDIntersecting(_ rect: CGRect) -> String? {
        var bestID: String?
        var bestArea: CGFloat = 0
        for (id, frame) in chapterFrames {
            let area = frame.intersection(rect).area
            if area > bestArea {
                bestArea = area
                bestID = id
            }
        }
        return bestID
    }

    private func chapterRangeSelection(from startID: String, to endID: String) -> Set<String> {
        let ordered = vm.visibleChapters.map(\.id)
        guard let a = ordered.firstIndex(of: startID), let b = ordered.firstIndex(of: endID) else {
            return []
        }
        let low = min(a, b)
        let high = max(a, b)
        return Set(ordered[low...high])
    }

    private func chapterSections(metrics: LayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(vm.filteredVolumeSections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if metrics.isNarrow {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(section.volumeName)
                                    .font(MGFont.section)
                                    .foregroundStyle(.primary.opacity(0.9))

                                Text("\(section.chapterCount) 话")
                                    .mgStatusPill(tint: MGTheme.accent, selected: false)
                            }

                            HStack {
                                Text("已选 \(vm.selectedChapterCount(in: section.id)) / \(section.chapterCount)")
                                    .font(MGFont.micro)
                                    .foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Button(vm.areAllChaptersSelected(in: section.id) ? "清空本分类" : "全选本分类") {
                                    vm.toggleVolumeChapterSelection(volumeID: section.id)
                                }
                                .buttonStyle(MGActionButtonStyle(variant: .neutral))
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(section.volumeName)
                                .font(MGFont.section)
                                .foregroundStyle(.primary.opacity(0.9))

                            Text("\(section.chapterCount) 话")
                                .mgStatusPill(tint: MGTheme.accent, selected: false)

                            Text("已选 \(vm.selectedChapterCount(in: section.id)) / \(section.chapterCount)")
                                .font(MGFont.micro)
                                .foregroundStyle(.secondary)

                            Spacer(minLength: 0)

                            Button(vm.areAllChaptersSelected(in: section.id) ? "清空本分类" : "全选本分类") {
                                vm.toggleVolumeChapterSelection(volumeID: section.id)
                            }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        }
                    }

                    sectionChapterGrid(section.chapters, columns: metrics.chapterColumns)
                }
                .padding(9)
                .mgInsetPanel(cornerRadius: 10, prominence: 0.62)
            }
        }
        .padding(.top, 2)
    }

    private func sectionChapterGrid(_ chapters: [ComicChapter], columns: Int) -> some View {
        let gridColumns = Array(repeating: GridItem(.flexible(minimum: 108, maximum: 210), spacing: 6), count: max(1, columns))
        return LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 6) {
            ForEach(chapters) { chapter in
                chapterCell(chapter)
                    .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
            }
        }
    }

    private func chapterCell(_ chapter: ComicChapter) -> some View {
        ChapterChip(chapter: chapter, isSelected: vm.selectedChapterIDs.contains(chapter.id))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ChapterFrameKey.self,
                        value: [chapter.id: proxy.frame(in: .named("chapter-canvas"))]
                    )
                }
            )
            .onTapGesture {
                vm.selectChapter(chapter, modifiers: currentModifiers())
            }
    }

    private func currentModifiers() -> NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? []
    }

    private func openInBrowser(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func layoutMetrics(for width: CGFloat) -> LayoutMetrics {
        let sizeClass: LayoutSizeClass
        if width < 940 {
            sizeClass = .narrow
        } else if width < 1320 {
            sizeClass = .regular
        } else {
            sizeClass = .wide
        }
        return LayoutMetrics(sizeClass: sizeClass, width: width)
    }
}

private struct ChapterChip: View {
    let chapter: ComicChapter
    let isSelected: Bool
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? MGTheme.accentStrong : (isHovered ? MGTheme.accent : .secondary))
                    .scaleEffect(isHovered ? 1.05 : 1.0)
                Text(chapter.displayName)
                    .font(MGFont.bodyStrong)
                    .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(isHovered ? 0.96 : 0.88))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            if !chapter.volumeName.isEmpty {
                Text(chapter.volumeName)
                    .font(MGFont.micro)
                    .foregroundStyle(.secondary.opacity(isSelected ? 0.65 : 0.5))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(MGTheme.accentSoft.opacity(colorScheme == .dark ? 0.22 : (isHovered ? 0.72 : 0.58)))
                        : AnyShapeStyle(MGTheme.insetFill(for: colorScheme, prominence: isHovered ? 1.0 : 0.56))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(
                    isSelected ? MGTheme.accentStrong.opacity(isHovered ? 0.66 : 0.45) : MGTheme.stroke(for: colorScheme, prominence: isHovered ? 0.72 : 0.38),
                    lineWidth: 0.8
                )
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? MGTheme.accentStrong : MGTheme.accent.opacity(isHovered ? 0.48 : 0))
                .frame(width: 3)
                .padding(.vertical, 4)
        }
        .scaleEffect(isHovered ? 1.006 : 1.0)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension CGRect {
    var area: CGFloat {
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }
}

struct BrandMarkView: View {
    let size: CGFloat
    var elevated = false

    var body: some View {
        Image(nsImage: brandNSImage())
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(size * 0.12)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color.white.opacity(elevated ? 0.74 : 0.62))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(Color.white.opacity(0.56), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(elevated ? 0.08 : 0.05), radius: elevated ? 10 : 6, y: elevated ? 5 : 3)
    }
}
