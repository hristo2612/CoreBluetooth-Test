import Foundation
import CoreBluetooth
import os

class BLCentralManager: NSObject, ObservableObject {
    static let shared = BLCentralManager()
    private var centralManager: CBCentralManager!
    private var discoveredPeripheral: CBPeripheral?
    private var transferCharacteristic: CBCharacteristic?
    private var writeIterationsComplete = 0
    private var connectionIterationsComplete = 0
    private let defaultIterations = 1000
    private var data = Data()

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }

    func startScan() {
        retrievePeripheral()
    }

    func stopScan() {
        centralManager.stopScan()
        os_log("Scanning stopped")
        data.removeAll(keepingCapacity: false)
    }

    func writeData(_ text: String) {
        data = text.data(using: .utf8)!
        writeIterationsComplete = 0
        sendWriteData()
    }

    private func retrievePeripheral() {
        let connectedPeripherals: [CBPeripheral] = centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID])
        os_log("Found connected Peripherals with transfer service: %@", connectedPeripherals)
        if let connectedPeripheral = connectedPeripherals.last {
            os_log("Connecting to peripheral %@", connectedPeripheral)
            discoveredPeripheral = connectedPeripheral
            centralManager.connect(connectedPeripheral, options: nil)
        } else {
            centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    private func cleanup() {
        guard let discoveredPeripheral = discoveredPeripheral, discoveredPeripheral.state == .connected else { return }
        for service in (discoveredPeripheral.services ?? []) {
            for characteristic in (service.characteristics ?? []) where characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
                discoveredPeripheral.setNotifyValue(false, for: characteristic)
            }
        }
        centralManager.cancelPeripheralConnection(discoveredPeripheral)
    }

    private func sendWriteData() {
        guard let discoveredPeripheral = discoveredPeripheral, let transferCharacteristic = transferCharacteristic else { return }
        while writeIterationsComplete < defaultIterations && discoveredPeripheral.canSendWriteWithoutResponse {
            let mtu = discoveredPeripheral.maximumWriteValueLength(for: .withoutResponse)
            let bytesToCopy = min(mtu, data.count)
            var rawPacket = [UInt8](repeating: 0, count: bytesToCopy)
            data.copyBytes(to: &rawPacket, count: bytesToCopy)
            let packetData = Data(bytes: rawPacket, count: bytesToCopy)
            let stringFromData = String(data: packetData, encoding: .utf8)
            os_log("Writing %d bytes: %s", bytesToCopy, String(describing: stringFromData))
            discoveredPeripheral.writeValue(packetData, for: transferCharacteristic, type: .withoutResponse)
            writeIterationsComplete += 1
        }
        if writeIterationsComplete == defaultIterations {
            discoveredPeripheral.setNotifyValue(false, for: transferCharacteristic)
        }
    }
}

extension BLCentralManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            os_log("CBManager is powered on")
            retrievePeripheral()
        case .poweredOff:
            os_log("CBManager is not powered on")
        case .resetting:
            os_log("CBManager is resetting")
        case .unauthorized:
            if #available(iOS 13.0, *) {
                switch central.authorization {
                case .denied:
                    os_log("You are not authorized to use Bluetooth")
                case .restricted:
                    os_log("Bluetooth is restricted")
                default:
                    os_log("Unexpected authorization")
                }
            }
        case .unknown:
            os_log("CBManager state is unknown")
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
        @unknown default:
            os_log("A previously unknown central manager state occurred")
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard RSSI.intValue >= -50 else {
            os_log("Discovered peripheral not in expected range, at %d", RSSI.intValue)
            return
        }
        os_log("Discovered %s at %d", String(describing: peripheral.name), RSSI.intValue)
        if discoveredPeripheral != peripheral {
            discoveredPeripheral = peripheral
            os_log("Connecting to peripheral %@", peripheral)
            centralManager.connect(peripheral, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        os_log("Failed to connect to %@. %s", peripheral, String(describing: error))
        cleanup()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        os_log("Peripheral Connected")
        centralManager.stopScan()
        os_log("Scanning stopped")
        connectionIterationsComplete += 1
        writeIterationsComplete = 0
        data.removeAll(keepingCapacity: false)
        peripheral.delegate = self
        peripheral.discoverServices([TransferService.serviceUUID])
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        os_log("Peripheral Disconnected")
        discoveredPeripheral = nil
        if connectionIterationsComplete < defaultIterations {
            retrievePeripheral()
        } else {
            os_log("Connection iterations completed")
        }
    }
}

extension BLCentralManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
        for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
            os_log("Transfer service is invalidated - rediscover services")
            peripheral.discoverServices([TransferService.serviceUUID])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            os_log("Error discovering services: %s", error.localizedDescription)
            cleanup()
            return
        }
        guard let peripheralServices = peripheral.services else { return }
        for service in peripheralServices {
            peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            os_log("Error discovering characteristics: %s", error.localizedDescription)
            cleanup()
            return
        }
        guard let serviceCharacteristics = service.characteristics else { return }
        for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.characteristicUUID {
            transferCharacteristic = characteristic
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Error updating value for characteristic: %s", error.localizedDescription)
            cleanup()
            return
        }
        guard let characteristicData = characteristic.value, let stringFromData = String(data: characteristicData, encoding: .utf8) else { return }
        os_log("Received %d bytes: %s", characteristicData.count, stringFromData)
        if stringFromData == "EOM" {
            // Handle end of message if needed
        } else {
            data.append(characteristicData)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            os_log("Error changing notification state: %s", error.localizedDescription)
            return
        }
        guard characteristic.uuid == TransferService.characteristicUUID else { return }
        if characteristic.isNotifying {
            os_log("Notification began on %@", characteristic)
        } else {
            os_log("Notification stopped on %@. Disconnecting", characteristic)
            cleanup()
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        os_log("Peripheral is ready, send data")
        sendWriteData()
    }
}
