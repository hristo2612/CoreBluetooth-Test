import Foundation
import CoreBluetooth
import os

struct TransferService {
    static let serviceUUID = CBUUID(string: "E20A39F4-73F5-4BC4-A12F-17D1AD07A961")
    static let characteristicUUID = CBUUID(string: "08590F7E-DB05-467E-8757-72F6FAEB13D4")
}

class BLPeripheralManager: NSObject, ObservableObject {
    static let shared = BLPeripheralManager()
    private var peripheralManager: CBPeripheralManager!
    private var transferCharacteristic: CBMutableCharacteristic?
    private var connectedCentral: CBCentral?
    private var dataToSend = Data()
    private var sendDataIndex: Int = 0
    private static var sendingEOM = false
    
    override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: [CBPeripheralManagerOptionShowPowerAlertKey: true])
    }
    
    func initSetup() {
        setupPeripheral()
    }
    
    func startAdvertising() {
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [TransferService.serviceUUID]])
    }
    
    func stopAdvertising() {
        peripheralManager.stopAdvertising()
    }
    
    func sendData(_ text: String) {
        dataToSend = text.data(using: .utf8)!
        sendDataIndex = 0
        sendDataChunks()
    }
    
    private func setupPeripheral() {
        let transferCharacteristic = CBMutableCharacteristic(type: TransferService.characteristicUUID,
                                                             properties: [.notify, .writeWithoutResponse],
                                                             value: nil,
                                                             permissions: [.readable, .writeable])
        
        let transferService = CBMutableService(type: TransferService.serviceUUID, primary: true)
        transferService.characteristics = [transferCharacteristic]
        peripheralManager.add(transferService)
        self.transferCharacteristic = transferCharacteristic
    }
    
    private func sendDataChunks() {
        guard let transferCharacteristic = transferCharacteristic else { return }
        
        if BLPeripheralManager.sendingEOM {
            let didSend = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
            if didSend {
                BLPeripheralManager.sendingEOM = false
                os_log("Sent: EOM")
            }
            return
        }
        
        if sendDataIndex >= dataToSend.count {
            return
        }
        
        var didSend = true
        while didSend {
            var amountToSend = dataToSend.count - sendDataIndex
            if let mtu = connectedCentral?.maximumUpdateValueLength {
                amountToSend = min(amountToSend, mtu)
            }
            
            let chunk = dataToSend.subdata(in: sendDataIndex..<(sendDataIndex + amountToSend))
            didSend = peripheralManager.updateValue(chunk, for: transferCharacteristic, onSubscribedCentrals: nil)
            
            if !didSend {
                return
            }
            
            let stringFromData = String(data: chunk, encoding: .utf8)
            os_log("Sent %d bytes: %s", chunk.count, String(describing: stringFromData))
            
            sendDataIndex += amountToSend
            
            if sendDataIndex >= dataToSend.count {
                BLPeripheralManager.sendingEOM = true
                let eomSent = peripheralManager.updateValue("EOM".data(using: .utf8)!, for: transferCharacteristic, onSubscribedCentrals: nil)
                if eomSent {
                    BLPeripheralManager.sendingEOM = false
                    os_log("Sent: EOM")
                }
                return
            }
        }
    }
}

extension BLPeripheralManager: CBPeripheralManagerDelegate {
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            os_log("CBManager is powered on")
            setupPeripheral()
        case .poweredOff:
            os_log("CBManager is not powered on")
            return
        case .resetting:
            os_log("CBManager is resetting")
            return
        case .unauthorized:
            if #available(iOS 13.0, *) {
                switch peripheral.authorization {
                case .denied:
                    os_log("You are not authorized to use Bluetooth")
                case .restricted:
                    os_log("Bluetooth is restricted")
                default:
                    os_log("Unexpected authorization")
                }
            }
            return
        case .unknown:
            os_log("CBManager state is unknown")
            return
        case .unsupported:
            os_log("Bluetooth is not supported on this device")
            return
        @unknown default:
            os_log("A previously unknown peripheral manager state occurred")
            return
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        os_log("Central subscribed to characteristic")
        connectedCentral = central
        sendDataChunks()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        os_log("Central unsubscribed from characteristic")
        connectedCentral = nil
    }
    
    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        sendDataChunks()
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for aRequest in requests {
            guard let requestValue = aRequest.value,
                  let stringFromData = String(data: requestValue, encoding: .utf8) else { continue }
            
            os_log("Received write request of %d bytes: %s", requestValue.count, stringFromData)
        }
    }
}
