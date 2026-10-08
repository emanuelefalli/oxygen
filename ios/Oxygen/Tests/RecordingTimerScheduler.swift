@testable import Oxygen

@MainActor final class RecordingTimerScheduler: SyncTimerScheduling {
    private(set) var scheduled: [(SyncTimer, Int)] = []
    private(set) var cancelled: [SyncTimer] = []

    func schedule(_ timer: SyncTimer, afterSeconds seconds: Int) {
        scheduled.append((timer, seconds))
    }

    func cancel(_ timer: SyncTimer) {
        cancelled.append(timer)
    }
}
