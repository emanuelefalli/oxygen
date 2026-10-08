import Foundation

enum StrapConnectionEvent: Equatable, Sendable {
    case bluetoothPoweredOn
    case bluetoothPoweredOff
    case bluetoothUnauthorized
    case strapDiscovered
    case connected(maximumWriteLength: Int, notifiable: Set<StrapCharacteristic>)
    case connectionFailed
    case linkLost
    case notification(StrapCharacteristic, Data)
    case notifyStateChanged(StrapCharacteristic, enabled: Bool)
}

@MainActor protocol StrapConnecting: AnyObject {
    func startScan()
    func stopScan()
    func connect()
    func disconnect()
    func write(_ data: Data, to characteristic: StrapCharacteristic)
    func setNotify(_ characteristic: StrapCharacteristic, enabled: Bool)
}
