//
//  SideRollApp.swift
//  SideRoll
//

import SwiftUI

@main
struct SideRollApp: App {
    @StateObject private var deviceBrowser = DeviceBrowser()
    @State private var enumerator: PhotoEnumerator?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceBrowser)
                .task {
                    deviceBrowser.start()
                }
                .onReceive(deviceBrowser.$connectedDevice) { device in
                    if let device {
                        let new = PhotoEnumerator(device: device)
                        new.start()
                        self.enumerator = new
                    } else {
                        self.enumerator?.stop()
                        self.enumerator = nil
                    }
                }
        }
    }
}
