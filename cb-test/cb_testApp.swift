//
//  cb_testApp.swift
//  cb-test
//
//  Created by Hristo on 2.06.24.
//

import SwiftUI

@main
struct cb_testApp: App {
    init() {
        BluetoothManager.shared.startAdvertising()
        BluetoothManager.shared.startScanning()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(CBManager())
        }
    }
}
