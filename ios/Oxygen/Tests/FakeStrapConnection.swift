import Foundation
import ZeppKit
@testable import Oxygen

@MainActor final class FakeStrapConnection: StrapConnecting {
    weak var runner: SyncRunner?
    let link: FakeStrapDeviceLink
    var isSilent = false
    private(set) var calls: [String] = []

    init(link: FakeStrapDeviceLink) {
        self.link = link
    }

    func startScan() {
        calls.append("startScan")
        send(.strapDiscovered)
    }

    func stopScan() {
        calls.append("stopScan")
    }

    func connect() {
        calls.append("connect")
        send(.connected(maximumWriteLength: 244, notifiable: FakeStrapDeviceLink.notifiable))
    }

    func disconnect() {
        calls.append("disconnect")
    }

    func write(_ data: Data, to characteristic: StrapCharacteristic) {
        calls.append("write")
        guard !isSilent else { return }
        for notification in link.device.phoneWrote(ZeppWrite(characteristic, [UInt8](data))) {
            send(.notification(notification.characteristic, Data(notification.bytes)))
        }
    }

    func setNotify(_ characteristic: StrapCharacteristic, enabled: Bool) {
        calls.append("setNotify")
        send(.notifyStateChanged(characteristic, enabled: enabled))
    }

    private func send(_ event: StrapConnectionEvent) {
        guard !isSilent else { return }
        runner?.receive(.connection(event))
    }
}
