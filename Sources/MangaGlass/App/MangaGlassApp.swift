import SwiftUI

@main
struct MangaGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
    }
}
