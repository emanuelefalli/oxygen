import Foundation

struct FetchedRound: Equatable, Sendable {
    let fetchType: StrapFetchType
    let roundStart: Date
    let payload: Data
    let receivedAt: Date
    let nextSince: Date?
}
