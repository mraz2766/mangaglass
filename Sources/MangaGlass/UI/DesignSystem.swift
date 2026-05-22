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
    static var activeTheme: AppColorTheme {
        let raw = UserDefaults.standard.string(forKey: "colorTheme") ?? AppColorTheme.classicBlue.rawValue
        return AppColorTheme(rawValue: raw) ?? .classicBlue
    }

    static var accent: Color {
        switch activeTheme {
        case .classicBlue:
            return Color(red: 0.18, green: 0.48, blue: 0.78)
        case .nordicAurora:
            return Color(red: 1.00, green: 0.34, blue: 0.00) // 极致工业安全橙 #FF5700
        case .champagneLuxury:
            return Color(red: 0.77, green: 0.63, blue: 0.35) // 拉丝黄铜金 #C5A059
        case .cyberNeon:
            return Color(red: 0.00, green: 0.54, blue: 0.48) // 禅意松石翠绿 #00897B
        }
    }

    static var accentStrong: Color {
        switch activeTheme {
        case .classicBlue:
            return Color(red: 0.09, green: 0.38, blue: 0.82)
        case .nordicAurora:
            return Color(red: 0.10, green: 0.10, blue: 0.12) // 信号钛黑
        case .champagneLuxury:
            return Color(red: 0.56, green: 0.43, blue: 0.23) // 中古铜金
        case .cyberNeon:
            return Color(red: 0.00, green: 0.30, blue: 0.25) // 深黛水墨绿
        }
    }

    static var accentSoft: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let theme = activeTheme
            if isDark {
                switch theme {
                case .classicBlue: return NSColor(red: 0.18, green: 0.48, blue: 0.78, alpha: 0.24)
                case .nordicAurora: return NSColor(red: 1.00, green: 0.34, blue: 0.00, alpha: 0.16)
                case .champagneLuxury: return NSColor(red: 0.77, green: 0.63, blue: 0.35, alpha: 0.16)
                case .cyberNeon: return NSColor(red: 0.00, green: 0.54, blue: 0.48, alpha: 0.16)
                }
            } else {
                switch theme {
                case .classicBlue: return NSColor(red: 0.79, green: 0.89, blue: 0.97, alpha: 1.0)
                case .nordicAurora: return NSColor(red: 1.00, green: 0.94, blue: 0.92, alpha: 1.0) // 温暖安全浅橙底色
                case .champagneLuxury: return NSColor(red: 0.96, green: 0.92, blue: 0.86, alpha: 1.0) // 中古羊皮纸底色
                case .cyberNeon: return NSColor(red: 0.00, green: 0.54, blue: 0.48, alpha: 0.08)
                }
            }
        })
    }

    static var cyanAction: Color {
        accent
    }
    
    static var success: Color {
        Color(nsColor: .systemGreen)
    }
    static var warning: Color {
        Color(nsColor: .systemOrange)
    }
    static var danger: Color {
        Color(nsColor: .systemRed)
    }
    static var queued: Color {
        Color(nsColor: .systemGray)
    }

    static var cornerRadius: CGFloat {
        switch activeTheme {
        case .classicBlue:
            return 12
        case .nordicAurora:
            return 10  // 润角工业钛金圆角（彻底告别直角）
        case .champagneLuxury:
            return 10  // 典雅温润书卷圆角（彻底告别直角）
        case .cyberNeon:
            return 12  // 禅意温润如玉大圆角
        }
    }

    static var fontDesign: Font.Design {
        switch activeTheme {
        case .classicBlue:
            return .rounded
        case .nordicAurora:
            return .default    // 现代无衬线理性几何
        case .champagneLuxury:
            return .serif      // 中古人文典雅衬线
        case .cyberNeon:
            return .serif      // 东方古典雅致衬线
        }
    }

    static func appBackground(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark ? darkBackgroundColors : lightBackgroundColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static var lightBackgroundColors: [Color] {
        switch activeTheme {
        case .classicBlue:
            return [Color(red: 0.96, green: 0.98, blue: 0.99), Color(red: 0.91, green: 0.94, blue: 0.97)]
        case .nordicAurora:
            return [Color(red: 0.93, green: 0.93, blue: 0.94), Color(red: 0.88, green: 0.88, blue: 0.89)] // 阳极氧化钛合金浅灰
        case .champagneLuxury:
            return [Color(red: 0.98, green: 0.96, blue: 0.92), Color(red: 0.93, green: 0.90, blue: 0.84)] // 中古手工羊皮宣纸色
        case .cyberNeon:
            return [Color(red: 0.95, green: 0.96, blue: 0.94), Color(red: 0.89, green: 0.91, blue: 0.88)] // 禅意温润浅竹素白
        }
    }

    private static var darkBackgroundColors: [Color] {
        switch activeTheme {
        case .classicBlue:
            return [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.05, green: 0.06, blue: 0.08)]
        case .nordicAurora:
            return [Color(red: 0.09, green: 0.09, blue: 0.10), Color(red: 0.05, green: 0.05, blue: 0.06)] // 工业冷峻信号黑
        case .champagneLuxury:
            return [Color(red: 0.10, green: 0.09, blue: 0.07), Color(red: 0.06, green: 0.05, blue: 0.04)]
        case .cyberNeon:
            return [Color(red: 0.08, green: 0.10, blue: 0.11), Color(red: 0.04, green: 0.05, blue: 0.06)] // 湿润青石板黛绿黑
        }
    }

    static func panelFill(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        switch activeTheme {
        case .classicBlue:
            return scheme == .dark
                ? Color.black.opacity(0.28 * prominence)
                : Color.white.opacity(0.82 * prominence)
        case .nordicAurora:
            return scheme == .dark
                ? Color(red: 0.13, green: 0.13, blue: 0.15).opacity(0.95 * prominence) // 工业黑钛金质地
                : Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.92 * prominence) // 钛铝合金面板
        case .champagneLuxury:
            return scheme == .dark
                ? Color(red: 0.12, green: 0.11, blue: 0.09).opacity(0.95 * prominence)
                : Color(red: 0.97, green: 0.95, blue: 0.90).opacity(0.96 * prominence)
        case .cyberNeon:
            return scheme == .dark
                ? Color(red: 0.11, green: 0.13, blue: 0.14).opacity(0.95 * prominence) // 雨后湿石板绿黑底色
                : Color(red: 0.97, green: 0.97, blue: 0.96).opacity(0.96 * prominence) // 素雅竹素白玉面板
        }
    }

    static func insetFill(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        switch activeTheme {
        case .classicBlue:
            return scheme == .dark
                ? Color.black.opacity(0.18 * prominence)
                : Color.white.opacity(0.42 * prominence)
        case .nordicAurora:
            return scheme == .dark
                ? Color(red: 0.08, green: 0.08, blue: 0.09).opacity(prominence)
                : Color(red: 0.89, green: 0.89, blue: 0.91).opacity(prominence)
        case .champagneLuxury:
            return scheme == .dark
                ? Color(red: 0.08, green: 0.07, blue: 0.06).opacity(0.85 * prominence)
                : Color(red: 0.93, green: 0.90, blue: 0.84).opacity(0.88 * prominence)
        case .cyberNeon:
            return scheme == .dark
                ? Color(red: 0.05, green: 0.07, blue: 0.08).opacity(prominence)
                : Color(red: 0.93, green: 0.93, blue: 0.91).opacity(prominence) // 凹陷竹青茶洗暗槽
        }
    }

    static func stroke(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        switch activeTheme {
        case .classicBlue:
            return scheme == .dark
                ? Color.white.opacity(0.12 * prominence)
                : Color.white.opacity(0.62 * prominence)
        case .nordicAurora:
            return scheme == .dark
                ? Color(red: 0.24, green: 0.24, blue: 0.26).opacity(0.80 * prominence) // 银灰钛金装配槽线
                : Color(red: 0.72, green: 0.72, blue: 0.75).opacity(0.70 * prominence)
        case .champagneLuxury:
            return scheme == .dark
                ? Color(red: 0.56, green: 0.43, blue: 0.23).opacity(0.75 * prominence)
                : Color(red: 0.77, green: 0.63, blue: 0.35).opacity(0.80 * prominence)
        case .cyberNeon:
            return scheme == .dark
                ? Color(red: 0.00, green: 0.54, blue: 0.48).opacity(0.20 * prominence) // 极简松石绿接缝
                : Color(red: 0.00, green: 0.54, blue: 0.48).opacity(0.18 * prominence)
        }
    }

    static func shadow(for scheme: ColorScheme) -> Color {
        switch activeTheme {
        case .classicBlue:
            return scheme == .dark ? Color.black.opacity(0.24) : Color.black.opacity(0.045)
        case .nordicAurora:
            return scheme == .dark
                ? Color.black.opacity(0.35) // 硬朗投影
                : Color.black.opacity(0.08)
        case .champagneLuxury:
            return scheme == .dark
                ? Color.black.opacity(0.45)
                : Color(red: 0.30, green: 0.22, blue: 0.12).opacity(0.08)
        case .cyberNeon:
            return scheme == .dark
                ? Color.black.opacity(0.35)
                : Color(red: 0.08, green: 0.12, blue: 0.10).opacity(0.045) // 极淡翠玉阴影
        }
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
    static var appTitle: Font { Font.system(size: 15, weight: .semibold, design: MGTheme.fontDesign) }
    static var title: Font { Font.system(size: 18, weight: .bold, design: MGTheme.fontDesign) }
    static var section: Font { Font.system(size: 14, weight: .semibold, design: MGTheme.fontDesign) }
    static var body: Font { Font.system(size: 12, weight: .medium, design: MGTheme.fontDesign) }
    static var bodyStrong: Font { Font.system(size: 12, weight: .semibold, design: MGTheme.fontDesign) }
    static var caption: Font { Font.system(size: 11, weight: .medium, design: MGTheme.fontDesign) }
    static var captionStrong: Font { Font.system(size: 11, weight: .semibold, design: MGTheme.fontDesign) }
    static var micro: Font { Font.system(size: 10, weight: .medium, design: MGTheme.fontDesign) }
    static var microStrong: Font { Font.system(size: 10, weight: .semibold, design: MGTheme.fontDesign) }
    static var number: Font { Font.system(size: 12, weight: .bold, design: .monospaced) }
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
    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    var theme: AppColorTheme {
        AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
    }
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var cornerRadius: CGFloat {
        if theme == .classicBlue {
            return 8
        } else {
            return MGTheme.cornerRadius
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MGFont.bodyStrong)
            .padding(.horizontal, MGSpacing.controlX)
            .padding(.vertical, MGSpacing.controlY)
            .foregroundStyle(foreground)
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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
        if theme == .cyberNeon {
            switch variant {
            case .primary, .accent:
                return .white  // 墨色背景配纯白字，传统优雅
            case .danger:
                return .white
            case .neutral, .ghost:
                return Color(red: 0.00, green: 0.54, blue: 0.48) // 经典松石绿文字
            }
        } else {
            switch variant {
            case .primary, .accent, .danger:
                return .white
            case .neutral, .ghost:
                return Color.primary.opacity(0.84)
            }
        }
    }

    private func background(_ pressed: Bool) -> Color {
        if theme == .cyberNeon {
            switch variant {
            case .primary:
                return pressed ? Color(red: 0.00, green: 0.44, blue: 0.38) : Color(red: 0.00, green: 0.54, blue: 0.48)
            case .accent:
                return pressed ? Color(red: 0.00, green: 0.40, blue: 0.35) : Color(red: 0.00, green: 0.50, blue: 0.44)
            case .danger:
                return pressed ? MGTheme.danger.opacity(0.88) : MGTheme.danger
            case .neutral:
                return Color(red: 0.00, green: 0.54, blue: 0.48).opacity(pressed ? 0.16 : (isHovered ? 0.10 : 0.04))
            case .ghost:
                return Color(red: 0.00, green: 0.54, blue: 0.48).opacity(pressed ? 0.10 : (isHovered ? 0.06 : 0.0))
            }
        } else {
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
    }

    private func stroke(_ pressed: Bool) -> Color {
        if theme == .cyberNeon {
            switch variant {
            case .primary, .accent:
                return Color.white.opacity(0.15)
            case .danger:
                return Color.white.opacity(0.20)
            case .neutral:
                return Color(red: 0.00, green: 0.54, blue: 0.48).opacity(pressed ? 0.70 : (isHovered ? 0.50 : 0.28))
            case .ghost:
                return .clear
            }
        } else {
            switch variant {
            case .primary:
                return Color.white.opacity(0.20)
            case .accent:
                return Color.white.opacity(0.22)
            case .danger:
                return Color.white.opacity(0.20)
            case .neutral:
                if theme == .classicBlue {
                    return MGTheme.stroke(for: colorScheme, prominence: pressed ? 0.85 : 0.55)
                } else {
                    return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08)
                }
            case .ghost:
                return .clear
            }
        }
    }
}

