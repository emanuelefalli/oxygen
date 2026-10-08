import Foundation
import UserNotifications

enum ResignReminder {
    static let identifier = "oxygen.resign-reminder"
    static let title = "Re-install Oxygen"
    static let body = "Oxygen stops opening tomorrow. Run it from Xcode on your Mac to renew it for 7 days."

    private static let leadTime: TimeInterval = 86_400

    static func fireDate(expiration: Date, now: Date) -> Date? {
        let fireDate = expiration.addingTimeInterval(-leadTime)
        guard fireDate > now else { return nil }
        return fireDate
    }

    static func schedule(expiration: Date?, now: Date, center: UNUserNotificationCenter) async {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let expiration, let fireDate = fireDate(expiration: expiration, now: now) else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: fireDate.timeIntervalSince(now), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
