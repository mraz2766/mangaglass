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
        .default
    }

    static func appBackground(for scheme: ColorScheme) -> LinearGradient {
        LinearGradient(
            colors: scheme == .dark ? darkBackgroundColors : lightBackgroundColors,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private static var lightBackgroundColors: [Color] {
        [Color(red: 0.965, green: 0.970, blue: 0.975), Color(red: 0.935, green: 0.942, blue: 0.950)]
    }

    private static var darkBackgroundColors: [Color] {
        [Color(red: 0.105, green: 0.110, blue: 0.120), Color(red: 0.070, green: 0.074, blue: 0.082)]
    }

    static func panelFill(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.040 * prominence)
            : Color.white.opacity(0.700 * prominence)
    }

    static func insetFill(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        scheme == .dark
            ? Color.black.opacity(0.180 * prominence)
            : Color.black.opacity(0.035 * prominence)
    }

    static func stroke(for scheme: ColorScheme, prominence: Double = 1) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.090 * prominence)
            : Color.black.opacity(0.080 * prominence)
    }

    static func shadow(for scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.black.opacity(0.22) : Color.black.opacity(0.035)
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
    let cornerRadius: CGFloat
    let prominence: Double
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MGTheme.panelFill(for: colorScheme, prominence: prominence))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MGTheme.stroke(for: colorScheme, prominence: 0.72), lineWidth: 0.8)
            )
            .shadow(
                color: shadow ? MGTheme.shadow(for: colorScheme) : .clear,
                radius: shadow ? 8 : 0,
                x: 0,
                y: shadow ? 3 : 0
            )
    }
}

private struct MGInsetSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat
    let prominence: Double

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MGTheme.insetFill(for: colorScheme, prominence: prominence))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(MGTheme.stroke(for: colorScheme, prominence: 0.28), lineWidth: 0.8)
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
            .foregroundStyle(selected ? tint : Color.primary.opacity(0.68))
            .padding(.horizontal, selected ? 8 : 6)
            .padding(.vertical, selected ? 4 : 3)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? tint.opacity(colorScheme == .dark ? 0.18 : 0.10) : Color.clear)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        selected ? tint.opacity(theme == .classicBlue ? 0.28 : 0.22) : Color.clear,
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
