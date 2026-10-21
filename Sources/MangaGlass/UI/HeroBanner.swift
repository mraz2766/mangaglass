import SwiftUI

/// Large header band. The backdrop is the comic's own cover, heavily blurred and darkened,
/// so every comic brings its own tone; without a cover it falls back to a neutral graphite wash.
/// Content is laid out in dark appearance (white text) regardless of the app theme.
struct MGHeroBanner<Content: View>: View {
    let coverURL: URL?
    var height: CGFloat = 210
    @ViewBuilder let content: () -> Content

    var body: some View {
        // The backdrop lives in `.background` so a fill-scaled cover can never widen the layout
        // (inside a ZStack it pushed the content out of the visible area).
        content()
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    backdrop
                    LinearGradient(
                        colors: [Color.black.opacity(0.18), Color.black.opacity(0.58)],
                        startPoint: .top, endPoint: .bottom
                    )
                }
                // The fill-scaled, enlarged cover overflows the banner; clipping hides it but does not
                // stop it from taking clicks (it covered the sidebar), so the backdrop never hit-tests.
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
    }

    @ViewBuilder private var backdrop: some View {
        let fallback = LinearGradient(
            colors: [Color(white: 0.30), Color(white: 0.16)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        if let coverURL, !CopyMangaMirror.isRetired(coverURL.host) {
            CachedCoverImage(url: coverURL) { phase in
                switch phase {
                case .success(let image):
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 48, opaque: true)
                        .saturation(1.25)
                        .scaleEffect(1.2)
                        .transition(.opacity)
                case .loading, .failure:
                    fallback
                }
            }
        } else {
            fallback
        }
    }
}

/// Cover as it sits on a banner: white hairline, soft shadow.
struct MGHeroCover: View {
    let url: URL?
    let title: String
    var width: CGFloat = 112

    var body: some View {
        MGBookCover(url: url, title: title)
            .frame(width: width, height: width * 1.38)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
    }
}

/// Pill buttons for use on a banner: white primary, translucent secondary.
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
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(kind == .primary ? Color.black : Color.white)
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
        case .primary: return Color.white.opacity(hovering ? 0.88 : 1)
        case .secondary: return Color.white.opacity(hovering ? 0.28 : 0.18)
        }
    }
}

/// Small translucent stat capsule on a banner.
struct MGBannerStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 12)).opacity(0.75)
            Text(value).font(.system(size: 13, weight: .semibold)).monospacedDigit()
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(Color.white.opacity(0.14), in: Capsule())
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
            VStack(spacing: 3) {
                if let parts = MGChapterTitleParts(title) {
                    Text(parts.number)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                    Text(parts.rest.isEmpty ? parts.unit : "\(parts.unit) \(parts.rest)")
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .opacity(0.6)
                } else {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 6)
                }
            }
            .foregroundStyle(selected ? palette.selectedText : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .background(selected ? palette.selectedFill : (hovering ? palette.cellHover : palette.cell),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? palette.selectedStroke : (palette.glass ? palette.cellStroke : .clear), lineWidth: 1)
            }
            .overlay(alignment: .topLeading) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.selectedText)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if downloaded {
                    Circle()
                        .fill(MGTheme.success)
                        .frame(width: 6, height: 6)
                        .padding(8)
                        .help("已下载")
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(MGTilePressStyle())
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.75), value: selected)
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
