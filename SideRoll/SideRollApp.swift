//
//  SideRollApp.swift
//  SideRoll
//

import SwiftUI
import AppKit

@main
struct SideRollApp: App {
    @StateObject private var deviceBrowser = DeviceBrowser()
    @State private var enumerator: PhotoEnumerator?

    var body: some Scene {
        WindowGroup {
            ContentView(enumerator: enumerator)
                .environmentObject(deviceBrowser)
                .onAppear {
                    // Force dark mode — Light Mode not yet adapted
                    NSApp.appearance = NSAppearance(named: .darkAqua)
                }
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
