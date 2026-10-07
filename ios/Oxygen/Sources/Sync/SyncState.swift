enum SyncStep: Equatable, Sendable {
    case scanning
    case connecting
    case authenticating
    case preparing
    case fetching(StrapFetchType)
    case persisting(StrapFetchType)
}

enum SyncFailureReason: Equatable, Sendable {
    case bluetoothOff
    case bluetoothUnauthorized
    case strapNotFound
    case strapBusy
    case keyRejected
    case keyMissing
    case linkLost(during: SyncStep)
    case fetchTimeout(StrapFetchType)
    case persistFailed(StrapFetchType)
}

enum SyncPhase: Equatable, Sendable {
    case idle
    case active(SyncStep)
    case waitingForRetry(SyncFailureReason)
    case failed(SyncFailureReason)
}

struct SyncState: Equatable, Sendable {
    var phase: SyncPhase
    var retryUsed: Bool
}