struct MGSelectionButtonStyle: ButtonStyle {
    let selected: Bool
    var tint: Color = MGTheme.accentStrong
    var font: Font = MGFont.captionStrong
    var horizontalPadding: CGFloat = 9
    var verticalPadding: CGFloat = 6
    var cornerRadius: CGFloat = 8

    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var theme: AppColorTheme {
        AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
    }

    private var actualRadius: CGFloat {
        theme == .classicBlue ? cornerRadius : max(0, MGTheme.cornerRadius - 2)
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(font)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(foreground)
            .background(background(configuration.isPressed), in: RoundedRectangle(cornerRadius: actualRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: actualRadius, style: .continuous)
                    .stroke(stroke(configuration.isPressed), lineWidth: 0.8)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
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
        if selected {
            return .white
        }
        if theme == .cyberNeon {
            return MGTheme.accent.opacity(isHovered ? 0.94 : 0.78)
        }
        return Color.primary.opacity(isHovered ? 0.92 : 0.78)
    }

    private func background(_ pressed: Bool) -> Color {
        if selected {
            return pressed ? tint.opacity(0.88) : tint
        }
        if theme == .classicBlue {
            let base = colorScheme == .dark ? Color.white : Color.black
            return base.opacity(pressed ? 0.14 : (isHovered ? 0.09 : 0.055))
        }
        return MGTheme.insetFill(for: colorScheme, prominence: pressed ? 1.08 : (isHovered ? 0.92 : 0.64))
    }

    private func stroke(_ pressed: Bool) -> Color {
        if selected {
            return Color.white.opacity(pressed ? 0.18 : 0.24)
        }
        if theme == .classicBlue {
            return MGTheme.stroke(for: colorScheme, prominence: pressed ? 0.75 : 0.46)
        }
        return MGTheme.stroke(for: colorScheme, prominence: pressed ? 0.70 : (isHovered ? 0.52 : 0.28))
    }
}

extension View {
    func mgPanel(cornerRadius: CGFloat = 12, prominence: Double = 1, shadow: Bool = true) -> some View {
        let theme = MGTheme.activeTheme
        let actualRadius = theme == .classicBlue ? cornerRadius : MGTheme.cornerRadius
        return modifier(MGSurfaceModifier(cornerRadius: actualRadius, prominence: prominence, shadow: shadow))
    }

