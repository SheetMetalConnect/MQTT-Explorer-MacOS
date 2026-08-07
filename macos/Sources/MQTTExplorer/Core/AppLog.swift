import Foundation

/// Session log, capped at 500 entries.
@Observable
@MainActor
final class AppLog {
    struct Entry: Identifiable, Sendable {
        enum Level: String, Sendable {
            case info
            case warning
            case error
        }

        let id = UUID()
        let at: Date
        let level: Level
        let message: String
    }

    static let shared = AppLog()
    private static let capacity = 500

    private(set) var entries: [Entry] = []

    func info(_ message: String) { append(.info, message) }
    func warning(_ message: String) { append(.warning, message) }
    func error(_ message: String) { append(.error, message) }

    private func append(_ level: Entry.Level, _ message: String) {
        entries.append(Entry(at: Date(), level: level, message: message))
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var text: String {
        entries
            .map { entry in
                let stamp = DateFormatterFormatting.format(entry.at, locale: nil)
                return "\(stamp)  [\(entry.level.rawValue)]  \(entry.message)"
            }
            .joined(separator: "\n")
    }
}
