import Foundation

enum SyncStatusText {
    static func make(state: SyncState, lastSyncCompletedAt: Date?, now: Date, timeZone: TimeZone) -> String {
        switch state.phase {
        case .idle:
            return idleText(lastSyncCompletedAt: lastSyncCompletedAt, now: now, timeZone: timeZone)
        case .active(let step):
            return activeText(step)
        case .waitingForRetry:
            return "Connection lost, retrying in \(SyncCoordinator.retryDelaySeconds) s"
        case .failed(let reason):
            return failureText(reason)
        }
    }

    private static func idleText(lastSyncCompletedAt: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let lastSyncCompletedAt else { return "Not synced yet" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = calendar.isDate(lastSyncCompletedAt, inSameDayAs: now) ? "HH:mm" : "d MMM HH:mm"
        return "Synced " + formatter.string(from: lastSyncCompletedAt)
    }

    private static func activeText(_ step: SyncStep) -> String {
        switch step {
        case .scanning: return "Looking for the strap"
        case .connecting: return "Connecting to the strap"
        case .authenticating: return "Authenticating"
        case .preparing: return "Preparing the strap"
        case .fetching(let fetchType): return "Fetching \(fetchType.displayName)"
        case .persisting(let fetchType): return "Saving \(fetchType.displayName)"
        }
    }

    private static func failureText(_ reason: SyncFailureReason) -> String {
        switch reason {
        case .bluetoothOff: return "Bluetooth is off"
        case .bluetoothUnauthorized: return "Bluetooth permission denied. Allow it in Settings."
        case .strapNotFound: return "Strap not found"
        case .strapBusy: return "Strap busy: turn off Bluetooth for Zepp"
        case .keyRejected: return "Key rejected: paste a new key"
        case .keyMissing: return "Paste the strap's auth key"
        case .linkLost: return "Connection lost"
        case .fetchTimeout(let fetchType): return "The strap stopped sending \(fetchType.displayName)"
        case .persistFailed(let fetchType): return "Could not save \(fetchType.displayName)"
        }
    }
}
