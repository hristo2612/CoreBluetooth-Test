import Foundation
import CoreBluetooth

class BluetoothManager: NSObject, CBPeripheralManagerDelegate, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let shared = BluetoothManager()
    var peripheralManager: CBPeripheralManager!
    var centralManager: CBCentralManager!
    var transferCharacteristic: CBMutableCharacteristic?
    var discoveredPeripherals: [CBPeripheral] = []
    var transferCharacteristics: [CBPeripheral: CBCharacteristic] = [:]
    var connectedCentrals: [CBCentral] = []
    var isConnecting: Bool = false // Track the connection state

    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    // Peripheral (Server) Side Methods
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            startAdvertising()
        } else {
            print("Peripheral is not powered on.")
        }
    }

    func startAdvertising() {
        let transferServiceUUID = CBUUID(string: "1234")
        transferCharacteristic = CBMutableCharacteristic(
            type: CBUUID(string: "5678"),
            properties: [.notify, .read, .writeWithoutResponse],
            value: nil,
            permissions: [.readable, .writeable]
        )

        let transferService = CBMutableService(type: transferServiceUUID, primary: true)
        transferService.characteristics = [transferCharacteristic!]
        peripheralManager.add(transferService)

        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [transferServiceUUID]
        ])
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        connectedCentrals.append(central)
        print("Central \(central.identifier) subscribed to characteristic \(characteristic.uuid).")
    }

    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if request.characteristic.uuid == transferCharacteristic?.uuid {
                if let value = request.value {
                    let message = String(data: value, encoding: .utf8) ?? "Unknown"
                    print("Received message: \(message) from central \(request.central.identifier)")
                }
            }
            peripheralManager.respond(to: request, withResult: .success)
        }
    }

    func sendData(_ data: Data) {
        for central in connectedCentrals {
            peripheralManager.updateValue(data, for: transferCharacteristic!, onSubscribedCentrals: [central])
        }
    }

    // Central (Client) Side Methods
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanning()
        } else {
            print("Central is not powered on.")
        }
    }

    func startScanning() {
        centralManager.scanForPeripherals(withServices: [CBUUID(string: "1234")], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: NSNumber(value: true)
        ])
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredPeripherals.append(peripheral)
            
            // Implement a decision mechanism to avoid race conditions
            if !isConnecting && shouldConnectToPeripheral(peripheral) {
                isConnecting = true
                centralManager.connect(peripheral, options: nil)
            }
        }
    }

    func shouldConnectToPeripheral(_ peripheral: CBPeripheral) -> Bool {
        // Custom logic to determine if this device should initiate the connection
        // For example, based on UUID comparison:
        return peripheral.identifier.uuidString < centralManager.retrieveConnectedPeripherals(withServices: []).first?.identifier.uuidString ?? ""
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([CBUUID(string: "1234")])
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let services = peripheral.services {
            for service in services {
                peripheral.discoverCharacteristics([CBUUID(string: "5678")], for: service)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                if characteristic.uuid == CBUUID(string: "5678") {
                    transferCharacteristics[peripheral] = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let value = characteristic.value {
            let message = String(data: value, encoding: .utf8) ?? "Unknown"
            print("Received message: \(message) from peripheral \(peripheral.identifier)")
        }
    }

    func sendDataToPeripheral(_ data: Data) {
        for (peripheral, characteristic) in transferCharacteristics {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        }
    }
}
