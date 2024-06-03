//
//  ContentView.swift
//  cb-test
//
//  Created by Hristo on 2.06.24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Button {
                BLPeripheralManager.shared.sendData("Hello from Personal (Peripheral)")
                BLCentralManager.shared.writeData("Hello from Personal (Central)")
            } label: {
                Text("Connect to Magic Keyboard")
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}

#Preview {
    ContentView()
}
