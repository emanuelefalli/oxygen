import Foundation
import ZeppKit
@testable import Oxygen

final class FakeStrapDeviceLink {
    static let notifiable: Set<StrapCharacteristic> = [.chunkedRead, .chunkedWrite, .activityControl, .activityData]

    let device: FakeZeppDevice

    init(deviceKey: StrapAuthKey, seeded fixtures: [DecoderFixture], listsDeviceInfo: Bool = false) {
        device = FakeZeppDevice(authKey: [UInt8](deviceKey.bytes),
                                privateKey: Array(UInt8(0x81)...UInt8(0x98)),
                                random: Array(UInt8(0xf0)...UInt8(0xff)),
                                writeLength: 244)
        let utc = TimeZone(identifier: "UTC")!
        for fixture in fixtures {
            device.fetchData[fixture.fetchType.zeppFetchType] = (start: ZeppFetchTimestamp.encode(fixture.roundStart, timeZone: utc),
                                                                 data: fixture.payload)
        }
        if !listsDeviceInfo {
            device.services.removeAll { $0.endpoint == ZeppEndpoint.deviceInfo }
        }
    }
}

func drive(_ session: StrapSession, _ link: FakeStrapDeviceLink, _ input: StrapSessionInput) -> [StrapSessionOutput] {
    var pending = session.handle(input)
    var observed: [StrapSessionOutput] = []
    while !pending.isEmpty {
        let output = pending.removeFirst()
        switch output {
        case .write(let characteristic, let data):
            for notification in link.device.phoneWrote(ZeppWrite(characteristic, [UInt8](data))) {
                pending += session.handle(.notification(notification.characteristic, Data(notification.bytes)))
            }
        case .setNotify(let characteristic, let enabled):
            observed.append(output)
            pending += session.handle(.notifyStateChanged(characteristic, enabled: enabled))
        default:
            observed.append(output)
        }
    }
    return observed
}
