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
                        .font(.system(size: 18, weight: .semibold))
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
                HStack(spacing: 6) {
                    Text(record.siteName)
                    Text(relativeTime(record.updatedAt))
                        .help(absoluteTime(record.updatedAt))
                }
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                Text(record.input)
                    .font(MGFont.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(record.input)
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
        }
        .padding(MGSpacing.sm)
        .frame(minHeight: 76)
        .mgHoverBackground(radius: 0)
    }

    private static let relativeFormatter = RelativeDateTimeFormatter()

    private func relativeTime(_ date: Date) -> String {
        let now = Date()
        // Records saved this instant would read "0 秒钟后"; never show a future time.
        return Self.relativeFormatter.localizedString(for: min(date, now), relativeTo: now)
    }

    private func absoluteTime(_ date: Date) -> String {
        DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short)
    }
}

struct SettingsWorkspaceView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var formWidth: CGFloat = 720
    @State private var revealCookie = false
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: MGSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("设置")
                    .font(.system(size: 18, weight: .semibold))
                Text("外观、访问凭据和本地下载目录。")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: MGSpacing.lg) {

                settingsSection("主题", detail: vm.themeStyle.detail) {
                    Picker("主题", selection: $vm.themeStyle) {
                        ForEach(AppThemeStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                settingsSection("外观", detail: "每个主题都有浅色与深色两套配色，按这里的模式切换。") {
                    Picker("显示模式", selection: $vm.themeMode) {
                        ForEach(AppThemeMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                settingsSection("关闭窗口时", detail: vm.windowCloseBehavior.detail + " Command-Q 或菜单“退出”仍会询问并完全退出应用。") {
                    Picker("关闭窗口时", selection: $vm.windowCloseBehavior) {
                        ForEach(WindowCloseBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                settingsSection("下载目录", detail: vm.destinationFolder.path) {
                    HStack {
                        Text(vm.destinationFolder.lastPathComponent.isEmpty ? vm.destinationFolder.path : vm.destinationFolder.lastPathComponent)
                            .font(MGFont.bodyStrong)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(vm.destinationFolder.path)
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
                        .buttonStyle(MGActionButtonStyle(variant: .secondary, iconOnly: true))
                        .frame(width: 28, height: 28)
                        .help(revealCookie ? "隐藏 Cookie" : "显示 Cookie")
                    }
                }

                settingsSection("下载性能", detail: "Copy 章节并发固定为 3；图片请求继续使用 80–180ms 错峰和动态降速。") {
                    adaptiveSettingRow("Copy 图片并发") {
                        Picker("Copy 图片并发", selection: $vm.copyImageConcurrency) {
                            ForEach(4...8, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    adaptiveSettingRow("Copy 图片质量") {
                        Picker("Copy 图片质量", selection: $vm.copyImageQuality) {
                            ForEach(CopyImageQuality.allCases) { quality in
                                Text(quality.title).tag(quality)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }

                settingsSection("站点入口", detail: "在默认浏览器中打开支持站点。") {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: MGSpacing.xs) { siteButtons }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: MGSpacing.xs)], alignment: .leading, spacing: MGSpacing.xs) {
                            siteButtons
                        }
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
                .frame(maxWidth: 720, alignment: .leading)
                .padding(.bottom, MGSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(GeometryReader { proxy in
                Color.clear.onAppear { formWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { formWidth = $0 }
            })
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
        VStack(alignment: .leading, spacing: 16) {
            let layout = formWidth >= 600
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            layout {
                Text(title).font(MGFont.section)
                    .lineLimit(1)
                    .frame(width: formWidth >= 600 ? 112 : nil, alignment: .leading)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 10) {
                    content()
                    Text(detail).font(MGFont.caption).foregroundStyle(.secondary)
                        .lineLimit(title == "下载目录" ? 1 : nil)
                        .truncationMode(.middle).help(detail).textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func adaptiveSettingRow<Control: View>(
        _ title: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        let layout = formWidth >= 600
            ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
        return layout {
            Text(title)
                .font(MGFont.body)
                .frame(width: formWidth >= 600 ? 112 : nil, alignment: .leading)
            control()
        }
    }

    @ViewBuilder private var siteButtons: some View {
        ForEach(CopyMangaMirror.allCases) { mirror in
            Button(mirror.displayName) {
                openInBrowser(mirror.webBaseURL.absoluteString)
            }
            .buttonStyle(MGActionButtonStyle(variant: .secondary))
            .help(mirror.webBaseURL.host ?? mirror.displayName)
        }
        Button("漫画柜") { openInBrowser("https://www.manhuagui.com") }
            .buttonStyle(MGActionButtonStyle(variant: .secondary))
        Button("包子漫画") { openInBrowser("https://www.baozimh.com") }
            .buttonStyle(MGActionButtonStyle(variant: .secondary))
    }

    private func openInBrowser(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }
}
