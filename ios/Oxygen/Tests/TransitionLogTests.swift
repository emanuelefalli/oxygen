import Foundation
import Testing
@testable import Oxygen

struct TransitionLogTests {
    let instant = Date(timeIntervalSince1970: 1_791_355_333.512)

    @Test func lineFormat() {
        var log = TransitionLog(lines: [])
        log.append(TransitionLogEntry(timestamp: instant, from: SyncState(phase: .idle, retryUsed: false),
                                      event: .syncRequested,
                                      to: SyncState(phase: .active(.scanning), retryUsed: false)))
        #expect(log.lines == ["2026-10-07T06:42:13.512Z idle --syncRequested--> scanning"])
    }

    @Test func describesNestedReasonAndRetryFlag() {
        let failedState = SyncState(phase: .failed(.linkLost(during: .fetching(.temperature))), retryUsed: true)
        #expect(failedState.logDescription == "failed(linkLost(fetching(temperature))) retryUsed")
        #expect(SyncEvent.fetchCompleted(.temperature).logDescription == "fetchCompleted(temperature)")
    }

    @Test func keepsOnlyLastCapacityLines() {
        var log = TransitionLog(lines: (0..<2000).map { "line \($0)" })
        log.append(TransitionLogEntry(timestamp: instant, from: SyncState(phase: .idle, retryUsed: false),
                                      event: .linkLost, to: SyncState(phase: .idle, retryUsed: false)))
        #expect(log.lines.count == 2000)
        #expect(log.lines.first == "line 1")
    }

    @Test func renderedTextEndsWithNewline() {
        #expect(TransitionLog(lines: ["a", "b"]).renderedText() == "a\nb\n")
        #expect(TransitionLog(lines: []).renderedText() == "")
    }

    @Test func fileRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".txt")
        let file = TransitionLogFile(url: url)
        try file.write(TransitionLog(lines: ["a", "b"]))
        #expect(file.load() == ["a", "b"])
    }
}
