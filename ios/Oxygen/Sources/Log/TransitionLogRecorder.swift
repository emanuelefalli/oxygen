import Foundation

struct TransitionLogFile: Sendable {
    let url: URL

    func load() -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").map(String.init)
    }

    func write(_ log: TransitionLog) throws {
        try Data(log.renderedText().utf8).write(to: url, options: .atomic)
    }
}

@MainActor final class TransitionLogRecorder {
    private(set) var log: TransitionLog
    private let file: TransitionLogFile?

    init(file: TransitionLogFile?) {
        self.file = file
        self.log = TransitionLog(lines: file?.load() ?? [])
    }

    func record(_ entry: TransitionLogEntry) {
        log.append(entry)
        guard let file else { return }
        try? file.write(log)
    }
}
