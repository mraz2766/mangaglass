import AppKit
import SwiftUI

/// The standard macOS Settings window (⌘,): tabs of grouped native forms, sharing the main view model.
struct SettingsView: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        TabView {
            GeneralSettingsPane(vm: vm)
                .tabItem { Label("通用", systemImage: "gearshape") }
            DownloadSettingsPane(vm: vm)
                .tabItem { Label("下载", systemImage: "arrow.down.circle") }
            SitesSettingsPane(vm: vm)
                .tabItem { Label("账户与站点", systemImage: "globe") }
        }
        .frame(width: 560)
        .tint(MGTheme.accent)
        .preferredColorScheme(vm.preferredColorScheme)
        // Same rebuild trigger as the main window, so theme previews repaint.
        .id(vm.appearanceID)
    }
}

private struct GeneralSettingsPane: View {
    @ObservedObject var vm: MainViewModel

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(AppThemeStyle.allCases) { style in
                        ThemeCard(style: style, selected: vm.themeStyle == style) {
                            vm.themeStyle = style
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
            } header: {
                Text("主题")
            } footer: {
                Text(vm.themeStyle.detail).foregroundStyle(.secondary)
            }

            Section {
                Picker("外观", selection: $vm.themeMode) {
                    ForEach(AppThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("跟随系统强调色", isOn: $vm.followsSystemAccent)
            } footer: {
                Text("开启后，选中与主要按钮使用「系统设置 › 外观」里的强调色。").foregroundStyle(.secondary)
            }

            Section {
                Picker("关闭窗口时", selection: $vm.windowCloseBehavior) {
                    ForEach(WindowCloseBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior)
                    }
                }
            } footer: {
                Text(vm.windowCloseBehavior.detail + " ⌘Q 或菜单「退出」仍会询问并完全退出应用。").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct DownloadSettingsPane: View {
    @ObservedObject var vm: MainViewModel
    @State private var showClearConfirmation = false

    var body: some View {
        Form {
            Section("下载目录") {
                LabeledContent {
                    HStack {
                        Button("选择…") { vm.chooseDestination() }
                        Button("在访达中显示") { vm.openDownloadDirectory() }
                    }
                } label: {
                    Text(vm.destinationFolder.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(vm.destinationFolder.path)
                        .textSelection(.enabled)
                }
            }

            Section {
                Picker("下载节奏", selection: $vm.downloadPacingMode) {
                    ForEach(DownloadPacingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                Picker("Copy 图片质量", selection: $vm.copyImageQuality) {
                    ForEach(CopyImageQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(vm.downloadPacingMode.detail + " 所有站点都会在限流时自动降速，并在冷却后自动继续。")
                    PacingSummary(mode: vm.downloadPacingMode)
                }
                .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("缓存与当前解析结果") {
                    Button("清除…", role: .destructive) { showClearConfirmation = true }
                }
            } header: {
                Text("本地数据")
            } footer: {
                Text("清除当前输入、解析结果与缓存，不会删除已下载的文件。").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .alert("清空缓存？", isPresented: $showClearConfirmation) {
            Button("清缓存", role: .destructive) { vm.clearCaches() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会清空当前输入、解析结果和缓存内容，但不会删除已经下载到本地的文件。")
        }
    }
}

private struct SitesSettingsPane: View {
    @ObservedObject var vm: MainViewModel
    @State private var revealCookie = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Group {
                        if revealCookie {
                            TextField("Cookie", text: $vm.authCookie, prompt: Text("可选"))
                        } else {
                            SecureField("Cookie", text: $vm.authCookie, prompt: Text("可选"))
                        }
                    }
                    Button {
                        revealCookie.toggle()
                    } label: {
                        Image(systemName: revealCookie ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.borderless)
                    .help(revealCookie ? "隐藏 Cookie" : "显示 Cookie")
                    .accessibilityLabel(revealCookie ? "隐藏 Cookie" : "显示 Cookie")
                }
            } header: {
                Text("访问凭据")
            } footer: {
                Text("仅在需要登录或访问受限章节时填写；留空即不发送。").foregroundStyle(.secondary)
            }

            Section {
                ForEach(CopyMangaMirror.allCases) { mirror in
                    siteRow(mirror.displayName, mirror.webBaseURL)
                }
                if let url = URL(string: "https://www.manhuagui.com") { siteRow("漫画柜", url) }
                if let url = URL(string: "https://www.baozimh.com") { siteRow("包子漫画", url) }
            } header: {
                Text("站点入口")
            } footer: {
                Text("在默认浏览器中打开支持的站点。").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func siteRow(_ title: String, _ url: URL) -> some View {
        LabeledContent {
            Button("打开") { NSWorkspace.shared.open(url) }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(url.host ?? url.absoluteString).font(MGFont.caption).foregroundStyle(.secondary)
            }
        }
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
                    (palette.sidebar ?? palette.canvas)
                        .background(palette.glass ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.clear))
                        .frame(width: 18)
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
                .clipShape(RoundedRectangle(cornerRadius: MGRadius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: MGRadius.small, style: .continuous)
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
