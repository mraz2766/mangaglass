import SwiftUI

enum WorkspaceDestination: String, CaseIterable, Identifiable {
    case download
    case queue
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .download: return "首页"
        case .queue: return "下载"
        case .history: return "书架"
        }
    }

    var systemImage: String {
        switch self {
        case .download: return "house"
        case .queue: return "arrow.down.circle"
        case .history: return "books.vertical"
        }
    }
}

/// Owns in-flight "+N" capsules and the badge bump; a class so the environment closure is Sendable.
@MainActor
final class MGFlightCenter: ObservableObject {
    @Published var flights: [MGFlight] = []
    @Published var bump = 0

    func launch(count: Int, from point: CGPoint, animated: Bool) {
        if animated {
            flights.append(MGFlight(count: count, start: point))
        } else {
            bump += 1
        }
    }

    func land(_ flight: MGFlight) {
        flights.removeAll { $0.id == flight.id }
        bump += 1
    }
}

struct ContentView: View {
    @ObservedObject var vm: MainViewModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var destination: WorkspaceDestination = .download
    @State private var showLogs = false
    @State private var didCheckRestoredQueue = false
    @StateObject private var flightCenter = MGFlightCenter()
    @State private var queueTarget: CGRect = .zero

    var body: some View {
        ZStack {
            shell
            MGCelebrationLayer(downloader: vm.downloader)
            ForEach(flightCenter.flights) { flight in
                MGFlightView(flight: flight, target: CGPoint(x: queueTarget.midX, y: queueTarget.midY)) {
                    flightCenter.land(flight)
                }
            }
        }
        .coordinateSpace(name: MGRootSpace)
        .onPreferenceChange(MGQueueTargetKey.self) { queueTarget = $0 }
        .environment(\.mgFlyToQueue, { [flightCenter, reduceMotion] count, point in
            flightCenter.launch(count: count, from: point, animated: !reduceMotion)
        })
        .frame(minWidth: 720, minHeight: 540)
        .foregroundStyle(MGTheme.palette.text)
        .tint(MGTheme.accent)
        .preferredColorScheme(vm.preferredColorScheme)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : MGMotion.page, value: destination)
        .onAppear(perform: presentRestoredQueuePromptIfNeeded)
        .sheet(isPresented: $showLogs) {
            ActivityLogSheet(vm: vm)
        }
        .modifier(ContentAlerts(vm: vm, destination: $destination, restoredQueueBinding: restoredQueueBinding, terminationBinding: terminationBinding))
    }

    private var shell: some View {
        HStack(spacing: 0) {
            WorkspaceSidebar(downloader: vm.downloader, destination: $destination, bump: flightCenter.bump)
                .frame(width: 72)
                .id(vm.appearanceID)

            Rectangle()
                .fill(MGTheme.divider(for: colorScheme))
                .frame(width: 1)
                .ignoresSafeArea()

            GeometryReader { proxy in
                ZStack {
                    MGTheme.background(for: colorScheme)
                        .ignoresSafeArea()

                    // Rebuild on theme change so views that don't observe `vm` repaint too.
                    ForEach(WorkspaceDestination.allCases) { workspaceDestination in
                        if workspaceDestination == destination {
                            workspace(for: workspaceDestination)
                                .padding(MGSpacing.md)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(workspaceTransition)
                        }
                    }
                }
                .id(vm.appearanceID)
                .overlay(alignment: .top) {
                    if restoredQueueBinding.wrappedValue {
                        RestoredQueueBanner(
                            summary: vm.restoredQueuePromptSummary,
                            resume: { vm.resumeRestoredQueue() },
                            open: {
                                vm.dismissRestoredQueuePrompt()
                                destination = .queue
                            },
                            later: { vm.dismissRestoredQueuePrompt() }
                        )
                        .padding(.top, 12)
                        .padding(.horizontal, 24)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.85), value: restoredQueueBinding.wrappedValue)
            }
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
        }
    }

    private var workspaceTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        // The old page gets out of the way fast so the two never smear together; the new one
        // rises a few points and settles.
        return .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: 12))
                .combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
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

private struct ContentAlerts: ViewModifier {
    @ObservedObject var vm: MainViewModel
    @Binding var destination: WorkspaceDestination
    let restoredQueueBinding: Binding<Bool>
    let terminationBinding: Binding<Bool>

    func body(content: Content) -> some View {
        content
        // The restored-queue prompt is an inline banner (`RestoredQueueBanner`), not an alert:
        // a sheet presented at launch could end up attached but invisible, freezing the window.
        .alert("退出 MangaGlass？", isPresented: terminationBinding) {
            Button("取消", role: .cancel) { vm.cancelTermination() }
            Button("退出", role: .destructive) { vm.confirmTermination() }
        } message: {
            Text(vm.terminationConfirmation?.message ?? "")
        }
    }
}

/// Non-modal prompt shown when the app starts with unfinished downloads.
private struct RestoredQueueBanner: View {
    let summary: String
    let resume: () -> Void
    let open: () -> Void
    let later: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(MGTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("发现上次未完成的下载").font(MGFont.bodyStrong)
                Text(summary).font(MGFont.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            Button("稍后", action: later)
                .buttonStyle(MGActionButtonStyle(variant: .ghost))
            Button("打开下载", action: open)
                .buttonStyle(MGActionButtonStyle(variant: .secondary))
            Button("继续下载", action: resume)
                .buttonStyle(MGActionButtonStyle(variant: .primary, capsule: true))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 720)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: MGRadius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: MGRadius.card, style: .continuous).stroke(MGTheme.palette.divider, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
    }
}
