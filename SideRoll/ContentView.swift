//
//  ContentView.swift
//  SideRoll
//

import SwiftUI
import Combine
import ImageCaptureCore

struct ContentView: View {
    var enumerator: PhotoEnumerator?

    // Folder & time window
    @State private var targetFolder: URL?
    @State private var cameraPhotos: [CameraPhoto] = []
    @State private var buffer: TimeInterval = TimeWindowResolver.defaultBuffer
    @State private var subfolderName: String = "iPhone"

    // Candidates & selection
    @State private var selectedNames: Set<String> = []
    @State private var exifDates: [String: Date] = [:]  // fileName → EXIF DateTimeOriginal

    // Import state
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importProgressText = ""
    @State private var importCancelled = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""

    // Preferences
    @State private var onlyNewFiles = true
    @State private var autoDisconnect = true
    @State private var keepOriginalEXIF = true
    @State private var deleteAfterImport = false

    // Device observation
    @State private var deviceFileCount: Int = 0

    private var fileCountPublisher: AnyPublisher<Int, Never> {
        if let enumerator {
            return enumerator.$totalCount.eraseToAnyPublisher()
        }
        return Just(0).eraseToAnyPublisher()
    }

    private var timeWindow: TimeWindow? {
        TimeWindowResolver.resolve(photos: cameraPhotos, buffer: buffer)
    }

    /// Resolve the best date for an iPhone photo: EXIF DateTimeOriginal > creationDate
    private func resolvedDate(for file: ICCameraFile) -> Date? {
        if let name = file.name, let exifDate = exifDates[name] {
            return exifDate
        }
        return file.creationDate
    }

    private var candidates: [ICCameraFile] {
        guard let window = timeWindow, let enumerator else { return [] }
        return enumerator.availableFiles.filter { file in
            guard let date = resolvedDate(for: file) else { return false }
            return date >= window.start && date <= window.end
        }
    }

    private var selectedFiles: [ICCameraFile] {
        candidates.filter { selectedNames.contains($0.name ?? "") }
    }

    private var totalSizeMB: Double {
        let bytes = selectedFiles.reduce(0) { $0 + Int($1.fileSize) }
        return Double(bytes) / 1_048_576
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top device bar
            DeviceBar(enumerator: enumerator, deviceFileCount: deviceFileCount)

            Divider().overlay(Color("Accent", bundle: nil).opacity(0.3))

            // Main content: sidebar + grid
            HSplitView {
                SidebarView(
                    targetFolder: $targetFolder,
                    cameraPhotos: $cameraPhotos,
                    buffer: $buffer,
                    subfolderName: $subfolderName,
                    timeWindow: timeWindow,
                    onlyNewFiles: $onlyNewFiles,
                    autoDisconnect: $autoDisconnect,
                    keepOriginalEXIF: $keepOriginalEXIF,
                    deleteAfterImport: $deleteAfterImport
                )
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

                // Right: grid
                VStack(spacing: 0) {
                    GridHeaderView(
                        totalCount: candidates.count,
                        selectedCount: selectedNames.count,
                        onSelectAll: { selectedNames = Set(candidates.compactMap(\.name)) },
                        onInvertSelection: {
                            let all = Set(candidates.compactMap(\.name))
                            selectedNames = all.subtracting(selectedNames)
                        }
                    )

                    Divider()

                    CandidateGridView(
                        candidates: candidates,
                        selectedNames: $selectedNames,
                        enumerator: enumerator,
                        exifDates: exifDates
                    )
                }
            }

            Divider().overlay(Color.amber.opacity(0.3))

            // Bottom bar
            BottomBar(
                selectedCount: selectedNames.count,
                totalSizeMB: totalSizeMB,
                isImporting: isImporting,
                progress: importProgress,
                progressText: importProgressText,
                onImport: { startImport() },
                onCancel: { importCancelled = true }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 900, minHeight: 640)
        .onReceive(fileCountPublisher) { count in
            let oldCount = deviceFileCount
            deviceFileCount = count
            if oldCount == 0 && count > 0 {
                autoSelectAll()
                fetchEXIFDates()
            }
        }
        .onChange(of: cameraPhotos) { _, _ in
            autoSelectAll()
            fetchEXIFDates()
        }
        .onChange(of: buffer) { _, _ in autoSelectAll() }
        .alert("传送完成", isPresented: $showImportResult) {
            Button("完成") { }
        } message: {
            Text(importResultMessage)
        }
    }

