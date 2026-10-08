import Foundation
import Testing
@testable import Oxygen

struct ScreenTextTests {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let now = Date(timeIntervalSince1970: 1_791_367_200)
    let lastSync = Date(timeIntervalSince1970: 1_791_355_320)

    @Test func idleSameDayShowsTime() {
        let text = SyncStatusText.make(state: SyncState(phase: .idle, retryUsed: false), lastSyncCompletedAt: lastSync,
                                       now: now, timeZone: berlin)
        #expect(text == "Synced 08:42")
    }

    @Test func idleEarlierDayShowsDate() {
        let twoDaysEarlier = lastSync.addingTimeInterval(-172_800)
        let text = SyncStatusText.make(state: SyncState(phase: .idle, retryUsed: false), lastSyncCompletedAt: twoDaysEarlier,
                                       now: now, timeZone: berlin)
        #expect(text == "Synced 5 Oct 08:42")
    }

    @Test(arguments: [
        (SyncPhase.idle, "Not synced yet"),
        (.active(.fetching(.heartRateVariability)), "Fetching heart rate variability"),
        (.active(.persisting(.pai)), "Saving PAI"),
        (.waitingForRetry(.linkLost(during: .connecting)), "Connection lost, retrying in 10 s"),
        (.failed(.strapBusy), "Strap busy: turn off Bluetooth for Zepp"),
        (.failed(.keyMissing), "Paste the strap's auth key"),
        (.failed(.fetchTimeout(.temperature)), "The strap stopped sending skin temperature"),
    ])
    func statusCopy(_ phase: SyncPhase, _ text: String) {
        let made = SyncStatusText.make(state: SyncState(phase: phase, retryUsed: false), lastSyncCompletedAt: nil,
                                       now: now, timeZone: berlin)
        #expect(made == text)
    }

    @Test func summaryHasThirteenRowsInSyncOrder() {
        let records = [
            DecodedStrapRecord(fetchType: .activity, timestamp: lastSync, fields: [], receivedAt: now),
            DecodedStrapRecord(fetchType: .activity, timestamp: now, fields: [], receivedAt: now),
        ]
        let rows = RecordSummary.make(records: records)
        #expect(rows.map(\.fetchType) == StrapFetchType.syncOrder)
        #expect(rows[0] == RecordSummaryRow(fetchType: .activity, count: 2, oldest: lastSync, newest: now))
        #expect(rows[1] == RecordSummaryRow(fetchType: .manualHeartRate, count: 0, oldest: nil, newest: nil))
    }

    @Test func resignCopy() {
        #expect(ResignStatusText.line(.valid(daysRemaining: 6)) == "Re-install within 6 days")
        #expect(ResignStatusText.line(.expiringSoon(daysRemaining: 1)) == "Re-install within 1 day")
        #expect(ResignStatusText.banner(.expiringSoon(daysRemaining: 1)) == "Oxygen expires in 1 day. Re-install it from Xcode.")
        #expect(ResignStatusText.line(.expiringSoon(daysRemaining: 0)) == "Re-install today")
        #expect(ResignStatusText.banner(.valid(daysRemaining: 6)) == nil)
        #expect(ResignStatusText.line(.unknown) == "Re-sign status unknown")
    }
}
