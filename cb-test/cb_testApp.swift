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
        // BLPeripheralManager.shared.initSetup()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // BLPeripheralManager.shared.startAdvertising()
        }
        BLCentralManager.shared.startScan()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                // .environmentObject(BLPeripheralManager.shared)
                .environmentObject(BLCentralManager.shared)
        }
    }
}
