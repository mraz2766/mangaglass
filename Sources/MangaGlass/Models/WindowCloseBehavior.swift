import Foundation

enum WindowCloseBehavior: String, CaseIterable, Identifiable {
    case ask
    case quit
    case background

    static let storageKey = "windowCloseBehavior"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: return "弹窗询问"
        case .quit: return "直接退出"
        case .background: return "留在后台"
        }
    }

    var detail: String {
        switch self {
        case .ask: return "关闭窗口前询问是否退出；取消后继续使用。"
        case .quit: return "关闭窗口立即退出并停止下载，队列保留到下次打开。"
        case .background: return "关闭窗口后继续下载；点击 Dock 中的 MangaGlass 图标恢复窗口。"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .ask
    }
}
