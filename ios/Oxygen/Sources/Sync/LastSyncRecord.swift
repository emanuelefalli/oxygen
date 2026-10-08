import Foundation

struct LastSyncRecord {
    static let key = "oxygen.lastSyncCompletedAt"

    let defaults: UserDefaults

    func load() -> Date? {
        defaults.object(forKey: Self.key) as? Date
    }

    func save(_ date: Date) {
        defaults.set(date, forKey: Self.key)
    }
}
