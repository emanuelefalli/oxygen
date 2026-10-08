// Adapted from ios/OpenCircuit/Helio/HelioConnection.swift at upstream 63e2796d323cea42d4835cf364bd0a4ebfa99682.
import CoreBluetooth
import Foundation
import ZeppKit

@MainActor final class StrapConnection: NSObject, StrapConnecting, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let peripheralIdentifierKey = "oxygen.strapPeripheralIdentifier"

    let events: AsyncStream<StrapConnectionEvent>

    private struct PendingWrite {
        let characteristic: StrapCharacteristic
        let data: Data
    }

    private static let mainServiceUUID = CBUUID(string: ZeppGATT.mainServiceUUID)
    private static let firmwareUpdateServiceUUID = CBUUID(string: ZeppGATT.firmwareUpdateServiceUUID)

    private let defaults: UserDefaults
    private let continuation: AsyncStream<StrapConnectionEvent>.Continuation
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var characteristics: [StrapCharacteristic: CBCharacteristic] = [:]
    private var writeQueue: [PendingWrite] = []
    private var pendingServiceCount = 0
    private var isScanPending = false
    private var isScanning = false
    private var isDisconnectRequested = false

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let stream = AsyncStream.makeStream(of: StrapConnectionEvent.self)
        events = stream.stream
        continuation = stream.continuation
        super.init()
    }

    // MARK: StrapConnecting

    func startScan() {
        let central = ensureCentral()
        switch central.state {
        case .poweredOn:
            findStrap(central)
        case .unknown, .resetting:
            isScanPending = true
        case .poweredOff, .unsupported:
            continuation.yield(.bluetoothPoweredOff)
        case .unauthorized:
            continuation.yield(.bluetoothUnauthorized)
        @unknown default:
            continuation.yield(.bluetoothPoweredOff)
        }
    }

    func stopScan() {
        isScanPending = false
        isScanning = false
        central?.stopScan()
    }

    func connect() {
        guard let central, let peripheral else {
            continuation.yield(.connectionFailed)
            return
        }
        isDisconnectRequested = false
        characteristics = [:]
        writeQueue = []
        pendingServiceCount = 0
        central.connect(peripheral, options: nil)
    }

    func disconnect() {
        isDisconnectRequested = true
        writeQueue = []
        guard let central, let peripheral else { return }
        central.cancelPeripheralConnection(peripheral)
    }

    func write(_ data: Data, to characteristic: StrapCharacteristic) {
        writeQueue.append(PendingWrite(characteristic: characteristic, data: data))
        flushWrites()
    }

    func setNotify(_ characteristic: StrapCharacteristic, enabled: Bool) {
        guard let peripheral, let target = characteristics[characteristic] else { return }
        peripheral.setNotifyValue(enabled, for: target)
    }

    // MARK: Finding the strap

    private func ensureCentral() -> CBCentralManager {
        if let central {
            return central
        }
        let created = CBCentralManager(delegate: self, queue: .main,
                                       options: [CBCentralManagerOptionShowPowerAlertKey: false])
        central = created
        return created
    }

    private func findStrap(_ central: CBCentralManager) {
        if let held = heldStrap(central) {
            adopt(held)
            continuation.yield(.strapDiscovered)
            return
        }
        isScanning = true
        central.scanForPeripherals(withServices: nil, options: nil)
    }

    private func heldStrap(_ central: CBCentralManager) -> CBPeripheral? {
        let held = central.retrieveConnectedPeripherals(withServices: [Self.mainServiceUUID])
        if let storedIdentifier, let known = held.first(where: { $0.identifier == storedIdentifier }) {
            return known
        }
        return held.first { ZeppDeviceModel.match(advertisedName: $0.name ?? "") == .helioStrap }
    }

    private var storedIdentifier: UUID? {
        guard let text = defaults.string(forKey: Self.peripheralIdentifierKey) else { return nil }
        return UUID(uuidString: text)
    }

    private func adopt(_ peripheral: CBPeripheral) {
        defaults.set(peripheral.identifier.uuidString, forKey: Self.peripheralIdentifierKey)
        peripheral.delegate = self
        self.peripheral = peripheral
    }

    private func centralStateChanged(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            continuation.yield(.bluetoothPoweredOn)
            guard isScanPending, let central else { return }
            isScanPending = false
            findStrap(central)
        case .poweredOff, .unsupported:
            isScanPending = false
            isScanning = false
            continuation.yield(.bluetoothPoweredOff)
        case .unauthorized:
            isScanPending = false
            isScanning = false
            continuation.yield(.bluetoothUnauthorized)
        case .unknown, .resetting:
            return
        @unknown default:
            return
        }
    }

    private func discovered(_ peripheral: CBPeripheral, name: String) {
        guard isScanning else { return }
        guard ZeppDeviceModel.match(advertisedName: name) == .helioStrap else { return }
        isScanning = false
        adopt(peripheral)
        continuation.yield(.strapDiscovered)
    }

    // MARK: Link

    private func servicesDiscovered(_ peripheral: CBPeripheral, failed: Bool) {
        guard peripheral === self.peripheral else { return }
        let services = (peripheral.services ?? []).filter { $0.uuid != Self.firmwareUpdateServiceUUID }
        guard !failed, !services.isEmpty else {
            central?.cancelPeripheralConnection(peripheral)
            return
        }
        pendingServiceCount = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    private func characteristicsDiscovered(_ peripheral: CBPeripheral, service: CBService) {
        guard peripheral === self.peripheral, service.uuid != Self.firmwareUpdateServiceUUID else { return }
        for characteristic in service.characteristics ?? [] {
            guard let known = Self.strapCharacteristic(matching: characteristic.uuid) else { continue }
            characteristics[known] = characteristic
        }
        pendingServiceCount -= 1
        guard pendingServiceCount == 0 else { return }
        continuation.yield(.connected(maximumWriteLength: peripheral.maximumWriteValueLength(for: .withoutResponse),
                                      notifiable: notifiableCharacteristics()))
    }

    private func linkDropped(_ peripheral: CBPeripheral) {
        guard peripheral === self.peripheral else { return }
        characteristics = [:]
        writeQueue = []
        pendingServiceCount = 0
        guard !isDisconnectRequested else { return }
        continuation.yield(.linkLost)
    }

    private static func strapCharacteristic(matching uuid: CBUUID) -> StrapCharacteristic? {
        StrapCharacteristic.allCases.first { CBUUID(string: $0.uuidString) == uuid }
    }

    private func knownCharacteristic(_ characteristic: CBCharacteristic) -> StrapCharacteristic? {
        characteristics.first { $0.value === characteristic }?.key
    }

    private func notifiableCharacteristics() -> Set<StrapCharacteristic> {
        var notifiable: Set<StrapCharacteristic> = []
        for (known, characteristic) in characteristics {
            let properties = characteristic.properties
            guard properties.contains(.notify) || properties.contains(.indicate) else { continue }
            notifiable.insert(known)
        }
        return notifiable
    }

    private func flushWrites() {
        guard let peripheral else { return }
        while let next = writeQueue.first {
            guard let target = characteristics[next.characteristic] else {
                writeQueue.removeFirst()
                continue
            }
            let withoutResponse = target.properties.contains(.writeWithoutResponse)
            if withoutResponse && !peripheral.canSendWriteWithoutResponse {
                return
            }
            writeQueue.removeFirst()
            peripheral.writeValue(next.data, for: target, type: withoutResponse ? .withoutResponse : .withResponse)
        }
    }

    // MARK: CBCentralManagerDelegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        MainActor.assumeIsolated {
            centralStateChanged(central.state)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any], rssi RSSI: NSNumber) {
        MainActor.assumeIsolated {
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name ?? ""
            discovered(peripheral, name: name)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            guard peripheral === self.peripheral else { return }
            continuation.yield(.connectionFailed)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        MainActor.assumeIsolated {
            linkDropped(peripheral)
        }
    }

    // MARK: CBPeripheralDelegate

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        let failed = error != nil
        MainActor.assumeIsolated {
            servicesDiscovered(peripheral, failed: failed)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        MainActor.assumeIsolated {
            characteristicsDiscovered(peripheral, service: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                                error: Error?) {
        MainActor.assumeIsolated {
            guard let known = knownCharacteristic(characteristic) else { return }
            continuation.yield(.notifyStateChanged(known, enabled: characteristic.isNotifying))
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                                error: Error?) {
        let failed = error != nil
        MainActor.assumeIsolated {
            guard !failed, let known = knownCharacteristic(characteristic), let value = characteristic.value else { return }
            continuation.yield(.notification(known, value))
        }
    }

    nonisolated func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        MainActor.assumeIsolated {
            flushWrites()
        }
    }
}
