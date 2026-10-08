import CryptoKit
import Foundation

struct StoredRound: Equatable, Sendable {
    let fetchType: StrapFetchType
    let roundStart: Date
    let payload: Data
    let payloadDigest: String
    let receivedAt: Date

    init(fetchType: StrapFetchType, roundStart: Date, payload: Data, payloadDigest: String, receivedAt: Date) {
        self.fetchType = fetchType
        self.roundStart = roundStart
        self.payload = payload
        self.payloadDigest = payloadDigest
        self.receivedAt = receivedAt
    }

    init(fetched: FetchedRound) {
        self.init(fetchType: fetched.fetchType,
                  roundStart: fetched.roundStart,
                  payload: fetched.payload,
                  payloadDigest: Self.sha256Hex(fetched.payload),
                  receivedAt: fetched.receivedAt)
    }

    var identity: String {
        let roundStartMilliseconds = Int64(roundStart.timeIntervalSince1970 * 1000)
        return "\(fetchType.rawValue)-\(roundStartMilliseconds)-\(payloadDigest)"
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
