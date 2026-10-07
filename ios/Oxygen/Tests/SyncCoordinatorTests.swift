import Testing
@testable import Oxygen

fileprivate func state(_ phase: SyncPhase, retryUsed: Bool = false) -> SyncState {
    SyncState(phase: phase, retryUsed: retryUsed)
}

fileprivate func step(_ activeStep: SyncStep, retryUsed: Bool = false) -> SyncState {
    state(.active(activeStep), retryUsed: retryUsed)
}

fileprivate func failed(_ reason: SyncFailureReason) -> SyncState {
    state(.failed(reason))
}

fileprivate func expectedTeardown(_ activeStep: SyncStep) -> [SyncEffect] {
    switch activeStep {
    case .scanning: return [.cancelTimer(.scan), .stopScan]
    case .authenticating, .preparing: return [.cancelTimer(.session), .disconnect]
    case .fetching: return [.cancelTimer(.fetch), .disconnect]
    case .connecting, .persisting: return [.disconnect]
    }
}

fileprivate let connectedSteps: [SyncStep] = [
    .connecting, .authenticating, .preparing, .fetching(.temperature), .persisting(.temperature),
]

fileprivate let allSteps: [SyncStep] = [.scanning] + connectedSteps

struct SyncCoordinatorTransitionRow: Sendable, CustomTestStringConvertible {
    let name: String
    let state: SyncState
    let event: SyncEvent
    let nextState: SyncState
    let effects: [SyncEffect]

    var testDescription: String { name }
}

struct SyncCoordinatorStateEventPair: Sendable, CustomTestStringConvertible {
    let state: SyncState
    let event: SyncEvent

    var testDescription: String { "\(state) + \(event)" }
}

enum SyncCoordinatorTable {
    static func row(_ name: String, _ from: SyncState, _ event: SyncEvent,
                    _ to: SyncState, _ effects: [SyncEffect]) -> SyncCoordinatorTransitionRow {
        SyncCoordinatorTransitionRow(name: name, state: from, event: event, nextState: to, effects: effects)
    }

