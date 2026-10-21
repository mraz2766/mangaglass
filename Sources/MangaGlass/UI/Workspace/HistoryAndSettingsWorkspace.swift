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
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("书架").font(.system(size: 22, weight: .semibold))
                Text("\(records.count) 部").font(MGFont.caption).foregroundStyle(.secondary)
                Spacer()
                Button("清空书架", role: .destructive) { showClearConfirmation = true }
                    .buttonStyle(MGActionButtonStyle(variant: .ghost))
                    .disabled(records.isEmpty)
            }

            if records.isEmpty {
                MGEmptyState(
                    title: "书架还是空的",
                    systemImage: "books.vertical",
                    detail: "在首页解析过的漫画会摆在这里，点一下就能回到它。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 128, maximum: 168), spacing: 20, alignment: .top)],
                              alignment: .leading, spacing: 24) {
                        ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                            shelfItem(record)
                                .mgStaggerAppear(index: index * 2)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: records.map(\.id))
        .onAppear { MGRevealClock.mark() }
        .alert("清空书架？", isPresented: $showClearConfirmation) {
            Button("清空", role: .destructive) { vm.clearRecentRecords() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将移除 \(records.count) 部最近打开的漫画，不会影响已经下载到本地的文件。")
        }
    }

    private func shelfItem(_ record: RecentComicRecord) -> some View {
        Button {
            vm.applyRecentRecord(record)
            openDownload()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                MGBookCover(url: record.coverURL, title: record.title)
                    .aspectRatio(0.72, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .mgHoverLift()
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.title).font(MGFont.bodyStrong).lineLimit(2)
                    HStack(spacing: 4) {
                        Text(record.siteName)
                        Text("·")
                        Text(relativeTime(record.updatedAt)).help(absoluteTime(record.updatedAt))
                    }
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    if CopyMangaMirror.isRetired(record.input) {
                        Text("站点已停用").font(MGFont.caption).foregroundStyle(MGTheme.danger)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(record.input)
        .contextMenu {
            Button("打开") {
                vm.applyRecentRecord(record)
                openDownload()
            }
            Button("复制链接") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(record.input, forType: .string)
            }
            Divider()
            Button("从书架移除", role: .destructive) { vm.removeRecentRecord(record) }
        }
        .accessibilityLabel("\(record.title)，\(record.siteName)")
        .accessibilityHint("打开这部漫画")
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
                    HStack(spacing: 12) {
                        ForEach(AppThemeStyle.allCases) { style in
                            ThemeCard(style: style, selected: vm.themeStyle == style) {
                                vm.themeStyle = style
                            }
                        }
                    }
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

                settingsSection("下载节奏", detail: vm.downloadPacingMode.detail + " 所有站点都会在限流时自动降速，并在冷却后自动继续。") {
                    adaptiveSettingRow("节奏") {
                        Picker("下载节奏", selection: $vm.downloadPacingMode) {
                            ForEach(DownloadPacingMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                    PacingSummary(mode: vm.downloadPacingMode)
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

/// Theme option drawn as a tiny window: sidebar, two chapter cells (one selected) and the accent button.
private struct ThemeCard: View {
    let style: AppThemeStyle
    let selected: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let palette = MGPalette.forStyle(style)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    (palette.sidebar ?? palette.canvas).frame(width: 18)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(palette.selectedFill).frame(height: 14)
                            RoundedRectangle(cornerRadius: 3).fill(palette.cell).frame(height: 14)
                        }
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 3).fill(palette.cell).frame(height: 14)
                            RoundedRectangle(cornerRadius: 3).fill(palette.cell).frame(height: 14)
                        }
                        Spacer(minLength: 0)
                        HStack {
                            Spacer()
                            Capsule().fill(palette.accent).frame(width: 34, height: 10)
                        }
                    }
                    .padding(8)
                    .background(palette.canvas)
                }
                .frame(width: 124, height: 78)
                .background(palette.glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(selected ? MGTheme.accent : MGTheme.palette.divider, lineWidth: selected ? 2 : 0.5)
                }
                .scaleEffect(hovering && !reduceMotion ? 1.03 : 1)
                Text(style.title)
                    .font(selected ? MGFont.bodyStrong : MGFont.body)
                    .foregroundStyle(selected ? MGTheme.accent : Color.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.75), value: hovering)
        .animation(reduceMotion ? nil : MGMotion.regular, value: selected)
        .accessibilityLabel("主题：\(style.title)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Per-site numbers behind the selected pacing mode, so the choice isn't a black box.
private struct PacingSummary: View {
    let mode: DownloadPacingMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach([SiteFamily.manhuaGui, .copy, .other], id: \.self) { family in
                let pacing = SitePacing.make(mode: mode, family: family)
                Text("\(family.title)：\(Self.range(pacing.chapterConcurrency)) 话并发 · 图片间隔 \(pacing.imageSpacingMS.lowerBound)–\(pacing.imageSpacingMS.upperBound)ms · 每 \(pacing.restEveryChapters) 话休息约 \(pacing.restSeconds.lowerBound)s")
                    .font(MGFont.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private static func range(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }
}
