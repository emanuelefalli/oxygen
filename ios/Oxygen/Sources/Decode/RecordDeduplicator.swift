import Foundation

enum RecordDeduplicator {
    private struct RecordKey: Hashable {
        let fetchType: StrapFetchType
        let timestamp: Date
    }

    static func merge(_ records: [DecodedStrapRecord]) -> [DecodedStrapRecord] {
        var latestByKey: [RecordKey: DecodedStrapRecord] = [:]
        for record in records {
            let key = RecordKey(fetchType: record.fetchType, timestamp: record.timestamp)
            if let kept = latestByKey[key], kept.receivedAt > record.receivedAt {
                continue
            }
            latestByKey[key] = record
        }
        return latestByKey.values.sorted(by: isOrderedBefore)
    }

    private static func isOrderedBefore(_ left: DecodedStrapRecord, _ right: DecodedStrapRecord) -> Bool {
        if left.fetchType.rawValue != right.fetchType.rawValue {
            return left.fetchType.rawValue < right.fetchType.rawValue
        }
        return left.timestamp < right.timestamp
    }
}
