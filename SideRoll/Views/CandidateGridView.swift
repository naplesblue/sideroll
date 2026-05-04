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
                        ForEach(candidates, id: \.name) { file in
                            CandidateTile(
                                file: file,
                                isSelected: selectedNames.contains(file.name ?? ""),
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
}

struct CandidateTile: View {
    let file: ICCameraFile
    let isSelected: Bool
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
        .task(id: file.name) {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard thumbnail == nil, let enumerator else { return }
        do {
            let img = try await ThumbnailLoader.loadThumbnail(for: file, via: enumerator)
            thumbnail = img
        } catch {
            // Keep placeholder
        }
    }

    nonisolated private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm"
        return f
    }()
}
