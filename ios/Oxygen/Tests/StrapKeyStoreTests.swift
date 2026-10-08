import Foundation
import Testing
@testable import Oxygen

final class StrapKeyStoreTests {
    let store = StrapKeyStore(service: "com.emanuelefalli.oxygen.tests.\(UUID().uuidString)")

    deinit { try? store.delete() }

    @Test func emptyStoreLoadsNil() throws {
        #expect(try store.load() == nil)
        #expect(try store.isRejected() == false)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let key = try #require(StrapAuthKey.parse("00112233445566778899aabbccddeeff"))
        try store.save(key)
        #expect(try store.load() == key)
    }

    @Test func saveClearsRejectionMark() throws {
        let key = try #require(StrapAuthKey.parse("00112233445566778899aabbccddeeff"))
        try store.markRejected()
        #expect(try store.isRejected())
        try store.save(key)
        #expect(try store.isRejected() == false)
    }
}
