//
//  SidebarView.swift
//  SideRoll — Left sidebar: folder card, buffer slider, target, preferences
//

import SwiftUI
import UniformTypeIdentifiers

enum ManualWindowPreset: String, CaseIterable, Identifiable {
    case today, yesterday, last7Days, custom
    var id: String { rawValue }

    func label(_ l: AppLanguage) -> String {
        switch self {
        case .today:      return L.presetToday(l)
        case .yesterday:  return L.presetYesterday(l)
        case .last7Days:  return L.presetLast7Days(l)
        case .custom:     return L.presetCustom(l)
        }
    }

    /// Resolves the preset to a concrete TimeWindow. For `.custom`, uses the
    /// passed-in dates; returns nil if start ≥ end.
    func window(customStart: Date, customEnd: Date) -> TimeWindow? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let endOfToday = cal.date(byAdding: DateComponents(day: 1, second: -1), to: today)!
        switch self {
        case .today:
            return TimeWindow(start: today, end: endOfToday)
        case .yesterday:
            let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
            let endOfYesterday = cal.date(byAdding: DateComponents(day: 1, second: -1), to: yesterday)!
            return TimeWindow(start: yesterday, end: endOfYesterday)
        case .last7Days:
            let start = cal.date(byAdding: .day, value: -6, to: today)!
            return TimeWindow(start: start, end: endOfToday)
        case .custom:
            guard customStart < customEnd else { return nil }
            return TimeWindow(start: customStart, end: customEnd)
        }
    }
}

struct SidebarView: View {
    @Binding var targetFolder: URL?
    @Binding var cameraPhotos: [CameraPhoto]
    @Binding var buffer: TimeInterval
    @Binding var subfolderName: String
    var timeWindow: TimeWindow?

    @Binding var useManualWindow: Bool
    @Binding var manualPreset: ManualWindowPreset
    @Binding var customStart: Date
    @Binding var customEnd: Date

    @Binding var onlyNewFiles: Bool
    @Binding var autoQuit: Bool
    @Binding var keepOriginalEXIF: Bool

    @State private var isScanning = false
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.en.rawValue
    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Top group: folder + time window (primary actions)
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader(L.cameraFolder(lang))
                            folderCard
                            if targetFolder != nil {
                                targetSection
                            }
                        }
                        timeWindowSection
                    }

                    Spacer(minLength: 24)

                    // Bottom group: options (rarely-changed settings)
                    VStack(alignment: .leading, spacing: 10) {
                        sectionHeader(L.options(lang))
                        preferencesSection
                    }
                }
                .padding(16)
                .frame(minHeight: geo.size.height, alignment: .top)
            }
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
                            Text(L.photosCount(lang, cameraPhotos.count))
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
                    Text(L.chooseFolder(lang))
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

    // MARK: - Time window section (header + content)

    private var timeWindowSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: title on left, mode picker on right
            HStack(spacing: 8) {
                Text(L.timeWindow(lang))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $useManualWindow) {
                    Text(L.modeAuto(lang)).tag(false)
                    Text(L.modeManual(lang)).tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .frame(width: 110)
            }

            if useManualWindow {
                manualWindowControls
            } else {
                autoWindowControls
            }

            // Active range readout (both modes)
            if let w = timeWindow {
                Text("\(Self.timeFmt.string(from: w.start)) → \(Self.timeFmt.string(from: w.end))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var autoWindowControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Slider(value: $buffer, in: 0...43200, step: 1800)
                .tint(.amber)
                .controlSize(.small)
            Text(L.hours(lang, String(format: "%.1f", buffer / 3600)))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var manualWindowControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $manualPreset) {
                ForEach(ManualWindowPreset.allCases) { preset in
                    Text(preset.label(lang)).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .labelsHidden()

            if manualPreset == .custom {
                VStack(alignment: .leading, spacing: 4) {
                    DatePicker(L.startDate(lang), selection: $customStart)
                        .controlSize(.small)
                        .datePickerStyle(.compact)
                        .font(.caption)
                    DatePicker(L.endDate(lang), selection: $customEnd)
                        .controlSize(.small)
                        .datePickerStyle(.compact)
                        .font(.caption)
                    if customStart >= customEnd {
                        Text(L.invalidDateRange(lang))
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.top, 2)
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
                    TextField(L.subfolder(lang), text: $subfolderName)
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
                Text(L.notSelected(lang))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preferences

    private var preferencesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            prefToggle(L.newFilesOnly(lang), isOn: $onlyNewFiles)
            prefToggle(L.preserveEXIF(lang), isOn: $keepOriginalEXIF)
            prefToggle(L.quitAfterImport(lang), isOn: $autoQuit)
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
        panel.prompt = L.choose(lang)
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
