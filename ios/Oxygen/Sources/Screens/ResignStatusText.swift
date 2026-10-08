enum ResignStatusText {
    static func line(_ status: ResignStatus) -> String {
        switch status {
        case .unknown:
            return "Re-sign status unknown"
        case .valid(let daysRemaining):
            return "Re-install within \(dayCount(daysRemaining))"
        case .expiringSoon(0):
            return "Re-install today"
        case .expiringSoon(let daysRemaining):
            return "Re-install within \(dayCount(daysRemaining))"
        }
    }

    static func banner(_ status: ResignStatus) -> String? {
        switch status {
        case .unknown, .valid:
            return nil
        case .expiringSoon(0):
            return "Oxygen expires today. Re-install it from Xcode."
        case .expiringSoon(let daysRemaining):
            return "Oxygen expires in \(dayCount(daysRemaining)). Re-install it from Xcode."
        }
    }

    private static func dayCount(_ days: Int) -> String {
        days == 1 ? "1 day" : "\(days) days"
    }
}
