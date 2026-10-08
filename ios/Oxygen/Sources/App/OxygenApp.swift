import SwiftUI
import UserNotifications

@MainActor final class OxygenComposition {
    let store: RawStore
    let keyStore: StrapKeyStore
    let connection: StrapConnection
    let timerFires: AsyncStream<SyncTimer>
    let lastSync: LastSyncRecord
    let runner: SyncRunner
    let profileExpiration: Date?

    init() throws {
        let logURL = try Self.transitionLogURL()
        let container = try RawStore.makeContainer(inMemory: false)
        store = RawStore(container: container)
        keyStore = StrapKeyStore(service: StrapKeyStore.productionService)
        let logRecorder = TransitionLogRecorder(file: TransitionLogFile(url: logURL))
        let timerStream = AsyncStream.makeStream(of: SyncTimer.self)
        timerFires = timerStream.stream
        let timers = TaskSyncTimerScheduler(fired: timerStream.continuation)
        connection = StrapConnection(defaults: .standard)
        lastSync = LastSyncRecord(defaults: .standard)
        let initialState = SyncCoordinator.initialState(hasKey: (try? keyStore.load()) != nil,
                                                        keyRejected: (try? keyStore.isRejected()) ?? false)
        runner = SyncRunner(initialState: initialState, connection: connection, timers: timers, store: store,
                            keyStore: keyStore, lastSync: lastSync, logRecorder: logRecorder,
                            now: Date.init, timeZone: .current)
        profileExpiration = ProvisioningProfileReader.embeddedProfileExpirationDate(bundle: .main)
    }

    private static func transitionLogURL() throws -> URL {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let folder = support.appendingPathComponent("Oxygen", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("transition-log.txt")
    }
}

@main
struct OxygenApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private let composition: Result<OxygenComposition, Error>

    init() {
        composition = Result { try OxygenComposition() }
    }

    var body: some Scene {
        WindowGroup {
            switch composition {
            case .success(let parts):
                content(parts)
            case .failure(let error):
                Text("Oxygen could not open its data store: \(error.localizedDescription)")
                    .padding()
            }
        }
    }

    private func content(_ parts: OxygenComposition) -> some View {
        FoundationScreen(runner: parts.runner, store: parts.store, keyStore: parts.keyStore,
                         lastSync: parts.lastSync, profileExpiration: parts.profileExpiration)
            .task {
                for await event in parts.connection.events {
                    parts.runner.receive(.connection(event))
                }
            }
            .task {
                for await timer in parts.timerFires {
                    parts.runner.receive(.timerFired(timer))
                }
            }
            .task {
                await scheduleResignReminder(expiration: parts.profileExpiration)
            }
            .onChange(of: scenePhase, initial: true) { _, phase in
                guard phase == .active else { return }
                parts.runner.receive(.syncRequested)
            }
    }

    private func scheduleResignReminder(expiration: Date?) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert])
        await ResignReminder.schedule(expiration: expiration, now: Date(), center: center)
    }
}
