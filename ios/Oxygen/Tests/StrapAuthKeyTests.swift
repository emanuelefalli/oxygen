import Foundation
import Testing
@testable import Oxygen

struct StrapAuthKeyTests {
    let expected = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff])

    @Test(arguments: [
        "00112233445566778899aabbccddeeff",
        "0x00112233445566778899AABBCCDDEEFF\n",
        "00:11:22:33:44:55:66:77:88:99:aa:bb:cc:dd:ee:ff",
        "  0011 2233 4455 6677 8899 aabb ccdd eeff  ",
    ])
    func acceptsValidSpellings(_ text: String) {
        #expect(StrapAuthKey.parse(text)?.bytes == expected)
        #expect(StrapAuthKey.parse(text)?.hexString == "00112233445566778899aabbccddeeff")
    }

    @Test(arguments: [
        "", "0x",
        "0011223344556677889 9aabbccddeef",
        "00112233445566778899aabbccddeeff0",
        "g0112233445566778899aabbccddeeff",
    ])
    func rejectsInvalidSpellings(_ text: String) {
        #expect(StrapAuthKey.parse(text) == nil)
    }

    @Test func descriptionNeverShowsTheKey() throws {
        let key = try #require(StrapAuthKey.parse("00112233445566778899aabbccddeeff"))
        #expect(!"\(key)".contains("0011"))
        #expect(!String(reflecting: key).contains("0011"))
    }
}
