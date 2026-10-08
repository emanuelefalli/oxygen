import Foundation
import Testing
@testable import Oxygen

@MainActor struct SyncRunnerTests {
    let key = StrapAuthKey.parse("00112233445566778899aabbccddeeff")!
    let now = Date(timeIntervalSince1970: 1_791_355_320)

    struct Harness {
        let runner: SyncRunner
        let connection: FakeStrapConnection
        let store: RawStoring
        let keyStore: InMemoryStrapKeyStore
        let timers: RecordingTimerScheduler
        let lastSync: LastSyncRecord
    }

    func makeHarness(deviceKey: StrapAuthKey? = nil, storedKey: StrapAuthKey?, store: RawStoring? = nil,
                     initialState: SyncState = SyncState(phase: .idle, retryUsed: false),
                     silent: Bool = false) throws -> Harness {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey ?? key, seeded: DecoderFixture.all)
        let connection = FakeStrapConnection(link: link)
        connection.isSilent = silent
        let rawStore: RawStoring
        if let store {
            rawStore = store
        } else {
            rawStore = RawStore(container: try RawStore.makeContainer(inMemory: true))
        }
        let keyStore = InMemoryStrapKeyStore(key: storedKey)
        let timers = RecordingTimerScheduler()
        let lastSync = LastSyncRecord(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let fixedNow = now
        let runner = SyncRunner(initialState: initialState, connection: connection, timers: timers, store: rawStore,
                                keyStore: keyStore, lastSync: lastSync, logRecorder: TransitionLogRecorder(file: nil),
                                now: { fixedNow }, timeZone: TimeZone(identifier: "UTC")!)
        connection.runner = runner
        return Harness(runner: runner, connection: connection, store: rawStore, keyStore: keyStore, timers: timers,
                       lastSync: lastSync)
    }

    @Test func fullSyncReachesIdleAndCommitsEveryType() throws {
        let h = try makeHarness(storedKey: key)
        h.runner.receive(.syncRequested)
        #expect(h.runner.state == SyncState(phase: .idle, retryUsed: false))
        for type in StrapFetchType.syncOrder {
            #expect(try h.store.watermark(for: type) != nil)
        }
        #expect(h.lastSync.load() == now)
        #expect(h.connection.calls.first == "startScan")
        #expect(h.connection.calls.last == "disconnect")
        #expect(h.connection.link.device.fetchAcks.allSatisfy { $0 == 0x09 })
    }

    @Test func wrongKeyEndsInKeyRejected() throws {
        let h = try makeHarness(deviceKey: StrapAuthKey.parse("ffeeddccbbaa99887766554433221100")!, storedKey: key)
        h.runner.receive(.syncRequested)
        #expect(h.runner.state.phase == .failed(.keyRejected))
        #expect(try h.keyStore.isRejected())
    }

    @Test func missingKeyEndsInKeyMissing() throws {
        let h = try makeHarness(storedKey: nil)
        h.runner.receive(.syncRequested)
        #expect(h.runner.state.phase == .failed(.keyMissing))
    }

    @Test func authTimeoutEndsInStrapBusy() throws {
        let h = try makeHarness(storedKey: key, initialState: SyncState(phase: .active(.authenticating), retryUsed: false),
                                silent: true)
        h.runner.receive(.timerFired(.session))
        #expect(h.runner.state.phase == .failed(.strapBusy))
        #expect(h.connection.calls.last == "disconnect")
    }

    @Test func persistFailureLeavesWatermarkUnchanged() throws {
        let inner = RawStore(container: try RawStore.makeContainer(inMemory: true))
        let h = try makeHarness(storedKey: key, store: FailingRawStore(wrapping: inner, failingType: .activity))
        h.runner.receive(.syncRequested)
        #expect(h.runner.state.phase == .failed(.persistFailed(.activity)))
        #expect(try h.store.watermark(for: .activity) == nil)
    }

    @Test func secondSyncAddsNoDuplicateRecords() throws {
        let h = try makeHarness(storedKey: key)
        h.runner.receive(.syncRequested)
        let roundsAfterFirst = try h.store.allRounds().count
        let recordsAfterFirst = RecordDeduplicator.merge(try h.store.allRounds().flatMap { try StrapRecordDecoder.decode($0) }).count
        h.runner.receive(.syncRequested)
        #expect(try h.store.allRounds().count == roundsAfterFirst)
        #expect(RecordDeduplicator.merge(try h.store.allRounds().flatMap { try StrapRecordDecoder.decode($0) }).count
                == recordsAfterFirst)
    }

    @Test func fetchTimerMapsToCurrentFetchType() throws {
        let h = try makeHarness(storedKey: key, initialState: SyncState(phase: .active(.fetching(.activity)), retryUsed: false),
                                silent: true)
        h.runner.receive(.timerFired(.fetch))
        #expect(h.runner.state == SyncState(phase: .waitingForRetry(.fetchTimeout(.activity)), retryUsed: true))
        #expect(h.timers.scheduled.last?.0 == .retry)
        #expect(h.timers.scheduled.last?.1 == 10)
    }

    @Test func bluetoothOffMidFetchKeepsWatermark() throws {
        let h = try makeHarness(storedKey: key, initialState: SyncState(phase: .active(.fetching(.activity)), retryUsed: false),
                                silent: true)
        h.runner.receive(.connection(.bluetoothPoweredOff))
        #expect(h.runner.state.phase == .failed(.bluetoothOff))
        #expect(try h.store.watermark(for: .activity) == nil)
    }

    @Test func transitionsAreLogged() throws {
        let h = try makeHarness(storedKey: key)
        h.runner.receive(.syncRequested)
        let lines = h.runner.transitionLogLines
        #expect(lines.first?.hasSuffix(" idle --syncRequested--> scanning") == true)
        #expect(lines.last?.hasSuffix(" persisting(heartRateVariability) --persistSucceeded(heartRateVariability)--> idle") == true)
    }
}