    func mgInsetPanel(cornerRadius: CGFloat = 9, prominence: Double = 1) -> some View {
        let theme = MGTheme.activeTheme
        let actualRadius: CGFloat
        if theme == .classicBlue {
            actualRadius = cornerRadius
        } else {
            actualRadius = max(0, MGTheme.cornerRadius - (MGTheme.cornerRadius > 4 ? 2 : 1))
        }
        return modifier(MGInsetSurfaceModifier(cornerRadius: actualRadius, prominence: prominence))
    }

    func mgStatusPill(tint: Color = MGTheme.accent, selected: Bool = false) -> some View {
        modifier(MGStatusPillModifier(tint: tint, selected: selected))
    }

    func mgSegmentContainer(cornerRadius: CGFloat = 10, prominence: Double = 0.72) -> some View {
        let theme = MGTheme.activeTheme
        let actualRadius = theme == .classicBlue ? cornerRadius : max(0, MGTheme.cornerRadius - 1)
        return modifier(MGSegmentContainerModifier(cornerRadius: actualRadius, prominence: prominence))
    }

    func mgRefractiveShine() -> some View {
        modifier(MGRefractiveShineModifier())
    }
}

private struct MGSegmentContainerModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    let cornerRadius: CGFloat
    let prominence: Double

