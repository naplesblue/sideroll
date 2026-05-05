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
    @State private var exifDates: [String: Date] = [:]   // fileName → EXIF DateTimeOriginal
    @State private var exifFetched: Set<String> = []     // files where EXIF was attempted
    @State private var existingFiles: Set<String> = []   // files already in target subfolder

    // Import state
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importProgressText = ""
    @State private var importCancelled = false
    @State private var showImportResult = false
    @State private var importResultMessage = ""

    // Preferences (persisted via UserDefaults)
    @AppStorage("onlyNewFiles") private var onlyNewFiles = true
    @AppStorage("keepOriginalEXIF") private var keepOriginalEXIF = true
    @AppStorage("autoQuit") private var autoQuit = false

    // Device observation
    @State private var deviceFileCount: Int = 0
    @State private var thumbnailSize: CGFloat = 110

    private var fileCountPublisher: AnyPublisher<Int, Never> {
        if let enumerator {
            return enumerator.$totalCount.eraseToAnyPublisher()
        }
        return Just(0).eraseToAnyPublisher()
    }

    private var timeWindow: TimeWindow? {
        TimeWindowResolver.resolve(photos: cameraPhotos, buffer: buffer)
    }

    /// Resolve the best date for an iPhone photo.
    /// - EXIF fetched + date found → use EXIF date
    /// - EXIF fetched + date NOT found → nil (exclude from candidates)
    /// - EXIF not yet fetched → use creationDate (pre-EXIF rough display)
    private func resolvedDate(for file: ICCameraFile) -> Date? {
        guard let name = file.name else { return file.creationDate }
        if let exifDate = exifDates[name] {
            return exifDate
        }
        if exifFetched.contains(name) {
            // EXIF was fetched but DateTimeOriginal not found — exclude
            return nil
        }
        // Not yet fetched — fall back to creationDate
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
                    autoQuit: $autoQuit,
                    keepOriginalEXIF: $keepOriginalEXIF
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

                    // Thumbnail size slider
                    HStack(spacing: 6) {
                        Image(systemName: "photo")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Slider(value: $thumbnailSize, in: 70...220, step: 10)
                            .controlSize(.mini)
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)

                    Divider()

                    CandidateGridView(
                        candidates: candidates,
                        selectedNames: $selectedNames,
                        enumerator: enumerator,
                        exifDates: exifDates,
                        existingFiles: existingFiles,
                        onlyNewFiles: onlyNewFiles,
                        thumbnailSize: thumbnailSize
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
            scanExistingFiles()
            autoSelectAll()
            fetchEXIFDates()
        }
        .onChange(of: buffer) { _, _ in autoSelectAll() }
        .onChange(of: onlyNewFiles) { _, _ in autoSelectAll() }
        .onChange(of: subfolderName) { _, _ in scanExistingFiles() }
        .alert("传送完成", isPresented: $showImportResult) {
            Button(autoQuit ? "完成并退出" : "完成") {
                if autoQuit {
                    NSApplication.shared.terminate(nil)
                }
            }
        } message: {
            Text(importResultMessage)
        }
    }

    private func autoSelectAll() {
        if onlyNewFiles {
            // Only select candidates not already in target folder
            selectedNames = Set(candidates.compactMap(\.name).filter { !existingFiles.contains($0) })
        } else {
            selectedNames = Set(candidates.compactMap(\.name))
        }
    }

    /// Scan the target subfolder for already-imported filenames.
    private func scanExistingFiles() {
        guard let folder = targetFolder else {
            existingFiles = []
            return
        }
        let destName = subfolderName.trimmingCharacters(in: .whitespaces).isEmpty ? "iPhone" : subfolderName
        let destFolder = folder.appendingPathComponent(destName, isDirectory: true)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: destFolder, includingPropertiesForKeys: nil) else {
            existingFiles = []
            return
        }
        existingFiles = Set(contents.map { $0.lastPathComponent })
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

        let videoExts: Set<String> = ["mov", "mp4", "m4v"]
        Task {
            var dates = exifDates
            var fetched = exifFetched
            for file in roughCandidates {
                guard let name = file.name else { continue }
                // Skip if already attempted
                guard !fetched.contains(name) else { continue }
                // Videos: skip EXIF fetch, use creationDate (reliable for unedited videos)
                let ext = (name as NSString).pathExtension.lowercased()
                if videoExts.contains(ext) { continue }
                fetched.insert(name)
                do {
                    let metadata = try await enumerator.requestMetadata(for: file)
                    if let exifDate = PhotoEnumerator.exifCaptureDate(from: metadata) {
                        dates[name] = exifDate
                    } else {
                        print("[EXIF] No DateTimeOriginal for \(name)")
                    }
                } catch {
                    print("[EXIF] Metadata failed for \(name): \(error.localizedDescription)")
                }
            }
            exifDates = dates
            exifFetched = fetched
            // Re-select after EXIF dates refine the candidate list
            autoSelectAll()
            print("[EXIF] Resolved \(dates.count) dates, \(fetched.count) fetched")
        }
    }

    private func startImport() {
        guard let folder = targetFolder, let enumerator else { return }
        let destName = subfolderName.trimmingCharacters(in: .whitespaces).isEmpty ? "iPhone" : subfolderName
        let destFolder = folder.appendingPathComponent(destName, isDirectory: true)
        guard !selectedFiles.isEmpty else { return }

        // Expand each selected file to include its Live Photo .MOV sidecar
        // (when present). Each row carries the parent's EXIF date so the
        // .MOV gets the same file-system timestamp, keeping pairs together
        // in chronological views.
        let resolvedDates = exifDates
        struct Pending { let file: ICCameraFile; let preferredDate: Date? }
        let pending: [Pending] = selectedFiles.flatMap { parent -> [Pending] in
            let date = parent.name.flatMap { resolvedDates[$0] }
            return LivePhotoPairing.filesToImport(for: parent).map {
                Pending(file: $0, preferredDate: date)
            }
        }
        guard !pending.isEmpty else { return }

        // Capture option values before entering async context
        let skipExisting = onlyNewFiles
        let preserveEXIF = keepOriginalEXIF

        let engine = ImportEngine(device: enumerator.device)
        isImporting = true
        importCancelled = false
        importProgress = 0
        importProgressText = "开始传送…"

        Task {
            var downloaded = 0, skipped = 0, failed = 0
            let total = pending.count

            for (i, item) in pending.enumerated() {
                if importCancelled {
                    let remaining = total - i
                    importProgressText = "已取消 · \(downloaded) 已传送 · \(remaining) 剩余"
                    break
                }

                importProgressText = "[\(i + 1)/\(total)] \(item.file.name ?? "?")"

                do {
                    let result = try await engine.download(file: item.file, to: destFolder, skipExisting: skipExisting)
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

                importProgress = Double(i + 1) / Double(total)
            }

            if !importCancelled {
                importResultMessage = "\(downloaded) 张已传送\(skipped > 0 ? "\n\(skipped) 张已跳过（重复）" : "")\(failed > 0 ? "\n\(failed) 张失败" : "")"
                importProgressText = "完成 · \(downloaded) 已传送 · \(skipped) 已跳过 · \(failed) 失败"
            } else {
                importResultMessage = "已取消\n\(downloaded) 张已传送，\(total - downloaded - skipped - failed) 张未处理"
            }
            isImporting = false
            scanExistingFiles()
            autoSelectAll()
            showImportResult = true
        }
    }
}
