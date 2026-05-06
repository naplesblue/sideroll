//
//  SidebarView.swift
//  SideRoll — Left sidebar: folder card, buffer slider, target, preferences
//

import SwiftUI
import UniformTypeIdentifiers

struct SidebarView: View {
    @Binding var targetFolder: URL?
    @Binding var cameraPhotos: [CameraPhoto]
    @Binding var buffer: TimeInterval
    @Binding var subfolderName: String
    var timeWindow: TimeWindow?

    @Binding var onlyNewFiles: Bool
    @Binding var autoQuit: Bool
    @Binding var keepOriginalEXIF: Bool

    @State private var isScanning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // — Camera folder
                sectionHeader("Camera Folder")
                folderCard

                // — Time window buffer
                sectionHeader("Time Buffer")
                bufferSection

                // — Target
                sectionHeader("Destination")
                targetSection

                // — Options
                sectionHeader("Options")
                preferencesSection
            }
            .padding(16)
        }
    }

    // MARK: - Folder Card

    private var folderCard: some View {
        Button(action: browseFolder) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.title3)
                    .foregroundStyle(Color.amber)

                if let folder = targetFolder {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(folder.lastPathComponent)
                            .font(.callout)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if !cameraPhotos.isEmpty {
                            Text("\(cameraPhotos.count) photos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let w = timeWindow {
                                Text("\(Self.timeFmt.string(from: w.start)) → \(Self.timeFmt.string(from: w.end))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if isScanning {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                } else {
                    Text("Choose Folder…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(10)
            .background(Color.white.opacity(0.05))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                      isDir.boolValue else { return }
                DispatchQueue.main.async {
                    handleFolderDrop(url)
                }
            }
            return true
        }
    }

    // MARK: - Buffer

    private var bufferSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("±\(String(format: "%.1f", buffer / 3600)) hours")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.amber)

            Slider(value: $buffer, in: 0...43200, step: 1800)
                .tint(.amber)
                .controlSize(.small)

            if let w = timeWindow {
                Text("\(Self.timeFmt.string(from: w.start)) → \(Self.timeFmt.string(from: w.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Target

    private var targetSection: some View {
        Group {
            if let folder = targetFolder {
                HStack(spacing: 0) {
                    Text("…/\(folder.lastPathComponent)/")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    TextField("Subfolder", text: $subfolderName)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: 80)
                    Text("/")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(6)
                .background(Color.white.opacity(0.05))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            } else {
                Text("Not selected")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            prefToggle("New files only", isOn: $onlyNewFiles)
            prefToggle("Preserve EXIF dates", isOn: $keepOriginalEXIF)
            prefToggle("Quit after import", isOn: $autoQuit)
        }
    }

    @ViewBuilder
    private func prefToggle(_ label: String, isOn: Binding<Bool>, dimmed: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(dimmed && !isOn.wrappedValue ? .secondary : .primary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(.amber)
        }
    }

    // MARK: - Actions

    private func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        scanFolder(url)
    }

    private func handleFolderDrop(_ url: URL) {
        scanFolder(url)
    }

    private func scanFolder(_ url: URL) {
        targetFolder = url
        isScanning = true
        Task {
            do {
                let name = subfolderName.trimmingCharacters(in: .whitespaces).isEmpty ? "iPhone" : subfolderName
                let photos = try await CameraFolderScanner.scan(folder: url, excludingSubfolders: [name])
                cameraPhotos = photos
            } catch {
                print("[SidebarView] Scan error: \(error)")
                cameraPhotos = []
            }
            isScanning = false
        }
    }

    nonisolated private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
