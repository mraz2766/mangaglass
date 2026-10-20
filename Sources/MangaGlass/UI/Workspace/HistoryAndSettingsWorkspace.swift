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
            MGPageHeader(title: "历史", subtitle: "最近解析过的漫画会保留在本机。") {
                Button("清空历史…", role: .destructive) { showClearConfirmation = true }
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
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            if index > 0 {
                                MGHairlineDivider(opacity: 0.7).padding(.leading, MGSpacing.sm)
                            }
                            historyRow(record)
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(record.title)
                        .font(MGFont.bodyStrong)
                        .lineLimit(1)
                    if CopyMangaMirror.isRetired(record.input) {
                        Text("站点已停用")
                            .font(MGFont.caption)
                            .foregroundStyle(MGTheme.danger)
                    }
                }
                HStack(spacing: 4) {
                    Text(record.siteName)
                    Text("·")
                    Text(relativeTime(record.updatedAt))
                        .help(absoluteTime(record.updatedAt))
                    Text("·")
                    Text(record.input)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(record.input)
                }
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("加载") {
                vm.applyRecentRecord(record)
                openDownload()
            }
            .buttonStyle(MGActionButtonStyle(variant: .secondary))
            Button {
                vm.removeRecentRecord(record)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(MGActionButtonStyle(variant: .ghost, iconOnly: true))
            .frame(width: 28, height: 28)
            .help("删除历史记录")
            .accessibilityLabel("删除历史记录")
        }
        .padding(.horizontal, MGSpacing.sm)
        .padding(.vertical, 8)
        .frame(minHeight: 52)
        .mgHoverBackground(radius: 0)
    }

    private func relativeTime(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func absoluteTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

struct SettingsWorkspaceView: View {
    @ObservedObject var vm: MainViewModel
    @State private var revealCookie = false
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.xs) {
            MGPageHeader(title: "设置")

            Form {
                Section {
                    Picker("外观", selection: $vm.themeMode) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Picker("关闭窗口时", selection: $vm.windowCloseBehavior) {
                        ForEach(WindowCloseBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                } header: {
                    Text("通用")
                } footer: {
                    footnote(vm.windowCloseBehavior.detail + " Command-Q 或菜单“退出”仍会询问并完全退出应用。")
                }

                Section {
                    LabeledContent("下载目录") {
                        HStack(spacing: MGSpacing.xs) {
                            Text(vm.destinationFolder.lastPathComponent.isEmpty ? vm.destinationFolder.path : vm.destinationFolder.lastPathComponent)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                                .help(vm.destinationFolder.path)
                            Button("选择…") { vm.chooseDestination() }
                            Button {
                                vm.openDownloadDirectory()
                            } label: {
                                Image(systemName: "arrow.right.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("在访达中显示")
                            .accessibilityLabel("在访达中显示")
                        }
                    }
                    Picker("Copy 图片并发", selection: $vm.copyImageConcurrency) {
                        ForEach(4...8, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Picker("Copy 图片质量", selection: $vm.copyImageQuality) {
                        ForEach(CopyImageQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                } header: {
                    Text("下载")
                } footer: {
                    footnote("Copy 章节并发固定为 3；图片请求使用 80–180ms 错峰和动态降速。")
                }

                Section {
                    LabeledContent("Cookie") {
                        HStack(spacing: 6) {
                            Group {
                                if revealCookie {
                                    TextField("Cookie", text: $vm.authCookie, prompt: Text("可选"))
                                } else {
                                    SecureField("Cookie", text: $vm.authCookie, prompt: Text("可选"))
                                }
                            }
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                            Button {
                                revealCookie.toggle()
                            } label: {
                                Image(systemName: revealCookie ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(revealCookie ? "隐藏 Cookie" : "显示 Cookie")
                            .accessibilityLabel(revealCookie ? "隐藏 Cookie" : "显示 Cookie")
                        }
                    }
                } header: {
                    Text("访问")
                } footer: {
                    footnote("仅在需要登录或访问受限章节时填写；留空即不发送。")
                }

                Section {
                    LabeledContent("站点入口") {
                        Menu("打开站点") {
                            ForEach(CopyMangaMirror.allCases) { mirror in
                                Button(mirror.displayName) { openInBrowser(mirror.webBaseURL.absoluteString) }
                            }
                            Divider()
                            Button("漫画柜") { openInBrowser("https://www.manhuagui.com") }
                            Button("包子漫画") { openInBrowser("https://www.baozimh.com") }
                        }
                        .fixedSize()
                    }
                    LabeledContent("缓存与当前解析结果") {
                        Button("清除…", role: .destructive) { showClearConfirmation = true }
                    }
                } header: {
                    Text("其他")
                } footer: {
                    footnote("清除当前输入、解析结果与缓存，不会删除下载文件。")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, -MGSpacing.content)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .alert("清空缓存？", isPresented: $showClearConfirmation) {
            Button("清缓存", role: .destructive) { vm.clearCaches() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前输入、解析结果和缓存内容，但不会删除已经下载到本地的文件。")
        }
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(MGFont.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openInBrowser(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
