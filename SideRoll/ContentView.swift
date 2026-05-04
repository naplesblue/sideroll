//
//  ContentView.swift
//  SideRoll
//

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var scanResult: String = "Click the button to scan a camera folder."
    @State private var isScanning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Scan Folder…") { pickAndScan() }
                    .disabled(isScanning)
                if isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            ScrollView {
                Text(scanResult)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .border(Color(nsColor: .separatorColor))
        }
        .padding()
        .frame(minWidth: 640, minHeight: 400)
    }

    // Temporary verification UI for T2.2. Replaced by FolderDropView in T4.2.
    private func pickAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isScanning = true
        scanResult = "Scanning \(url.path)…"
        Task {
            let start = Date()
            do {
                let photos = try await CameraFolderScanner.scan(folder: url)
                let elapsed = Date().timeIntervalSince(start)
                scanResult = format(photos: photos, source: url, elapsed: elapsed)
            } catch {
                scanResult = "Error: \(error)"
            }
            isScanning = false
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
