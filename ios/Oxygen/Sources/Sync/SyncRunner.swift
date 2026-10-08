import Foundation
import Observation

enum SyncRunnerInput: Equatable, Sendable {
    case syncRequested
    case authKeyEntered
    case connection(StrapConnectionEvent)
    case timerFired(SyncTimer)
}

@MainActor @Observable final class SyncRunner {
    private(set) var state: SyncState
    private(set) var deviceSummary: StrapDeviceSummary?

    var transitionLogLines: [String] { logRecorder.log.lines }

    private enum PendingWork {
        case input(SyncRunnerInput)
        case event(SyncEvent)
    }

    private let connection: StrapConnecting
    private let timers: SyncTimerScheduling
    private let store: RawStoring
    private let keyStore: StrapKeyStoring
    private let lastSync: LastSyncRecord
    private let logRecorder: TransitionLogRecorder
    private let now: () -> Date
    private let timeZone: TimeZone

    @ObservationIgnored private var session = StrapSession()
    @ObservationIgnored private var maximumWriteLength = 0
    @ObservationIgnored private var notifiable: Set<StrapCharacteristic> = []
    @ObservationIgnored private var pendingRounds: [StrapFetchType: [FetchedRound]] = [:]
    @ObservationIgnored private var pendingWork: [PendingWork] = []
    @ObservationIgnored private var isDraining = false

    init(initialState: SyncState, connection: StrapConnecting, timers: SyncTimerScheduling, store: RawStoring,
         keyStore: StrapKeyStoring, lastSync: LastSyncRecord, logRecorder: TransitionLogRecorder,
         now: @escaping () -> Date, timeZone: TimeZone) {
        self.state = initialState
        self.connection = connection
        self.timers = timers
        self.store = store
        self.keyStore = keyStore
        self.lastSync = lastSync
        self.logRecorder = logRecorder
        self.now = now
        self.timeZone = timeZone
    }

    func receive(_ input: SyncRunnerInput) {
        pendingWork.append(.input(input))
        guard !isDraining else { return }
        isDraining = true
        while !pendingWork.isEmpty {
            switch pendingWork.removeFirst() {
            case .input(let next):
                handleInput(next)
            case .event(let event):
                apply(event)
            }
        }
        isDraining = false
    }

    private func enqueue(_ event: SyncEvent) {
        pendingWork.append(.event(event))
    }

    // MARK: Inputs

    private func handleInput(_ input: SyncRunnerInput) {
        switch input {
        case .syncRequested:
            enqueue(.syncRequested)
        case .authKeyEntered:
            enqueue(.authKeyEntered)
        case .connection(let event):
            handleConnectionEvent(event)
        case .timerFired(let timer):
            handleTimerFired(timer)
        }
    }

    private func handleConnectionEvent(_ event: StrapConnectionEvent) {
        switch event {
        case .bluetoothPoweredOn:
            enqueue(.bluetoothPoweredOn)
        case .bluetoothPoweredOff:
            enqueue(.bluetoothPoweredOff)
        case .bluetoothUnauthorized:
            enqueue(.bluetoothUnauthorized)
        case .strapDiscovered:
            enqueue(.strapDiscovered)
        case .connected(let maximumWriteLength, let notifiable):
            self.maximumWriteLength = maximumWriteLength
            self.notifiable = notifiable
            session = StrapSession()
            enqueue(.connected)
        case .connectionFailed:
            enqueue(.connectionFailed)
        case .linkLost:
            enqueue(.linkLost)
        case .notification(let characteristic, let data):
            process(session.handle(.notification(characteristic, data)))
        case .notifyStateChanged(let characteristic, let enabled):
            process(session.handle(.notifyStateChanged(characteristic, enabled: enabled)))
        }
    }

