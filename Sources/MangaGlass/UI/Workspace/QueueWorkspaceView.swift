import SwiftUI

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

    @ObservedObject var vm: MainViewModel
    @Binding var showLogs: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var filter: QueueFilter = .all
    @State private var expandedTaskID: UUID?
    @State private var confirmation: QueueConfirmation?

    private var filteredItems: [DownloadTaskItem] {
        vm.downloader.taskItems.filter { item in
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
        vm.downloader.countsSummary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { header; Spacer(minLength: 0); controls }
                VStack(alignment: .leading, spacing: 8) { header; controls }
            }
            filters
            if let circuit = vm.downloader.manhuaGuiSoftCircuit {
                softCircuitNotice(circuit)
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("队列").font(.system(size: 18, weight: .semibold))
            Text("进行中 \(counts.running) · 失败 \(counts.failed) · 完成 \(counts.done)")
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
            Button {
                showLogs = true
            } label: {
                Image(systemName: "doc.text")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .help("活动日志")
        }
    }

    private var controls: some View {
        HStack(spacing: MGSpacing.xs) {
            if counts.queued > 0 && !vm.downloader.isRunning {
                Button("开始 \(counts.queued)") { vm.startQueuedDownloads() }
                    .buttonStyle(MGActionButtonStyle(variant: .primary))
            }
            if vm.downloader.isRunning {
                Button(vm.downloader.isPaused ? "继续" : "暂停") {
                    vm.downloader.isPaused ? vm.resumeDownload() : vm.pauseDownload()
                }
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
            }
            if counts.failed > 0 {
                Button("重试失败") { vm.retryFailed() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
            }
            Menu {
                Button("打开下载目录") { vm.openDownloadDirectory() }
                Button("清空已完成") { vm.clearCompletedTasks() }
                    .disabled(counts.done == 0)
                Divider()
                Button("取消并清空队列", role: .destructive) { confirmation = .cancelAll }
                    .disabled(vm.downloader.taskItems.isEmpty)
                Button("清空全部记录", role: .destructive) { confirmation = .clearAll }
                    .disabled(vm.downloader.taskItems.isEmpty || vm.downloader.isRunning)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, MGSpacing.xs)
    }

    private var filters: some View {
        HStack(spacing: 6) {
            ForEach(QueueFilter.allCases) { item in
                Button { filter = item } label: {
                    Text("\(item.rawValue) \(count(for: item))")
                        .font(MGFont.caption).padding(.horizontal, 8).frame(height: 28)
                }
                .buttonStyle(MGChoiceButtonStyle(selected: filter == item, bordered: false))
                .accessibilityValue(filter == item ? "已选中" : "未选中")
            }
            Spacer(minLength: 0)
        }
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
                    ForEach(filteredItems) { item in
                        taskRow(item)
                        Divider()
                            .overlay(MGTheme.divider(for: colorScheme))
                    }
                }
            }
        }
        .mgSurface()
    }

    private func taskRow(_ item: DownloadTaskItem) -> some View {
        let tint = MGTheme.statusColor(for: item.state)
        return HStack(alignment: .top, spacing: MGSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.comic.name)
                        .font(MGFont.bodyStrong)
                        .lineLimit(1)
                    Label(statusTitle(item.state), systemImage: statusImage(item.state))
                        .font(MGFont.caption)
                        .foregroundStyle(tint)
                    Spacer()
                    taskActions(item)
                }
                Text(item.chapter.displayName)
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if expandedTaskID == item.id {
                    taskDetails(item)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, MGSpacing.sm)
        .padding(.vertical, 10)
        .frame(minHeight: 64)
        .mgHoverBackground(radius: 0)
        .animation(reduceMotion ? nil : MGMotion.regular, value: expandedTaskID)
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
        if failureReason(item.state) != nil || vm.downloader.durationText(for: item) != nil {
            Button {
                expandedTaskID = expandedTaskID == item.id ? nil : item.id
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
            if let duration = vm.downloader.durationText(for: item) {
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
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(vm.downloader.message).font(MGFont.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 8)
                progressMetrics
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(vm.downloader.message).font(MGFont.caption).foregroundStyle(.secondary).lineLimit(1)
                progressMetrics
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 44, maxHeight: 64)
        .overlay(alignment: .top) { Divider() }
    }

    private var progressMetrics: some View {
        let summary = vm.downloader.progressSummary()
        return HStack(spacing: 8) {
            Text("已下载 \(summary.completedPages)/\(summary.totalPages) 页 · 完成 \(summary.completedTasks)/\(summary.totalTasks) 话")
                .font(MGFont.caption).monospacedDigit().foregroundStyle(.secondary).fixedSize()
            ProgressView(value: vm.downloader.progress)
                .progressViewStyle(.linear).frame(minWidth: 60, maxWidth: .infinity)
            if !vm.downloader.speedText.isEmpty {
                Text(vm.downloader.speedText).font(MGFont.caption).monospacedDigit()
                    .foregroundStyle(MGTheme.accent).fixedSize()
            }
        }
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

    private var headerSubtitle: String {
        if vm.downloader.isRunning {
            return "正在执行 · 排队 \(counts.queued) · 进行中 \(counts.running)"
        }
        return vm.downloader.taskItems.isEmpty ? "队列空闲" : "等待操作 · 共 \(vm.downloader.taskItems.count) 项"
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
        case .all: return vm.downloader.taskItems.count
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
