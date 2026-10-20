import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var downloader: DownloadCoordinator
    @Binding var destination: WorkspaceDestination
    var bump = 0
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let counts = downloader.countsSummary()
        VStack(spacing: 10) {
            BrandMarkView(size: 28)
                .padding(.vertical, 12)
                .help("MangaGlass")
            ForEach(WorkspaceDestination.allCases.filter { $0 != .settings }) { item in
                navigationButton(item, badge: item == .queue ? counts.queued + counts.running : 0)
            }
            Spacer(minLength: 8)
            if downloader.isRunning {
                runningIndicator
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            navigationButton(.settings, badge: 0)
        }
        .padding(.vertical, 8)
        .frame(width: 64)
        .frame(maxHeight: .infinity)
        .background {
            (MGTheme.palette.sidebar ?? MGTheme.palette.canvas).ignoresSafeArea()
        }
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: destination)
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

    private func navigationButton(_ item: WorkspaceDestination, badge: Int) -> some View {
        let selected = destination == item
        return Button { destination = item } label: {
            VStack(spacing: 2) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            SidebarBadge(count: badge, bump: bump)
                                .offset(x: 10, y: -8)
                        }
                    }
                if selected {
                    Text(item.title).font(.system(size: 10, weight: .medium))
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .top)))
                }
            }
            .foregroundStyle(selected ? MGTheme.palette.softSelectedText : Color.secondary)
            .frame(width: 44, height: 44)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(MGTheme.palette.softSelectedFill)
                        .matchedGeometryEffect(id: "nav-selection", in: indicator)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SidebarPressStyle())
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

private struct SidebarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarPressBody(configuration: configuration)
    }
}

private struct SidebarPressBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .background(hovering ? MGTheme.palette.cellHover.opacity(0.6) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
            .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
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

struct BrandMarkView: View {
    let size: CGFloat

    var body: some View {
        if let image = brandImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        } else {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(MGTheme.accent)
                .frame(width: size, height: size)
                .background(MGTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
    }

    private var brandImage: NSImage? { Self.cachedBrandImage }

    private static let cachedBrandImage: NSImage? = {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
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
