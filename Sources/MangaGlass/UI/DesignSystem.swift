import SwiftUI

enum MGActionVariant {
    case primary
    case secondary
    case destructive
    case ghost
}

enum MGTheme {
    static let accent = Color(red: 0.039, green: 0.357, blue: 0.847)
    static let accentStrong = Color(red: 0.027, green: 0.278, blue: 0.690)
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)
    static let danger = Color(nsColor: .systemRed)
    static let queued = Color.secondary

    static func background(for scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.075, green: 0.078, blue: 0.090)
            : Color(red: 0.965, green: 0.967, blue: 0.973)
    }

    static func surface(for scheme: ColorScheme, elevated: Bool = false) -> Color {
        if scheme == .dark {
            return Color.white.opacity(elevated ? 0.070 : 0.045)
        }
        return Color.white.opacity(elevated ? 0.94 : 0.78)
    }

    static func inset(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.045)
    }

    static func divider(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.10)
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
    static let appTitle = Font.system(size: 15, weight: .semibold)
    static let title = Font.system(size: 22, weight: .bold)
    static let section = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 13, weight: .regular)
    static let bodyStrong = Font.system(size: 13, weight: .semibold)
    static let caption = Font.system(size: 11, weight: .regular)
    static let captionStrong = Font.system(size: 11, weight: .semibold)
    static let mono = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let number = Font.system(size: 12, weight: .semibold, design: .monospaced)
}

enum MGSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
}

struct MGActionButtonStyle: ButtonStyle {
    let variant: MGActionVariant
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MGFont.bodyStrong)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(background(pressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(border, lineWidth: variant == .ghost ? 0 : 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch variant {
        case .primary, .destructive: return .white
        case .secondary, .ghost: return .primary.opacity(0.86)
        }
    }

    private func background(pressed: Bool) -> Color {
        switch variant {
        case .primary:
            return (pressed ? MGTheme.accentStrong : MGTheme.accent)
        case .destructive:
            return pressed ? MGTheme.danger.opacity(0.82) : MGTheme.danger
        case .secondary:
            return MGTheme.inset(for: colorScheme).opacity(pressed ? 1.55 : 1)
        case .ghost:
            return Color.clear
        }
    }

    private var border: Color {
        switch variant {
        case .primary, .destructive: return Color.white.opacity(0.22)
        case .secondary: return MGTheme.divider(for: colorScheme)
        case .ghost: return .clear
        }
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
            .background(selected ? tint.opacity(colorScheme == .dark ? 0.25 : 0.12) : MGTheme.inset(for: colorScheme).opacity(0.56), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(selected ? tint.opacity(0.55) : MGTheme.divider(for: colorScheme).opacity(0.7), lineWidth: 0.8)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
    func mgSurface(elevated: Bool = false, radius: CGFloat = 12) -> some View {
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
                    .stroke(MGTheme.divider(for: colorScheme).opacity(elevated ? 1 : 0.72), lineWidth: 0.8)
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
            .padding(.vertical, 8)
            .background(MGTheme.inset(for: colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MGTheme.divider(for: colorScheme), lineWidth: 0.8)
            }
    }
}
