import SwiftUI

/// Compact, semantic status feedback inspired by Fluid Functionalism's motion tiers.
struct MGActivityMark: View {
    let isLoading: Bool
    let hasResult: Bool
    let hasError: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    private var title: String {
        isLoading ? "正在解析" : (hasError ? "解析失败" : (hasResult ? "目录已就绪" : "等待漫画链接"))
    }
    private var tint: Color {
        hasError ? MGTheme.danger : ((isLoading || hasResult) ? MGTheme.accent : .secondary)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isLoading || reduceMotion)) { context in
            HStack(spacing: 3) {
                ForEach(0..<3) { index in
                    let wave = sin(context.date.timeIntervalSinceReferenceDate * 5 - Double(index) * 0.9)
                    Circle().fill(tint)
                        .frame(width: 5, height: 5)
                        .opacity(isLoading && !reduceMotion ? 0.55 + wave * 0.35 : (hovering ? 1 : 0.7))
                        .offset(y: reduceMotion ? 0 : (isLoading ? wave * 2 : (hovering && index == 1 ? -2 : 0)))
                }
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : MGMotion.regular, value: hovering)
        .animation(reduceMotion ? nil : MGMotion.fast, value: hasResult)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .help(title)
    }
}

enum MGSelectionState {
    case none, partial, all
    var symbol: String {
        switch self {
        case .none: return "square"
        case .partial: return "minus.square.fill"
        case .all: return "checkmark.square.fill"
        }
    }
    var description: String {
        switch self {
        case .none: return "未选中"
        case .partial: return "部分选中"
        case .all: return "全部选中"
        }
    }
}

struct MGGroupSelectionButton: View {
    let title: String
    let state: MGSelectionState
    let action: () -> Void
    private var actionTitle: String { state == .all ? "取消本组选择" : "全选本组" }

    var body: some View {
        Button(action: action) {
            Image(systemName: state.symbol)
                .foregroundStyle(state == .none ? Color.secondary : MGTheme.accent)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(MGActionButtonStyle(variant: .secondary, iconOnly: true))
        .help(actionTitle)
        .accessibilityLabel("\(title)：\(actionTitle)")
        .accessibilityValue(state.description)
    }
}

struct MGChapterSelectionCell: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: selected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(selected ? MGTheme.accent : .secondary)
                Text(title).font(MGFont.body).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 38)
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(MGChoiceButtonStyle(selected: selected))
        .help(title).accessibilityLabel(title).accessibilityValue(selected ? "已选择" : "未选择")
    }
}

enum MGActionVariant {
    case primary
    case secondary
    case destructive
    case ghost
}

enum MGTheme {
    static let accent = Color(nsColor: .systemBlue)
    static let accentStrong = Color(nsColor: .systemBlue).opacity(0.82)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let queued = Color.secondary

    static func background(for scheme: ColorScheme) -> Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static func surface(for scheme: ColorScheme, elevated: Bool = false) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func inset(for scheme: ColorScheme) -> Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static func divider(for scheme: ColorScheme) -> Color {
        Color(nsColor: .separatorColor)
    }

    static func statusColor(for state: DownloadTaskItem.State) -> Color {
        switch state {
        case .queued: return queued
        case .running: return accent
        case .done: return success
        case .canceled: return warning
        case .failed: return danger
        }
    }
}

enum MGFont {
    static let appTitle = Font.system(size: 14, weight: .semibold)
    static let title = Font.system(size: 22, weight: .semibold)
    static let section = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyStrong = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12, weight: .regular)
    static let captionStrong = Font.system(size: 12, weight: .medium)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let number = Font.system(size: 12, weight: .semibold, design: .monospaced)
}

enum MGSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let content: CGFloat = 20
}

enum MGMotion {
    static let fast = Animation.easeOut(duration: 0.08)
    static let regular = Animation.easeInOut(duration: 0.16)
    static let panel = Animation.easeInOut(duration: 0.24)
}

struct MGActionButtonStyle: ButtonStyle {
    let variant: MGActionVariant
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        MGActionBody(configuration: configuration, variant: variant, iconOnly: iconOnly)
    }
}

private struct MGActionBody: View {
    let configuration: ButtonStyle.Configuration
    let variant: MGActionVariant
    let iconOnly: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(MGFont.bodyStrong)
            .foregroundStyle(!enabled ? Color.secondary : (variant == .primary || variant == .destructive ? .white : .primary))
            .padding(.horizontal, iconOnly ? 0 : 10)
            .frame(minWidth: iconOnly ? 28 : nil, minHeight: variant == .primary ? 32 : 28)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(focused ? MGTheme.accent : (variant == .secondary ? MGTheme.divider(for: scheme) : .clear), lineWidth: focused ? 2 : 0.7)
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
            .animation(reduceMotion ? nil : MGMotion.fast, value: configuration.isPressed)
    }

    private var fill: Color {
        guard enabled else { return Color.primary.opacity(0.035) }
        if variant == .primary || variant == .destructive {
            let color = variant == .primary ? MGTheme.accent : MGTheme.danger
            return color.opacity(configuration.isPressed ? 0.75 : (hovering ? 0.88 : 1))
        }
        return Color.primary.opacity(configuration.isPressed ? 0.09 : (hovering ? 0.055 : (variant == .secondary ? 0.025 : 0)))
    }
}