    static let rows: [SyncCoordinatorTransitionRow] = [
        row("idleSyncRequestedStartsScan", state(.idle), .syncRequested,
            step(.scanning), [.startScan, .armTimer(.scan, seconds: 15)]),
        row("idleBluetoothPoweredOffFails", state(.idle), .bluetoothPoweredOff,
            failed(.bluetoothOff), []),
        row("idleBluetoothUnauthorizedFails", state(.idle), .bluetoothUnauthorized,
            failed(.bluetoothUnauthorized), []),
        row("scanningStrapDiscoveredConnects", step(.scanning), .strapDiscovered,
            step(.connecting), [.cancelTimer(.scan), .stopScan, .connect]),
        row("scanningTimeoutFailsNotFound", step(.scanning), .scanTimedOut,
            failed(.strapNotFound), [.stopScan]),
        row("scanningSyncRequestedIsIgnored", step(.scanning), .syncRequested,
            step(.scanning), []),
        row("connectingConnectedAuthenticates", step(.connecting), .connected,
            step(.authenticating), [.authenticate, .armTimer(.session, seconds: 10)]),
        row("connectingFailureWaitsForRetry", step(.connecting), .connectionFailed,
            state(.waitingForRetry(.linkLost(during: .connecting)), retryUsed: true),
            [.disconnect, .armTimer(.retry, seconds: 10)]),
        row("connectingFailureAfterRetryFails", step(.connecting, retryUsed: true), .connectionFailed,
            state(.failed(.linkLost(during: .connecting)), retryUsed: true), [.disconnect]),
        row("authenticatingSuccessPrepares", step(.authenticating), .authSucceeded,
            step(.preparing), [.cancelTimer(.session), .prepareSession]),
        row("authenticatingRejectedMarksKey", step(.authenticating), .authRejected,
            failed(.keyRejected), [.cancelTimer(.session), .markKeyRejected, .disconnect]),
        row("authenticatingKeyMissingFails", step(.authenticating), .authKeyMissing,
            failed(.keyMissing), [.cancelTimer(.session), .disconnect]),
        row("authenticatingBusyFails", step(.authenticating), .strapBusyDetected,
            failed(.strapBusy), [.cancelTimer(.session), .disconnect]),
        row("authenticatingTimeoutFailsBusy", step(.authenticating), .authTimedOut,
            failed(.strapBusy), [.disconnect]),
        row("preparingStepStartedArmsTimer", step(.preparing), .preparationStepStarted,
            step(.preparing), [.armTimer(.session, seconds: 5)]),
        row("preparingStepTimeoutSkipsStep", step(.preparing), .preparationStepTimedOut,
            step(.preparing), [.skipPreparationStep]),
        row("preparingDoneFetchesActivity", step(.preparing), .sessionPrepared,
            step(.fetching(.activity)),
            [.cancelTimer(.session), .fetch(.activity), .armTimer(.fetch, seconds: 30)]),
        row("fetchingProgressRearmsTimer", step(.fetching(.temperature)), .fetchProgressed(.temperature),
            step(.fetching(.temperature)), [.armTimer(.fetch, seconds: 30)]),
        row("fetchingCompletedPersists", step(.fetching(.temperature)), .fetchCompleted(.temperature),
            step(.persisting(.temperature)), [.cancelTimer(.fetch), .persist(.temperature)]),
        row("fetchingTimeoutWaitsForRetry", step(.fetching(.temperature)), .fetchTimedOut(.temperature),
            state(.waitingForRetry(.fetchTimeout(.temperature)), retryUsed: true),
            [.cancelTimer(.fetch), .disconnect, .armTimer(.retry, seconds: 10)]),
        row("fetchingTimeoutAfterRetryFails", step(.fetching(.temperature), retryUsed: true),
            .fetchTimedOut(.temperature),
            state(.failed(.fetchTimeout(.temperature)), retryUsed: true), [.cancelTimer(.fetch), .disconnect]),
        row("fetchingSyncRequestedIsIgnored", step(.fetching(.temperature)), .syncRequested,
            step(.fetching(.temperature)), []),
        row("persistingSuccessFetchesNextType", step(.persisting(.temperature)), .persistSucceeded(.temperature),
            step(.fetching(.sleepRespiratoryRate)),
            [.fetch(.sleepRespiratoryRate), .armTimer(.fetch, seconds: 30)]),
        row("persistingLastTypeCompletesSync", step(.persisting(.heartRateVariability), retryUsed: true),
            .persistSucceeded(.heartRateVariability),
            state(.idle), [.disconnect, .recordSyncCompleted]),
        row("persistingFailureFails", step(.persisting(.temperature)), .persistFailed(.temperature),
            failed(.persistFailed(.temperature)), [.disconnect]),
        row("waitingRetryTimerScansAgain",
            state(.waitingForRetry(.linkLost(during: .connecting)), retryUsed: true), .retryTimerFired,
            step(.scanning, retryUsed: true), [.startScan, .armTimer(.scan, seconds: 15)]),
        row("failedKeyRejectedIgnoresSync", failed(.keyRejected), .syncRequested,
            failed(.keyRejected), []),
        row("failedKeyRejectedKeyEnteredIdles", failed(.keyRejected), .authKeyEntered,
            state(.idle), []),
        row("failedKeyMissingIgnoresSync", failed(.keyMissing), .syncRequested,
            failed(.keyMissing), []),
        row("failedKeyMissingKeyEnteredIdles", failed(.keyMissing), .authKeyEntered,
            state(.idle), []),
        row("failedBluetoothOffPoweredOnIdles", failed(.bluetoothOff), .bluetoothPoweredOn,
            state(.idle), []),
        row("failedBluetoothUnauthorizedPoweredOnIdles", failed(.bluetoothUnauthorized), .bluetoothPoweredOn,
            state(.idle), []),
    ]

    static let representativeFailures: [SyncFailureReason] = [
        .bluetoothOff, .bluetoothUnauthorized, .strapNotFound, .strapBusy,
        .keyRejected, .keyMissing, .persistFailed(.temperature),
    ]

    static let representativeStates: [SyncState] = {
        var states: [SyncState] = [state(.idle)]
        states += allSteps.map { step($0) }
        states.append(state(.waitingForRetry(.linkLost(during: .connecting)), retryUsed: true))
        states += representativeFailures.map { failed($0) }
        return states
    }()

    static let untypedEvents: [SyncEvent] = [
        .syncRequested, .authKeyEntered, .authKeyMissing,
        .bluetoothPoweredOn, .bluetoothPoweredOff, .bluetoothUnauthorized,
        .strapDiscovered, .strapBusyDetected, .scanTimedOut, .connected, .connectionFailed,
        .authSucceeded, .authRejected, .authTimedOut,
        .preparationStepStarted, .preparationStepTimedOut, .sessionPrepared,
        .linkLost, .retryTimerFired,
    ]

    static func typedEvents(for fetchType: StrapFetchType) -> [SyncEvent] {
        [.fetchProgressed(fetchType), .fetchCompleted(fetchType), .fetchTimedOut(fetchType),
         .persistSucceeded(fetchType), .persistFailed(fetchType)]
    }

    static let allEvents: [SyncEvent] = untypedEvents + typedEvents(for: .temperature) + typedEvents(for: .activity)

    static func isListed(_ pair: SyncCoordinatorStateEventPair) -> Bool {
        rows.contains { $0.state == pair.state && $0.event == pair.event }
    }

