import Combine
import SwiftUI

@MainActor
private final class QueueStructureObserver: ObservableObject {
    private var cancellables: Set<AnyCancellable> = []

    init(downloader: DownloadCoordinator) {
        forward(downloader.$taskItems)
        forward(downloader.$isRunning)
        forward(downloader.$isPaused)
        forward(downloader.$manhuaGuiSoftCircuit)
        forward(downloader.$copySoftCircuit)
    }

    private func forward<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher
            .dropFirst()
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }
}

/// All queued chapters of one comic, shown as a collapsible group.
private struct QueueGroup: Identifiable {
    let id: String
    let comic: ComicInfo
    var items: [DownloadTaskItem]

    var doneCount: Int { items.filter { $0.state == .done }.count }
    var runningCount: Int { items.filter { $0.state == .running }.count }
    var failedCount: Int {
        items.filter {
            if case .failed = $0.state { return true }
            return $0.state == .canceled
        }.count
    }
    var fraction: Double { items.isEmpty ? 0 : Double(doneCount) / Double(items.count) }
    var isFinished: Bool { doneCount == items.count }
}

struct QueueWorkspaceView: View {
    private enum QueueFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case active = "进行中"
        case queued = "排队"
        case done = "已完成"
        case failed = "失败"

        var id: String { rawValue }
    }

    private enum QueueConfirmation: Identifiable {
        case cancelAll
        case clearAll

        var id: String {
            switch self {
            case .cancelAll: return "cancel-all"
            case .clearAll: return "clear-all"
            }
        }
    }

    let vm: MainViewModel
    private let downloader: DownloadCoordinator
    @StateObject private var structureObserver: QueueStructureObserver
    @Binding var showLogs: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: QueueFilter = .all
    @State private var expandedTaskID: UUID?
    @State private var groupExpansion: [String: Bool] = [:]
    @State private var confirmation: QueueConfirmation?

    init(vm: MainViewModel, showLogs: Binding<Bool>) {
        self.vm = vm
        self.downloader = vm.downloader
        self._structureObserver = StateObject(wrappedValue: QueueStructureObserver(downloader: vm.downloader))
        self._showLogs = showLogs
    }

    private func matches(_ item: DownloadTaskItem) -> Bool {
        switch filter {
        case .all: return true
        case .active: return item.state == .running
        case .queued: return item.state == .queued
        case .done: return item.state == .done
        case .failed:
            if case .failed = item.state { return true }
            return item.state == .canceled
        }
    }

    private var groups: [QueueGroup] {
        var order: [String] = []
        var byID: [String: QueueGroup] = [:]
        for item in downloader.taskItems where matches(item) {
            let key = "\(item.comic.site.displayName)|\(item.comic.slug)|\(item.comic.name)"
            if byID[key] == nil {
                order.append(key)
                byID[key] = QueueGroup(id: key, comic: item.comic, items: [])
            }
            byID[key]?.items.append(item)
        }
        return order.compactMap { byID[$0] }
    }

    private var counts: (queued: Int, running: Int, failed: Int, done: Int) {
        downloader.countsSummary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            QueueSummaryCard(downloader: downloader, vm: vm)
            if let circuit = downloader.manhuaGuiSoftCircuit {
                softCircuitNotice(circuit)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let circuit = downloader.copySoftCircuit {
                copySoftCircuitNotice(circuit)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            filters
            taskList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.86), value: downloader.taskItems.map(\.id))
        .animation(reduceMotion ? nil : MGMotion.panel, value: filter)
        .alert(confirmationTitle, isPresented: confirmationBinding, presenting: confirmation) { item in
            switch item {
            case .cancelAll:
                Button("取消并清空", role: .destructive) { vm.cancelAndClearAllDownloads() }
                Button("返回", role: .cancel) {}
            case .clearAll:
                Button("清空全部记录", role: .destructive) { vm.clearQueue() }
                Button("返回", role: .cancel) {}
            }
        } message: { item in
            switch item {
            case .cancelAll:
                Text("这会取消正在执行的下载并清空队列；已经保存到本地的文件不会被删除。")
            case .clearAll:
                Text("这会移除下载管理器中的全部记录；已经保存到本地的文件不会被删除。")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("下载").font(.system(size: 22, weight: .semibold))
            Spacer()
            Button { showLogs = true } label: {
                Image(systemName: "doc.text").frame(width: 28, height: 28)
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .help("活动日志")
            .accessibilityLabel("活动日志")
            Menu {
                Button("打开下载目录") { vm.openDownloadDirectory() }
                Button("清空已完成") { vm.clearCompletedTasks() }
                    .disabled(counts.done == 0)
                Divider()
                Button("取消并清空队列", role: .destructive) { confirmation = .cancelAll }
                    .disabled(downloader.taskItems.isEmpty)
                Button("清空全部记录", role: .destructive) { confirmation = .clearAll }
                    .disabled(downloader.taskItems.isEmpty || downloader.isRunning)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QueueFilter.allCases) { item in
                    MGChip(title: item.rawValue, count: count(for: item), selected: filter == item) { filter = item }
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if groups.isEmpty {
                    MGEmptyState(
                        title: downloader.taskItems.isEmpty ? "还没有下载任务" : "没有匹配任务",
                        systemImage: "arrow.down.circle",
                        detail: downloader.taskItems.isEmpty ? "在首页选好章节后加入队列，进度会显示在这里。" : "换一个筛选看看。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .transition(.opacity)
                } else {
                    ForEach(groups) { group in
                        groupCard(group)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func isExpanded(_ group: QueueGroup) -> Bool {
        if let override = groupExpansion[group.id] { return override }
        if group.isFinished { return false }
        return group.runningCount > 0 || group.failedCount > 0 || group.items.count <= 6
    }

    private func groupCard(_ group: QueueGroup) -> some View {
        let expanded = isExpanded(group)
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    groupExpansion[group.id] = !expanded
                }
            } label: {
                HStack(spacing: 12) {
                    MGBookCover(url: group.comic.coverURL, title: group.comic.name)
                        .frame(width: 34, height: 46)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(group.comic.name).font(MGFont.bodyStrong).lineLimit(1)
                            Text("\(group.doneCount) / \(group.items.count) 话")
                                .font(MGFont.caption).monospacedDigit().foregroundStyle(.secondary)
                                .contentTransition(.numericText())
                            if group.failedCount > 0 {
                                Text("\(group.failedCount) 失败").font(MGFont.caption).foregroundStyle(MGTheme.danger)
                            }
                            if group.isFinished {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(MGTheme.success)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        MGProgressBar(value: group.fraction, tint: group.isFinished ? MGTheme.success : MGTheme.accent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(group.comic.name)，\(group.doneCount) / \(group.items.count) 话，\(expanded ? "折叠" : "展开")")

            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        MGHairlineDivider(opacity: 0.8).padding(.leading, 60)
                        QueueTaskRow(
                            item: item,
                            downloader: downloader,
                            expanded: expandedTaskID == item.id,
                            onToggleDetails: {
                                withAnimation(reduceMotion ? nil : MGMotion.regular) {
                                    expandedTaskID = expandedTaskID == item.id ? nil : item.id
                                }
                            },
                            onCancel: { vm.cancelItem(item) },
                            onRetry: { vm.retryItem(item) }
                        )
                        .transition(.opacity)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .mgPanel(radius: 12)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func softCircuitNotice(_ circuit: DownloadCoordinator.ManhuaGuiSoftCircuit) -> some View {
        HStack(spacing: MGSpacing.xs) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MGTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("漫画柜可能触发风控")
                    .font(MGFont.bodyStrong)
                Text("\(circuit.chapterTitle) · HTTP \(circuit.statusCode) · \(circuit.host)")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("打开网页") { vm.openManhuaGuiWebCheck() }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
            Button("继续") { vm.continueManhuaGuiDownloadAfterCheck() }
                .buttonStyle(MGActionButtonStyle(variant: .primary))
        }
        .padding(MGSpacing.sm)
        .background(MGTheme.warning.opacity(colorScheme == .dark ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func copySoftCircuitNotice(_ circuit: DownloadCoordinator.CopySoftCircuit) -> some View {
        HStack(spacing: MGSpacing.xs) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(MGTheme.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("拷贝漫画请求已自动降速暂停")
                    .font(MGFont.bodyStrong)
                Text("\(circuit.chapterTitle) · \(circuit.reason) · 约 \(circuit.remainingSeconds) 秒后可继续")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("冷却后继续") { vm.continueCopyDownloadAfterCooldown() }
                .buttonStyle(MGActionButtonStyle(variant: .primary))
        }
        .padding(MGSpacing.sm)
        .background(MGTheme.warning.opacity(colorScheme == .dark ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .cancelAll: return "取消并清空所有下载？"
        case .clearAll: return "清空下载队列？"
        case nil: return ""
        }
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(get: { confirmation != nil }, set: { if !$0 { confirmation = nil } })
    }

    private func count(for item: QueueFilter) -> Int {
        switch item {
        case .all: return downloader.taskItems.count
        case .active: return counts.running
        case .queued: return counts.queued
        case .done: return counts.done
        case .failed: return counts.failed
        }
    }
}

/// One chapter inside a group; shakes once when it turns into a failure.
private struct QueueTaskRow: View {
    let item: DownloadTaskItem
    let downloader: DownloadCoordinator
    let expanded: Bool
    let onToggleDetails: () -> Void
    let onCancel: () -> Void
    let onRetry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes: CGFloat = 0

    private var failureReason: String? {
        guard case .failed(let message) = item.state else { return nil }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let tint = MGTheme.statusColor(for: item.state)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: statusImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(item.state == .queued ? Color.secondary : tint)
                    .frame(width: 20)
                    .contentTransition(.opacity)
                Text(item.chapter.displayName).font(MGFont.body).lineLimit(1)
                Spacer(minLength: 8)
                Text(statusTitle)
                    .font(MGFont.caption)
                    .foregroundStyle(item.state == .queued ? Color.secondary : tint)
                actions
            }
            if expanded {
                details
                    .padding(.leading, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.leading, 30)
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .mgHoverBackground(radius: 0)
        .modifier(MGShakeEffect(animatableData: shakes))
        .onChange(of: failureReason != nil) { failed in
            guard failed, !reduceMotion else { return }
            withAnimation(.linear(duration: 0.4)) { shakes += 1 }
        }
    }

    @ViewBuilder private var actions: some View {
        if item.state == .queued || item.state == .running {
            Button(action: onCancel) { Image(systemName: "xmark.circle") }
                .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
                .help("取消任务")
                .accessibilityLabel("取消任务")
        } else if failureReason != nil {
            Button(action: onRetry) { Image(systemName: "arrow.clockwise") }
                .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
                .help("重试任务")
                .accessibilityLabel("重试任务")
        }
        if failureReason != nil || downloader.durationText(for: item) != nil {
            Button(action: onToggleDetails) {
                Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .help("任务详情")
            .accessibilityLabel("任务详情")
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let reason = failureReason {
                Text(reason)
                    .font(MGFont.caption)
                    .foregroundStyle(MGTheme.danger)
                    .textSelection(.enabled)
            }
            if let duration = downloader.durationText(for: item) {
                Text("该话耗时 \(duration)")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
            }
            Text(item.destination.path)
                .font(MGFont.mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(item.destination.path)
        }
    }

    private var statusTitle: String {
        switch item.state {
        case .queued: return "排队中"
        case .running: return "下载中"
        case .done: return "已完成"
        case .canceled: return "已取消"
        case .failed: return "失败"
        }
    }

    private var statusImage: String {
        switch item.state {
        case .queued: return "clock"
        case .running: return "arrow.down.circle"
        case .done: return "checkmark.circle.fill"
        case .canceled: return "xmark.circle"
        case .failed: return "exclamationmark.circle.fill"
        }
    }
}

/// Overall progress, speed, remaining time and the run controls.
private struct QueueSummaryCard: View {
    @ObservedObject var downloader: DownloadCoordinator
    let vm: MainViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let summary = downloader.progressSummary()
        let counts = downloader.countsSummary()
        let percent = Int((downloader.progress * 100).rounded())
        HStack(alignment: .center, spacing: 18) {
            Text("\(percent)%")
                .font(.system(size: 30, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: percent)
                .frame(minWidth: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                MGProgressBar(value: downloader.progress, tint: MGTheme.accent, height: 6)
                HStack(spacing: 6) {
                    Text(statusLine(counts: counts))
                    Text("·")
                    Text("\(summary.completedTasks) / \(summary.totalTasks) 话 · \(summary.completedPages) / \(summary.totalPages) 页")
                        .monospacedDigit()
                }
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            controls(counts: counts)
        }
        .padding(16)
        .mgPanel(radius: 14)
    }

    private func statusLine(counts: (queued: Int, running: Int, failed: Int, done: Int)) -> String {
        if downloader.isRunning {
            if downloader.isPaused { return "已暂停" }
            // speedText already carries the coordinator's own time-remaining estimate.
            return downloader.speedText.isEmpty ? "正在下载" : downloader.speedText
        }
        if counts.queued > 0 { return "等待开始" }
        if downloader.taskItems.isEmpty { return "队列空闲" }
        return counts.failed > 0 ? "已结束，\(counts.failed) 话失败" : "全部完成"
    }

    @ViewBuilder private func controls(counts: (queued: Int, running: Int, failed: Int, done: Int)) -> some View {
        HStack(spacing: 8) {
            if counts.failed > 0 {
                Button("重试失败") { vm.retryFailed() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
            }
            if downloader.isRunning {
                Button {
                    downloader.isPaused ? vm.resumeDownload() : vm.pauseDownload()
                } label: {
                    Label(downloader.isPaused ? "继续" : "暂停", systemImage: downloader.isPaused ? "play.fill" : "pause.fill")
                }
                .buttonStyle(MGActionButtonStyle(variant: .emphasis))
            } else if counts.queued > 0 {
                Button {
                    vm.startQueuedDownloads()
                } label: {
                    Label("开始 \(counts.queued)", systemImage: "play.fill")
                }
                .buttonStyle(MGActionButtonStyle(variant: .primary))
            }
        }
        .fixedSize()
    }
}

/// Thin rounded bar whose fill animates smoothly toward `value`.
struct MGProgressBar: View {
    let value: Double
    var tint: Color = MGTheme.accent
    var height: CGFloat = 4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(MGTheme.palette.divider.opacity(0.7))
                Capsule().fill(tint)
                    .frame(width: max(value > 0 ? height : 0, proxy.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: height)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: value)
        .accessibilityElement()
        .accessibilityValue("\(Int(value * 100))%")
    }
}
