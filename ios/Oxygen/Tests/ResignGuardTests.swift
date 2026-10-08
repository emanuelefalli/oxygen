import Foundation
import Testing
@testable import Oxygen

struct ResignGuardTests {
    let now = Date(timeIntervalSince1970: 1_791_355_320)
    let expiry = Date(timeIntervalSince1970: 1_791_873_720)

    func profileData(_ plistBody: String) -> Data {
        var data = Data([0x30, 0x82, 0x01])
        let plist = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict>" + plistBody + "</dict></plist>"
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0xa0]))
        return data
    }

    @Test func readsExpirationDate() {
        let data = profileData("<key>ExpirationDate</key><date>2026-10-13T06:42:00Z</date>")
        #expect(ProvisioningProfileReader.expirationDate(fromProfileData: data) == expiry)
    }

    @Test func missingPlistOrKeyGivesNil() {
        #expect(ProvisioningProfileReader.expirationDate(fromProfileData: Data([0x01, 0x02])) == nil)
        #expect(ProvisioningProfileReader.expirationDate(fromProfileData: profileData("<key>Name</key><string>x</string>")) == nil)
    }

    @Test func statusBoundaries() {
        #expect(ResignStatus.evaluate(expiration: nil, now: now) == .unknown)
        #expect(ResignStatus.evaluate(expiration: expiry, now: now) == .valid(daysRemaining: 6))
        #expect(ResignStatus.evaluate(expiration: now.addingTimeInterval(172_800), now: now) == .expiringSoon(daysRemaining: 2))
        #expect(ResignStatus.evaluate(expiration: now.addingTimeInterval(172_801), now: now) == .valid(daysRemaining: 2))
        #expect(ResignStatus.evaluate(expiration: now.addingTimeInterval(-1), now: now) == .expiringSoon(daysRemaining: 0))
    }

    @Test func reminderFiresOneDayBeforeExpiry() {
        #expect(ResignReminder.fireDate(expiration: expiry, now: now) == Date(timeIntervalSince1970: 1_791_787_320))
        #expect(ResignReminder.fireDate(expiration: now.addingTimeInterval(86_400), now: now) == nil)
    }
}
