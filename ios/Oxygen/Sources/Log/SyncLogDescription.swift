extension SyncStep {
    var logDescription: String {
        switch self {
        case .scanning: return "scanning"
        case .connecting: return "connecting"
        case .authenticating: return "authenticating"
        case .preparing: return "preparing"
        case .fetching(let fetchType): return "fetching(\(fetchType))"
        case .persisting(let fetchType): return "persisting(\(fetchType))"
        }
    }
}

extension SyncFailureReason {
    var logDescription: String {
        switch self {
        case .bluetoothOff: return "bluetoothOff"
        case .bluetoothUnauthorized: return "bluetoothUnauthorized"
        case .strapNotFound: return "strapNotFound"
        case .strapBusy: return "strapBusy"
        case .keyRejected: return "keyRejected"
        case .keyMissing: return "keyMissing"
        case .linkLost(let activeStep): return "linkLost(\(activeStep.logDescription))"
        case .fetchTimeout(let fetchType): return "fetchTimeout(\(fetchType))"
        case .persistFailed(let fetchType): return "persistFailed(\(fetchType))"
        }
    }
}

extension SyncState {
    var logDescription: String {
        let phaseDescription: String
        switch phase {
        case .idle: phaseDescription = "idle"
        case .active(let activeStep): phaseDescription = activeStep.logDescription
        case .waitingForRetry(let reason): phaseDescription = "waitingForRetry(\(reason.logDescription))"
        case .failed(let reason): phaseDescription = "failed(\(reason.logDescription))"
        }
        return retryUsed ? phaseDescription + " retryUsed" : phaseDescription
    }
}

extension SyncEvent {
    var logDescription: String {
        switch self {
        case .syncRequested: return "syncRequested"
        case .authKeyEntered: return "authKeyEntered"
        case .authKeyMissing: return "authKeyMissing"
        case .bluetoothPoweredOn: return "bluetoothPoweredOn"
        case .bluetoothPoweredOff: return "bluetoothPoweredOff"
        case .bluetoothUnauthorized: return "bluetoothUnauthorized"
        case .strapDiscovered: return "strapDiscovered"
        case .strapBusyDetected: return "strapBusyDetected"
        case .scanTimedOut: return "scanTimedOut"
        case .connected: return "connected"
        case .connectionFailed: return "connectionFailed"
        case .authSucceeded: return "authSucceeded"
        case .authRejected: return "authRejected"
        case .authTimedOut: return "authTimedOut"
        case .preparationStepStarted: return "preparationStepStarted"
        case .preparationStepTimedOut: return "preparationStepTimedOut"
        case .sessionPrepared: return "sessionPrepared"
        case .fetchProgressed(let fetchType): return "fetchProgressed(\(fetchType))"
        case .fetchCompleted(let fetchType): return "fetchCompleted(\(fetchType))"
        case .fetchTimedOut(let fetchType): return "fetchTimedOut(\(fetchType))"
        case .linkLost: return "linkLost"
        case .persistSucceeded(let fetchType): return "persistSucceeded(\(fetchType))"
        case .persistFailed(let fetchType): return "persistFailed(\(fetchType))"
        case .retryTimerFired: return "retryTimerFired"
        }
    }
}
