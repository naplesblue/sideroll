//
//  ContentView.swift
//  SideRoll
//

import SwiftUI
import AppKit
import ImageCaptureCore

struct ContentView: View {
    var enumerator: PhotoEnumerator?

    @State private var output: String = "1. Click Scan Folder… to pick a target folder.\n2. Plug in iPhone (wait for ready in console).\n3. Click Import Latest iPhone Photo to copy one to <target>/iPhone/."
    @State private var targetFolder: URL?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Scan Folder…") { pickFolderAndScan() }
                    .disabled(isWorking)
                Button("Import Latest iPhone Photo") { importLatest() }
                    .disabled(isWorking || targetFolder == nil)
                if isWorking {
                    ProgressView().controlSize(.small)
                }
            }
            if let folder = targetFolder {
                Text("Target: \(folder.path)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))
        }
        .padding()
        .frame(minWidth: 720, minHeight: 480)
    }

    // Temporary verification UI for Phase 2/3. Replaced by FolderDropView and
    // candidate grid in Phase 4.
    private func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        targetFolder = url
        isWorking = true
        output = "Scanning \(url.path)…"
        Task {
            let start = Date()
            do {
                let photos = try await CameraFolderScanner.scan(folder: url)
                let elapsed = Date().timeIntervalSince(start)
                output = format(photos: photos, source: url, elapsed: elapsed)
            } catch {
                output = "Scan error: \(error)"
            }
            isWorking = false
        }
    }

    private func importLatest() {
        guard let target = targetFolder else {
            output = "Pick a target folder first."
            return
        }
        guard let enumerator else {
            output = "iPhone not ready. Wait for 'Device became ready (complete content catalog)' in console."
            return
        }
        let all = enumerator.availableFiles
        // Find latest IMAGE (skip standalone videos when picking "latest"); if
        // it is a Live Photo we'll also pull the .MOV companion.
        guard let latestImage = all.reversed().first(where: { f in
            let ext = ((f.name ?? "") as NSString).pathExtension.lowercased()
            return LivePhotoPairing.imageExtensions.contains(ext)
        }) else {
            output = "No image files found in iPhone catalog."
            return
        }
        let toImport = LivePhotoPairing.filesToImport(for: latestImage, in: all)
        let engine = ImportEngine(device: enumerator.device)
        let iphoneFolder = target.appendingPathComponent("iPhone", isDirectory: true)

        isWorking = true
        let names = toImport.compactMap { $0.name }.joined(separator: " + ")
        output = "Importing \(names) → \(iphoneFolder.path)…"
        let start = Date()
        Task {
            let report = await engine.importBatch(files: toImport, to: iphoneFolder)
            let elapsed = Date().timeIntervalSince(start)

            var lines: [String] = []
            for (file, url) in report.downloaded {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int) ?? 0
                lines.append("  ✅ \(file.name ?? "?") → \(url.lastPathComponent) (\(size) bytes, source \(file.fileSize))")
            }
            for (file, url) in report.skipped {
                lines.append("  ⏭ \(file.name ?? "?") — already exists at \(url.lastPathComponent)")
            }
            for (file, error) in report.failed {
                lines.append("  ❌ \(file.name ?? "?") — \(error.localizedDescription)")
            }

            let pairing = toImport.count > 1 ? " (Live Photo pair)" : ""
            let allPairs = LivePhotoPairing.allPairs(in: all)

            // Diagnostic: extension breakdown
            var extCounts: [String: Int] = [:]
            for f in all {
                let ext = ((f.name ?? "") as NSString).pathExtension.lowercased()
                extCounts[ext.isEmpty ? "(no ext)" : ext, default: 0] += 1
            }
            let extReport = extCounts
                .sorted { $0.value > $1.value }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")

            let summary = "Result: \(report.downloaded.count) downloaded, \(report.skipped.count) skipped, \(report.failed.count) failed — \(String(format: "%.2f", elapsed))s\(pairing)"
            let folder = "  Folder: \(iphoneFolder.path)"
            let stats = "Catalog stats: \(allPairs.count) Live Photo pair(s) detected across \(all.count) total iPhone items.\nBy extension: \(extReport)"
            output = summary + "\n" + lines.joined(separator: "\n") + "\n" + folder + "\n\n" + stats
            isWorking = false
        }
    }

    private func format(photos: [CameraPhoto], source: URL, elapsed: TimeInterval) -> String {
        guard !photos.isEmpty else {
            return "No photos with EXIF DateTimeOriginal found in \(source.path)."
        }
        let sorted = photos.sorted { $0.captureDate < $1.captureDate }
        let earliest = sorted.first!.captureDate
        let latest = sorted.last!.captureDate
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current

        var lines: [String] = []
        lines.append("Folder: \(source.path)")
        lines.append("Photos: \(photos.count)")
        lines.append("Range:  \(formatter.string(from: earliest)) → \(formatter.string(from: latest))")
        lines.append("Time:   \(String(format: "%.2f", elapsed))s")
        lines.append("")
        lines.append("First 10 by captureDate:")
        for p in sorted.prefix(10) {
            lines.append("  \(formatter.string(from: p.captureDate))  \(p.url.lastPathComponent)")
        }
        return lines.joined(separator: "\n")
    }
}

#Preview {
    ContentView()
}
