//
//  ImportCoordinator.swift
//  SideRoll — Orchestrates file import from iPhone to destination folder
//

import SwiftUI
import Combine
import ImageCaptureCore

@MainActor
final class ImportCoordinator: ObservableObject {
    @Published var isImporting = false
    @Published var progress: Double = 0
    @Published var progressText = ""
    @Published var cancelled = false
    @Published var showResult = false
    @Published var resultMessage = ""

    func start(
        files: [ICCameraFile],
        exifDates: [String: Date],
        destination: URL,
        device: ICCameraDevice,
        skipExisting: Bool,
        preserveEXIF: Bool,
        lang: AppLanguage
    ) {
        struct Pending { let file: ICCameraFile; let preferredDate: Date? }
        let pending: [Pending] = files.flatMap { parent -> [Pending] in
            let date = parent.name.flatMap { exifDates[$0] }
            return LivePhotoPairing.filesToImport(for: parent).map {
                Pending(file: $0, preferredDate: date)
            }
        }
        guard !pending.isEmpty else { return }

        let engine = ImportEngine(device: device)
        isImporting = true
        cancelled = false
        progress = 0
        progressText = L.starting(lang)

        Task {
            var downloaded = 0, skipped = 0, failed = 0
            let total = pending.count

            for (i, item) in pending.enumerated() {
                if cancelled {
                    let remaining = total - i
                    progressText = L.cancelled(lang, downloaded, remaining)
                    break
                }

                progressText = "[\(i + 1)/\(total)] \(item.file.name ?? "?")"

                do {
                    let result = try await engine.download(file: item.file, to: destination, skipExisting: skipExisting)
                    switch result {
                    case .downloaded(let url):
                        downloaded += 1
                        if preserveEXIF, let date = item.preferredDate {
                            engine.setFileDate(url, to: date)
                        }
                    case .skipped:
                        skipped += 1
                    }
                } catch {
                    failed += 1
                }

                progress = Double(i + 1) / Double(total)
            }

            if !cancelled {
                resultMessage = L.importResult(lang, downloaded, skipped, failed)
                progressText = L.importSummary(lang, downloaded, skipped, failed)
            } else {
                resultMessage = L.cancelledResult(lang, downloaded, total - downloaded - skipped - failed)
            }
            isImporting = false
            showResult = true
        }
    }
}
