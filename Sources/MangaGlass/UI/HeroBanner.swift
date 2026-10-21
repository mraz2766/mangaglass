import SwiftUI

/// Large header band: frosted white glass (dark glass in dark mode) with a hairline edge and a soft
/// shadow. Content uses the normal foreground colors, so it reads like the rest of the page.
struct MGHeroBanner<Content: View>: View {
    var height: CGFloat = 210
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MGRadius.hero, style: .continuous)
        content()
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    shape.fill(.regularMaterial)
                    // Brightens the material toward white; barely there in dark mode.
                    shape.fill(Color.white.opacity(colorScheme == .dark ? 0.04 : 0.55))
                }
                .allowsHitTesting(false)
            }
            .clipShape(shape)
            .contentShape(shape)
            .overlay {
                shape.stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.06), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.06), radius: 14, y: 4)
    }
}

/// Cover as it sits on a banner: hairline edge, soft shadow.
struct MGHeroCover: View {
    let url: URL?
    let title: String
    var width: CGFloat = 112

    var body: some View {
        MGBookCover(url: url, title: title)
            .frame(width: width, height: width * 1.38)
            .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
    }
}

/// Pill buttons for use on a banner: accent primary, quiet gray secondary.
struct MGBannerButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        MGBannerButtonBody(configuration: configuration, kind: kind)
    }
}

private struct MGBannerButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: MGBannerButtonStyle.Kind
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(MGFont.body.weight(.semibold))
            .foregroundStyle(kind == .primary ? Color.white : Color.primary)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(fill, in: Capsule())
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.65), value: configuration.isPressed)
            .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
    }

    private var fill: Color {
        switch kind {
        case .primary: return MGTheme.accent.opacity(hovering ? 0.88 : 1)
        case .secondary: return Color.primary.opacity(hovering ? 0.10 : 0.06)
        }
    }
}

/// Small translucent stat capsule on a banner.
struct MGBannerStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(MGFont.caption).opacity(0.75)
            Text(value).font(MGFont.body.weight(.semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

/// Chapter tile: big number, small unit, no checkbox. Selected = inverted fill with a check;
/// downloaded = green dot.
struct MGChapterTile: View {
    let title: String
    let selected: Bool
    let downloaded: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let palette = MGTheme.palette
        Button(action: action) {
            VStack(spacing: 1) {
                if let parts = MGChapterTitleParts(title) {
                    Text(parts.number)
                        .font(MGFont.section)
                        .monospacedDigit()
                    Text(parts.rest.isEmpty ? parts.unit : "\(parts.unit) \(parts.rest)")
                        .font(MGFont.micro)
                        .lineLimit(1)
                        .opacity(0.6)
                } else {
                    Text(title)
                        .font(MGFont.captionStrong)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                }
            }
            .foregroundStyle(selected ? palette.selectedText : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(selected ? palette.selectedFill : (hovering ? palette.cellHover : palette.cell),
                        in: RoundedRectangle(cornerRadius: MGRadius.small, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: MGRadius.small, style: .continuous)
                    .stroke(selected ? palette.selectedStroke : (palette.glass ? palette.cellStroke : .clear), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.selectedText)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if downloaded {
                    Circle()
                        .fill(MGTheme.success)
                        .frame(width: 5, height: 5)
                        .padding(5)
                        .help("已下载")
                        // Pops in when a chapter finishes while the grid is on screen.
                        .transition(.scale(scale: 0.1).combined(with: .opacity))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: MGRadius.small, style: .continuous))
        }
        .buttonStyle(MGTilePressStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.75), value: selected)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.55), value: downloaded)
        .animation(reduceMotion ? nil : MGMotion.fast, value: hovering)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue([selected ? "已选择" : "未选择", downloaded ? "已下载" : nil].compactMap { $0 }.joined(separator: "，"))
    }
}

private struct MGTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MGTilePressBody(configuration: configuration)
    }
}

private struct MGTilePressBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
