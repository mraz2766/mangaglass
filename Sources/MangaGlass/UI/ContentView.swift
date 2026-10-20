import SwiftUI

enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case download
    case queue
    case history
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "首页"
        case .queue: return "队列"
        case .history: return "历史"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .download: return "house"
        case .queue: return "tray.full"
        case .history: return "clock"
        case .settings: return "gearshape"
        }
    }
}

enum WorkspaceLayout {
    static let sidebarWidth: CGFloat = 176
    static let minWindowWidth: CGFloat = 880
}

struct ContentView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: WorkspaceDestination = .download
    @State private var showLogs = false
    @State private var didCheckRestoredQueue = false

    var body: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(downloader: vm.downloader, destination: $destination)
                .frame(width: WorkspaceLayout.sidebarWidth)

            Divider()

            GeometryReader { proxy in
                ZStack {
                    MGTheme.background(for: colorScheme)
                        .ignoresSafeArea()

                    ForEach(WorkspaceDestination.allCases) { workspaceDestination in
                        if workspaceDestination == destination {
                            workspace(for: workspaceDestination)
                                .padding(.horizontal, MGSpacing.content)
                                .padding(.vertical, MGSpacing.md)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(workspaceTransition)
                        }
                    }
                }
            }
        }
        .frame(minWidth: WorkspaceLayout.minWindowWidth, minHeight: 560)
        .preferredColorScheme(vm.preferredColorScheme)
        .animation(reduceMotion ? nil : MGMotion.panel, value: destination)
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
    private func workspace(for workspaceDestination: WorkspaceDestination) -> some View {
        switch workspaceDestination {
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

    private var workspaceTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .offset(y: -6))
        )
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
