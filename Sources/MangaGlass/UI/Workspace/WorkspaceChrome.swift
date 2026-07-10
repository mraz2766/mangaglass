import AppKit
import SwiftUI

struct WorkspaceSidebar: View {
    @ObservedObject var vm: MainViewModel
    @Binding var destination: WorkspaceDestination
    @Environment(\.colorScheme) private var colorScheme

    private var counts: (queued: Int, running: Int, failed: Int, done: Int) {
        vm.downloader.countsSummary()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.md) {
            HStack(spacing: 9) {
                BrandMarkView(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("MangaGlass")
                        .font(MGFont.appTitle)
                    Text("本地下载工作台")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, MGSpacing.sm)
            .padding(.top, MGSpacing.sm)

            VStack(spacing: 3) {
                ForEach(WorkspaceDestination.allCases) { item in
                    Button {
                        destination = item
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: item.systemImage)
                                .frame(width: 16)
                            Text(item.title)
                            Spacer(minLength: 0)
                            if item == .queue, counts.queued + counts.running > 0 {
                                Text("\(counts.queued + counts.running)")
                                    .font(MGFont.captionStrong)
                                    .foregroundStyle(item == destination ? MGTheme.accent : .secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(item == destination ? MGTheme.accent.opacity(colorScheme == .dark ? 0.23 : 0.11) : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(item == destination ? MGTheme.accent : .primary.opacity(0.82))
                    .accessibilityLabel("打开\(item.title)")
                }
            }
            .font(MGFont.bodyStrong)
            .padding(.horizontal, MGSpacing.xs)

            Spacer(minLength: 0)

            Button {
                destination = .queue
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label(queueStateTitle, systemImage: vm.downloader.isRunning ? "arrow.down.circle.fill" : "tray")
                            .font(MGFont.captionStrong)
                            .foregroundStyle(vm.downloader.isRunning ? MGTheme.accent : .secondary)
                        Spacer()
                        if !vm.downloader.speedText.isEmpty {
                            Text(vm.downloader.speedText)
                                .font(MGFont.mono)
                                .foregroundStyle(MGTheme.accent)
                        }
                    }
                    if vm.downloader.isRunning || counts.queued > 0 {
                        ProgressView(value: vm.downloader.progress)
                            .progressViewStyle(.linear)
                    }
                    Text("排队 \(counts.queued) · 进行中 \(counts.running) · 失败 \(counts.failed)")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(MGSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .mgInset()
            }
            .buttonStyle(.plain)
            .padding(MGSpacing.xs)
        }
        .padding(.vertical, MGSpacing.xs)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    private var queueStateTitle: String {
        if vm.downloader.isRunning { return "正在下载" }
        if counts.queued > 0 { return "等待开始" }
        return "队列空闲"
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
        } else {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(MGTheme.accent)
                .frame(width: size, height: size)
                .background(MGTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
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
