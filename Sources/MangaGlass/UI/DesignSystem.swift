import AppKit
import SwiftUI

enum MGActionVariant {
    case primary
    case accent
    case danger
    case neutral
    case ghost
}

enum MGTheme {
    static let accent = Color(red: 0.18, green: 0.48, blue: 0.78)
    static let accentStrong = Color(red: 0.09, green: 0.38, blue: 0.82)
    static let accentSoft = Color(red: 0.79, green: 0.89, blue: 0.97)
    static let cyanAction = Color(red: 0.20, green: 0.67, blue: 0.86)
    static let success = Color(red: 0.16, green: 0.64, blue: 0.33)
    static let warning = Color(red: 0.82, green: 0.48, blue: 0.13)
    static let danger = Color(red: 0.86, green: 0.18, blue: 0.22)
    static let queued = Color(red: 0.46, green: 0.50, blue: 0.56)

    static func appBackground(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark
                ? [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.05, green: 0.06, blue: 0.08)]
                : [Color(red: 0.96, green: 0.98, blue: 0.99), Color(red: 0.91, green: 0.94, blue: 0.97)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static func panelFill(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.055 * prominence)
            : Color.white.opacity(0.55 * prominence)
    }

    static func insetFill(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.045 * prominence)
            : Color.white.opacity(0.30 * prominence)
    }

    static func stroke(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.12 * prominence)
            : Color.white.opacity(0.62 * prominence)
    }

    static func shadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.045)
    }

    static func statusColor(for state: DownloadTaskItem.State) -> Color {
        switch state {
        case .queued: return queued
        case .running: return accentStrong
        case .done: return success
        case .canceled: return warning
        case .failed: return danger
        }
    }

    static func statusFill(for state: DownloadTaskItem.State, scheme: ColorScheme) -> Color {
        let color = statusColor(for: state)
        return scheme == .dark ? color.opacity(0.20) : color.opacity(0.10)
    }
}

enum MGFont {
    static let appTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
    static let title = Font.system(size: 18, weight: .bold, design: .rounded)
    static let section = Font.system(size: 14, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 12, weight: .medium, design: .rounded)
    static let bodyStrong = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let caption = Font.system(size: 11, weight: .medium, design: .rounded)
    static let captionStrong = Font.system(size: 11, weight: .semibold, design: .rounded)
    static let micro = Font.system(size: 10, weight: .medium, design: .rounded)
    static let microStrong = Font.system(size: 10, weight: .semibold, design: .rounded)
    static let number = Font.system(size: 12, weight: .bold, design: .monospaced)
}

enum MGSpacing {
    static let page: CGFloat = 14
    static let panel: CGFloat = 12
    static let row: CGFloat = 8
    static let tight: CGFloat = 6
    static let controlX: CGFloat = 10
    static let controlY: CGFloat = 6
}

struct MGActionButtonStyle: ButtonStyle {
    let variant: MGActionVariant
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MGFont.bodyStrong)
            .padding(.horizontal, MGSpacing.controlX)
            .padding(.vertical, MGSpacing.controlY)
            .foregroundStyle(foreground)
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(stroke(configuration.isPressed), lineWidth: variant == .ghost ? 0 : 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var foreground: Color {
        switch variant {
        case .primary, .accent, .danger:
            return .white
        case .neutral, .ghost:
            return Color.primary.opacity(0.84)
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch variant {
        case .primary:
            return pressed ? MGTheme.accentStrong.opacity(0.92) : MGTheme.accentStrong
        case .accent:
            return pressed ? MGTheme.cyanAction.opacity(0.88) : MGTheme.cyanAction
        case .danger:
            return pressed ? MGTheme.danger.opacity(0.88) : MGTheme.danger
        case .neutral:
            let base = colorScheme == .dark ? Color.white : Color.black
            return base.opacity(pressed ? 0.16 : (isHovered ? 0.10 : 0.065))
        case .ghost:
            let base = colorScheme == .dark ? Color.white : Color.black
            return base.opacity(pressed ? 0.12 : (isHovered ? 0.075 : 0))
        }
    }

    private func stroke(_ pressed: Bool) -> Color {
        switch variant {
        case .primary:
            return Color.white.opacity(0.20)
        case .accent:
            return Color.white.opacity(0.22)
        case .danger:
            return Color.white.opacity(0.20)
        case .neutral:
            return MGTheme.stroke(for: colorScheme, prominence: pressed ? 0.85 : 0.55)
        case .ghost:
            return .clear
        }
    }
}

extension View {
    func mgPanel(cornerRadius: CGFloat = 12, prominence: Double = 1, shadow: Bool = true) -> some View {
        modifier(MGSurfaceModifier(cornerRadius: cornerRadius, prominence: prominence, shadow: shadow))
    }

    func mgInsetPanel(cornerRadius: CGFloat = 9, prominence: Double = 1) -> some View {
        modifier(MGInsetSurfaceModifier(cornerRadius: cornerRadius, prominence: prominence))
    }

    func mgStatusPill(tint: Color = MGTheme.accent, selected: Bool = false) -> some View {
        modifier(MGStatusPillModifier(tint: tint, selected: selected))
    }
}

private struct MGSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let prominence: Double
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(MGTheme.panelFill(for: colorScheme, prominence: prominence), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MGTheme.stroke(for: colorScheme), lineWidth: 0.8)
            )
            .shadow(color: shadow ? MGTheme.shadow(for: colorScheme) : .clear, radius: shadow ? 14 : 0, y: shadow ? 7 : 0)
    }
}

private struct MGInsetSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let prominence: Double

    func body(content: Content) -> some View {
        content
            .background(MGTheme.insetFill(for: colorScheme, prominence: prominence), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MGTheme.stroke(for: colorScheme, prominence: 0.55), lineWidth: 0.8)
            )
    }
}

private struct MGStatusPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let tint: Color
    let selected: Bool

    func body(content: Content) -> some View {
        content
            .font(MGFont.captionStrong)
            .foregroundStyle(selected ? tint : Color.primary.opacity(0.78))
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? tint.opacity(colorScheme == .dark ? 0.22 : 0.13) : MGTheme.insetFill(for: colorScheme))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(selected ? tint.opacity(0.42) : MGTheme.stroke(for: colorScheme, prominence: 0.45), lineWidth: 0.8)
            )
    }
}
