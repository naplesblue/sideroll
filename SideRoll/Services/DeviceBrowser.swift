//
//  DeviceBrowser.swift
//  SideRoll
//

import Foundation
import Combine
import ImageCaptureCore

final class DeviceBrowser: NSObject, ObservableObject {
    @Published private(set) var connectedDevice: ICCameraDevice?

    private let browser: ICDeviceBrowser

    override init() {
        self.browser = ICDeviceBrowser()
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.camera.rawValue
                | ICDeviceLocationTypeMask.local.rawValue
        )!
    }

    func start() {
        print("[DeviceBrowser] starting…")
        browser.start()
    }

    func stop() {
        browser.stop()
    }
}

extension DeviceBrowser: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didAdd device: ICDevice,
        moreComing: Bool
    ) {
        let name = device.name ?? "<unnamed>"
        print("[DeviceBrowser] Found device: \(name) (moreComing=\(moreComing))")
        guard let camera = device as? ICCameraDevice else { return }
        Task { @MainActor in
            self.connectedDevice = camera
        }
    }

    nonisolated func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didRemove device: ICDevice,
        moreGoing: Bool
    ) {
        let name = device.name ?? "<unnamed>"
        print("[DeviceBrowser] Device removed: \(name)")
        Task { @MainActor in
            // Unconditionally clear — we only support one device at a time,
            // and after USB disconnect the old object may not compare equal.
            self.connectedDevice = nil
        }
    }
}
