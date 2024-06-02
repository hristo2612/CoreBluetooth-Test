import Foundation
import CoreBluetooth

class CBManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    var cbCentralManager: CBCentralManager!
    let centralManagerQueue = DispatchQueue(label: "com.icidev.centralManagerQueue", attributes: .concurrent)
    
    override init() {
        super.init()
        self.cbCentralManager = CBCentralManager(delegate: self, queue: centralManagerQueue)
    }
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("Bluetooth is powered on")
            // Start scanning for peripherals
            cbCentralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        case .poweredOff:
            print("Bluetooth is powered off")
        case .resetting:
            print("Bluetooth is resetting")
        case .unauthorized:
            print("Bluetooth is unauthorized")
        case .unsupported:
            print("Bluetooth is unsupported")
        case .unknown:
            print("Bluetooth state is unknown")
        @unknown default:
            print("Unknown Bluetooth state")
        }
    }
    
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Filter for desired devices based on their names
        if let peripheralName = peripheral.name {
            print(peripheralName)
            if peripheralName.contains("Magic Mouse") {
                cbCentralManager.connect(peripheral)
            }
        }
    }
}
