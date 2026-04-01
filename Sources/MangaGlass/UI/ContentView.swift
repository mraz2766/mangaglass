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
    private enum DragAxisLock {
        case horizontal
        case vertical
    }

    @StateObject private var vm = MainViewModel()
    @State private var chapterFrames: [String: CGRect] = [:]
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var dragAdditive = false
    @State private var dragStartChapterID: String?
    @State private var dragAxisLock: DragAxisLock?
    @State private var showLogPanel = false
    @State private var animateBackground = false
    @State private var expandComicTitle = false
    @State private var showDownloadManager = false
    @State private var showAdvancedSettings = false
    @Environment(\.colorScheme) private var colorScheme

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
            let compact = proxy.size.width < 1000

            ZStack {
                background

                VStack(spacing: 12) {
                    toolbar(compact: compact)

                    Group {
                        if compact {
                            VStack(spacing: 12) {
                                sidePanel(compact: compact)
                                chapterPanel(compact: compact)
                            }
                        } else {
                            HStack(alignment: .top, spacing: 12) {
                                sidePanel(compact: compact)
                                chapterPanel(compact: compact)
                            }
                        }
                    }
                    .layoutPriority(1)

                    simplifiedDownloadPanel
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 840, minHeight: 600)
    }

    private var background: some View {
        ZStack {
            let gradientColors = colorScheme == .dark 
                ? [Color(red: 0.09, green: 0.10, blue: 0.12), Color(red: 0.05, green: 0.06, blue: 0.08)]
                : [Color(red: 0.97, green: 0.98, blue: 0.99), Color(red: 0.93, green: 0.95, blue: 0.98)]
            
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            GeometryReader { proxy in
                Circle()
                    .fill(Color(red: 0.49, green: 0.75, blue: 0.93).opacity(0.18))
                    .blur(radius: 90)
                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
                    .position(x: proxy.size.width * 0.2, y: proxy.size.height * 0.3)
                    .offset(x: animateBackground ? 30 : -30, y: animateBackground ? 20 : -20)
                
                Circle()
                    .fill(Color(red: 0.68, green: 0.83, blue: 0.94).opacity(0.12))
                    .blur(radius: 90)
                    .frame(width: proxy.size.width * 0.3, height: proxy.size.width * 0.3)
                    .position(x: proxy.size.width * 0.8, y: proxy.size.height * 0.7)
                    .offset(x: animateBackground ? -40 : 40, y: animateBackground ? -30 : 30)
                    .scaleEffect(animateBackground ? 1.1 : 0.9)
            }
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
                    animateBackground.toggle()
                }
            }
        }
    }

    private func toolbar(compact: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                toolbarIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
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
                    Text("输入链接、解析目录、批量下载")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.trailing, 4)

                Menu("拷贝漫画") {
                    ForEach(CopyMangaMirror.allCases) { mirror in
                        Button(mirror.displayName) {
                            openInBrowser(mirror.webBaseURL.absoluteString)
                        }
                    }
                }
                .buttonStyle(ActionButtonStyle(variant: .ghost))

                Button("漫画柜") {
                    openInBrowser("https://www.manhuagui.com")
                }
                .buttonStyle(ActionButtonStyle(variant: .ghost))

                TextField("输入漫画链接或 path_word", text: $vm.inputURL)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .frame(maxWidth: compact ? .infinity : 540)
                    .submitLabel(.go)
                    .onSubmit {
                        vm.loadComic()
                    }

                Button(vm.isLoading ? "加载中" : "加载") {
                    vm.loadComic()
                }
                .buttonStyle(ActionButtonStyle(variant: .primary))
                .disabled(vm.isLoading)
                .keyboardShortcut(.defaultAction)
            }

            HStack(spacing: 8) {
                Button("选择目录") {
                    vm.chooseDestination()
                }
                .buttonStyle(ActionButtonStyle(variant: .neutral))

                Text(vm.destinationFolder.path)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !compact {
                    Spacer(minLength: 0)
                }

                if !vm.recentRecords.isEmpty {
                    Menu("最近打开") {
                        ForEach(vm.recentRecords) { record in
                            Button("\(record.title) · \(record.siteName)") {
                                vm.applyRecentRecord(record)
                            }
                        }
                    }
                    .buttonStyle(ActionButtonStyle(variant: .neutral))
                }

                parseStatusChip

                Button("加入队列") {
                    vm.startDownload()
                }
                .buttonStyle(ActionButtonStyle(variant: .accent))
                .disabled(vm.comic == nil && vm.downloader.taskItems.isEmpty)
            }
        }
        .padding(10)
        .quietCard()
        .sheet(isPresented: $showDownloadManager) {
            DownloadManagerView(vm: vm)
        }
    }

    @ViewBuilder
    private func sidePanel(compact: Bool) -> some View {
        if compact {
            HStack(alignment: .top, spacing: 16) {
                coverView
                    .frame(width: 126, height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                ScrollView(showsIndicators: false) {
                    detailsColumn(compact: compact)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .quietCard()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                coverView
                    .frame(height: 210)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                ScrollView(showsIndicators: false) {
                    detailsColumn(compact: compact)
                }
                
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 300)
            .quietCard()
        }
    }

    private func detailsColumn(compact: Bool) -> some View {
        let comicName = vm.comic?.name ?? "未加载漫画"
        let titleIsLong = vm.comic != nil && comicName.count > 20

        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(comicName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(expandComicTitle ? nil : 1)
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
                        .buttonStyle(ActionButtonStyle(variant: .neutral))

                        Text(expandComicTitle ? "已展开" : "已折叠")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(vm.statusText)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(3)
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
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                    }
                }
            }

            statRow

            infoSection
            formSection
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

    private var statRow: some View {
        HStack(spacing: 8) {
            statItem("已选分类", "\(selectedVolumeCount)")
            statItem("已选章节", "\(selectedCount)")
            statItem("失败", "\(failedCount)")
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("漫画信息")
            statusLine("站点", vm.comic?.site.displayName ?? "尚未解析")
            statusLine("分类 / 章节", vm.comic == nil ? "等待加载" : "\(vm.displayVolumes.count) / \(vm.totalChapterCount)")
            statusLine("目录", vm.destinationFolder.path, multiline: true)
            statusLine("Cookie", vm.authCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未填写" : "已填写")
            statusLine("代理", proxySummaryText)
        }
        .padding(10)
        .glassInsetCard()
    }

    private var proxySummaryText: String {
        if vm.proxyType == .none {
            return "未启用"
        }
        let host = vm.proxyHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = vm.proxyPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if host.isEmpty || port.isEmpty {
            return "\(vm.proxyType.displayName)（待补全）"
        }
        return "\(vm.proxyType.displayName) \(host):\(port)"
    }

    private func statItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.20, green: 0.55, blue: 0.80))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.20, green: 0.55, blue: 0.80).opacity(0.12), in: Capsule())
            } else if vm.isLoading, !vm.parseLiveText.isEmpty {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text(vm.parseLiveText)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.30, green: 0.60, blue: 0.90))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(red: 0.30, green: 0.60, blue: 0.90).opacity(0.12), in: Capsule())
            }
        }
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

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                withAnimation { showAdvancedSettings.toggle() }
            }) {
                HStack(spacing: 4) {
                    Text("认证与代理设定")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Image(systemName: showAdvancedSettings ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if showAdvancedSettings {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Cookie（可选）", text: $vm.authCookie)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, weight: .medium, design: .rounded))

                    Picker("代理", selection: $vm.proxyType) {
                        ForEach(ProxyType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if vm.proxyType != .none {
                        HStack(spacing: 8) {
                            TextField("主机", text: $vm.proxyHost)
                                .textFieldStyle(.roundedBorder)
                            TextField("端口", text: $vm.proxyPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 86)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))

                        HStack(spacing: 8) {
                            TextField("用户名", text: $vm.proxyUsername)
                                .textFieldStyle(.roundedBorder)
                            SecureField("密码", text: $vm.proxyPassword)
                                .textFieldStyle(.roundedBorder)
                        }
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                }
                .padding(10)
                .glassInsetCard()
            }
        }
    }

    private var volumeSelectionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("分类选择")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Button("全选") {
                    vm.selectAllVolumes()
                }
                .buttonStyle(ActionButtonStyle(variant: .neutral))
                Button("清空") {
                    vm.deselectAllVolumes()
                }
                .buttonStyle(ActionButtonStyle(variant: .neutral))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.displayVolumes) { volume in
                        Button {
                            vm.toggleVolume(volume.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: vm.selectedVolumeIDs.contains(volume.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(vm.selectedVolumeIDs.contains(volume.id) ? .blue : .secondary)
                                Text(volume.displayName)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .lineLimit(1)
                                Text("\(volume.chapters.count)")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(vm.selectedVolumeIDs.contains(volume.id) ? AnyShapeStyle(Color(red: 0.70, green: 0.84, blue: 0.94).opacity(0.42)) : AnyShapeStyle(Color.white.opacity(0.32)))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(vm.selectedVolumeIDs.contains(volume.id) ? Color(red: 0.40, green: 0.58, blue: 0.74).opacity(0.55) : Color.white.opacity(0.38), lineWidth: 0.9)
                            )
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
            Image(systemName: systemImage)
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func chapterPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分类 / 章节")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("按分组浏览章节，支持多选、⌘/⇧ 范围选择与拖拽框选")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer()

                Text("分类 \(selectedVolumeCount) · 章节 \(selectedCount)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.12), in: Capsule())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Picker("排序", selection: $vm.chapterSortDirection) {
                    ForEach(SortDirection.allCases) { direction in
                        Text(direction.rawValue).tag(direction)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 120)

                Button("全选") { vm.selectAllVisible() }
                    .buttonStyle(ActionButtonStyle(variant: .neutral))
                Button("清空") { vm.deselectAllVisible() }
                    .buttonStyle(ActionButtonStyle(variant: .neutral))
            }

            volumeSelectionStrip

            Divider().opacity(0.45)

            if let emptyState = emptyStateContent {
                emptyStateCard(title: emptyState.title, detail: emptyState.detail, systemImage: emptyState.systemImage)
            } else {
                ScrollView {
                    chapterSections(compact: compact)
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
                            }
                            if let start = dragStart, dragAxisLock == nil {
                                let dx = abs(value.location.x - start.x)
                                let dy = abs(value.location.y - start.y)
                                if dx > 12 || dy > 12 {
                                    dragAxisLock = dy >= dx ? .vertical : .horizontal
                                }
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
                            dragAxisLock = nil
                        }
                )
                .overlay(DragRectOverlay(rect: dragRect))
                .onPreferenceChange(ChapterFrameKey.self) { frames in
                    chapterFrames = frames
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .quietCard()
    }

    private var simplifiedDownloadPanel: some View {
        let counts = vm.downloader.countsSummary()
        let failures = vm.downloader.failureSummary()

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("下载摘要")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()

                if vm.downloader.isRunning || !vm.downloader.taskItems.isEmpty {
                    ProgressView(value: vm.downloader.progress)
                        .progressViewStyle(.linear)
                        .frame(width: 150)
                    Text("\(Int(vm.downloader.progress * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 8)
                }

                if !vm.downloader.speedText.isEmpty {
                    Text(vm.downloader.speedText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Button(action: { showDownloadManager = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                        Text("下载管理")
                    }
                }
                .buttonStyle(ActionButtonStyle(variant: .accent))

                Button(showLogPanel ? "隐藏日志" : "显示日志") {
                    showLogPanel.toggle()
                }
                .buttonStyle(ActionButtonStyle(variant: .neutral))
            }

            HStack(spacing: 8) {
                queueStat("进行中", counts.running, tint: .blue)
                queueStat("排队", counts.queued, tint: .secondary)
                queueStat("失败", counts.failed, tint: .red)
                queueStat("完成", counts.done, tint: .green)
            }

            if !vm.downloader.currentTaskTitle.isEmpty || !failures.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !vm.downloader.currentTaskTitle.isEmpty {
                        statusLine("当前任务", vm.downloader.currentTaskTitle, multiline: true)
                    }
                    if let firstFailure = failures.first {
                        statusLine("失败概览", "\(firstFailure.reason) · \(firstFailure.count) 话")
                    }
                }
                .padding(10)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if showLogPanel {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Toggle("只看错误", isOn: $vm.showOnlyErrorLogs)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                        Spacer()
                        Button("复制最近 50 条") {
                            vm.copyRecentLogs()
                        }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                        Button("清空日志") {
                            vm.clearLogs()
                        }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            if vm.filteredLogLines.isEmpty {
                            Text("暂无日志，加载/下载后会实时显示。")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
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
                    .frame(minHeight: 120, maxHeight: 180)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
        .padding(10)
        .quietCard()
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
        if let startID = dragStartChapterID,
           let current = dragCurrent,
           let currentID = chapterID(at: current) ?? nearestChapterID(to: current, preferVertical: dragAxisLock == .vertical) {
            hits = chapterRangeSelection(from: startID, to: currentID)
        } else {
            let yRangeHits = Set(chapterFrames.compactMap { key, frame in
                (frame.maxY >= rect.minY && frame.minY <= rect.maxY) ? key : nil
            })
            let directHits = Set(chapterFrames.compactMap { key, frame in
                frame.intersects(rect) ? key : nil
            })
            hits = yRangeHits.union(directHits)
        }
        vm.applyDragSelection(hits, additive: dragAdditive)
    }

    private func chapterID(at point: CGPoint) -> String? {
        for (id, frame) in chapterFrames where frame.contains(point) {
            return id
        }
        return nil
    }

    private func nearestChapterID(to point: CGPoint, preferVertical: Bool) -> String? {
        var bestID: String?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (id, frame) in chapterFrames {
            let dy = abs(frame.midY - point.y)
            let dxWeight: CGFloat = preferVertical ? 0.04 : 0.2
            let dx = abs(frame.midX - point.x) * dxWeight
            let distance = dy + dx
            if distance < bestDistance {
                bestDistance = distance
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

    private func chapterSections(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(vm.filteredVolumeSections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(section.volumeName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary.opacity(0.9))

                        Text("\(section.chapterCount) 话")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(red: 0.31, green: 0.49, blue: 0.64))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.55), in: Capsule())

                        Spacer(minLength: 0)

                        Button(vm.areAllChaptersSelected(in: section.id) ? "清空本分类" : "全选本分类") {
                            vm.toggleVolumeChapterSelection(volumeID: section.id)
                        }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                    }

                    Text("已选 \(vm.selectedChapterCount(in: section.id)) / \(section.chapterCount)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)

                    sectionChapterGrid(section.chapters, compact: compact)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.32))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
                )
            }
        }
        .padding(2)
    }

    private func sectionChapterGrid(_ chapters: [ComicChapter], compact: Bool) -> some View {
        let columns = compact ? 2 : 3
        let rows = chunked(chapters, size: columns)
        return VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                let row = rows[rowIndex]
                HStack(spacing: 8) {
                    ForEach(row) { chapter in
                        chapterCell(chapter)
                            .transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .opacity))
                    }
                    if row.count < columns {
                        ForEach(0..<(columns - row.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(2)
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

    private func chunked(_ source: [ComicChapter], size: Int) -> [[ComicChapter]] {
        guard size > 0 else { return [source] }
        var result: [[ComicChapter]] = []
        result.reserveCapacity((source.count + size - 1) / size)
        var idx = 0
        while idx < source.count {
            let end = min(source.count, idx + size)
            result.append(Array(source[idx..<end]))
            idx = end
        }
        return result
    }

    private func currentModifiers() -> NSEvent.ModifierFlags {
        NSApp.currentEvent?.modifierFlags ?? []
    }

    private func openInBrowser(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct ChapterChip: View {
    let chapter: ComicChapter
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(red: 0.34, green: 0.55, blue: 0.73) : .secondary)
                Text(chapter.displayName)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(chapter.volumeName)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isSelected
                        ? AnyShapeStyle(Color(red: 0.77, green: 0.88, blue: 0.96).opacity(isHovered ? 0.78 : 0.58))
                        : AnyShapeStyle(Color.white.opacity(isHovered ? 0.48 : 0.34))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isSelected ? Color(red: 0.42, green: 0.60, blue: 0.76).opacity(0.58) : Color.white.opacity(isHovered ? 0.42 : 0.28),
                    lineWidth: 0.9
                )
        )
        .shadow(color: Color.black.opacity(isSelected ? 0.06 : 0.03), radius: isHovered ? 12 : 7, y: isHovered ? 8 : 4)
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
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

enum ActionVariant {
    case primary
    case accent
    case danger
    case neutral
    case ghost
}

struct ActionButtonStyle: ButtonStyle {
    let variant: ActionVariant
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(foreground)
            .background(background(configuration.isPressed, hovered: isHovered), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovered = hovering
                }
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var foreground: Color {
        switch variant {
        case .neutral, .ghost:
            return Color.primary.opacity(0.8)
        default:
            return .white
        }
    }

    private func background(_ pressed: Bool, hovered: Bool) -> Color {
        switch variant {
        case .primary:
            return pressed ? Color(red: 0.17, green: 0.50, blue: 0.90) : Color(red: 0.21, green: 0.56, blue: 0.95)
        case .accent:
            return pressed ? Color(red: 0.25, green: 0.65, blue: 0.85) : Color(red: 0.32, green: 0.72, blue: 0.92)
        case .danger:
            return pressed ? Color(red: 0.40, green: 0.50, blue: 0.85) : Color(red: 0.48, green: 0.58, blue: 0.92)
        case .neutral:
            return pressed ? Color.gray.opacity(0.3) : (hovered ? Color.gray.opacity(0.22) : Color.gray.opacity(0.15))
        case .ghost:
            return pressed ? Color.gray.opacity(0.15) : (hovered ? Color.gray.opacity(0.1) : Color.clear)
        }
    }
}

private extension View {
    func quietCard() -> some View {
        self
            .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 18, x: 0, y: 10)
    }

    func glassInsetCard() -> some View {
        self
            .background(Color.white.opacity(0.20), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
            )
    }
}
