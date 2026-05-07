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

    // Manual time window (F1)
    @AppStorage("useManualWindow") private var useManualWindow = false
    @State private var manualPreset: ManualWindowPreset = .today
    @State private var customStart: Date = Calendar.current.startOfDay(for: Date())
    @State private var customEnd: Date = Calendar.current.date(
        byAdding: DateComponents(day: 1, second: -1),
        to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()

    // Candidates & selection
    @State private var selectedNames: Set<String> = []
    @State private var exifDates: [String: Date] = [:]
    @State private var exifFetched: Set<String> = []
    @State private var existingFiles: Set<String> = []

    // Import
    @StateObject private var importer = ImportCoordinator()

    // Preferences (persisted via UserDefaults)
    @AppStorage("onlyNewFiles") private var onlyNewFiles = true
    @AppStorage("keepOriginalEXIF") private var keepOriginalEXIF = true
    @AppStorage("autoQuit") private var autoQuit = false
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.en.rawValue
    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    // Device observation
    @State private var deviceFileCount: Int = 0
    @State private var thumbnailSize: CGFloat = 110

    // Preview
    @State private var previewImage: NSImage?
    @State private var previewLoading = false
    @State private var previewEngine: ImportEngine?

    // MARK: - Computed properties

    private var fileCountPublisher: AnyPublisher<Int, Never> {
        if let enumerator {
            return enumerator.$totalCount.eraseToAnyPublisher()
        }
        return Just(0).eraseToAnyPublisher()
    }

    private var timeWindow: TimeWindow? {
        if useManualWindow {
            return manualPreset.window(customStart: customStart, customEnd: customEnd)
        }
        return TimeWindowResolver.resolve(photos: cameraPhotos, buffer: buffer)
    }

    private var candidates: [ICCameraFile] {
        guard let window = timeWindow, let enumerator else { return [] }
        return CandidateFilter.filter(
            files: enumerator.availableFiles,
            window: window,
            exifDates: exifDates,
            exifFetched: exifFetched
        )
    }

    private var selectedFiles: [ICCameraFile] {
        candidates.filter { selectedNames.contains($0.name ?? "") }
    }

    private var totalSizeMB: Double {
        let bytes = selectedFiles.reduce(0) { $0 + Int($1.fileSize) }
        return Double(bytes) / 1_048_576
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            DeviceBar(enumerator: enumerator, deviceFileCount: deviceFileCount)

            Divider().overlay(Color.amber.opacity(0.3))

            HSplitView {
                SidebarView(
                    targetFolder: $targetFolder,
                    cameraPhotos: $cameraPhotos,
                    buffer: $buffer,
                    subfolderName: $subfolderName,
                    timeWindow: timeWindow,
                    useManualWindow: $useManualWindow,
                    manualPreset: $manualPreset,
                    customStart: $customStart,
                    customEnd: $customEnd,
                    onlyNewFiles: $onlyNewFiles,
                    autoQuit: $autoQuit,
                    keepOriginalEXIF: $keepOriginalEXIF
                )
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)

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
                        thumbnailSize: thumbnailSize,
                        onPreview: { file in previewFile(file) }
                    )
                }
            }

            Divider().overlay(Color.amber.opacity(0.3))

            BottomBar(
                selectedCount: selectedNames.count,
                totalSizeMB: totalSizeMB,
                isImporting: importer.isImporting,
                progress: importer.progress,
                progressText: importer.progressText,
                onImport: { startImport() },
                onCancel: { importer.cancelled = true }
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if previewImage != nil || previewLoading {
                PreviewOverlay(
                    image: previewImage,
                    isLoading: previewLoading,
                    onDismiss: { dismissPreview() }
                )
            }
        }
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
        .onChange(of: useManualWindow) { _, _ in autoSelectAll() }
        .onChange(of: manualPreset) { _, _ in autoSelectAll() }
        .onChange(of: customStart) { _, _ in autoSelectAll() }
        .onChange(of: customEnd) { _, _ in autoSelectAll() }
        .alert(L.importComplete(lang), isPresented: $importer.showResult) {
            Button(autoQuit ? L.doneQuit(lang) : L.done(lang)) {
                if autoQuit {
                    NSApplication.shared.terminate(nil)
                }
            }
        } message: {
            Text(importer.resultMessage)
        }
        .onChange(of: importer.showResult) { _, done in
            if done {
                scanExistingFiles()
                autoSelectAll()
            }
        }
    }

    // MARK: - Actions

    private func dismissPreview() {
        previewImage = nil
        previewLoading = false
    }

    private func autoSelectAll() {
        if onlyNewFiles {
            selectedNames = Set(candidates.compactMap(\.name).filter { !existingFiles.contains($0) })
        } else {
            selectedNames = Set(candidates.compactMap(\.name))
        }
    }

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

    private func previewFile(_ file: ICCameraFile) {
        guard let enumerator, !previewLoading else { return }
        previewLoading = true
        previewImage = nil

        let engine = ImportEngine(device: enumerator.device)
        previewEngine = engine
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SideRollPreview", isDirectory: true)

        Task {
            do {
                let result = try await engine.download(file: file, to: tempDir, skipExisting: false)
                if case .downloaded(let url) = result {
                    if let image = NSImage(contentsOf: url) {
                        previewImage = image
                    }
                    try? FileManager.default.removeItem(at: url)
                }
            } catch {
                print("[Preview] Failed: \(error.localizedDescription)")
            }
            previewEngine = nil
            if previewImage == nil {
                previewLoading = false
            }
        }
    }

    private func fetchEXIFDates() {
        guard let enumerator, let window = timeWindow else { return }
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
                guard !fetched.contains(name) else { continue }
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
            autoSelectAll()
            print("[EXIF] Resolved \(dates.count) dates, \(fetched.count) fetched")
        }
    }

    private func startImport() {
        guard let folder = targetFolder, let enumerator else { return }
        let destName = subfolderName.trimmingCharacters(in: .whitespaces).isEmpty ? "iPhone" : subfolderName
        let destFolder = folder.appendingPathComponent(destName, isDirectory: true)
        guard !selectedFiles.isEmpty else { return }

        importer.start(
            files: selectedFiles,
            exifDates: exifDates,
            destination: destFolder,
            device: enumerator.device,
            skipExisting: onlyNewFiles,
            preserveEXIF: keepOriginalEXIF,
            lang: lang
        )
    }
}
