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
    @State private var confirmation: QueueConfirmation?

    init(vm: MainViewModel, showLogs: Binding<Bool>) {
        self.vm = vm
        self.downloader = vm.downloader
        self._structureObserver = StateObject(wrappedValue: QueueStructureObserver(downloader: vm.downloader))
        self._showLogs = showLogs
    }

    private var filteredItems: [DownloadTaskItem] {
        downloader.taskItems.filter { item in
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
    }

    private var counts: (queued: Int, running: Int, failed: Int, done: Int) {
        downloader.countsSummary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            MGPageHeader(title: "队列", subtitle: headerSubtitle) { controls }
            filters
            if let circuit = downloader.manhuaGuiSoftCircuit {
                softCircuitNotice(circuit)
            }
            if let circuit = downloader.copySoftCircuit {
                copySoftCircuitNotice(circuit)
            }
            taskList
            progressFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var controls: some View {
        HStack(spacing: MGSpacing.xs) {
            if counts.queued > 0 && !downloader.isRunning {
                Button("开始 \(counts.queued)") { vm.startQueuedDownloads() }
                    .buttonStyle(MGActionButtonStyle(variant: .primary))
            }
            if downloader.isRunning {
                Button(downloader.isPaused ? "继续" : "暂停") {
                    downloader.isPaused ? vm.resumeDownload() : vm.pauseDownload()
                }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
            }
            if counts.failed > 0 {
                Button("重试失败") { vm.retryFailed() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
            }
            Button {
                showLogs = true
            } label: {
                Image(systemName: "doc.text")
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
        Picker("筛选", selection: $filter) {
            ForEach(QueueFilter.allCases) { item in
                Text("\(item.rawValue) \(count(for: item))").monospacedDigit().tag(item)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filteredItems.isEmpty {
                    MGEmptyState(
                        title: "没有匹配任务",
                        systemImage: "tray",
                        detail: "开始下载后，任务、进度和失败原因会显示在这里。"
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            MGHairlineDivider(opacity: 0.7).padding(.leading, MGSpacing.sm)
                        }
                        taskRow(item)
                    }
                }
            }
        }
        .mgSurface()
    }

    private func taskRow(_ item: DownloadTaskItem) -> some View {
        let tint = MGTheme.statusColor(for: item.state)
        return HStack(alignment: .top, spacing: MGSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: MGSpacing.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.chapter.displayName)
                            .font(MGFont.bodyStrong)
                            .lineLimit(1)
                        Text(item.comic.name)
                            .font(MGFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: MGSpacing.xs)
                    Label(statusTitle(item.state), systemImage: statusImage(item.state))
                        .font(MGFont.caption)
                        .foregroundStyle(item.state == .queued ? Color.secondary : tint)
                        .fixedSize()
                    taskActions(item)
                }
                if expandedTaskID == item.id {
                    taskDetails(item)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, MGSpacing.sm)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .mgHoverBackground(radius: 0)
    }

    @ViewBuilder
    private func taskActions(_ item: DownloadTaskItem) -> some View {
        if item.state == .queued || item.state == .running {
            Button {
                vm.cancelItem(item)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .frame(width: 28, height: 28)
            .help("取消任务")
        } else if case .failed = item.state {
            Button {
                vm.retryItem(item)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .frame(width: 28, height: 28)
            .help("重试任务")
        }
        if failureReason(item.state) != nil || downloader.durationText(for: item) != nil {
            Button {
                withAnimation(reduceMotion ? nil : MGMotion.regular) {
                    expandedTaskID = expandedTaskID == item.id ? nil : item.id
                }
            } label: {
                Image(systemName: expandedTaskID == item.id ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .frame(width: 28, height: 28)
            .help("任务详情")
        }
    }

    @ViewBuilder
    private func taskDetails(_ item: DownloadTaskItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let reason = failureReason(item.state) {
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
        .padding(.top, 4)
    }

    private var progressFooter: some View {
        QueueProgressFooter(downloader: downloader)
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
        .background(MGTheme.warning.opacity(colorScheme == .dark ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
        .background(MGTheme.warning.opacity(colorScheme == .dark ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var headerSubtitle: String {
        if downloader.isRunning {
            return "正在执行 · 排队 \(counts.queued) · 进行中 \(counts.running)"
        }
        return downloader.taskItems.isEmpty ? "队列空闲" : "等待操作 · 共 \(downloader.taskItems.count) 项"
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

    private func statusTitle(_ state: DownloadTaskItem.State) -> String {
        switch state {
        case .queued: return "排队中"
        case .running: return "下载中"
        case .done: return "已完成"
        case .canceled: return "已取消"
        case .failed: return "失败"
        }
    }

    private func statusImage(_ state: DownloadTaskItem.State) -> String {
        switch state {
        case .queued: return "clock"
        case .running: return "arrow.down.circle"
        case .done: return "checkmark.circle"
        case .canceled: return "xmark.circle"
        case .failed: return "exclamationmark.circle"
        }
    }

    private func failureReason(_ state: DownloadTaskItem.State) -> String? {
        guard case .failed(let message) = state else { return nil }
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct QueueProgressFooter: View {
    @ObservedObject var downloader: DownloadCoordinator

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                message
                Spacer(minLength: 8)
                progressMetrics
            }
            VStack(alignment: .leading, spacing: 4) {
                message
                progressMetrics
            }
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 36, maxHeight: 56)
    }

    private var message: some View {
        Text(downloader.message)
            .font(MGFont.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var progressMetrics: some View {
        let summary = downloader.progressSummary()
        return HStack(spacing: 8) {
            Text("已下载 \(summary.completedPages)/\(summary.totalPages) 页 · 完成 \(summary.completedTasks)/\(summary.totalTasks) 话")
                .font(MGFont.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
            ProgressView(value: downloader.progress)
                .progressViewStyle(.linear)
                .frame(minWidth: 60, maxWidth: .infinity)
            if !downloader.speedText.isEmpty {
                Text(downloader.speedText)
                    .font(MGFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(MGTheme.accent)
                    .fixedSize()
            }
        }
    }
}
