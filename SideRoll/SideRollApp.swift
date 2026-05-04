//
//  SideRollApp.swift
//  SideRoll
//

import SwiftUI
import ImageCaptureCore

@main
struct SideRollApp: App {
    @StateObject private var deviceBrowser = DeviceBrowser()
    @State private var enumerator: PhotoEnumerator?

    var body: some Scene {
        WindowGroup {
            ContentView(enumerator: enumerator)
                .environmentObject(deviceBrowser)
                .task {
                    deviceBrowser.start()
                }
                .onReceive(deviceBrowser.$connectedDevice) { device in
                    if let device {
                        print("[SideRollApp] connectedDevice changed → \(device.name ?? "?"), creating new PhotoEnumerator")
                        let new = PhotoEnumerator(device: device)
                        new.start()
                        self.enumerator = new
                    } else {
                        print("[SideRollApp] connectedDevice changed → nil, stopping enumerator")
                        self.enumerator?.stop()
                        self.enumerator = nil
                    }
                }
        }
    }
}
