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
            case .narrow: return 8
            case .regular: return 10
            case .wide: return 12
            }
        }
        var rowSpacing: CGFloat {
            switch sizeClass {
            case .narrow: return 6
            case .regular: return 7
            case .wide: return 8
            }
        }
        var headerIconSize: CGFloat {
            switch sizeClass {
            case .narrow: return 32
            case .regular: return 36
            case .wide: return 40
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

    @State private var filter: FilterType = .all
    @State private var isFloating = false

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
        HStack {
            HStack(spacing: 12) {
                BrandMarkView(size: metrics.headerIconSize, elevated: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("下载管理")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    Text(headerSubtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            
            Spacer()
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1), in: Circle())
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 18, fillOpacity: 0.30)
    }

    private func controlBar(metrics: LayoutMetrics) -> some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FilterType.allCases) { type in
                        Button(action: { filter = type }) {
                            HStack(spacing: 6) {
                                Text(type.rawValue)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Text("\(count(for: type))")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(filter == type ? Color.white.opacity(0.24) : Color.black.opacity(0.04), in: Capsule())
                            }
                            .foregroundStyle(filter == type ? .white : .primary.opacity(0.78))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(filter == type ? AnyShapeStyle(Color(red: 0.44, green: 0.62, blue: 0.78)) : AnyShapeStyle(Color.white.opacity(0.18)))
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if metrics.isWide {
                        Spacer(minLength: 8)
                    }

                    if !metrics.isNarrow {
                        summaryPill("全部", count(for: .all), tint: Color(red: 0.38, green: 0.52, blue: 0.67))
                        summaryPill("进行中", count(for: .active), tint: .blue)
                        summaryPill("失败", count(for: .failed), tint: Color(red: 0.78, green: 0.39, blue: 0.30))
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if vm.downloader.isRunning {
                        Button("暂停所有") { vm.pauseDownload() }
                            .buttonStyle(ActionButtonStyle(variant: .neutral))
                            .disabled(vm.downloader.isPaused)

                        Button("继续下载") { vm.resumeDownload() }
                            .buttonStyle(ActionButtonStyle(variant: .neutral))
                            .disabled(!vm.downloader.isPaused)
                    } else {
                        Button("开始/继续") { vm.startDownload() }
                            .buttonStyle(ActionButtonStyle(variant: .accent))
                            .disabled(vm.downloader.taskItems.filter { $0.state == .queued }.isEmpty)
                    }

                    Button("取消所有") { vm.cancelDownload() }
                        .buttonStyle(ActionButtonStyle(variant: .danger))
                        .disabled(!vm.downloader.isRunning)

                    Button("重试失败") { vm.retryFailed() }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                        .disabled(vm.downloader.failedItems().isEmpty)

                    Button("清空完成") { vm.clearCompletedTasks() }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                        .disabled(vm.downloader.taskItems.allSatisfy { $0.state != .done })

                    Button("清空所有") { vm.clearQueue() }
                        .buttonStyle(ActionButtonStyle(variant: .danger))
                        .disabled(vm.downloader.isRunning)

                    if let firstFailure = vm.downloader.failureSummary().first {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle")
                            Text("\(firstFailure.reason) \(firstFailure.count)")
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(red: 0.56, green: 0.29, blue: 0.22))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.98, green: 0.92, blue: 0.88), in: Capsule())
                    }

                    Button("打开下载目录") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.destinationFolder.path)
                    }
                    .buttonStyle(ActionButtonStyle(variant: .neutral))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPanel(cornerRadius: 16, fillOpacity: 0.18)
    }

    private func summaryPill(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.22), in: Capsule())
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
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassPanel(cornerRadius: 18, fillOpacity: 0.16)
    }

    private func taskRow(for item: DownloadTaskItem, metrics: LayoutMetrics) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(statusColor(for: item.state).opacity(0.88))
                .frame(width: 6)
                .padding(.vertical, 8)

            HStack(spacing: metrics.isNarrow ? 10 : 14) {
                Circle()
                    .fill(statusColor(for: item.state))
                    .frame(width: 9, height: 9)
                    .shadow(color: statusColor(for: item.state).opacity(0.28), radius: 4)

                VStack(alignment: .leading, spacing: 4) {
                    if metrics.isNarrow {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(item.comic.name)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(.primary.opacity(0.92))
                                    .lineLimit(1)

                                Text(statusString(for: item.state))
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(statusColor(for: item.state))
                                    .lineLimit(1)
                            }

                            Text(item.chapter.displayName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Text(item.comic.name)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.primary.opacity(0.92))
                                .lineLimit(1)

                            Text(statusString(for: item.state))
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(statusColor(for: item.state))
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(item.chapter.volumeName)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color(red: 0.38, green: 0.54, blue: 0.68))
                                .lineLimit(1)

                            Text("·")
                                .foregroundStyle(.secondary)

                            Text(item.chapter.displayName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if item.state == .queued || item.state == .running {
                        Button(action: {
                            vm.cancelItem(item)
                        }) {
                            Label("取消", systemImage: "xmark.circle")
                        }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                    } else if case .failed = item.state {
                        Button(action: {
                            vm.retryItem(item)
                        }) {
                            Label("重试", systemImage: "arrow.clockwise.circle")
                        }
                        .buttonStyle(ActionButtonStyle(variant: .neutral))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, metrics.isNarrow ? 7 : 8)
        }
        .background(taskBackground(for: item.state), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.42), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.03), radius: 8, y: 4)
    }

    private func progressFooter(metrics: LayoutMetrics) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(vm.downloader.message)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if !vm.downloader.currentTaskTitle.isEmpty {
                    Text(vm.downloader.currentTaskTitle)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: metrics.footerTaskWidth, alignment: .trailing)
                }
                if !vm.downloader.speedText.isEmpty {
                    Text(vm.downloader.speedText)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
            ProgressView(value: vm.downloader.progress)
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, metrics.isNarrow ? 7 : 8)
        .glassPanel(cornerRadius: 16, fillOpacity: 0.22)
    }

    private var headerSubtitle: String {
        if vm.downloader.isRunning {
            return "当前队列正在执行，下面可以直接查看进度与失败项。"
        }
        if vm.downloader.taskItems.isEmpty {
            return "队列空闲中，开始下载后会在这里集中管理任务。"
        }
        return "当前有 \(vm.downloader.taskItems.count) 个任务，支持查看状态与批量操作。"
    }

    private var downloadManagerBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.98, blue: 0.99),
                    Color(red: 0.92, green: 0.95, blue: 0.98)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color(red: 0.64, green: 0.82, blue: 0.95).opacity(0.13))
                .blur(radius: 95)
                .frame(width: 340, height: 340)
                .offset(x: -220, y: -180)

            Circle()
                .fill(Color(red: 0.86, green: 0.91, blue: 0.98).opacity(0.32))
                .blur(radius: 90)
                .frame(width: 300, height: 300)
                .offset(x: 240, y: 210)
        }
        .ignoresSafeArea()
    }

    private func taskBackground(for state: DownloadTaskItem.State) -> some ShapeStyle {
        switch state {
        case .running:
            return AnyShapeStyle(Color(red: 0.90, green: 0.96, blue: 1.0).opacity(0.88))
        case .queued:
            return AnyShapeStyle(Color.white.opacity(0.52))
        case .done:
            return AnyShapeStyle(Color(red: 0.92, green: 0.98, blue: 0.94).opacity(0.86))
        case .canceled:
            return AnyShapeStyle(Color(red: 0.97, green: 0.94, blue: 0.90).opacity(0.86))
        case .failed:
            return AnyShapeStyle(Color(red: 0.99, green: 0.92, blue: 0.89).opacity(0.88))
        }
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
        switch state {
        case .queued: return .gray
        case .running: return .blue
        case .done: return .green
        case .canceled: return .orange
        case .failed: return .red
        }
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

private extension View {
    func glassPanel(cornerRadius: CGFloat, fillOpacity: Double) -> some View {
        self
            .background(Color.white.opacity(fillOpacity), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.46), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, y: 7)
    }
}
