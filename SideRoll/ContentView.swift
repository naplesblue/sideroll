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
        guard let enumerator,
              let latest = enumerator.availableFiles.last else {
            output = "iPhone not ready or no files yet. Wait for 'Device became ready (complete content catalog)' in console."
            return
        }
        let engine = ImportEngine(device: enumerator.device)
        let iphoneFolder = target.appendingPathComponent("iPhone", isDirectory: true)

        isWorking = true
        output = "Importing \(latest.name ?? "?") → \(iphoneFolder.path)…"
        let start = Date()
        Task {
            do {
                let url = try await engine.download(file: latest, to: iphoneFolder)
                let elapsed = Date().timeIntervalSince(start)
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs?[.size] as? Int) ?? 0
                output = """
                Imported in \(String(format: "%.2f", elapsed))s
                  Saved to: \(url.path)
                  Size on disk: \(size) bytes
                  Source on device: \(latest.name ?? "?") (\(latest.fileSize) bytes)
                """
            } catch {
                output = "Import failed: \(error)"
            }
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
