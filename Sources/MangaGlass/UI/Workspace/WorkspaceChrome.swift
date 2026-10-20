import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var downloader: DownloadCoordinator
    @Binding var destination: WorkspaceDestination

    var body: some View {
        let counts = downloader.countsSummary()
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                BrandMarkView(size: 22)
                Text("MangaGlass").font(MGFont.bodyStrong)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityElement(children: .combine)

            VStack(spacing: 2) {
                ForEach([WorkspaceDestination.download, .queue, .history]) { item in
                    row(item, badge: item == .queue ? counts.queued + counts.running : 0)
                }
                Spacer(minLength: MGSpacing.md)
                row(.settings, badge: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 10)

            if downloader.isRunning {
                queueStatus
            }
        }
        .frame(maxHeight: .infinity)
        .background(SidebarMaterial().ignoresSafeArea())
    }

    private func row(_ item: WorkspaceDestination, badge: Int) -> some View {
        SidebarRow(item: item, badge: badge, selected: destination == item) { destination = item }
    }

    private var queueStatus: some View {
        Button { destination = .queue } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(downloader.isPaused ? "已暂停" : "正在下载")
                    Spacer(minLength: 4)
                    Text(downloader.speedText).monospacedDigit()
                }
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                ProgressView(value: downloader.progress)
                    .progressViewStyle(.linear)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { MGHairlineDivider(opacity: 0.6) }
        .help("打开队列")
        .accessibilityLabel("下载进度，打开队列")
    }
}

private struct SidebarRow: View {
    let item: WorkspaceDestination
    let badge: Int
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(MGTheme.accent)
                    .frame(width: 20)
                Text(item.title).font(MGFont.body)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(MGFont.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("打开\(item.title)")
        .accessibilityValue(selected ? "当前页面" : (badge > 0 ? "\(badge) 项" : ""))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if selected { return Color.primary.opacity(scheme == .dark ? 0.12 : 0.09) }
        return hovering ? Color.primary.opacity(scheme == .dark ? 0.06 : 0.04) : .clear
    }
}

private struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
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

    private var brandImage: NSImage? {
        guard let url = Bundle.module.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}

struct ActivityLogSheet: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

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
                Toggle("只看错误", isOn: $vm.showOnlyErrorLogs)
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
                    if vm.filteredLogLines.isEmpty {
                        MGEmptyState(title: "暂无日志", systemImage: "doc.text", detail: "加载或下载后会显示实时记录。")
                            .frame(maxWidth: .infinity, minHeight: 220)
                    } else {
                        ForEach(Array(vm.filteredLogLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
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
