import Foundation
@testable import Oxygen

@MainActor final class FailingRawStore: RawStoring {
    struct InjectedFailure: Error {}

    private let wrapped: RawStore
    private let failingType: StrapFetchType

    init(wrapping wrapped: RawStore, failingType: StrapFetchType) {
        self.wrapped = wrapped
        self.failingType = failingType
    }

    func watermark(for type: StrapFetchType) throws -> Date? {
        try wrapped.watermark(for: type)
    }

    func commit(rounds: [StoredRound], type: StrapFetchType, watermark: Date?) throws {
        guard type != failingType else { throw InjectedFailure() }
        try wrapped.commit(rounds: rounds, type: type, watermark: watermark)
    }

    func allRounds() throws -> [StoredRound] {
        try wrapped.allRounds()
    }
}
