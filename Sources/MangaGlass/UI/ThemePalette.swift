import AppKit
import SwiftUI

enum AppThemeStyle: String, CaseIterable, Identifiable {
    case classic
    case ink
    case graphite

    static let storageKey = "themeStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "经典"
        case .ink: return "墨与纸"
        case .graphite: return "石墨"
        }
    }

    var detail: String {
        switch self {
        case .classic: return "系统蓝与原生材质，最初的外观。"
        case .ink: return "暖白纸面、墨色选中、朱红主操作；深色下为墨底纸字。"
        case .graphite: return "分层石墨灰，紫色只用于选中与主操作；浅色下为银灰。"
        }
    }
}

/// One theme's colors. Every value is a dynamic `NSColor`, so light/dark resolve from the
/// window's appearance without threading `ColorScheme` through call sites.
struct MGPalette {
    let canvas: Color
    let sidebar: Color?
    let text: Color
    let divider: Color
    let accent: Color
    let cell: Color
    let cellHover: Color
    let cellPressed: Color
    let field: Color
    let fieldStroke: Color
    let selectedFill: Color
    let selectedText: Color
    let selectedStroke: Color
    let softSelectedFill: Color
    let softSelectedText: Color
    let emphasisFill: Color
    let emphasisText: Color
    let numberForwardChapters: Bool

    static func forStyle(_ style: AppThemeStyle) -> MGPalette {
        switch style {
        case .classic: return classic
        case .ink: return ink
        case .graphite: return graphite
        }
    }

    private static let classic: MGPalette = {
        let blue = NSColor.systemBlue
        let accentWash = dynamic { blue.withAlphaComponent($0 ? 0.20 : 0.10) }
        return MGPalette(
            canvas: Color(nsColor: .windowBackgroundColor),
            sidebar: nil,
            text: Color(nsColor: .labelColor),
            divider: Color(nsColor: .separatorColor),
            accent: Color(nsColor: blue),
            cell: dynamic { $0 ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.035) },
            cellHover: dynamic { $0 ? NSColor.white.withAlphaComponent(0.10) : NSColor.black.withAlphaComponent(0.06) },
            cellPressed: dynamic { $0 ? NSColor.white.withAlphaComponent(0.13) : NSColor.black.withAlphaComponent(0.085) },
            field: dynamic { $0 ? NSColor.white.withAlphaComponent(0.06) : NSColor.black.withAlphaComponent(0.035) },
            fieldStroke: .clear,
            selectedFill: accentWash,
            selectedText: Color(nsColor: blue),
            selectedStroke: Color(nsColor: blue.withAlphaComponent(0.68)),
            softSelectedFill: accentWash,
            softSelectedText: Color(nsColor: blue),
            emphasisFill: Color(nsColor: blue),
            emphasisText: .white,
            numberForwardChapters: false
        )
    }()

    private static let ink = MGPalette(
        canvas: hex(0xF7F5F0, 0x1C1B19),
        sidebar: hex(0xEFECE4, 0x161513),
        text: hex(0x2C2C2A, 0xEDEBE4),
        divider: hex(0xDEDBD2, 0x34332F),
        accent: hex(0xD85A30, 0xE8774F),
        cell: hex(0xFFFFFF, 0x262522),
        cellHover: hex(0xEFECE4, 0x302F2B),
        cellPressed: hex(0xE6E2D8, 0x383733),
        field: hex(0xFFFFFF, 0x262522),
        fieldStroke: hex(0xDEDBD2, 0x34332F),
        selectedFill: hex(0x2C2C2A, 0xEDEBE4),
        selectedText: hex(0xF7F5F0, 0x1C1B19),
        selectedStroke: .clear,
        softSelectedFill: hex(0xE4E0D5, 0x302F2B),
        softSelectedText: hex(0x2C2C2A, 0xEDEBE4),
        emphasisFill: hex(0x2C2C2A, 0xEDEBE4),
        emphasisText: hex(0xF7F5F0, 0x1C1B19),
        numberForwardChapters: true
    )

    private static let graphite = MGPalette(
        canvas: hex(0xF5F5F7, 0x18181A),
        sidebar: hex(0xEBEBEE, 0x111113),
        text: hex(0x1C1C1E, 0xEDEDED),
        divider: hex(0xDCDCE0, 0x2E2E32),
        accent: hex(0x534AB7, 0x7F77DD),
        cell: hex(0xFFFFFF, 0x222225),
        cellHover: hex(0xF0F0F3, 0x2A2A2E),
        cellPressed: hex(0xE6E6EA, 0x323236),
        field: hex(0xFFFFFF, 0x222225),
        fieldStroke: hex(0xDCDCE0, 0x333336),
        selectedFill: hex(0xEEEDFE, 0x3C3489),
        selectedText: hex(0x3C3489, 0xEEEDFE),
        selectedStroke: hex(0xAFA9EC, 0x7F77DD),
        softSelectedFill: hex(0xE2E2E8, 0x2A2A2E),
        softSelectedText: hex(0x534AB7, 0xAFA9EC),
        emphasisFill: hex(0xE2E2E8, 0x2C2C30),
        emphasisText: hex(0x1C1C1E, 0xEDEDED),
        numberForwardChapters: true
    )

    private static func hex(_ light: UInt32, _ dark: UInt32) -> Color {
        dynamic { NSColor(rgb: $0 ? dark : light) }
    }

    private static func dynamic(_ resolve: @escaping @Sendable (_ isDark: Bool) -> NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            resolve(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        })
    }
}

private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
