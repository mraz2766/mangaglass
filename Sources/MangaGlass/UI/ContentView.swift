import AppKit
import SwiftUI

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
        Image(nsImage: NSApp.applicationIconImage)
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
                : [Color(red: 0.95, green: 0.97, blue: 0.99), Color(red: 0.91, green: 0.94, blue: 0.98)]
            
            LinearGradient(
                colors: gradientColors,
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            GeometryReader { proxy in
                Circle()
                    .fill(Color(red: 0.35, green: 0.85, blue: 1.0).opacity(0.25))
                    .blur(radius: 60)
                    .frame(width: proxy.size.width * 0.4, height: proxy.size.width * 0.4)
                    .position(x: proxy.size.width * 0.2, y: proxy.size.height * 0.3)
                    .offset(x: animateBackground ? 30 : -30, y: animateBackground ? 20 : -20)
                
                Circle()
                    .fill(Color(red: 0.45, green: 0.75, blue: 0.95).opacity(0.15))
                    .blur(radius: 60)
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
        HStack(spacing: 8) {
            toolbarIcon
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: Color.black.opacity(0.1), radius: 2, y: 1)

            Text("MangaGlass")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)

            Menu {
                ForEach(CopyMangaMirror.allCases) { mirror in
                    Button(mirror.displayName) {
                        openInBrowser(mirror.webBaseURL.absoluteString)
                    }
                }
            } label: {
                Text("拷贝漫画")
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

            Button("目录") {
                vm.chooseDestination()
            }
            .buttonStyle(ActionButtonStyle(variant: .neutral))

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

            if !compact {
                Spacer(minLength: 0)
            }

            Button("加入队列") {
                vm.startDownload()
            }
            .buttonStyle(ActionButtonStyle(variant: .accent))
            .disabled(vm.comic == nil && vm.downloader.taskItems.isEmpty)
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
                    .frame(width: 140, height: 200)
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
                    .frame(height: 260)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                ScrollView(showsIndicators: false) {
                    detailsColumn(compact: compact)
                }
                
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: 320)
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
                Text(vm.errorText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.indigo)
            }

            statRow

            formSection

            Text("目录：\(vm.destinationFolder.path)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
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
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                                    .fill(vm.selectedVolumeIDs.contains(volume.id) ? AnyShapeStyle(Color.blue.opacity(0.15)) : AnyShapeStyle(.regularMaterial))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(vm.selectedVolumeIDs.contains(volume.id) ? Color.blue.opacity(0.5) : Color.black.opacity(0.05), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func chapterPanel(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("分类 / 章节")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Text("分类独立选择，支持多选、⌘/⇧ 范围选择与拖拽框选")
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

            if vm.visibleChapters.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text("暂无可显示话")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text("先加载漫画，或先选择至少一个分类")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                ScrollView {
                    chapterGrid(compact: compact)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("实时日志")
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

            if showLogPanel {
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        if vm.logLines.isEmpty {
                            Text("暂无日志，加载/下载后会实时显示。")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(Array(vm.logLines.enumerated()), id: \.offset) { _, line in
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

    private func chapterGrid(compact: Bool) -> some View {
        let columns = compact ? 2 : 3
        let rows = chunked(vm.visibleChapters, size: columns)
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
                    .foregroundStyle(isSelected ? .blue : .secondary)
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
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.blue.opacity(isHovered ? 0.2 : 0.14)) : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.blue.opacity(0.55) : Color.primary.opacity(isHovered ? 0.15 : 0.05), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
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
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 6)
    }
}
