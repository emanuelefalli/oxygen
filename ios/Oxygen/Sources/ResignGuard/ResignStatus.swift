import Foundation

enum ResignStatus: Equatable, Sendable {
    case unknown
    case valid(daysRemaining: Int)
    case expiringSoon(daysRemaining: Int)

    static let expiringSoonInterval: TimeInterval = 172_800

    static func evaluate(expiration: Date?, now: Date) -> ResignStatus {
        guard let expiration else { return .unknown }
        let interval = expiration.timeIntervalSince(now)
        let daysRemaining = max(0, Int((interval / 86_400).rounded(.down)))
        guard interval > expiringSoonInterval else { return .expiringSoon(daysRemaining: daysRemaining) }
        return .valid(daysRemaining: daysRemaining)
    }
}
