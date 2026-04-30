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
        .defaultSize(width: 1080, height: 760)
        .windowResizability(.contentMinSize)
    }
}
