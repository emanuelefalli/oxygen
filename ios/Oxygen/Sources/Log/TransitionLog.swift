import Foundation

struct TransitionLogEntry: Equatable, Sendable {
    let timestamp: Date
    let from: SyncState
    let event: SyncEvent
    let to: SyncState
}

struct TransitionLog: Equatable, Sendable {
    static let capacity = 2000

    private(set) var lines: [String]

    init(lines: [String]) {
        self.lines = Array(lines.suffix(Self.capacity))
    }

    mutating func append(_ entry: TransitionLogEntry) {
        lines.append(Self.line(for: entry))
        let overflow = lines.count - Self.capacity
        if overflow > 0 { lines.removeFirst(overflow) }
    }

    func renderedText() -> String {
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func line(for entry: TransitionLogEntry) -> String {
        let timestamp = timestampFormatter.string(from: entry.timestamp)
        return "\(timestamp) \(entry.from.logDescription) --\(entry.event.logDescription)--> \(entry.to.logDescription)"
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
