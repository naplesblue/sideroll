//
//  ImportEngine.swift
//  SideRoll
//

import Foundation
import ImageCaptureCore

@MainActor
final class ImportEngine: NSObject {
    private let device: ICCameraDevice
    private var pending: [ObjectIdentifier: PendingDownload] = [:]

    init(device: ICCameraDevice) {
        self.device = device
        super.init()
    }

    // MARK: - Single file download

    /// Result of a single file download attempt.
    enum DownloadResult {
        case downloaded(URL)
        case skipped(URL)  // file already exists at destination
    }

    /// Download one file to `folder`.
    /// - `skipExisting`: if true (default), returns `.skipped` when file already exists.
    ///   If false, overwrites existing file.
    func download(file: ICCameraFile, to folder: URL, skipExisting: Bool = true) async throws -> DownloadResult {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let saveName = file.name ?? "untitled"
        let targetURL = folder.appendingPathComponent(saveName)

        // T3.3: Idempotent — skip if file exists and skipExisting is on
        if skipExisting && FileManager.default.fileExists(atPath: targetURL.path) {
            return .skipped(targetURL)
        }

        // Remove existing file if overwriting
        if !skipExisting && FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }

        let url: URL = try await withCheckedThrowingContinuation { cont in
            let id = ObjectIdentifier(file)
            if pending[id] != nil {
                cont.resume(throwing: ImportError.alreadyPending)
                return
            }

            pending[id] = PendingDownload(continuation: cont, targetURL: targetURL)

            let options: [ICDownloadOption: Any] = [
                .downloadsDirectoryURL: folder,
                .saveAsFilename: saveName,
            ]
            device.requestDownloadFile(
                file,
                options: options,
                downloadDelegate: self,
                didDownloadSelector: #selector(didDownloadFile(_:error:options:contextInfo:)),
                contextInfo: nil
            )
        }
        return .downloaded(url)
    }

    /// Set the file's creation & modification dates to match the EXIF capture time.
    func setFileDate(_ url: URL, to date: Date) {
        do {
            try FileManager.default.setAttributes([
                .creationDate: date,
                .modificationDate: date,
            ], ofItemAtPath: url.path)
        } catch {
            print("[ImportEngine] Failed to set file date: \(error)")
        }
    }

    /// Request deletion of files from the connected iPhone.
    func deleteFiles(_ files: [ICCameraItem]) {
        guard !files.isEmpty else { return }
        device.requestDeleteFiles(files)
        print("[ImportEngine] Requested deletion of \(files.count) files from device")
    }

    // MARK: - Batch download (T3.4)

    /// Aggregated result of a batch download. Single-file failures do not
    /// interrupt the batch; they are collected in `failed`.
    struct ImportReport {
        var downloaded: [(file: ICCameraFile, url: URL)] = []
        var skipped: [(file: ICCameraFile, url: URL)] = []
        var failed: [(file: ICCameraFile, error: Error)] = []

        var totalAttempted: Int { downloaded.count + skipped.count + failed.count }
    }

    /// Download multiple files, catching per-file errors so one failure never
    /// aborts the rest of the batch (T3.4).
    func importBatch(files: [ICCameraFile], to folder: URL) async -> ImportReport {
        var report = ImportReport()
        for file in files {
            do {
                let result = try await download(file: file, to: folder)
                switch result {
                case .downloaded(let url):
                    report.downloaded.append((file: file, url: url))
                case .skipped(let url):
                    report.skipped.append((file: file, url: url))
                }
            } catch {
                report.failed.append((file: file, error: error))
            }
        }
        return report
    }

    // MARK: - Private

    private struct PendingDownload {
        let continuation: CheckedContinuation<URL, Error>
        let targetURL: URL
    }

    enum ImportError: Error, CustomStringConvertible {
        case alreadyPending

        var description: String {
            switch self {
            case .alreadyPending: return "Download already in progress for this file"
            }
        }
    }
}

extension ImportEngine: ICCameraDeviceDownloadDelegate {
    func didDownloadFile(
        _ file: ICCameraFile,
        error: (any Error)?,
        options: [String: Any] = [:],
        contextInfo: UnsafeMutableRawPointer?
    ) {
        let id = ObjectIdentifier(file)
        guard let p = pending.removeValue(forKey: id) else { return }
        if let error = error {
            p.continuation.resume(throwing: error)
        } else {
            p.continuation.resume(returning: p.targetURL)
        }
    }
}
