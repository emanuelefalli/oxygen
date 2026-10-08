// Adapted from ios/OpenCircuit/Helio/HelioSession.swift at upstream 63e2796d323cea42d4835cf364bd0a4ebfa99682.
import Foundation
import ZeppKit

struct StrapDeviceSummary: Equatable, Sendable {
    let batteryPercent: Int?
    let firmwareVersion: String?
}

enum StrapSessionInput: Equatable, Sendable {
    case authenticate(key: StrapAuthKey, maximumWriteLength: Int, notifiable: Set<StrapCharacteristic>)
    case prepare(now: Date, timeZone: TimeZone)
    case skipPreparationStep
    case fetch(StrapFetchType, since: Date, now: Date, timeZone: TimeZone)
    case notification(StrapCharacteristic, Data)
    case notifyStateChanged(StrapCharacteristic, enabled: Bool)
}

enum StrapSessionOutput: Equatable, Sendable {
    case write(StrapCharacteristic, Data)
    case setNotify(StrapCharacteristic, enabled: Bool)
    case authSucceeded
    case authRejected
    case authBusy
    case preparationStepStarted
    case sessionPrepared(StrapDeviceSummary)
    case fetchProgressed(StrapFetchType)
    case fetchCompleted(StrapFetchType, [FetchedRound])
}

final class StrapSession {
    private enum PreparationStep: Equatable {
        case servicesList
        case deviceInfo
        case battery
        case setTime

        var endpoint: UInt16 {
            switch self {
            case .servicesList: return ZeppEndpoint.servicesList
            case .deviceInfo: return ZeppEndpoint.deviceInfo
            case .battery: return ZeppEndpoint.battery
            case .setTime: return ZeppEndpoint.time
            }
        }

        var next: PreparationStep? {
            switch self {
            case .servicesList: return .deviceInfo
            case .deviceInfo: return .battery
            case .battery: return .setTime
            case .setTime: return nil
            }
        }
    }

    private struct PreparationProgress {
        var step: PreparationStep
        let now: Date
        let timeZone: TimeZone
        var services: ZeppServicesList?
        var deviceInfo: ZeppDeviceInfo?
        var battery: ZeppBatteryStatus?

        var summary: StrapDeviceSummary {
            StrapDeviceSummary(batteryPercent: battery?.level, firmwareVersion: deviceInfo?.firmwareVersion)
        }

        func isListed(_ candidate: PreparationStep) -> Bool {
            if candidate == .servicesList {
                return true
            }
            return services?.contains(candidate.endpoint) == true
        }

        func request(for candidate: PreparationStep) -> [UInt8] {
            switch candidate {
            case .servicesList: return ZeppServicesList.request
            case .deviceInfo: return ZeppDeviceInfo.request
            case .battery: return ZeppBatteryStatus.request
            case .setTime: return ZeppTimeCommand.setTime(now, timeZone: timeZone)
            }
        }

        mutating func recordReply(_ payload: [UInt8]) {
            switch step {
            case .servicesList:
                services = ZeppServicesList.parse(payload)
            case .deviceInfo:
                guard let info = ZeppDeviceInfo.parse(payload), !info.isAmbiguous else { return }
                deviceInfo = info
            case .battery:
                battery = ZeppBatteryStatus.parse(payload)
            case .setTime:
                return
            }
        }
    }

    private struct FetchRequest {
        let fetchType: StrapFetchType
        let since: Date
        let now: Date
        let timeZone: TimeZone
    }

    private struct FetchProgress {
        let request: FetchRequest
        var machine: ZeppHistoryFetch
        var rounds: [FetchedRound]
    }

    private enum Step {
        case idle
        case subscribingForAuthentication(pending: Set<StrapCharacteristic>, chunkedWriteRequested: Bool)
        case authenticating(chunkedWriteSubscribed: Bool)
        case authenticated
        case preparing(PreparationProgress)
        case ready
        case subscribingForFetch(FetchRequest, pending: Set<StrapCharacteristic>)
        case fetching(FetchProgress)
    }

    private var step: Step = .idle
    private var link: ZeppLink?
    private var maximumWriteLength = 0

    init() {}