    private func autoSelectAll() {
        selectedNames = Set(candidates.compactMap(\.name))
    }

    /// Fetch EXIF DateTimeOriginal for iPhone photos whose creationDate falls
    /// near the camera time window. Uses a generous ±24h margin for the rough
    /// filter to catch photos with drifted file-system dates.
    private func fetchEXIFDates() {
        guard let enumerator, let window = timeWindow else { return }
        // Generous rough filter: ±24 hours beyond the buffered window
        let roughStart = window.start.addingTimeInterval(-86400)
        let roughEnd = window.end.addingTimeInterval(86400)
        let roughCandidates = enumerator.availableFiles.filter { file in
            guard let date = file.creationDate else { return false }
            return date >= roughStart && date <= roughEnd
        }
        guard !roughCandidates.isEmpty else { return }
        print("[EXIF] Fetching metadata for \(roughCandidates.count) rough candidates…")

        Task {
            var resolved: [String: Date] = [:]
            for file in roughCandidates {
                guard let name = file.name else { continue }
                // Skip if already resolved
                guard exifDates[name] == nil else {
                    resolved[name] = exifDates[name]
                    continue
                }
                do {
                    let metadata = try await enumerator.requestMetadata(for: file)
                    if let exifDate = PhotoEnumerator.exifCaptureDate(from: metadata) {
                        resolved[name] = exifDate
                    } else {
                        // No EXIF date found, fall back to creationDate
                        resolved[name] = file.creationDate
                    }
                } catch {
                    // Metadata request failed, keep creationDate
                    resolved[name] = file.creationDate
                }
            }
            exifDates = resolved
            // Re-select after EXIF dates refine the candidate list
            autoSelectAll()
            print("[EXIF] Resolved \(resolved.count) dates")
        }
    }

    private func startImport() {
        guard let folder = targetFolder, let enumerator else { return }
        let destName = subfolderName.trimmingCharacters(in: .whitespaces).isEmpty ? "iPhone" : subfolderName
        let destFolder = folder.appendingPathComponent(destName, isDirectory: true)
        let filesToImport = selectedFiles
        guard !filesToImport.isEmpty else { return }

        let engine = ImportEngine(device: enumerator.device)
        isImporting = true
        importCancelled = false
        importProgress = 0
        importProgressText = "开始传送…"

        Task {
            var downloaded = 0, skipped = 0, failed = 0
            let total = filesToImport.count

            for (i, file) in filesToImport.enumerated() {
                if importCancelled {
                    let remaining = total - i
                    importProgressText = "已取消 · \(downloaded) 已传送 · \(remaining) 剩余"
                    break
                }

                importProgressText = "[\(i + 1)/\(total)] \(file.name ?? "?")"

                do {
                    let result = try await engine.download(file: file, to: destFolder)
                    switch result {
                    case .downloaded: downloaded += 1
                    case .skipped: skipped += 1
                    }
                } catch {
                    failed += 1
                }

                importProgress = Double(i + 1) / Double(total)
            }

            if !importCancelled {
                importResultMessage = "\(downloaded) 张已传送\(skipped > 0 ? "\n\(skipped) 张已跳过（重复）" : "")\(failed > 0 ? "\n\(failed) 张失败" : "")"
                importProgressText = "完成 · \(downloaded) 已传送 · \(skipped) 已跳过 · \(failed) 失败"
            } else {
                importResultMessage = "已取消\n\(downloaded) 张已传送，\(filesToImport.count - downloaded - skipped - failed) 张未处理"
            }
            isImporting = false
            showImportResult = true
        }
    }
}
