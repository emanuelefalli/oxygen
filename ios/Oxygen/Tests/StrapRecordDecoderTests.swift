import Foundation
import Testing
import ZeppKit
@testable import Oxygen

struct StrapRecordDecoderTests {
    @Test(arguments: DecoderFixture.all)
    func decodesUpstreamVector(_ fixture: DecoderFixture) throws {
        let round = StoredRound(fetched: FetchedRound(fetchType: fixture.fetchType, roundStart: fixture.roundStart,
                                                      payload: Data(fixture.payload), receivedAt: fixture.roundStart,
                                                      nextSince: nil))
        let records = try StrapRecordDecoder.decode(round)
        #expect(records.count == fixture.expectedRecordCount)
        #expect(records.first?.timestamp == fixture.expectedFirstTimestamp)
        #expect(records.first?.fields == fixture.expectedFirstFields)
        #expect(records.first?.fields.map(\.name) == StrapRecordDecoder.fieldNames(for: fixture.fetchType))
    }

    @Test func coversAllThirteenTypes() {
        #expect(Set(DecoderFixture.all.map(\.fetchType)) == Set(StrapFetchType.allCases))
    }

    @Test func zeppTypeKeepsTheWireCode() {
        for type in StrapFetchType.allCases {
            #expect(type.zeppFetchType.rawValue == type.rawValue)
        }
    }
}
