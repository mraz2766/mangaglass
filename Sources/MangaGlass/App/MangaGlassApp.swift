import SwiftUI

@main
struct MangaGlassApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = MainViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(vm: viewModel)
                .onAppear {
                    appDelegate.viewModel = viewModel
                }
        }
        .defaultSize(width: min(1200, NSScreen.main?.visibleFrame.width ?? 1200),
                     height: min(800, (NSScreen.main?.visibleFrame.height ?? 828) - 28))
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(vm: viewModel)
        }
    }
}
