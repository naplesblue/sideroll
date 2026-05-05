//
//  PhotoEnumerator.swift
//  SideRoll
//

import Foundation
import Combine
import ImageCaptureCore

final class PhotoEnumerator: NSObject, ObservableObject {
    @Published private(set) var totalCount: Int = 0
    @Published private(set) var availableFiles: [ICCameraFile] = []
    @Published private(set) var isLocked: Bool = true  // assume locked until catalog arrives

    let device: ICCameraDevice
    private var hasScheduledReport = false
    private var hasReported = false
    private var pendingThumbnails: [ObjectIdentifier: CheckedContinuation<CGImage, Error>] = [:]
    private var pendingMetadata: [ObjectIdentifier: CheckedContinuation<[AnyHashable: Any], Error>] = [:]

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
        print("[PhotoEnumerator] Closing session…")
        device.requestCloseSession()
    }

    func eject() {
        print("[PhotoEnumerator] Ejecting device…")
        device.requestEjectOrDisconnect()
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
        case metadataAlreadyPending
        case metadataNotAvailable
    }

    @MainActor
    func requestMetadata(for item: ICCameraItem) async throws -> [AnyHashable: Any] {
        try await withCheckedThrowingContinuation { cont in
            let id = ObjectIdentifier(item)
            if pendingMetadata[id] != nil {
                cont.resume(throwing: PhotoEnumeratorError.metadataAlreadyPending)
                return
            }
            pendingMetadata[id] = cont
            item.requestMetadata()
        }
    }

    /// Extract capture date from metadata dict returned by requestMetadata.
    /// Tries {Exif}.DateTimeOriginal first (photos), then {TIFF}.DateTime (videos).
    nonisolated static func exifCaptureDate(from metadata: [AnyHashable: Any]) -> Date? {
        // Photos: {Exif} → DateTimeOriginal
        if let exif = metadata["{Exif}"] as? [AnyHashable: Any],
           let dateStr = exif["DateTimeOriginal"] as? String,
           let date = exifDateFormatter.date(from: dateStr) {
            return date
        }
        // Videos (MOV/MP4): {TIFF} → DateTime
        if let tiff = metadata["{TIFF}"] as? [AnyHashable: Any],
           let dateStr = tiff["DateTime"] as? String,
           let date = exifDateFormatter.date(from: dateStr) {
            return date
        }
        return nil
    }

    nonisolated private static let exifDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }()

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

        let items = device.mediaFiles ?? []
        let files = items.compactMap { $0 as? ICCameraFile }
        guard !files.isEmpty else {
            print("[PhotoEnumerator] No media files yet — will retry after unlock")
            hasScheduledReport = false  // allow reschedule when files arrive
            return
        }

        hasReported = true
        totalCount = files.count

        let sorted = files.sorted {
            ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
        }
        availableFiles = sorted
        isLocked = false
        print("[PhotoEnumerator] Catalog ready: \(files.count) files")
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
    ) {
        let id = ObjectIdentifier(item)
        Task { @MainActor in
            guard let cont = self.pendingMetadata.removeValue(forKey: id) else { return }
            if let error = error {
                cont.resume(throwing: error)
            } else if let metadata = metadata {
                cont.resume(returning: metadata)
            } else {
                cont.resume(throwing: PhotoEnumeratorError.metadataNotAvailable)
            }
        }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didCompleteDeleteFilesWithError error: (any Error)?) {
        if let error = error {
            print("[PhotoEnumerator] Delete failed: \(error.localizedDescription)")
        } else {
            print("[PhotoEnumerator] Delete completed successfully")
        }
    }

    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        print("[PhotoEnumerator] Access restriction enabled — iPhone locked")
        Task { @MainActor in
            self.isLocked = true
        }
    }

    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {
        print("[PhotoEnumerator] Access restriction removed — iPhone unlocked")
        Task { @MainActor in
            self.isLocked = false
        }
    }
}
