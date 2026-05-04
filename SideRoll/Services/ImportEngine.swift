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

    func download(file: ICCameraFile, to folder: URL) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        return try await withCheckedThrowingContinuation { cont in
            let id = ObjectIdentifier(file)
            if pending[id] != nil {
                cont.resume(throwing: ImportError.alreadyPending)
                return
            }

            let saveName = file.name ?? "untitled"
            let targetURL = folder.appendingPathComponent(saveName)
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
    }

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
