import Foundation

/// Activity log kept apart from `MainViewModel`, so appending a line only refreshes the log sheet
/// instead of every view that observes the main model.
@MainActor
final class ActivityLogStore: ObservableObject {
    struct Entry: Identifiable, Equatable {
        let id: Int
        let text: String
        let isError: Bool
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var errorEntries: [Entry] = []
    @Published var showOnlyErrors = false

    private let limit: Int
    private var nextID = 0
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(limit: Int = 400) {
        self.limit = limit
    }

    var visibleEntries: [Entry] {
        showOnlyErrors ? errorEntries : entries
    }

    func append(_ message: String) {
        let text = "[\(Self.timeFormatter.string(from: Date()))] \(message)"
        let entry = Entry(id: nextID, text: text, isError: Self.isError(text))
        nextID += 1
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
            if let oldest = entries.first?.id, errorEntries.first.map({ $0.id < oldest }) == true {
                errorEntries.removeAll { $0.id < oldest }
            }
        }
        if entry.isError {
            errorEntries.append(entry)
        }
    }

    func clear() {
        entries = []
        errorEntries = []
    }

    private static func isError(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("失败") || lowered.contains("错误") || lowered.contains("error")
            || lowered.contains("http 4") || lowered.contains("http 5")
    }
}
