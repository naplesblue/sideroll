//
//  LivePhotoPairing.swift
//  SideRoll
//

import Foundation
import ImageCaptureCore

enum LivePhotoPairing {
    nonisolated static let imageExtensions: Set<String> = ["heic", "heif", "jpg", "jpeg"]
    nonisolated static let videoExtensions: Set<String> = ["mov", "mp4"]

    /// Returns the .MOV/.MP4 companion of `file` in `all`, when `file` is an
    /// image whose basename matches a video file in the same set. iPhone
    /// reports Live Photos as two separate files (e.g. `IMG_0001.HEIC` +
    /// `IMG_0001.MOV`) sharing a basename; we match by basename + extension
    /// since the UTI from PTP is the generic `public.image` for everything.
    nonisolated static func videoCompanion(
        of file: ICCameraFile,
        in all: [ICCameraFile]
    ) -> ICCameraFile? {
        guard let name = file.name, isImage(name: name) else { return nil }
        let basename = (name as NSString).deletingPathExtension
        return all.first { other in
            guard other !== file,
                  let otherName = other.name,
                  isVideo(name: otherName) else { return false }
            return (otherName as NSString).deletingPathExtension == basename
        }
    }

    /// Files to download when the user selects `file`. For an image with a
    /// matching video → returns [image, video]. For anything else → [file].
    nonisolated static func filesToImport(
        for file: ICCameraFile,
        in all: [ICCameraFile]
    ) -> [ICCameraFile] {
        if let companion = videoCompanion(of: file, in: all) {
            return [file, companion]
        }
        return [file]
    }

    /// All Live Photo (image + video) pairs in the catalog. O(N) via basename
    /// grouping. Useful for diagnostics and bulk-import planning.
    nonisolated static func allPairs(
        in all: [ICCameraFile]
    ) -> [(image: ICCameraFile, video: ICCameraFile)] {
        var byBasename: [String: (image: ICCameraFile?, video: ICCameraFile?)] = [:]
        for f in all {
            guard let name = f.name else { continue }
            let base = (name as NSString).deletingPathExtension
            var entry = byBasename[base] ?? (image: nil, video: nil)
            if isImage(name: name) {
                entry.image = f
            } else if isVideo(name: name) {
                entry.video = f
            }
            byBasename[base] = entry
        }
        return byBasename.values.compactMap { entry in
            guard let img = entry.image, let vid = entry.video else { return nil }
            return (image: img, video: vid)
        }
    }

    nonisolated private static func isImage(name: String) -> Bool {
        imageExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    nonisolated private static func isVideo(name: String) -> Bool {
        videoExtensions.contains((name as NSString).pathExtension.lowercased())
    }
}
