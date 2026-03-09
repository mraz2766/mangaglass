import SwiftUI

struct DownloadManagerView: View {
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
        VStack(spacing: 0) {
            header
            
            HStack(spacing: 0) {
                sidebar
                
                VStack(spacing: 0) {
                    toolbar
                    listContent
                    
                    if vm.downloader.isRunning {
                        progressFooter
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.textBackgroundColor).opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 850, height: 600)
    }

    private var header: some View {
        HStack {
            Text("下载管理")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
            
            Spacer()
                .contentShape(Rectangle())
                .gesture(DragGesture().onChanged { _ in }) // Put drag gesture only on the empty space
            
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
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("过滤选项")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 16)

            ForEach(FilterType.allCases) { type in
                Button(action: { filter = type }) {
                    HStack {
                        Text(type.rawValue)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Spacer()
                        if count(for: type) > 0 {
                            Text("\(count(for: type))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(filter == type ? .white : .secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(filter == type ? Color.blue.opacity(0.8) : Color.gray.opacity(0.2), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(filter == type ? Color.blue.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }
            Spacer()
        }
        .frame(width: 180)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .trailing)
    }

    private var toolbar: some View {
        HStack {
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

            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 1, height: 16).padding(.horizontal, 4)

            Button("重新下载失败项") { vm.retryFailed() }
                .buttonStyle(ActionButtonStyle(variant: .neutral))
                .disabled(vm.downloader.failedItems().isEmpty)
                
            Button("清空已完成") { vm.clearCompletedTasks() }
                .buttonStyle(ActionButtonStyle(variant: .neutral))
                .disabled(vm.downloader.taskItems.allSatisfy { $0.state != .done })
                
            Button("清空所有") { vm.clearQueue() }
                .buttonStyle(ActionButtonStyle(variant: .danger))
                .disabled(vm.downloader.isRunning)

            Spacer()
            
            Button("打开下载目录") {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: vm.destinationFolder.path)
            }
            .buttonStyle(ActionButtonStyle(variant: .neutral))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(Divider(), alignment: .bottom)
    }

    private var listContent: some View {
        ScrollView {
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.tertiary)
                        .offset(y: isFloating ? -5 : 4)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                                isFloating.toggle()
                            }
                        }
                    Text("无匹配任务")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 100)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(filteredItems) { item in
                        taskRow(for: item)
                    }
                }
                .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func taskRow(for item: DownloadTaskItem) -> some View {
        HStack(spacing: 16) {
            // Status Indicator
            Circle()
                .fill(statusColor(for: item.state))
                .frame(width: 8, height: 8)
                .shadow(color: statusColor(for: item.state).opacity(0.4), radius: 3)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(item.comic.name)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Text("[\(item.chapter.volumeName)] \(item.chapter.displayName)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Status Text
            Text(statusString(for: item.state))
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            
            // Action button
            if item.state == .queued || item.state == .running {
                Button(action: {
                    if let idx = vm.downloader.taskItems.firstIndex(where: { $0.id == item.id }) {
                        vm.downloader.taskItems[idx].state = .canceled
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            } else if case .failed = item.state {
                Button(action: {
                    vm.retryItem(item)
                }) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var progressFooter: some View {
        VStack(spacing: 8) {
            HStack {
                Text(vm.downloader.message)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                if !vm.downloader.speedText.isEmpty {
                    Text(vm.downloader.speedText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
            }
            ProgressView(value: vm.downloader.progress)
                .progressViewStyle(.linear)
        }
        .padding(16)
        .background(.regularMaterial)
        .overlay(Divider(), alignment: .top)
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
}
