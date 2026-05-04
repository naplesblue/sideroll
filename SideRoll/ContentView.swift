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

    // Candidates & selection
    @State private var selectedNames: Set<String> = []

    // Import state
    @State private var isImporting = false
    @State private var importProgress: Double = 0
    @State private var importProgressText = ""
    @State private var importCancelled = false

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

    private var candidates: [ICCameraFile] {
        guard let window = timeWindow, let enumerator else { return [] }
        return enumerator.availableFiles.filter { file in
            guard let date = file.creationDate else { return false }
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
                        enumerator: enumerator
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
            deviceFileCount = count
            if count > 0 { autoSelectAll() }
        }
        .onChange(of: cameraPhotos) { _, _ in autoSelectAll() }
        .onChange(of: buffer) { _, _ in autoSelectAll() }
    }

    private func autoSelectAll() {
        let names = Set(candidates.compactMap(\.name))
        selectedNames = names
    }

    private func startImport() {
        guard let folder = targetFolder, let enumerator else { return }
        let iphoneFolder = folder.appendingPathComponent("iPhone", isDirectory: true)
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
                    let result = try await engine.download(file: file, to: iphoneFolder)
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
                importProgressText = "完成 · \(downloaded) 已传送 · \(skipped) 已跳过 · \(failed) 失败"
            }
            isImporting = false
        }
    }
}
