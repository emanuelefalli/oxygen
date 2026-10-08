import Foundation
import SwiftData

@MainActor protocol RawStoring: AnyObject {
    func watermark(for type: StrapFetchType) throws -> Date?
    func commit(rounds: [StoredRound], type: StrapFetchType, watermark: Date?) throws
    func allRounds() throws -> [StoredRound]
}

@MainActor final class RawStore: RawStoring {
    private let context: ModelContext

    static func makeContainer(inMemory: Bool) throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: StrapHistoryRound.self, StrapFetchWatermark.self, configurations: configuration)
    }

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func watermark(for type: StrapFetchType) throws -> Date? {
        try storedWatermark(fetchTypeCode: Int(type.rawValue))?.watermark
    }

    func commit(rounds: [StoredRound], type: StrapFetchType, watermark: Date?) throws {
        var insertedIdentities = Set<String>()
        for round in rounds {
            let identity = round.identity
            guard !insertedIdentities.contains(identity) else { continue }
            guard try !isStored(identity: identity) else { continue }
            context.insert(StrapHistoryRound(round))
            insertedIdentities.insert(identity)
        }

        if let watermark {
            try advanceWatermark(fetchTypeCode: Int(type.rawValue), to: watermark)
        }

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func allRounds() throws -> [StoredRound] {
        let descriptor = FetchDescriptor<StrapHistoryRound>(sortBy: [
            SortDescriptor(\.fetchTypeCode), SortDescriptor(\.roundStart), SortDescriptor(\.receivedAt),
        ])
        return try context.fetch(descriptor).compactMap(Self.storedRound(from:))
    }

    private func isStored(identity: String) throws -> Bool {
        var descriptor = FetchDescriptor<StrapHistoryRound>(predicate: #Predicate { $0.identity == identity })
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }

    private func storedWatermark(fetchTypeCode: Int) throws -> StrapFetchWatermark? {
        var descriptor = FetchDescriptor<StrapFetchWatermark>(predicate: #Predicate { $0.fetchTypeCode == fetchTypeCode })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func advanceWatermark(fetchTypeCode: Int, to watermark: Date) throws {
        guard let existing = try storedWatermark(fetchTypeCode: fetchTypeCode) else {
            context.insert(StrapFetchWatermark(fetchTypeCode: fetchTypeCode, watermark: watermark))
            return
        }
        if watermark > existing.watermark { existing.watermark = watermark }
    }

    private static func storedRound(from record: StrapHistoryRound) -> StoredRound? {
        guard let code = UInt8(exactly: record.fetchTypeCode), let fetchType = StrapFetchType(rawValue: code) else {
            return nil
        }
        return StoredRound(fetchType: fetchType, roundStart: record.roundStart, payload: record.payload,
                           payloadDigest: record.payloadDigest, receivedAt: record.receivedAt)
    }
}
