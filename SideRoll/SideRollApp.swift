//
//  SideRollApp.swift
//  SideRoll
//

import SwiftUI

@main
struct SideRollApp: App {
    @StateObject private var deviceBrowser = DeviceBrowser()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(deviceBrowser)
                .task {
                    deviceBrowser.start()
                }
        }
    }
}
