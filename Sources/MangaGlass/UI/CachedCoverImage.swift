import AppKit
import SwiftUI

/// Decoded covers kept in memory, so revisiting a comic or opening the large preview
/// does not download and decode the same image again.
@MainActor
final class CoverImageCache {
    static let shared = CoverImageCache()

    private let images = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    private init() {
        images.countLimit = 64
    }

    func cachedImage(for url: URL) -> NSImage? {
        images.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> NSImage? {
        if let cached = cachedImage(for: url) { return cached }
        if let task = inFlight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            return NSImage(data: data)
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        return image
    }
}

enum CoverImagePhase {
    case loading
    case success(NSImage)
    case failure
}

struct CachedCoverImage<Content: View>: View {
    typealias Phase = CoverImagePhase

    let url: URL
    let content: (Phase) -> Content
    @State private var phase: Phase = .loading

    init(url: URL, @ViewBuilder content: @escaping (Phase) -> Content) {
        self.url = url
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                if let cached = CoverImageCache.shared.cachedImage(for: url) {
                    phase = .success(cached)
                    return
                }
                phase = .loading
                let image = await CoverImageCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) {
                    phase = image.map(Phase.success) ?? .failure
                }
            }
    }
}

/// Book-shaped cover: the real image when available, otherwise a tinted tile with the first character.
struct MGBookCover: View {
    let url: URL?
    let title: String

    var body: some View {
        Group {
            if let url, !CopyMangaMirror.isRetired(url.host) {
                CachedCoverImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        Image(nsImage: image).resizable().scaledToFill()
                            .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    case .loading, .failure:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        // Keep clicks inside the visible cover; a fill-scaled image otherwise hit-tests past the clip.
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
    }

    private var placeholder: some View {
        ZStack {
            MGTheme.palette.softSelectedFill
            Text(String(title.prefix(1)))
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(MGTheme.palette.softSelectedText)
        }
    }
}
