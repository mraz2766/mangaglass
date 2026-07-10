import AppKit
import Foundation
import SwiftUI

struct HistoryWorkspaceView: View {
    @ObservedObject var vm: MainViewModel
    let openDownload: () -> Void
    @State private var showClearConfirmation = false

    private var records: [RecentComicRecord] {
        vm.recentRecords.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("历史")
                        .font(MGFont.title)
                    Text("最近解析过的漫画会保留在本机。")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清空历史", role: .destructive) { showClearConfirmation = true }
                    .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    .disabled(records.isEmpty)
            }

            if records.isEmpty {
                MGEmptyState(
                    title: "还没有历史记录",
                    systemImage: "clock.arrow.circlepath",
                    detail: "成功解析漫画后，可从这里快速返回。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .mgSurface()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(records) { record in
                            historyRow(record)
                            Divider()
                        }
                    }
                }
                .mgSurface()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("清空历史记录？", isPresented: $showClearConfirmation) {
            Button("清空", role: .destructive) { vm.clearRecentRecords() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除 \(records.count) 条最近打开记录，不会影响已经下载到本地的文件。")
        }
    }

    private func historyRow(_ record: RecentComicRecord) -> some View {
        HStack(spacing: MGSpacing.sm) {
            Image(systemName: "book.closed")
                .foregroundStyle(MGTheme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(MGFont.bodyStrong)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(record.siteName)
                    Text(relativeTime(record.updatedAt))
                }
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                Text(record.input)
                    .font(MGFont.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button("加载") {
                vm.applyRecentRecord(record)
                openDownload()
            }
            .buttonStyle(MGActionButtonStyle(variant: .primary))
            Button {
                vm.removeRecentRecord(record)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost))
            .help("删除历史记录")
        }
        .padding(MGSpacing.sm)
    }

    private func relativeTime(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

struct SettingsWorkspaceView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var revealCookie = false
    @State private var showClearConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MGSpacing.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("设置")
                        .font(MGFont.title)
                    Text("外观、访问凭据和本地下载目录。")
                        .font(MGFont.caption)
                        .foregroundStyle(.secondary)
                }

                settingsSection("外观", detail: "仅保留系统、浅色和深色三种显示模式。") {
                    Picker("显示模式", selection: $vm.themeMode) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                settingsSection("下载目录", detail: vm.destinationFolder.path) {
                    HStack {
                        Text(vm.destinationFolder.lastPathComponent.isEmpty ? vm.destinationFolder.path : vm.destinationFolder.lastPathComponent)
                            .font(MGFont.bodyStrong)
                            .lineLimit(1)
                        Spacer()
                        Button("选择目录") { vm.chooseDestination() }
                            .buttonStyle(MGActionButtonStyle(variant: .secondary))
                        Button("在访达中显示") { vm.openDownloadDirectory() }
                            .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    }
                }

                settingsSection("Cookie", detail: "仅在需要登录或访问受限章节时填写；留空即不发送。") {
                    HStack(spacing: MGSpacing.xs) {
                        Group {
                            if revealCookie {
                                TextField("可选 Cookie", text: $vm.authCookie)
                            } else {
                                SecureField("可选 Cookie", text: $vm.authCookie)
                            }
                        }
                        .mgTextField()
                        Button {
                            revealCookie.toggle()
                        } label: {
                            Image(systemName: revealCookie ? "eye.slash" : "eye")
                        }
                        .buttonStyle(MGActionButtonStyle(variant: .secondary))
                        .help(revealCookie ? "隐藏 Cookie" : "显示 Cookie")
                    }
                }

                settingsSection("站点入口", detail: "在默认浏览器中打开支持站点。") {
                    HStack(spacing: MGSpacing.xs) {
                        ForEach(CopyMangaMirror.allCases) { mirror in
                            Button(mirror.displayName) {
                                openInBrowser(mirror.webBaseURL.absoluteString)
                            }
                            .buttonStyle(MGActionButtonStyle(variant: .secondary))
                        }
                        Button("漫画柜") { openInBrowser("https://www.manhuagui.com") }
                            .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    }
                }

                settingsSection("本地数据", detail: "清除当前输入、解析结果与缓存，不会删除下载文件。") {
                    HStack {
                        Text("缓存与当前解析结果")
                            .font(MGFont.body)
                        Spacer()
                        Button("清缓存", role: .destructive) { showClearConfirmation = true }
                            .buttonStyle(MGActionButtonStyle(variant: .secondary))
                    }
                }
            }
            .padding(.bottom, MGSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("清空缓存？", isPresented: $showClearConfirmation) {
            Button("清缓存", role: .destructive) { vm.clearCaches() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前输入、解析结果和缓存内容，但不会删除已经下载到本地的文件。")
        }
    }

    private func settingsSection<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(MGFont.section)
                Text(detail)
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            content()
        }
        .padding(MGSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .mgSurface()
    }

    private func openInBrowser(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
