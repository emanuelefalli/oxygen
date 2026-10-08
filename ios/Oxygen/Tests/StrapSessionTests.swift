import Foundation
import Testing
@testable import Oxygen

struct StrapSessionTests {
    let deviceKey = StrapAuthKey.parse("00112233445566778899aabbccddeeff")!
    let otherKey = StrapAuthKey.parse("ffeeddccbbaa99887766554433221100")!
    let now = Date(timeIntervalSince1970: 1_791_355_320)
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let activity = DecoderFixture.all.first { $0.fetchType == .activity }!

    func authenticate(_ session: StrapSession, _ link: FakeStrapDeviceLink, key: StrapAuthKey) -> [StrapSessionOutput] {
        drive(session, link, .authenticate(key: key, maximumWriteLength: 244, notifiable: FakeStrapDeviceLink.notifiable))
    }

    func prepared(_ link: FakeStrapDeviceLink) -> StrapSession {
        let session = StrapSession()
        _ = authenticate(session, link, key: deviceKey)
        _ = drive(session, link, .prepare(now: now, timeZone: berlin))
        return session
    }

    @Test func authenticatesWithMatchingKey() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        let outputs = authenticate(StrapSession(), link, key: deviceKey)
        #expect(outputs.contains(.authSucceeded))
        #expect(outputs.contains(.setNotify(.chunkedWrite, enabled: false)))
        #expect(link.device.authenticated)
    }

    @Test func rejectsWrongKey() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        #expect(authenticate(StrapSession(), link, key: otherKey).contains(.authRejected))
    }

    @Test func secondPrepareIsIgnoredAndTimeWasSetOnce() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        let outputs = drive(prepared(link), link, .prepare(now: now, timeZone: berlin))
        #expect(outputs.isEmpty)
        #expect(link.device.timeSetCount == 1)
    }

    @Test func preparedSummaryCarriesBattery() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        let session = StrapSession()
        _ = authenticate(session, link, key: deviceKey)
        let outputs = drive(session, link, .prepare(now: now, timeZone: berlin))
        #expect(outputs.contains(.preparationStepStarted))
        #expect(outputs.last == .sessionPrepared(StrapDeviceSummary(batteryPercent: 87, firmwareVersion: nil)))
    }

    @Test func unansweredStepIsSkippedOnRequest() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [], listsDeviceInfo: true)
        let session = StrapSession()
        _ = authenticate(session, link, key: deviceKey)
        let waiting = drive(session, link, .prepare(now: now, timeZone: berlin))
        #expect(waiting.last == .preparationStepStarted)
        let resumed = drive(session, link, .skipPreparationStep)
        #expect(resumed.last == .sessionPrepared(StrapDeviceSummary(batteryPercent: 87, firmwareVersion: nil)))
    }

    @Test func fetchActivityReturnsSeededRounds() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [activity])
        let outputs = drive(prepared(link), link, .fetch(.activity, since: activity.roundStart, now: now, timeZone: berlin))
        #expect(outputs.contains(.fetchProgressed(.activity)))
        #expect(outputs.contains(.setNotify(.activityData, enabled: false)))
        guard case .fetchCompleted(.activity, let rounds)? = outputs.last else {
            Issue.record("no completion")
            return
        }
        #expect(!rounds.isEmpty)
        #expect(rounds.allSatisfy { $0.payload == Data(activity.payload) && $0.receivedAt == now })
        #expect(rounds.first?.nextSince == Date(timeIntervalSince1970: 1_790_632_980))
    }

    @Test func fetchAcksAreAlwaysKeep() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [activity])
        _ = drive(prepared(link), link, .fetch(.activity, since: activity.roundStart, now: now, timeZone: berlin))
        #expect(!link.device.fetchAcks.isEmpty)
        #expect(link.device.fetchAcks.allSatisfy { $0 == 0x09 })
    }

    @Test func fetchOfEmptyTypeCompletesWithNoRounds() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [activity])
        let outputs = drive(prepared(link), link, .fetch(.temperature, since: activity.roundStart, now: now, timeZone: berlin))
        #expect(outputs.last == .fetchCompleted(.temperature, []))
    }

    @Test func answersPing() {
        let link = FakeStrapDeviceLink(deviceKey: deviceKey, seeded: [])
        link.device.services.append((endpoint: 0x0015, flag: 0))
        let session = prepared(link)
        for notification in link.device.unsolicited(endpoint: 0x0015, [0x03]) {
            _ = drive(session, link, .notification(notification.characteristic, Data(notification.bytes)))
        }
        #expect(link.device.receivedEndpoints.last == 0x0015)
    }
}
