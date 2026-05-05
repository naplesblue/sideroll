//
//  CandidateGridView.swift
//  SideRoll — Thumbnail grid matching design spec
//

import SwiftUI
import ImageCaptureCore

struct CandidateGridView: View {
    var candidates: [ICCameraFile]
    @Binding var selectedNames: Set<String>
    var enumerator: PhotoEnumerator?
    var exifDates: [String: Date]
    var existingFiles: Set<String>
    var onlyNewFiles: Bool

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 150))]

    var body: some View {
        Group {
            if candidates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("暂无候选照片")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("选择相机文件夹并连接 iPhone")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        // Deduplicate by name (DCIM subfolders can have same-named files)
                        let unique = deduplicatedByName(candidates)
                        ForEach(unique, id: \.name) { file in
                            let alreadyImported = existingFiles.contains(file.name ?? "")
                            CandidateTile(
                                file: file,
                                isSelected: selectedNames.contains(file.name ?? ""),
                                isDimmed: onlyNewFiles && alreadyImported,
                                enumerator: enumerator,
                                exifDates: exifDates
                            ) {
                                toggleSelection(file)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggleSelection(_ file: ICCameraFile) {
        guard let name = file.name else { return }
        if selectedNames.contains(name) {
            selectedNames.remove(name)
        } else {
            selectedNames.insert(name)
        }
    }

    /// Keep only the first file for each unique name (DCIM subfolders may have duplicates)
    private func deduplicatedByName(_ files: [ICCameraFile]) -> [ICCameraFile] {
        var seen = Set<String>()
        return files.filter { file in
            guard let name = file.name, !seen.contains(name) else { return false }
            seen.insert(name)
            return true
        }
    }
}

struct CandidateTile: View {
    let file: ICCameraFile
    let isSelected: Bool
    var isDimmed: Bool = false
    var enumerator: PhotoEnumerator?
    var exifDates: [String: Date]
    let onToggle: () -> Void

    @State private var thumbnail: NSImage?

    private var fileExt: String {
        ((file.name ?? "") as NSString).pathExtension.uppercased()
    }

    private var fileNumber: String {
        let name = (file.name ?? "") as NSString
        let base = name.deletingPathExtension
        // Extract trailing digits: IMG_2501 → #2501
        if let range = base.range(of: "\\d+$", options: .regularExpression) {
            return "#\(base[range])"
        }
        return ""
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail area
            ZStack {
                // Image or placeholder
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 100, minHeight: 80)
                        .clipped()
                } else {
                    // Striped placeholder
                    Rectangle()
                        .fill(Color.white.opacity(0.04))
                        .frame(minWidth: 100, minHeight: 80)
                        .overlay {
                            Text(fileNumber)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                }

                // Checkmark — top right
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isSelected ? Color.amber : .white.opacity(0.4))
                            .shadow(radius: 2)
                            .padding(4)
                    }
                    Spacer()
                }
            }
            .aspectRatio(4/3, contentMode: .fit)
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture { onToggle() }

            // Info row: time + format
            HStack {
                let displayDate: Date? = {
                    if let name = file.name, let d = exifDates[name] { return d }
                    return file.creationDate
                }()
                if let date = displayDate {
                    Text(Self.timeFmt.string(from: date))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(fileExt)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)
            .padding(.top, 2)
        }
        .opacity(isDimmed ? 0.35 : 1.0)
        .task(id: file.name) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, let enumerator else { return }
        // Retry up to 3 times with increasing delay for PTP transient failures
        for attempt in 0..<3 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(500 * attempt))
            }
            do {
                let img = try await withThrowingTimeout(seconds: 5) {
                    try await ThumbnailLoader.loadThumbnail(for: file, via: enumerator)
                }
                thumbnail = img
                return
            } catch {
                // Retry on next iteration
            }
        }
    }

    /// Run an async operation with a timeout.
    private func withThrowingTimeout<T: Sendable>(
        seconds: Double,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    nonisolated private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
}
