import SwiftUI

struct DownloadManagerView: View {
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
        var padding: CGFloat {
            switch sizeClass {
            case .narrow: return 6
            case .regular: return 8
            case .wide: return 10
            }
        }
        var rowSpacing: CGFloat {
            switch sizeClass {
            case .narrow: return 4
            case .regular: return 5
            case .wide: return 6
            }
        }
        var footerTaskWidth: CGFloat {
            switch sizeClass {
            case .narrow: return 180
            case .regular: return 240
            case .wide: return 320
            }
        }
    }

    @ObservedObject var vm: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var filter: FilterType = .all
    @State private var isFloating = false
    @State private var expandedTaskID: UUID?

    enum FilterType: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "进行中"
        case queued = "排队"
        case done = "已完成"
        case failed = "失败"

        var id: String { rawValue }
    }

    var filteredItems: [DownloadTaskItem] {
        vm.downloader.taskItems.filter { item in
            switch filter {
            case .all: return true
            case .active: return item.state == .running
            case .queued: return item.state == .queued
            case .done: return item.state == .done
            case .failed:
                if case .failed = item.state { return true }
                if case .canceled = item.state { return true }
                return false
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = layoutMetrics(for: proxy.size.width)

            VStack(spacing: metrics.rowSpacing) {
                header(metrics: metrics)
                controlBar(metrics: metrics)
                listContent(metrics: metrics)
                progressFooter(metrics: metrics)
            }
            .padding(metrics.padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(downloadManagerBackground)
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private func header(metrics: LayoutMetrics) -> some View {
        let progressSummary = vm.downloader.progressSummary()
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("下载控制台")
                        .font(MGFont.title)

                    Text(headerSubtitle)
                        .mgStatusPill(tint: MGTheme.accent, selected: vm.downloader.isRunning)
                }

                HStack(spacing: 8) {
                    summaryPill("进行中", count(for: .active), tint: MGTheme.accentStrong)
                    summaryPill("失败", count(for: .failed), tint: MGTheme.danger)
                    summaryPill("完成", count(for: .done), tint: MGTheme.success)
                    Text("页进度 \(progressSummary.completedPages)/\(progressSummary.totalPages)")
                        .mgStatusPill()
                }
            }

            Spacer()

            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(MGTheme.insetFill(for: colorScheme), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .mgPanel(cornerRadius: 12, prominence: 0.92)
    }

    private func controlBar(metrics: LayoutMetrics) -> some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterType.allCases) { type in
                        Button(action: { filter = type }) {
                            HStack(spacing: 5) {
                                Text(type.rawValue)
                                    .font(MGFont.microStrong)
                                Text("\(count(for: type))")
                                    .font(MGFont.microStrong)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(filter == type ? Color.white.opacity(0.24) : MGTheme.insetFill(for: colorScheme, prominence: 0.7), in: Capsule())
                            }
                            .foregroundStyle(filter == type ? .white : .primary.opacity(0.78))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(filter == type ? AnyShapeStyle(MGTheme.accentStrong) : AnyShapeStyle(MGTheme.insetFill(for: colorScheme, prominence: 0.65)))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if !metrics.isNarrow {
                        summaryPill("总计", count(for: .all), tint: MGTheme.queued)
                    }

                    if vm.downloader.isRunning {
                        Button("暂停所有") { vm.pauseDownload() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                            .disabled(vm.downloader.isPaused)

                        Button("继续下载") { vm.resumeDownload() }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                            .disabled(!vm.downloader.isPaused)
                    }

                    Button("清空完成") { vm.clearCompletedTasks() }
                        .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        .disabled(vm.downloader.taskItems.allSatisfy { $0.state != .done })

                    if count(for: .failed) > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                            Text("失败 \(count(for: .failed))")
                        }
                        .font(MGFont.microStrong)
                        .foregroundStyle(MGTheme.danger)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(MGTheme.danger.opacity(colorScheme == .dark ? 0.20 : 0.10), in: Capsule())
                    }

                    Menu {
                        Button("开始/继续") { vm.startDownload() }
                            .disabled(vm.downloader.taskItems.filter { $0.state == .queued }.isEmpty)

                        Button("取消所有") { vm.cancelDownload() }
                            .disabled(!vm.downloader.isRunning)

                        Divider()

                        Button("重试失败") { vm.retryFailed() }
                            .disabled(vm.downloader.failedItems().isEmpty)

                        Button("清空所有") { vm.clearQueue() }
                            .disabled(vm.downloader.isRunning)

                        Divider()

                        Button("打开下载目录") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.destinationFolder.path)
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .mgPanel(cornerRadius: 10, prominence: 0.78, shadow: false)
    }

    private func summaryPill(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(MGFont.micro)
                .foregroundStyle(.secondary)
            Text("\(value)话")
                .font(MGFont.captionStrong)
                .foregroundStyle(tint)
        }
        .mgStatusPill(tint: tint, selected: false)
    }

    private func listContent(metrics: LayoutMetrics) -> some View {
        ScrollView {
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(Color(red: 0.59, green: 0.66, blue: 0.76))
                        .offset(y: isFloating ? -5 : 4)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                isFloating.toggle()
                            }
                        }
                    Text("无匹配任务")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("当前筛选下还没有任务，开始下载后会在这里看到完整队列。")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 72)
            } else {
                LazyVStack(spacing: metrics.rowSpacing) {
                    ForEach(filteredItems) { item in
                        taskRow(for: item, metrics: metrics)
                    }
                }
                .padding(6)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .mgPanel(cornerRadius: 12, prominence: 0.72, shadow: false)
    }

    private func taskRow(for item: DownloadTaskItem, metrics: LayoutMetrics) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statusColor(for: item.state).opacity(0.88))
                .frame(width: 6)
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: metrics.isNarrow ? 8 : 10) {
                    Circle()
                        .fill(statusColor(for: item.state))
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor(for: item.state).opacity(0.22), radius: 3)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(item.comic.name)
                                .font(MGFont.bodyStrong)
                                .foregroundStyle(.primary.opacity(0.92))
                                .lineLimit(1)

                            Text(primaryStatusText(for: item.state))
                                .font(MGFont.microStrong)
                                .foregroundStyle(statusColor(for: item.state))
                                .lineLimit(1)
                        }

                        Text(item.chapter.displayName)
                            .font(MGFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    HStack(spacing: 6) {
                        if item.state == .queued || item.state == .running {
                            Button(action: {
                                vm.cancelItem(item)
                            }) {
                                Image(systemName: "xmark.circle")
                            }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        } else if case .failed = item.state {
                            Button(action: {
                                vm.retryItem(item)
                            }) {
                                Image(systemName: "arrow.clockwise.circle")
                            }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        }

                        if shouldShowDetailsToggle(for: item) {
                            Button(action: {
                                expandedTaskID = expandedTaskID == item.id ? nil : item.id
                            }) {
                                Image(systemName: expandedTaskID == item.id ? "chevron.up.circle" : "ellipsis.circle")
                            }
                            .buttonStyle(MGActionButtonStyle(variant: .neutral))
                        }
                    }
                }

                if expandedTaskID == item.id {
                    Divider()
                        .overlay(Color.white.opacity(0.26))

                    VStack(alignment: .leading, spacing: 4) {
                        if let reason = failureReason(for: item.state) {
                            Text(reason)
                                .font(MGFont.micro)
                                .foregroundStyle(MGTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.leading, 18)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, metrics.isNarrow ? 5 : 6)
        }
        .background(taskBackground(for: item.state), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MGTheme.stroke(for: colorScheme, prominence: 0.50), lineWidth: 0.8)
        )
    }

    private func progressFooter(metrics: LayoutMetrics) -> some View {
        let progressSummary = vm.downloader.progressSummary()
        return HStack(spacing: 10) {
            Text(vm.downloader.message)
                .font(MGFont.micro)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if !vm.downloader.currentTaskTitle.isEmpty {
                Text(vm.downloader.currentTaskTitle)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: metrics.footerTaskWidth, alignment: .leading)
            }

            Spacer(minLength: 0)

            Text("已下载 \(progressSummary.completedPages)/\(progressSummary.totalPages) 页 · 完成 \(progressSummary.completedTasks)/\(progressSummary.totalTasks) 话")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            ProgressView(value: vm.downloader.progress)
                .progressViewStyle(.linear)
                .frame(maxWidth: metrics.isNarrow ? 120 : 180)

            if !vm.downloader.speedText.isEmpty {
                Text(vm.downloader.speedText)
                    .font(MGFont.number)
                    .foregroundStyle(MGTheme.accentStrong)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .mgPanel(cornerRadius: 10, prominence: 0.78, shadow: false)
    }

    private var headerSubtitle: String {
        let summary = vm.downloader.progressSummary()
        if vm.downloader.isRunning {
            return "队列执行中 · 已完成 \(summary.completedTasks)/\(summary.totalTasks) 话"
        }
        if vm.downloader.taskItems.isEmpty {
            return "队列空闲中"
        }
        return "当前有 \(summary.totalTasks) 话待管理"
    }

    private var downloadManagerBackground: some View {
        ZStack {
            MGTheme.appBackground(for: colorScheme)
            LinearGradient(
                colors: [MGTheme.accent.opacity(colorScheme == .dark ? 0.10 : 0.07), .clear],
                startPoint: .topLeading,
                endPoint: .center
            )
        }
        .ignoresSafeArea()
    }

    private func taskBackground(for state: DownloadTaskItem.State) -> some ShapeStyle {
        AnyShapeStyle(MGTheme.statusFill(for: state, scheme: colorScheme))
    }

    private func count(for type: FilterType) -> Int {
        vm.downloader.taskItems.filter { item in
            switch type {
            case .all: return true
            case .active: return item.state == .running
            case .queued: return item.state == .queued
            case .done: return item.state == .done
            case .failed:
                if case .failed = item.state { return true }
                if case .canceled = item.state { return true }
                return false
            }
        }.count
    }

    private func statusColor(for state: DownloadTaskItem.State) -> Color {
        MGTheme.statusColor(for: state)
    }

    private func statusString(for state: DownloadTaskItem.State) -> String {
        switch state {
            case .queued: return "排队中"
            case .running: return "下载中"
            case .done: return "已完成"
            case .canceled: return "已取消"
            case .failed(let msg): return "失败 (\(msg))"
        }
    }

    private func primaryStatusText(for state: DownloadTaskItem.State) -> String {
        switch state {
        case .queued: return "排队中"
        case .running: return "下载中"
        case .done: return "已完成"
        case .canceled: return "已取消"
        case .failed: return "失败"
        }
    }

    private func failureReason(for state: DownloadTaskItem.State) -> String? {
        guard case .failed(let message) = state else { return nil }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldShowDetailsToggle(for item: DownloadTaskItem) -> Bool {
        failureReason(for: item.state) != nil
    }

    private func layoutMetrics(for width: CGFloat) -> LayoutMetrics {
        let sizeClass: LayoutSizeClass
        if width < 760 {
            sizeClass = .narrow
        } else if width < 1120 {
            sizeClass = .regular
        } else {
            sizeClass = .wide
        }
        return LayoutMetrics(sizeClass: sizeClass, width: width)
    }
}
