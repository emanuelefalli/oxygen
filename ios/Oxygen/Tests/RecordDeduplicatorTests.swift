import Foundation
import Testing
@testable import Oxygen

struct RecordDeduplicatorTests {
    let t0 = Date(timeIntervalSince1970: 1_791_355_320)
    let t1 = Date(timeIntervalSince1970: 1_791_355_380)

    func record(_ type: StrapFetchType, _ at: Date, received: Date, value: String) -> DecodedStrapRecord {
        DecodedStrapRecord(fetchType: type, timestamp: at, fields: [StrapRecordField(name: "v", value: value)],
                           receivedAt: received)
    }

    @Test func laterReceiptWins() {
        let merged = RecordDeduplicator.merge([
            record(.activity, t1, received: t0, value: "b"),
            record(.activity, t0, received: t0, value: "old"),
            record(.activity, t0, received: t1, value: "new"),
        ])
        #expect(merged.map { $0.fields[0].value } == ["new", "b"])
    }

    @Test func differentTypesWithSameTimestampAreKept() {
        let merged = RecordDeduplicator.merge([record(.activity, t0, received: t0, value: "a"),
                                               record(.temperature, t0, received: t0, value: "t")])
        #expect(merged.count == 2)
    }
}