    static func isCoveredByGenericRule(_ pair: SyncCoordinatorStateEventPair) -> Bool {
        switch (pair.state.phase, pair.event) {
        case (.active(let activeStep), .linkLost):
            return activeStep != .scanning
        case (.active, .bluetoothPoweredOff), (.active, .bluetoothUnauthorized):
            return true
        case (.waitingForRetry, .bluetoothPoweredOff), (.waitingForRetry, .bluetoothUnauthorized):
            return true
        case (.failed(let reason), .syncRequested):
            return reason != .keyRejected && reason != .keyMissing
        default:
            return false
        }
    }

    static let ignoredPairs: [SyncCoordinatorStateEventPair] = representativeStates
        .flatMap { from in allEvents.map { SyncCoordinatorStateEventPair(state: from, event: $0) } }
        .filter { !isListed($0) && !isCoveredByGenericRule($0) }
}

struct SyncCoordinatorTests {
    @Test(arguments: SyncCoordinatorTable.rows)
    func listedTransition(_ row: SyncCoordinatorTransitionRow) {
        #expect(SyncCoordinator.reduce(row.state, row.event)
                == SyncTransition(nextState: row.nextState, effects: row.effects))
    }

    @Test(arguments: connectedSteps)
    func linkLostInConnectedStepWaitsForRetry(_ activeStep: SyncStep) {
        #expect(SyncCoordinator.reduce(step(activeStep), .linkLost)
                == SyncTransition(nextState: state(.waitingForRetry(.linkLost(during: activeStep)), retryUsed: true),
                                  effects: expectedTeardown(activeStep) + [.armTimer(.retry, seconds: 10)]))
    }

    @Test(arguments: connectedSteps)
    func linkLostAfterRetryFails(_ activeStep: SyncStep) {
        #expect(SyncCoordinator.reduce(step(activeStep, retryUsed: true), .linkLost)
                == SyncTransition(nextState: state(.failed(.linkLost(during: activeStep)), retryUsed: true),
                                  effects: expectedTeardown(activeStep)))
    }

    @Test(arguments: allSteps)
    func bluetoothPoweredOffInEveryActiveStepFails(_ activeStep: SyncStep) {
        #expect(SyncCoordinator.reduce(step(activeStep), .bluetoothPoweredOff)
                == SyncTransition(nextState: failed(.bluetoothOff), effects: expectedTeardown(activeStep)))
    }

    @Test(arguments: allSteps)
    func bluetoothUnauthorizedInEveryActiveStepFails(_ activeStep: SyncStep) {
        #expect(SyncCoordinator.reduce(step(activeStep), .bluetoothUnauthorized)
                == SyncTransition(nextState: failed(.bluetoothUnauthorized), effects: expectedTeardown(activeStep)))
    }

    @Test func bluetoothEventsWhileWaitingForRetryFail() {
        let waiting = state(.waitingForRetry(.linkLost(during: .connecting)), retryUsed: true)
        #expect(SyncCoordinator.reduce(waiting, .bluetoothPoweredOff)
                == SyncTransition(nextState: state(.failed(.bluetoothOff), retryUsed: true),
                                  effects: [.cancelTimer(.retry)]))
        #expect(SyncCoordinator.reduce(waiting, .bluetoothUnauthorized)
                == SyncTransition(nextState: state(.failed(.bluetoothUnauthorized), retryUsed: true),
                                  effects: [.cancelTimer(.retry)]))
    }

    @Test(arguments: [SyncFailureReason.bluetoothOff, .bluetoothUnauthorized, .strapNotFound, .strapBusy,
                      .linkLost(during: .connecting), .fetchTimeout(.temperature), .persistFailed(.temperature)])
    func syncRequestedAfterFailureScans(_ reason: SyncFailureReason) {
        #expect(SyncCoordinator.reduce(state(.failed(reason), retryUsed: true), .syncRequested)
                == SyncTransition(nextState: step(.scanning), effects: [.startScan, .armTimer(.scan, seconds: 15)]))
    }

    @Test(arguments: SyncCoordinatorTable.ignoredPairs)
    func ignoredPairLeavesStateUnchanged(_ pair: SyncCoordinatorStateEventPair) {
        #expect(SyncCoordinator.reduce(pair.state, pair.event) == SyncTransition(nextState: pair.state, effects: []))
    }

    @Test func initialState() {
        #expect(SyncCoordinator.initialState(hasKey: false, keyRejected: false) == failed(.keyMissing))
        #expect(SyncCoordinator.initialState(hasKey: false, keyRejected: true) == failed(.keyMissing))
        #expect(SyncCoordinator.initialState(hasKey: true, keyRejected: true) == failed(.keyRejected))
        #expect(SyncCoordinator.initialState(hasKey: true, keyRejected: false) == state(.idle))
    }
}
