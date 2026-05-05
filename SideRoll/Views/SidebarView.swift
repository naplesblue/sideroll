//
//  SidebarView.swift
//  SideRoll — Left sidebar: folder card, buffer slider, target, preferences
//

import SwiftUI

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
                // — 相机文件夹
                sectionHeader("相机文件夹")
                folderCard

                // — 时间窗口缓冲
                sectionHeader("时间窗口缓冲")
                bufferSection

                // — 目标
                sectionHeader("目标")
                targetSection

                // — 选项
                sectionHeader("选项")
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
                            Text("\(cameraPhotos.count) NEF")
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
                    Text("选择文件夹…")
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
    }

    // MARK: - Buffer

    private var bufferSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("±\(String(format: "%.1f", buffer / 3600)) 小时")
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
                    TextField("子文件夹", text: $subfolderName)
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
                Text("未选择")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            prefToggle("只传送新文件", isOn: $onlyNewFiles)
            prefToggle("保留原 EXIF 时间", isOn: $keepOriginalEXIF)
            prefToggle("完成后退出", isOn: $autoQuit)
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
        panel.prompt = "选择"
        guard panel.runModal() == .OK, let url = panel.url else { return }
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
