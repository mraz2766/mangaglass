import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var downloader: DownloadCoordinator
    @Binding var destination: WorkspaceDestination
    var bump = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let counts = downloader.countsSummary()
        VStack(spacing: 8) {
            ForEach(WorkspaceDestination.allCases.filter { $0 != .settings }) { item in
                SidebarNavButton(item: item,
                                 selected: destination == item,
                                 badge: item == .queue ? counts.queued + counts.running : 0,
                                 bump: bump) { destination = item }
            }
            Spacer(minLength: 8)
            if downloader.isRunning {
                runningIndicator
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            SidebarNavButton(item: .settings, selected: destination == .settings, badge: 0, bump: bump) {
                destination = .settings
            }
        }
        // The top safe area (transparent titlebar with the traffic lights) stays clear;
        // only the background runs under it.
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background {
            (MGTheme.palette.sidebar ?? MGTheme.palette.canvas).ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : MGMotion.regular, value: downloader.isRunning)
    }

    /// Small ring that fills with overall progress while downloading.
    private var runningIndicator: some View {
        Button { destination = .queue } label: {
            ZStack {
                Circle().stroke(MGTheme.palette.divider, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0.02, downloader.progress))
                    .stroke(MGTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: downloader.progress)
                Image(systemName: downloader.isPaused ? "pause.fill" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MGTheme.accent)
            }
            .frame(width: 24, height: 24)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(downloader.isPaused ? "已暂停" : "正在下载 · \(downloader.speedText)")
        .accessibilityLabel("下载进度 \(Int(downloader.progress * 100))%")
    }
}

/// One rail item. Kept structurally plain (like the chapter tiles): a `.plain` button whose
/// label draws its own selection and hover fill, with hover tracked outside the button style.
private struct SidebarNavButton: View {
    let item: WorkspaceDestination
    let selected: Bool
    let badge: Int
    let bump: Int
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let palette = MGTheme.palette
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .symbolVariant(selected ? .fill : .none)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            SidebarBadge(count: badge, bump: bump)
                                .offset(x: 10, y: -8)
                        }
                    }
                Text(item.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? palette.softSelectedText : Color.secondary)
            .frame(width: 52, height: 48)
            .background(
                selected ? palette.softSelectedFill : (hovering ? palette.cellHover.opacity(0.6) : Color.clear),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
        .animation(reduceMotion ? nil : MGMotion.fast, value: selected)
        .background {
            if item == .queue {
                GeometryReader { proxy in
                    Color.clear.preference(key: MGQueueTargetKey.self, value: proxy.frame(in: .named(MGRootSpace)))
                }
            }
        }
        .help(item.title)
        .accessibilityLabel("打开\(item.title)")
        .accessibilityValue(selected ? "当前页面" : (badge > 0 ? "\(badge) 项" : ""))
    }
}

/// Count capsule on the 下载 icon; pops whenever chapters land in the queue.
private struct SidebarBadge: View {
    let count: Int
    let bump: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popped = false

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .frame(minWidth: 15, minHeight: 15)
            .background(MGTheme.accent, in: Capsule())
            .scaleEffect(popped ? 1.35 : 1)
            .contentTransition(.numericText())
            .onChange(of: bump) { _ in
                guard !reduceMotion else { return }
                withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { popped = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { popped = false }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: count)
    }
}

struct ActivityLogSheet: View {
    let vm: MainViewModel
    @ObservedObject private var logs: ActivityLogStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    init(vm: MainViewModel) {
        self.vm = vm
        self._logs = ObservedObject(wrappedValue: vm.logStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("活动日志")
                        .font(MGFont.title)
                    Text("解析与下载过程会实时记录在这里。")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    .keyboardShortcut(.cancelAction)
            }

            HStack {
                Toggle("只看错误", isOn: $logs.showOnlyErrors)
                    .toggleStyle(.checkbox)
                    .font(MGFont.body)
                Spacer()
                Button("复制最近 50 条") { vm.copyRecentLogs() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
                Button("清空日志") { vm.clearLogs() }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if logs.visibleEntries.isEmpty {
                        MGEmptyState(title: "暂无日志", systemImage: "doc.text", detail: "加载或下载后会显示实时记录。")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(logs.visibleEntries) { entry in
                            Text(entry.text)
                                .font(MGFont.mono)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(MGSpacing.sm)
            }
            .mgInset()
        }
        .padding(MGSpacing.lg)
        .frame(minWidth: 640, minHeight: 440)
        .background(MGTheme.background(for: colorScheme))
    }
}
