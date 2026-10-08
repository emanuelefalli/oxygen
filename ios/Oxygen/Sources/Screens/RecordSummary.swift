import Foundation

struct RecordSummaryRow: Equatable, Identifiable, Sendable {
    let fetchType: StrapFetchType
    let count: Int
    let oldest: Date?
    let newest: Date?

    var id: UInt8 { fetchType.rawValue }
}

enum RecordSummary {
    static func make(records: [DecodedStrapRecord]) -> [RecordSummaryRow] {
        StrapFetchType.syncOrder.map { fetchType in
            let timestamps = records.filter { $0.fetchType == fetchType }.map(\.timestamp)
            return RecordSummaryRow(fetchType: fetchType, count: timestamps.count,
                                    oldest: timestamps.min(), newest: timestamps.max())
        }
    }
}