struct MGChoiceButtonStyle: ButtonStyle {
    let selected: Bool
    var bordered = true

    func makeBody(configuration: Configuration) -> some View {
        MGChoiceBody(configuration: configuration, selected: selected, bordered: bordered)
    }
}

private struct MGChoiceBody: View {
    let configuration: ButtonStyle.Configuration
    let selected: Bool
    let bordered: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(selected ? MGTheme.accent : .primary)
            .background(fill, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6).stroke(
                    focused ? MGTheme.accent : (selected && bordered ? MGTheme.accent.opacity(0.6) :
                        (bordered ? MGTheme.divider(for: scheme).opacity(0.75) : .clear)),
                    lineWidth: focused ? 2 : (selected ? 1 : 0.7))
            }
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
            .animation(reduceMotion ? nil : MGMotion.fast, value: selected)
            .animation(reduceMotion ? nil : MGMotion.fast, value: configuration.isPressed)
    }

    private var fill: Color {
        let active = enabled && (hovering || configuration.isPressed)
        if selected { return MGTheme.accent.opacity((scheme == .dark ? 0.20 : 0.10) + (active ? 0.07 : 0)) }
        return Color.primary.opacity(active ? 0.065 : (bordered ? 0.025 : 0))
    }
}

struct MGSearchField: View {
    let title: String
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var undoStack: [String] = []
    @State private var previousText = ""
    @State private var isApplyingUndo = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onAppear { previousText = text }
                .onChange(of: text) { newValue in
                    if isApplyingUndo {
                        isApplyingUndo = false
                    } else if previousText != newValue {
                        undoStack.append(previousText)
                        if undoStack.count > 50 { undoStack.removeFirst(undoStack.count - 50) }
                    }
                    previousText = newValue
                }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .help("清除搜索")
                    .accessibilityLabel("清除搜索")
            }
        }
        .font(MGFont.body)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .mgInset(radius: 6)
        .overlay { RoundedRectangle(cornerRadius: 6).stroke(focused ? MGTheme.accent : .clear, lineWidth: 2) }
        .background {
            Button(action: undoSearch) { Color.clear.frame(width: 1, height: 1) }
                .keyboardShortcut("z", modifiers: .control)
                .disabled(!focused || undoStack.isEmpty)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private func undoSearch() {
        guard focused, let previous = undoStack.popLast() else { return }
        isApplyingUndo = true
        text = previous
    }
}

struct MGSelectionButtonStyle: ButtonStyle {
    let selected: Bool
    var tint: Color = MGTheme.accent
    var font: Font = MGFont.captionStrong
    var horizontalPadding: CGFloat = 9
    var verticalPadding: CGFloat = 6
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .foregroundStyle(selected ? tint : Color.primary.opacity(0.78))
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(minHeight: 28)
            .background(selected ? tint.opacity(colorScheme == .dark ? 0.20 : 0.10) : (configuration.isPressed ? MGTheme.divider(for: colorScheme).opacity(0.45) : Color.clear), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct MGEmptyState: View {
    let title: String
    let systemImage: String
    let detail: String

    var body: some View {
        VStack(spacing: MGSpacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(MGFont.section)
            Text(detail)
                .font(MGFont.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(MGSpacing.lg)
    }
}

extension View {
    func mgSurface(elevated: Bool = false, radius: CGFloat = 10) -> some View {
        modifier(MGSurfaceModifier(elevated: elevated, radius: radius))
    }

    func mgInset(radius: CGFloat = 8) -> some View {
        modifier(MGInsetModifier(radius: radius))
    }

    func mgStatusTag(tint: Color = MGTheme.accent, active: Bool = true) -> some View {
        modifier(MGStatusTagModifier(tint: tint, active: active))
    }

    func mgTextField() -> some View {
        modifier(MGTextFieldModifier())
    }

    func mgHoverBackground(radius: CGFloat = 6) -> some View {
        modifier(MGHoverBackgroundModifier(radius: radius))
    }
}

private struct MGSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let elevated: Bool
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(MGTheme.surface(for: colorScheme, elevated: elevated), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MGTheme.divider(for: colorScheme).opacity(elevated ? 0.8 : 0), lineWidth: 0.6)
            }
    }
}

private struct MGInsetModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(MGTheme.inset(for: colorScheme), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MGTheme.divider(for: colorScheme).opacity(0.6), lineWidth: 0.8)
            }
    }
}

private struct MGStatusTagModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    let active: Bool

    func body(content: Content) -> some View {
        content
            .font(MGFont.captionStrong)
            .foregroundStyle(active ? tint : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(active ? tint.opacity(colorScheme == .dark ? 0.22 : 0.11) : MGTheme.inset(for: colorScheme), in: Capsule())
    }
}

private struct MGTextFieldModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(MGFont.body)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .background(MGTheme.inset(for: colorScheme), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(MGTheme.divider(for: colorScheme), lineWidth: 0.6)
            }
    }
}

private struct MGHoverBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(hovering ? (colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)) : .clear,
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
    }
}
