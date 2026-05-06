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
    var thumbnailSize: CGFloat
    var onPreview: ((ICCameraFile) -> Void)?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: thumbnailSize, maximum: thumbnailSize + 40))]
    }

    var body: some View {
        Group {
            if candidates.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.tertiary)
                    Text("No candidates")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("Select a camera folder and connect your iPhone")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 4) {
                        // Deduplicate by name (DCIM subfolders can have same-named files)
                        let unique = deduplicatedByName(candidates)
                        // Build fallback map from ALL device files (not just candidates,
                        // since paired JPGs may have been filtered out by ProRAW dedup)
                        let pairMap = basenameMap(enumerator?.availableFiles ?? candidates)
                        ForEach(unique, id: \.name) { file in
                            let alreadyImported = existingFiles.contains(file.name ?? "")
                            CandidateTile(
                                file: file,
                                isSelected: selectedNames.contains(file.name ?? ""),
                                isDimmed: onlyNewFiles && alreadyImported,
                                thumbnailFallback: thumbnailFallbackFile(for: file, in: pairMap),
                                enumerator: enumerator,
                                exifDates: exifDates
                            ) {
                                toggleSelection(file)
                            } onPreview: {
                                onPreview?(file)
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

    /// Group files by basename for DNG→JPG/HEIC thumbnail fallback.
    private func basenameMap(_ files: [ICCameraFile]) -> [String: [ICCameraFile]] {
        var map: [String: [ICCameraFile]] = [:]
        for file in files {
            guard let name = file.name else { continue }
            let base = (name as NSString).deletingPathExtension
            map[base, default: []].append(file)
        }
        return map
    }

    /// For a DNG file, find a paired JPG/HEIC to borrow its thumbnail.
    private static let rawExts: Set<String> = ["dng"]
    private static let imageExts: Set<String> = ["jpg", "jpeg", "heic", "heif"]

    private func thumbnailFallbackFile(for file: ICCameraFile, in map: [String: [ICCameraFile]]) -> ICCameraFile? {
        guard let name = file.name else { return nil }
        let ext = (name as NSString).pathExtension.lowercased()
        guard Self.rawExts.contains(ext) else { return nil }
        let base = (name as NSString).deletingPathExtension

        // Try direct match first (IMG_1908 → IMG_1908.JPG)
        if let match = map[base]?.first(where: { sibling in
            guard let n = sibling.name, sibling !== file else { return false }
            return Self.imageExts.contains((n as NSString).pathExtension.lowercased())
        }) {
            return match
        }

        // Try E-prefix variant (IMG_1908 → IMG_E1908.JPG)
        if let uRange = base.range(of: "_", options: .backwards) {
            let eBase = base.replacingCharacters(in: uRange, with: "_E")
            if let match = map[eBase]?.first(where: { sibling in
                guard let n = sibling.name else { return false }
                return Self.imageExts.contains((n as NSString).pathExtension.lowercased())
            }) {
                return match
            }
        }

        return nil
    }
}

struct CandidateTile: View {
    let file: ICCameraFile
    let isSelected: Bool
    var isDimmed: Bool = false
    var thumbnailFallback: ICCameraFile?  // paired JPG/HEIC for DNG thumbnail
    var enumerator: PhotoEnumerator?
    var exifDates: [String: Date]
    let onToggle: () -> Void
    var onPreview: () -> Void = {}

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
                        .aspectRatio(contentMode: .fit)
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
            .background(Color.black.opacity(0.3))
            .cornerRadius(4)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onPreview() }
            .onTapGesture(count: 1) { onToggle() }

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
        // Try the file itself first, then fall back to paired image (DNG→JPG/HEIC)
        let filesToTry = [file] + (thumbnailFallback.map { [$0] } ?? [])
        for target in filesToTry {
            for attempt in 0..<3 {
                if attempt > 0 {
                    try? await Task.sleep(for: .milliseconds(500 * attempt))
                }
                do {
                    let img = try await withThrowingTimeout(seconds: 5) {
                        try await ThumbnailLoader.loadThumbnail(for: target, via: enumerator)
                    }
                    thumbnail = img
                    return
                } catch {
                    // Retry on next iteration
                }
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
