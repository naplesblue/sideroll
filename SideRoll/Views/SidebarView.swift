//
//  SidebarView.swift
//  SideRoll — Left sidebar: folder card, buffer slider, target, preferences
//

import SwiftUI

struct SidebarView: View {
    @Binding var targetFolder: URL?
    @Binding var cameraPhotos: [CameraPhoto]
    @Binding var buffer: TimeInterval
    var timeWindow: TimeWindow?

    @Binding var onlyNewFiles: Bool
    @Binding var autoDisconnect: Bool
    @Binding var keepOriginalEXIF: Bool
    @Binding var deleteAfterImport: Bool

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

                // — 偏好
                sectionHeader("偏好")
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
                HStack(spacing: 6) {
                    Image(systemName: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                    Text("…/\(folder.lastPathComponent)/iPhone/")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            } else {
                Text("未选择")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            prefToggle("只传送新文件", isOn: $onlyNewFiles)
            prefToggle("传送完成后自动断开", isOn: $autoDisconnect)
            prefToggle("保留原 EXIF 时间", isOn: $keepOriginalEXIF)
            prefToggle("完成后删除 iPhone 原文件", isOn: $deleteAfterImport, dimmed: true)
        }
    }

    @ViewBuilder
    private func prefToggle(_ label: String, isOn: Binding<Bool>, dimmed: Bool = false) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.mini)
                .tint(.amber)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(dimmed && !isOn.wrappedValue ? .secondary : .primary)
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
                let photos = try await CameraFolderScanner.scan(folder: url)
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
        f.dateFormat = "HH:mm"
        return f
    }()

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}
