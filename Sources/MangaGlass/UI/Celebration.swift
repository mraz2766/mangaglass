import SwiftUI

/// Window-wide confetti when a download batch finishes cleanly. Watches the downloader on its own,
/// so ContentView doesn't re-render on every progress tick.
struct MGCelebrationLayer: View {
    @ObservedObject var downloader: DownloadCoordinator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var burst: MGConfettiBurst?

    var body: some View {
        ZStack {
            if let burst {
                MGConfettiView(burst: burst)
                    .transition(.opacity)
                    .id(burst.id)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: downloader.celebrationTick) { _ in
            guard !reduceMotion else { return }
            let next = MGConfettiBurst()
            burst = next
            DispatchQueue.main.asyncAfter(deadline: .now() + MGConfettiBurst.duration + 0.1) {
                if burst?.id == next.id { withAnimation(.easeOut(duration: 0.2)) { burst = nil } }
            }
        }
    }
}

struct MGConfettiBurst: Identifiable {
    static let duration: TimeInterval = 2.4
    let id = UUID()
    let start: Date
    let pieces: [Piece]

    struct Piece {
        let x: Double          // 0…1 across the window
        let delay: Double      // seconds
        let fall: Double       // points per second
        let drift: Double      // horizontal sway amplitude
        let sway: Double       // sway frequency
        let spin: Double       // radians per second
        let size: CGSize
        let color: Int
    }

    init(count: Int = 90, start: Date = Date()) {
        self.start = start
        var generator = SystemRandomNumberGenerator()
        pieces = (0..<count).map { _ in
            Piece(x: .random(in: 0.05...0.95, using: &generator),
                  delay: .random(in: 0...0.5, using: &generator),
                  fall: .random(in: 260...520, using: &generator),
                  drift: .random(in: 8...30, using: &generator),
                  sway: .random(in: 2...5, using: &generator),
                  spin: .random(in: 3...9, using: &generator),
                  size: CGSize(width: .random(in: 5...8, using: &generator), height: .random(in: 9...14, using: &generator)),
                  color: .random(in: 0..<6, using: &generator))
        }
    }
}

struct MGConfettiView: View {
    let burst: MGConfettiBurst

    var body: some View {
        let colors: [Color] = [MGTheme.accent, MGTheme.success, .orange, .pink, .yellow, .purple]
        TimelineView(.animation) { context in
            Canvas { canvas, size in
                let t = context.date.timeIntervalSince(burst.start)
                for piece in burst.pieces {
                    let local = t - piece.delay
                    guard local > 0 else { continue }
                    let y = -20 + piece.fall * local + 40 * local * local
                    guard y < size.height + 20 else { continue }
                    let x = piece.x * size.width + piece.drift * sin(local * piece.sway)
                    // Fade out over the last 0.6 s of the burst.
                    let fade = min(1, max(0, (MGConfettiBurst.duration - t) / 0.6))
                    let transform = CGAffineTransform(translationX: x, y: y)
                        .rotated(by: local * piece.spin)
                        // Tumbling: the piece's width swings through 0 like a turning paper strip.
                        .scaledBy(x: cos(local * piece.spin * 0.7), y: 1)
                    let rect = CGRect(x: -piece.size.width / 2, y: -piece.size.height / 2,
                                      width: piece.size.width, height: piece.size.height)
                    let path = Path(roundedRect: rect, cornerRadius: 1.5).applying(transform)
                    canvas.opacity = fade
                    canvas.fill(path, with: .color(colors[piece.color % colors.count]))
                }
            }
        }
        .ignoresSafeArea()
    }
}
