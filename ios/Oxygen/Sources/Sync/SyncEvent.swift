enum SyncEvent: Equatable, Sendable {
    case syncRequested
    case authKeyEntered
    case authKeyMissing
    case bluetoothPoweredOn
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case strapDiscovered
    case strapBusyDetected
    case scanTimedOut
    case connected
    case connectionFailed
    case authSucceeded
    case authRejected
    case authTimedOut
    case preparationStepStarted
    case preparationStepTimedOut
    case sessionPrepared
    case fetchProgressed(StrapFetchType)
    case fetchCompleted(StrapFetchType)
    case fetchTimedOut(StrapFetchType)
    case linkLost
    case persistSucceeded(StrapFetchType)
    case persistFailed(StrapFetchType)
    case retryTimerFired
}

enum SyncTimer: Hashable, Sendable {
    case scan
    case session
    case fetch
    case retry
}

enum SyncEffect: Equatable, Sendable {
    case startScan
    case stopScan
    case connect
    case disconnect
    case authenticate
    case prepareSession
    case skipPreparationStep
    case fetch(StrapFetchType)
    case persist(StrapFetchType)
    case armTimer(SyncTimer, seconds: Int)
    case cancelTimer(SyncTimer)
    case markKeyRejected
    case recordSyncCompleted
}

struct SyncTransition: Equatable, Sendable {
    let nextState: SyncState
    let effects: [SyncEffect]
}
