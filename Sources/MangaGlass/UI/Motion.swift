import AppKit
import SwiftUI

/// Named coordinate space covering the whole window; fly-to-queue points live in it.
let MGRootSpace = "mg-root"

// MARK: - Window glass

/// Frosted material behind the sidebar, used by themes with `palette.glass`.
struct MGWindowGlass: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

// MARK: - Skeleton

/// Breathing placeholder blocks shown while a catalog is being parsed.
struct MGSkeletonGrid: View {
    var rows = 6
    var columns = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 10) {
                RoundedRectangle(cornerRadius: 4).fill(MGTheme.palette.cell).frame(width: 120, height: 14)
                    .opacity(pulse(t, 0))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                    ForEach(0..<(rows * columns), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(MGTheme.palette.cell)
                            .frame(height: 38)
                            .opacity(pulse(t, Double(index % columns + index / columns) * 0.12))
                    }
                }
            }
        }
        .accessibilityLabel("正在解析目录")
    }

    private func pulse(_ t: Double, _ phase: Double) -> Double {
        reduceMotion ? 0.8 : 0.55 + 0.45 * (0.5 + 0.5 * sin(t * 3.2 - phase))
    }
}

// MARK: - Staggered reveal

/// Remembers when a fresh catalog arrived, so only cells built right after it animate in
/// (cells that appear later while scrolling show immediately).
@MainActor
enum MGRevealClock {
    static var revealedAt: Date = .distantPast
    static func mark() { revealedAt = Date() }
    static var isRevealing: Bool { Date().timeIntervalSince(revealedAt) < 0.9 }
}

private struct MGStaggerAppear: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Bool

    init(index: Int) {
        self.index = index
        _shown = State(initialValue: !MGRevealClock.isRevealing)
    }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 6)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            .onAppear {
                guard !shown else { return }
                let delay = Double(min(index, 48)) * 0.012
                withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.34, dampingFraction: 0.82).delay(delay)) {
                    shown = true
                }
            }
    }
}

// MARK: - Shake

struct MGShakeEffect: GeometryEffect {
    nonisolated init(travel: CGFloat = 4, animatableData: CGFloat) {
        self.travel = travel
        self.animatableData = animatableData
    }

    var travel: CGFloat = 4
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 4), y: 0))
    }
}

// MARK: - Fly to queue

struct MGFlight: Identifiable, Equatable {
    let id = UUID()
    let count: Int
    let start: CGPoint
}

/// Lets a deep view launch "+N" toward the sidebar download icon.
struct MGFlyToQueueKey: EnvironmentKey {
    static let defaultValue: @MainActor @Sendable (Int, CGPoint) -> Void = { _, _ in }
}

/// Frame of the sidebar download icon in `MGRootSpace`.
struct MGQueueTargetKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension EnvironmentValues {
    var mgFlyToQueue: @MainActor @Sendable (Int, CGPoint) -> Void {
        get { self[MGFlyToQueueKey.self] }
        set { self[MGFlyToQueueKey.self] = newValue }
    }
}

/// The travelling "+N" capsule; arcs from the enqueue button to the sidebar icon, then fades.
struct MGFlightView: View {
    let flight: MGFlight
    let target: CGPoint
    let onFinish: () -> Void
    @State private var progress: CGFloat = 0

    var body: some View {
        Text("+\(flight.count)")
            .font(MGFont.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(MGTheme.accent, in: Capsule())
            .modifier(MGArcFlight(start: flight.start, end: target, progress: progress))
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6)) { progress = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.62) { onFinish() }
            }
    }
}

private struct MGArcFlight: ViewModifier, @preconcurrency Animatable {
    let start: CGPoint
    let end: CGPoint
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let control = CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - 120)
        let u = 1 - progress
        let point = CGPoint(x: u * u * start.x + 2 * u * progress * control.x + progress * progress * end.x,
                            y: u * u * start.y + 2 * u * progress * control.y + progress * progress * end.y)
        content
            .scaleEffect(1 - progress * 0.55)
            .opacity(progress > 0.85 ? Double((1 - progress) / 0.15) : 1)
            .position(point)
    }
}

// MARK: - Hover lift

private struct MGHoverLift: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .offset(y: hovering && !reduceMotion ? -3 : 0)
            .shadow(color: .black.opacity(hovering ? 0.16 : 0.06), radius: hovering ? 12 : 4, y: hovering ? 6 : 2)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8), value: hovering)
    }
}

extension View {
    func mgStaggerAppear(index: Int) -> some View { modifier(MGStaggerAppear(index: index)) }
    func mgHoverLift() -> some View { modifier(MGHoverLift()) }

    /// Panel surface that follows the theme: solid cell color, plus a light hairline on glass themes.
    func mgPanel(radius: CGFloat = MGRadius.card) -> some View {
        background(MGTheme.palette.cell, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(MGTheme.palette.glass ? MGTheme.palette.cellStroke : MGTheme.palette.divider.opacity(0.6), lineWidth: 0.5)
            }
    }
}
