//
//  PhotoEnumerator.swift
//  SideRoll
//

import Foundation
import Combine
import ImageCaptureCore

final class PhotoEnumerator: NSObject, ObservableObject {
    @Published private(set) var totalCount: Int = 0

    private let device: ICCameraDevice
    private var hasScheduledReport = false
    private var hasReported = false
    private var pendingThumbnails: [ObjectIdentifier: CheckedContinuation<CGImage, Error>] = [:]

    init(device: ICCameraDevice) {
        self.device = device
        super.init()
    }

    func start() {
        device.delegate = self
        print("[PhotoEnumerator] Opening session for \(device.name ?? "<unnamed>")…")
        device.requestOpenSession()
    }

    func stop() {
        device.requestCloseSession()
    }

    @MainActor
    func requestThumbnail(for item: ICCameraItem) async throws -> CGImage {
        try await withCheckedThrowingContinuation { cont in
            let id = ObjectIdentifier(item)
            if pendingThumbnails[id] != nil {
                cont.resume(throwing: PhotoEnumeratorError.thumbnailAlreadyPending)
                return
            }
            pendingThumbnails[id] = cont
            item.requestThumbnail()
        }
    }

    enum PhotoEnumeratorError: Error {
        case thumbnailAlreadyPending
        case thumbnailNotAvailable
    }

    @MainActor
    private func scheduleReport() {
        guard !hasScheduledReport else { return }
        hasScheduledReport = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            self.reportFirstTen()
        }
    }

    @MainActor
    private func reportFirstTen() {
        guard !hasReported else { return }
        hasReported = true

        let items = device.mediaFiles ?? []
        let files = items.compactMap { $0 as? ICCameraFile }
        guard !files.isEmpty else {
            print("[PhotoEnumerator] No media files found after enumeration")
            return
        }

        totalCount = files.count

        let sorted = files.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
        print("[PhotoEnumerator] First 10 by creationDate (out of \(files.count) total):")
        let formatter = ISO8601DateFormatter()
        for f in sorted.prefix(10) {
            let name = f.name ?? "<unnamed>"
            let date = f.creationDate.map { formatter.string(from: $0) } ?? "<no date>"
            let size = f.fileSize
            let uti = f.uti ?? "<unknown>"
            print("  \(name) | \(date) | \(size) bytes | \(uti)")
        }

        // T1.3 verification: dump thumbnail of first file. Remove or relocate
        // to UI layer in Phase 4.
        if let first = sorted.first {
            Task {
                do {
                    let nsImage = try await ThumbnailLoader.loadThumbnail(for: first, via: self)
                    let url = try ThumbnailLoader.dumpJPEG(nsImage)
                    print("[ThumbnailLoader] Saved thumbnail (\(Int(nsImage.size.width))x\(Int(nsImage.size.height))) → \(url.path)")
                } catch {
                    print("[ThumbnailLoader] Failed: \(error)")
                }
            }
        }
    }
}

extension PhotoEnumerator: ICCameraDeviceDelegate {

    // MARK: ICDeviceDelegate (parent protocol)

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {
        if let error = error {
            print("[PhotoEnumerator] Session open failed: \(error.localizedDescription)")
        } else {
            print("[PhotoEnumerator] Session opened")
        }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        print("[PhotoEnumerator] Session closed (error: \(error?.localizedDescription ?? "nil"))")
    }

    nonisolated func didRemove(_ device: ICDevice) {
        print("[PhotoEnumerator] Device removed (delegate)")
    }

    nonisolated func deviceDidBecomeReady(_ device: ICDevice) {
        print("[PhotoEnumerator] Device became ready (basic)")
    }

    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        print("[PhotoEnumerator] Device became ready (complete content catalog)")
        Task { @MainActor in
            self.reportFirstTen()
        }
    }

    nonisolated func device(_ device: ICDevice, didReceiveStatusInformation status: [String: Any]) {}

    nonisolated func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        print("[PhotoEnumerator] Device error: \(error?.localizedDescription ?? "nil")")
    }

    // MARK: ICCameraDeviceDelegate

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let total = camera.mediaFiles?.count ?? 0
        print("[PhotoEnumerator] didAdd: +\(items.count) (total now: \(total))")
        Task { @MainActor in
            self.scheduleReport()
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}

    nonisolated func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveThumbnail thumbnail: CGImage?,
        for item: ICCameraItem,
        error: (any Error)?
    ) {
        let id = ObjectIdentifier(item)
        Task { @MainActor in
            guard let cont = self.pendingThumbnails.removeValue(forKey: id) else { return }
            if let error = error {
                cont.resume(throwing: error)
            } else if let thumbnail = thumbnail {
                cont.resume(returning: thumbnail)
            } else {
                cont.resume(throwing: PhotoEnumeratorError.thumbnailNotAvailable)
            }
        }
    }

    nonisolated func cameraDevice(
        _ camera: ICCameraDevice,
        didReceiveMetadata metadata: [AnyHashable: Any]?,
        for item: ICCameraItem,
        error: (any Error)?
    ) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        print("[PhotoEnumerator] Access restriction enabled — iPhone may be locked")
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        print("[PhotoEnumerator] Access restriction removed")
    }
}