    func handle(_ input: StrapSessionInput) -> [StrapSessionOutput] {
        switch input {
        case .authenticate(let key, let maximumWriteLength, let notifiable):
            return authenticate(key: key, maximumWriteLength: maximumWriteLength, notifiable: notifiable)
        case .prepare(let now, let timeZone):
            return prepare(now: now, timeZone: timeZone)
        case .skipPreparationStep:
            return skipPreparationStep()
        case .fetch(let fetchType, let since, let now, let timeZone):
            return requestFetch(FetchRequest(fetchType: fetchType, since: since, now: now, timeZone: timeZone))
        case .notification(let characteristic, let data):
            return receiveNotification(characteristic, bytes: [UInt8](data))
        case .notifyStateChanged(let characteristic, let enabled):
            return notifyStateChanged(characteristic, enabled: enabled)
        }
    }

    // MARK: Authentication

    private func authenticate(key: StrapAuthKey, maximumWriteLength: Int,
                              notifiable: Set<StrapCharacteristic>) -> [StrapSessionOutput] {
        guard case .idle = step else { return [] }
        link = ZeppLink(authKey: key.zeppAuthKey, random: .system, maxWriteLength: maximumWriteLength)
        self.maximumWriteLength = maximumWriteLength

        let chunkedWriteRequested = notifiable.contains(.chunkedWrite)
        var pending: Set<StrapCharacteristic> = [.chunkedRead]
        var outputs: [StrapSessionOutput] = [.setNotify(.chunkedRead, enabled: true)]
        if chunkedWriteRequested {
            pending.insert(.chunkedWrite)
            outputs.append(.setNotify(.chunkedWrite, enabled: true))
        }
        step = .subscribingForAuthentication(pending: pending, chunkedWriteRequested: chunkedWriteRequested)
        return outputs
    }

    private func startAuthentication(chunkedWriteSubscribed: Bool) -> [StrapSessionOutput] {
        step = .authenticating(chunkedWriteSubscribed: chunkedWriteSubscribed)
        guard let output = link?.startAuthentication() else { return [] }
        return process(output)
    }

    private func authenticationSucceeded() -> [StrapSessionOutput] {
        guard case .authenticating(let chunkedWriteSubscribed) = step else { return [] }
        step = .authenticated
        guard chunkedWriteSubscribed else { return [.authSucceeded] }
        return [.setNotify(.chunkedWrite, enabled: false), .authSucceeded]
    }

    private func authenticationFailed(_ failure: ZeppAuthFailure) -> [StrapSessionOutput] {
        guard case .authenticating = step else { return [] }
        step = .idle
        link = nil
        guard failure == .wrongAuthKey else { return [.authBusy] }
        return [.authRejected]
    }

    // MARK: Subscriptions

    private func notifyStateChanged(_ characteristic: StrapCharacteristic, enabled: Bool) -> [StrapSessionOutput] {
        guard enabled else { return [] }
        switch step {
        case .subscribingForAuthentication(var pending, let chunkedWriteRequested):
            guard pending.remove(characteristic) != nil else { return [] }
            guard pending.isEmpty else {
                step = .subscribingForAuthentication(pending: pending, chunkedWriteRequested: chunkedWriteRequested)
                return []
            }
            return startAuthentication(chunkedWriteSubscribed: chunkedWriteRequested)
        case .subscribingForFetch(let request, var pending):
            guard pending.remove(characteristic) != nil else { return [] }
            guard pending.isEmpty else {
                step = .subscribingForFetch(request, pending: pending)
                return []
            }
            return startFetch(request)
        default:
            return []
        }
    }

    // MARK: Link

    private func receiveNotification(_ characteristic: StrapCharacteristic, bytes: [UInt8]) -> [StrapSessionOutput] {
        switch characteristic {
        case .chunkedRead, .chunkedWrite:
            guard let output = link?.receive(bytes) else { return [] }
            return process(output)
        case .activityControl:
            guard case .fetching(var progress) = step else { return [] }
            let actions = progress.machine.receiveControl(bytes)
            return perform(actions, progress: progress)
        case .activityData:
            guard case .fetching(var progress) = step else { return [] }
            let actions = progress.machine.receiveData(bytes)
            return [.fetchProgressed(progress.request.fetchType)] + perform(actions, progress: progress)
        default:
            return []
        }
    }

    private func process(_ output: ZeppLink.Output) -> [StrapSessionOutput] {
        var outputs = output.writes.map(Self.writeOutput)
        for event in output.events {
            outputs += handle(event)
        }
        return outputs
    }

    private func handle(_ event: ZeppLink.Event) -> [StrapSessionOutput] {
        switch event {
        case .authenticated:
            return authenticationSucceeded()
        case .authenticationFailed(let failure):
            return authenticationFailed(failure)
        case .message(let message):
            return handle(message)
        case .deviceChunkAck, .droppedChunk, .undecryptable:
            return []
        }
    }

