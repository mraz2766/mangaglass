import SwiftUI

enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case download
    case queue
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "下载"
        case .queue: return "队列"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .download: return "arrow.down.circle"
        case .queue: return "tray.full"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var destination: WorkspaceDestination = .download
    @State private var showLogs = false
    @State private var didCheckRestoredQueue = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(vm: vm, destination: $destination)
                .frame(width: 204)

            Rectangle()
                .fill(MGTheme.divider(for: colorScheme))
                .frame(width: 1)

            ZStack {
                MGTheme.background(for: colorScheme)
                    .ignoresSafeArea()

                workspace
                    .padding(MGSpacing.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .id(destination)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .frame(minWidth: 720, minHeight: 540)
        .preferredColorScheme(vm.preferredColorScheme)
        .animation(.easeOut(duration: 0.18), value: destination)
        .onAppear(perform: presentRestoredQueuePromptIfNeeded)
        .sheet(isPresented: $showLogs) {
            ActivityLogSheet(vm: vm)
        }
        .alert("发现上次未完成的队列", isPresented: restoredQueueBinding) {
            Button("继续下载") { vm.resumeRestoredQueue() }
            Button("打开队列") {
                vm.dismissRestoredQueuePrompt()
                destination = .queue
            }
            Button("稍后处理", role: .cancel) { vm.dismissRestoredQueuePrompt() }
        } message: {
            Text(vm.restoredQueuePromptSummary)
        }
        .alert("退出 MangaGlass？", isPresented: terminationBinding) {
            Button("取消", role: .cancel) { vm.cancelTermination() }
            Button("退出", role: .destructive) { vm.confirmTermination() }
        } message: {
            Text(vm.terminationConfirmation?.message ?? "")
        }
    }

    @ViewBuilder
    private var workspace: some View {
        switch destination {
        case .download:
            DownloadWorkspaceView(
                vm: vm,
                showLogs: $showLogs,
                openQueue: { destination = .queue }
            )
        case .queue:
            QueueWorkspaceView(vm: vm, showLogs: $showLogs)
        case .history:
            HistoryWorkspaceView(vm: vm) {
                destination = .download
            }
        case .settings:
            SettingsWorkspaceView(vm: vm)
        }
    }

    private var restoredQueueBinding: Binding<Bool> {
        Binding(
            get: { didCheckRestoredQueue && vm.shouldOfferRestoredQueuePrompt },
            set: { presented in
                if !presented {
                    vm.dismissRestoredQueuePrompt()
                }
            }
        )
    }

    private var terminationBinding: Binding<Bool> {
        Binding(
            get: { vm.terminationConfirmation != nil },
            set: { presented in
                if !presented {
                    vm.cancelTermination()
                }
            }
        )
    }

    private func presentRestoredQueuePromptIfNeeded() {
        guard !didCheckRestoredQueue else { return }
        didCheckRestoredQueue = true
    }
}
