import Foundation
import Testing
@testable import Oxygen

@MainActor struct RawStoreTests {
    let t0 = Date(timeIntervalSince1970: 1_791_355_320)
    let t1 = Date(timeIntervalSince1970: 1_791_528_120)

    func makeStore() throws -> RawStore { RawStore(container: try RawStore.makeContainer(inMemory: true)) }

    func round(_ bytes: [UInt8], start: Date) -> StoredRound {
        StoredRound(fetched: FetchedRound(fetchType: .activity, roundStart: start, payload: Data(bytes),
                                          receivedAt: t0, nextSince: nil))
    }

    @Test func digestAndIdentity() {
        let stored = round([0x01, 0x02, 0x03], start: t0)
        #expect(stored.payloadDigest == "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
        #expect(stored.identity == "1-1791355320000-039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81")
    }

    @Test func commitStoresRoundsAndWatermark() throws {
        let store = try makeStore()
        try store.commit(rounds: [round([0x01, 0x02, 0x03], start: t0), round([0x0a, 0x0b], start: t0)],
                         type: .activity, watermark: t1)
        #expect(try store.allRounds().count == 2)
        #expect(try store.watermark(for: .activity) == t1)
        #expect(try store.watermark(for: .temperature) == nil)
    }

    @Test func committingSameRoundTwiceStoresOnce() throws {
        let store = try makeStore()
        try store.commit(rounds: [round([0x01, 0x02, 0x03], start: t0)], type: .activity, watermark: t0)
        try store.commit(rounds: [round([0x01, 0x02, 0x03], start: t0)], type: .activity, watermark: t0)
        #expect(try store.allRounds().count == 1)
    }

    @Test func duplicateRoundsInOneBatchStoreOnce() throws {
        let store = try makeStore()
        let duplicate = round([0x01, 0x02, 0x03], start: t0)
        try store.commit(rounds: [duplicate, duplicate], type: .activity, watermark: t0)
        #expect(try store.allRounds().count == 1)
    }

    @Test func watermarkNeverMovesBackward() throws {
        let store = try makeStore()
        try store.commit(rounds: [], type: .activity, watermark: t1)
        try store.commit(rounds: [], type: .activity, watermark: t0)
        try store.commit(rounds: [], type: .activity, watermark: nil)
        #expect(try store.watermark(for: .activity) == t1)
    }
}