    private func handleTimerFired(_ timer: SyncTimer) {
        switch (timer, state.phase) {
        case (.scan, _):
            enqueue(.scanTimedOut)
        case (.session, .active(.authenticating)):
            enqueue(.authTimedOut)
        case (.session, .active(.preparing)):
            enqueue(.preparationStepTimedOut)
        case (.fetch, .active(.fetching(let fetchType))):
            enqueue(.fetchTimedOut(fetchType))
        case (.retry, _):
            enqueue(.retryTimerFired)
        default:
            return
        }
    }

    // MARK: Session outputs

    private func process(_ outputs: [StrapSessionOutput]) {
        for output in outputs {
            switch output {
            case .write(let characteristic, let data):
                connection.write(data, to: characteristic)
            case .setNotify(let characteristic, let enabled):
                connection.setNotify(characteristic, enabled: enabled)
            case .authSucceeded:
                enqueue(.authSucceeded)
            case .authRejected:
                enqueue(.authRejected)
            case .authBusy:
                enqueue(.strapBusyDetected)
            case .preparationStepStarted:
                enqueue(.preparationStepStarted)
            case .sessionPrepared(let summary):
                deviceSummary = summary
                enqueue(.sessionPrepared)
            case .fetchProgressed(let fetchType):
                enqueue(.fetchProgressed(fetchType))
            case .fetchCompleted(let fetchType, let rounds):
                pendingRounds[fetchType] = rounds
                enqueue(.fetchCompleted(fetchType))
            }
        }
    }

    // MARK: Events and effects

    private func apply(_ event: SyncEvent) {
        let transition = SyncCoordinator.reduce(state, event)
        logRecorder.record(TransitionLogEntry(timestamp: now(), from: state, event: event, to: transition.nextState))
        state = transition.nextState
        for effect in transition.effects {
            execute(effect)
        }
    }

    private func execute(_ effect: SyncEffect) {
        switch effect {
        case .startScan:
            connection.startScan()
        case .stopScan:
            connection.stopScan()
        case .connect:
            connection.connect()
        case .disconnect:
            connection.disconnect()
        case .authenticate:
            authenticate()
        case .prepareSession:
            process(session.handle(.prepare(now: now(), timeZone: timeZone)))
        case .skipPreparationStep:
            process(session.handle(.skipPreparationStep))
        case .fetch(let fetchType):
            fetch(fetchType)
        case .persist(let fetchType):
            persist(fetchType)
        case .armTimer(let timer, let seconds):
            timers.schedule(timer, afterSeconds: seconds)
        case .cancelTimer(let timer):
            timers.cancel(timer)
        case .markKeyRejected:
            try? keyStore.markRejected()
        case .recordSyncCompleted:
            lastSync.save(now())
        }
    }

    private func authenticate() {
        guard let key = try? keyStore.load() else {
            enqueue(.authKeyMissing)
            return
        }
        process(session.handle(.authenticate(key: key, maximumWriteLength: maximumWriteLength, notifiable: notifiable)))
    }

    private func fetch(_ fetchType: StrapFetchType) {
        let currentNow = now()
        let watermark = try? store.watermark(for: fetchType)
        let since = WatermarkRule.fetchStart(watermark: watermark, now: currentNow)
        process(session.handle(.fetch(fetchType, since: since, now: currentNow, timeZone: timeZone)))
    }

    private func persist(_ fetchType: StrapFetchType) {
        let fetchedRounds = pendingRounds.removeValue(forKey: fetchType) ?? []
        let storedRounds = fetchedRounds.map(StoredRound.init(fetched:))
        let currentNow = now()
        var watermark = try? store.watermark(for: fetchType)
        for round in fetchedRounds {
            watermark = WatermarkRule.advanced(previous: watermark, nextSince: round.nextSince, now: currentNow)
        }
        do {
            try store.commit(rounds: storedRounds, type: fetchType, watermark: watermark)
            enqueue(.persistSucceeded(fetchType))
        } catch {
            enqueue(.persistFailed(fetchType))
        }
    }
}
