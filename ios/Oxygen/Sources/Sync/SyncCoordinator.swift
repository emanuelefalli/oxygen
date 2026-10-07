enum SyncCoordinator {
    static let scanTimeoutSeconds = 15
    static let authenticationTimeoutSeconds = 10
    static let preparationStepTimeoutSeconds = 5
    static let fetchTimeoutSeconds = 30
    static let retryDelaySeconds = 10

    static func initialState(hasKey: Bool, keyRejected: Bool) -> SyncState {
        guard hasKey else { return SyncState(phase: .failed(.keyMissing), retryUsed: false) }
        guard !keyRejected else { return SyncState(phase: .failed(.keyRejected), retryUsed: false) }
        return SyncState(phase: .idle, retryUsed: false)
    }

    static func reduce(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch state.phase {
        case .idle:
            return reduceIdle(state, event)
        case .active(let activeStep):
            return reduceActive(state, activeStep, event)
        case .waitingForRetry:
            return reduceWaitingForRetry(state, event)
        case .failed(let reason):
            return reduceFailed(state, reason, event)
        }
    }

    private static func reduceIdle(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .syncRequested:
            return startScanning(retryUsed: false)
        case .bluetoothPoweredOff:
            return move(state, to: .failed(.bluetoothOff), effects: [])
        case .bluetoothUnauthorized:
            return move(state, to: .failed(.bluetoothUnauthorized), effects: [])
        default:
            return unchanged(state)
        }
    }

    private static func reduceActive(_ state: SyncState, _ activeStep: SyncStep, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .bluetoothPoweredOff:
            return move(state, to: .failed(.bluetoothOff), effects: teardownEffects(for: activeStep))
        case .bluetoothUnauthorized:
            return move(state, to: .failed(.bluetoothUnauthorized), effects: teardownEffects(for: activeStep))
        case .linkLost where activeStep != .scanning:
            return retryOrFail(state, activeStep, reason: .linkLost(during: activeStep))
        default:
            break
        }

        switch activeStep {
        case .scanning:
            return reduceScanning(state, event)
        case .connecting:
            return reduceConnecting(state, event)
        case .authenticating:
            return reduceAuthenticating(state, event)
        case .preparing:
            return reducePreparing(state, event)
        case .fetching(let fetchType):
            return reduceFetching(state, fetchType, event)
        case .persisting(let fetchType):
            return reducePersisting(state, fetchType, event)
        }
    }

    private static func reduceScanning(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .strapDiscovered:
            return move(state, to: .active(.connecting), effects: [.cancelTimer(.scan), .stopScan, .connect])
        case .scanTimedOut:
            return move(state, to: .failed(.strapNotFound), effects: [.stopScan])
        default:
            return unchanged(state)
        }
    }

    private static func reduceConnecting(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .connected:
            return move(state, to: .active(.authenticating),
                        effects: [.authenticate, .armTimer(.session, seconds: authenticationTimeoutSeconds)])
        case .connectionFailed:
            return retryOrFail(state, .connecting, reason: .linkLost(during: .connecting))
        default:
            return unchanged(state)
        }
    }

    private static func reduceAuthenticating(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .authSucceeded:
            return move(state, to: .active(.preparing), effects: [.cancelTimer(.session), .prepareSession])
        case .authRejected:
            return move(state, to: .failed(.keyRejected),
                        effects: [.cancelTimer(.session), .markKeyRejected, .disconnect])
        case .authKeyMissing:
            return move(state, to: .failed(.keyMissing), effects: [.cancelTimer(.session), .disconnect])
        case .strapBusyDetected:
            return move(state, to: .failed(.strapBusy), effects: [.cancelTimer(.session), .disconnect])
        case .authTimedOut:
            return move(state, to: .failed(.strapBusy), effects: [.disconnect])
        default:
            return unchanged(state)
        }
    }

    private static func reducePreparing(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .preparationStepStarted:
            return SyncTransition(nextState: state,
                                  effects: [.armTimer(.session, seconds: preparationStepTimeoutSeconds)])
        case .preparationStepTimedOut:
            return SyncTransition(nextState: state, effects: [.skipPreparationStep])
        case .sessionPrepared:
            guard let firstType = StrapFetchType.syncOrder.first else { return unchanged(state) }
            return move(state, to: .active(.fetching(firstType)),
                        effects: [.cancelTimer(.session), .fetch(firstType),
                                  .armTimer(.fetch, seconds: fetchTimeoutSeconds)])
        default:
            return unchanged(state)
        }
    }

    private static func reduceFetching(_ state: SyncState, _ activeType: StrapFetchType,
                                       _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .fetchProgressed(let fetchType) where fetchType == activeType:
            return SyncTransition(nextState: state, effects: [.armTimer(.fetch, seconds: fetchTimeoutSeconds)])
        case .fetchCompleted(let fetchType) where fetchType == activeType:
            return move(state, to: .active(.persisting(activeType)),
                        effects: [.cancelTimer(.fetch), .persist(activeType)])
        case .fetchTimedOut(let fetchType) where fetchType == activeType:
            return retryOrFail(state, .fetching(activeType), reason: .fetchTimeout(activeType))
        default:
            return unchanged(state)
        }
    }

    private static func reducePersisting(_ state: SyncState, _ activeType: StrapFetchType,
                                         _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .persistSucceeded(let fetchType) where fetchType == activeType:
            guard let nextType = activeType.nextInSyncOrder else {
                return SyncTransition(nextState: SyncState(phase: .idle, retryUsed: false),
                                      effects: [.disconnect, .recordSyncCompleted])
            }
            return move(state, to: .active(.fetching(nextType)),
                        effects: [.fetch(nextType), .armTimer(.fetch, seconds: fetchTimeoutSeconds)])
        case .persistFailed(let fetchType) where fetchType == activeType:
            return move(state, to: .failed(.persistFailed(activeType)), effects: [.disconnect])
        default:
            return unchanged(state)
        }
    }

    private static func reduceWaitingForRetry(_ state: SyncState, _ event: SyncEvent) -> SyncTransition {
        switch event {
        case .retryTimerFired:
            return move(state, to: .active(.scanning),
                        effects: [.startScan, .armTimer(.scan, seconds: scanTimeoutSeconds)])
        case .bluetoothPoweredOff:
            return move(state, to: .failed(.bluetoothOff), effects: [.cancelTimer(.retry)])
        case .bluetoothUnauthorized:
            return move(state, to: .failed(.bluetoothUnauthorized), effects: [.cancelTimer(.retry)])
        default:
            return unchanged(state)
        }
    }

    private static func reduceFailed(_ state: SyncState, _ reason: SyncFailureReason,
                                     _ event: SyncEvent) -> SyncTransition {
        let needsKey = reason == .keyRejected || reason == .keyMissing
        let needsBluetooth = reason == .bluetoothOff || reason == .bluetoothUnauthorized
        switch event {
        case .syncRequested where !needsKey:
            return startScanning(retryUsed: false)
        case .authKeyEntered where needsKey:
            return move(state, to: .idle, effects: [])
        case .bluetoothPoweredOn where needsBluetooth:
            return move(state, to: .idle, effects: [])
        default:
            return unchanged(state)
        }
    }

    private static func startScanning(retryUsed: Bool) -> SyncTransition {
        SyncTransition(nextState: SyncState(phase: .active(.scanning), retryUsed: retryUsed),
                       effects: [.startScan, .armTimer(.scan, seconds: scanTimeoutSeconds)])
    }

    private static func retryOrFail(_ state: SyncState, _ activeStep: SyncStep,
                                    reason: SyncFailureReason) -> SyncTransition {
        let teardown = teardownEffects(for: activeStep)
        guard !state.retryUsed else {
            return move(state, to: .failed(reason), effects: teardown)
        }
        return SyncTransition(nextState: SyncState(phase: .waitingForRetry(reason), retryUsed: true),
                              effects: teardown + [.armTimer(.retry, seconds: retryDelaySeconds)])
    }

    private static func teardownEffects(for activeStep: SyncStep) -> [SyncEffect] {
        switch activeStep {
        case .scanning: return [.cancelTimer(.scan), .stopScan]
        case .authenticating, .preparing: return [.cancelTimer(.session), .disconnect]
        case .fetching: return [.cancelTimer(.fetch), .disconnect]
        case .connecting, .persisting: return [.disconnect]
        }
    }

    private static func move(_ state: SyncState, to phase: SyncPhase, effects: [SyncEffect]) -> SyncTransition {
        SyncTransition(nextState: SyncState(phase: phase, retryUsed: state.retryUsed), effects: effects)
    }

    private static func unchanged(_ state: SyncState) -> SyncTransition {
        SyncTransition(nextState: state, effects: [])
    }
}
