import SwiftUI

@MainActor
final class ChapterFrameStore: ObservableObject {
    var frames: [String: CGRect] = [:]
}

/// Writes one cell's frame straight into the non-published store, so layout and scrolling
/// never merge or republish the whole frame dictionary. Only rendered (lazy) cells keep an entry.
struct ChapterFrameReporter: View {
    let id: String
    let store: ChapterFrameStore

    var body: some View {
        GeometryReader { proxy in
            let frame = proxy.frame(in: .named("chapter-canvas"))
            Color.clear
                .onAppear { store.frames[id] = frame }
                .onChange(of: frame) { store.frames[id] = $0 }
                .onDisappear { store.frames[id] = nil }
        }
    }
}

struct DragRectOverlay: View {
    let rect: CGRect?

    var body: some View {
        GeometryReader { _ in
            if let rect {
                Rectangle()
                    .fill(MGTheme.accent.opacity(0.12))
                    .overlay(
                        Rectangle()
                            .stroke(MGTheme.accent.opacity(0.8), lineWidth: 1)
                    )
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }
}