    private func handle(_ message: ZeppMessage) -> [StrapSessionOutput] {
        if message.endpoint == ZeppEndpoint.connection {
            return handleConnectionMessage(message.payload)
        }
        guard case .preparing(var progress) = step, progress.step.endpoint == message.endpoint else { return [] }
        progress.recordReply(message.payload)
        if progress.step == .servicesList, let services = progress.services {
            link?.apply(servicesList: services)
        }
        return startFirstListedStep(from: progress.step.next, progress: progress)
    }

    private func handleConnectionMessage(_ payload: [UInt8]) -> [StrapSessionOutput] {
        switch payload.first {
        case 0x03?:
            return send(endpoint: ZeppEndpoint.connection, payload: [0x04]) ?? []
        case 0x02? where payload.count >= 3:
            let announced = Int(payload[1]) | Int(payload[2]) << 8
            guard announced >= 20 else { return [] }
            link?.setMaxWriteLength(min(announced, maximumWriteLength))
            return []
        default:
            return []
        }
    }

    private func send(endpoint: UInt16, payload: [UInt8]) -> [StrapSessionOutput]? {
        guard let writes = try? link?.send(endpoint: endpoint, payload: payload) else { return nil }
        return writes.map(Self.writeOutput)
    }

    private static func writeOutput(_ write: ZeppWrite) -> StrapSessionOutput {
        .write(write.characteristic, Data(write.bytes))
    }

    // MARK: Preparation

    private func prepare(now: Date, timeZone: TimeZone) -> [StrapSessionOutput] {
        guard case .authenticated = step else { return [] }
        let progress = PreparationProgress(step: .servicesList, now: now, timeZone: timeZone,
                                           services: nil, deviceInfo: nil, battery: nil)
        return startFirstListedStep(from: .servicesList, progress: progress)
    }

    private func skipPreparationStep() -> [StrapSessionOutput] {
        guard case .preparing(let progress) = step else { return [] }
        return startFirstListedStep(from: progress.step.next, progress: progress)
    }

    private func startFirstListedStep(from first: PreparationStep?, progress: PreparationProgress) -> [StrapSessionOutput] {
        var progress = progress
        var candidate = first
        while let current = candidate {
            candidate = current.next
            guard progress.isListed(current) else { continue }
            guard let writes = send(endpoint: current.endpoint, payload: progress.request(for: current)) else { continue }
            progress.step = current
            step = .preparing(progress)
            return [.preparationStepStarted] + writes
        }
        step = .ready
        return [.sessionPrepared(progress.summary)]
    }

    // MARK: Fetch

    private func requestFetch(_ request: FetchRequest) -> [StrapSessionOutput] {
        guard case .ready = step else { return [] }
        step = .subscribingForFetch(request, pending: [.activityControl, .activityData])
        return [.setNotify(.activityControl, enabled: true), .setNotify(.activityData, enabled: true)]
    }

    private func startFetch(_ request: FetchRequest) -> [StrapSessionOutput] {
        let configuration = ZeppHistoryFetch.Configuration(ackPolicy: .keepOnDevice, timeZone: request.timeZone)
        var machine = ZeppHistoryFetch(plan: [(type: request.fetchType.zeppFetchType, since: request.since)],
                                       now: request.now,
                                       configuration: configuration)
        let actions = machine.start()
        return perform(actions, progress: FetchProgress(request: request, machine: machine, rounds: []))
    }

    private func perform(_ actions: [ZeppHistoryFetch.Action], progress: FetchProgress) -> [StrapSessionOutput] {
        var progress = progress
        var pending = actions
        var outputs: [StrapSessionOutput] = []
        while !pending.isEmpty {
            let action = pending.removeFirst()
            switch action {
            case .sendControl(let bytes):
                outputs.append(.write(.activityControl, Data(bytes)))
            case .roundReady(let round):
                progress.rounds.append(FetchedRound(fetchType: progress.request.fetchType,
                                                    roundStart: round.start,
                                                    payload: Data(round.rawData),
                                                    receivedAt: progress.request.now,
                                                    nextSince: round.nextSince))
                pending.insert(contentsOf: progress.machine.commit(roundID: round.id, durable: false), at: 0)
            case .roundFailed, .noData:
                break
            case .finished:
                step = .ready
                return outputs + [
                    .setNotify(.activityControl, enabled: false),
                    .setNotify(.activityData, enabled: false),
                    .fetchCompleted(progress.request.fetchType, progress.rounds),
                ]
            }
        }
        step = .fetching(progress)
        return outputs
    }
}
