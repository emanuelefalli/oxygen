import Foundation
import SwiftData

@Model final class StrapHistoryRound {
    @Attribute(.unique) var identity: String
    var fetchTypeCode: Int
    var roundStart: Date
    var payload: Data
    var payloadDigest: String
    var receivedAt: Date

    init(_ round: StoredRound) {
        identity = round.identity
        fetchTypeCode = Int(round.fetchType.rawValue)
        roundStart = round.roundStart
        payload = round.payload
        payloadDigest = round.payloadDigest
        receivedAt = round.receivedAt
    }
}