    func body(content: Content) -> some View {
        let theme = AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
        content
            .padding(3)
            .background(MGTheme.insetFill(for: colorScheme, prominence: prominence), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        theme == .classicBlue ? MGTheme.stroke(for: colorScheme, prominence: 0.42) : MGTheme.stroke(for: colorScheme, prominence: 0.28),
                        lineWidth: 0.8
                    )
            )
    }
}

private struct MGSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    let cornerRadius: CGFloat
    let prominence: Double
    let shadow: Bool

    func body(content: Content) -> some View {
        let theme = AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
        let goldGradient = LinearGradient(
            colors: [
                Color(red: 0.90, green: 0.77, blue: 0.46), // 香槟金
                Color(red: 0.77, green: 0.63, blue: 0.35), // 黄铜金
                Color(red: 0.56, green: 0.43, blue: 0.23)  // 古铜金
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MGTheme.panelFill(for: colorScheme, prominence: prominence))
            )
            .overlay(
                Group {
                    if theme == .champagneLuxury {
                        // 🌟 弱化线条感设计：摒弃双层线，采用单层典雅微透金箔描边，宽度统一为 0.8
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(goldGradient.opacity(0.48), lineWidth: 0.8)
                    } else {
                        // 其它主题统一采用与经典原版完全相同的极简单层 0.8px 细描边，杜绝繁杂
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(MGTheme.stroke(for: colorScheme), lineWidth: 0.8)
                    }
                }
            )
            .shadow(
                color: shadow ? MGTheme.shadow(for: colorScheme) : .clear,
                radius: shadow ? (theme == .classicBlue ? 12 : (theme == .nordicAurora ? 10 : (theme == .champagneLuxury ? 8 : 12))) : 0,
                x: 0,
                y: shadow ? (theme == .classicBlue ? 6 : (theme == .nordicAurora ? 4 : (theme == .champagneLuxury ? 3 : 2))) : 0
            )
    }
}

