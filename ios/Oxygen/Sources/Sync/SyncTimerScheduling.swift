import Foundation

@MainActor protocol SyncTimerScheduling: AnyObject {
    func schedule(_ timer: SyncTimer, afterSeconds seconds: Int)
    func cancel(_ timer: SyncTimer)
}

@MainActor final class TaskSyncTimerScheduler: SyncTimerScheduling {
    private let fired: AsyncStream<SyncTimer>.Continuation
    private var pending: [SyncTimer: Task<Void, Never>] = [:]

    init(fired: AsyncStream<SyncTimer>.Continuation) {
        self.fired = fired
    }

    func schedule(_ timer: SyncTimer, afterSeconds seconds: Int) {
        pending[timer]?.cancel()
        pending[timer] = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.fire(timer)
        }
    }

    func cancel(_ timer: SyncTimer) {
        pending[timer]?.cancel()
        pending[timer] = nil
    }

    private func fire(_ timer: SyncTimer) {
        pending[timer] = nil
        fired.yield(timer)
    }
}