private struct MGInsetSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    let cornerRadius: CGFloat
    let prominence: Double

    func body(content: Content) -> some View {
        let theme = AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MGTheme.insetFill(for: colorScheme, prominence: prominence))
            )
            .overlay(
                Group {
                    if theme == .classicBlue {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(MGTheme.stroke(for: colorScheme, prominence: 0.45), lineWidth: 0.8)
                    } else {
                        // 极简扁平美学：非原版主题下的嵌套子面板一律取消描边线，杜绝线条过多过杂
                        Color.clear
                    }
                }
            )
    }
}

private struct MGStatusPillModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    let tint: Color
    let selected: Bool

    func body(content: Content) -> some View {
        let theme = AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
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
                    .stroke(
                        theme == .classicBlue
                            ? (selected ? tint.opacity(0.42) : MGTheme.stroke(for: colorScheme, prominence: 0.45))
                            : (selected ? tint.opacity(0.30) : Color.clear),
                        lineWidth: 0.8
                    )
            )
    }
}

private struct MGRefractiveShineModifier: ViewModifier {
    @AppStorage("colorTheme") private var colorThemeRaw = AppColorTheme.classicBlue.rawValue
    var theme: AppColorTheme {
        AppColorTheme(rawValue: colorThemeRaw) ?? .classicBlue
    }
    @Environment(\.colorScheme) private var colorScheme
    @State private var hoverLocation: CGPoint = .zero
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .onContinuousHover { phase in
                guard theme != .classicBlue else { return }
                switch phase {
                case .active(let location):
                    hoverLocation = location
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
            .overlay(
                GeometryReader { geo in
                    if isHovering {
                        if theme == .nordicAurora {
                            // 🛠️ 包豪斯硬核拉丝金属反光镜面高光 (Specular Metallic Sheen)
                            let width = geo.size.width
                            let offsetX = (hoverLocation.x - width / 2) * 1.6
                            
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .clear,
                                            .white.opacity(colorScheme == .dark ? 0.12 : 0.18),
                                            .white.opacity(colorScheme == .dark ? 0.28 : 0.38),
                                            .white.opacity(colorScheme == .dark ? 0.12 : 0.18),
                                            .clear
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: width * 0.38)
                                .rotationEffect(.degrees(45))
                                .offset(x: offsetX)
                                .blendMode(.plusLighter)
                                .allowsHitTesting(false)
                        } else if theme == .champagneLuxury {
                            // 📜 宣纸墨迹/红茶渍温润触压水墨洇湿晕开
                            RadialGradient(
                                colors: [
                                    Color(red: 0.45, green: 0.32, blue: 0.20).opacity(colorScheme == .dark ? 0.15 : 0.20),
                                    Color(red: 0.45, green: 0.32, blue: 0.20).opacity(0.02),
                                    Color.clear
                                ],
                                center: UnitPoint(x: hoverLocation.x / geo.size.width, y: hoverLocation.y / geo.size.height),
                                startRadius: 0,
                                endRadius: max(geo.size.width, geo.size.height) * 0.65
                            )
                            .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
                            .allowsHitTesting(false)
                        } else if theme == .cyberNeon {
                            // 🪷 墨染江南：雨后松石绿水墨在玉石表面慢速晕染的温润涟漪
                            RadialGradient(
                                colors: [
                                    Color(red: 0.00, green: 0.54, blue: 0.48).opacity(colorScheme == .dark ? 0.16 : 0.11),
                                    Color(red: 0.00, green: 0.54, blue: 0.48).opacity(0.04),
                                    Color.clear
                                ],
                                center: UnitPoint(x: hoverLocation.x / geo.size.width, y: hoverLocation.y / geo.size.height),
                                startRadius: 0,
                                endRadius: max(geo.size.width, geo.size.height) * 0.75
                            )
                            .blendMode(colorScheme == .dark ? .plusLighter : .multiply)
                            .allowsHitTesting(false)
                        }
                    }
                }
                .clipped()
            )
    }
}
