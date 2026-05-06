//
//  CandidateFilter.swift
//  SideRoll
//

import Foundation
import ImageCaptureCore

/// Filters iPhone photos by time window and deduplicates ProRAW pairs.
enum CandidateFilter {
    /// Extensions that should be hidden when a DNG with the same basename exists.
    private static let dngPairedExts: Set<String> = ["jpg", "jpeg", "heic", "heif"]

    /// Resolve the best date for an iPhone photo.
    /// - EXIF fetched + date found → use EXIF date
    /// - EXIF fetched + date NOT found → nil (exclude from candidates)
    /// - EXIF not yet fetched → use creationDate (pre-EXIF rough display)
    static func resolvedDate(
        for file: ICCameraFile,
        exifDates: [String: Date],
        exifFetched: Set<String>
    ) -> Date? {
        guard let name = file.name else { return file.creationDate }
        if let exifDate = exifDates[name] {
            return exifDate
        }
        if exifFetched.contains(name) {
            return nil  // EXIF was fetched but DateTimeOriginal not found
        }
        return file.creationDate  // Not yet fetched — rough estimate
    }

    /// Filter files within the time window and deduplicate ProRAW pairs.
    /// When a DNG exists, hide paired JPG/HEIC (including E-prefix variants
    /// like IMG_E1908.JPG → IMG_1908.DNG).
    static func filter(
        files: [ICCameraFile],
        window: TimeWindow,
        exifDates: [String: Date],
        exifFetched: Set<String>
    ) -> [ICCameraFile] {
        let inWindow = files.filter { file in
            guard let date = resolvedDate(for: file, exifDates: exifDates, exifFetched: exifFetched) else {
                return false
            }
            return date >= window.start && date <= window.end
        }

        // Collect DNG basenames for ProRAW deduplication
        let dngBasenames = Set(inWindow.compactMap { file -> String? in
            guard let name = file.name,
                  (name as NSString).pathExtension.lowercased() == "dng" else { return nil }
            return (name as NSString).deletingPathExtension
        })
        guard !dngBasenames.isEmpty else { return inWindow }

        return inWindow.filter { file in
            guard let name = file.name else { return true }
            let ext = (name as NSString).pathExtension.lowercased()
            if dngPairedExts.contains(ext) {
                let base = (name as NSString).deletingPathExtension
                // Direct match: IMG_1908.HEIC → IMG_1908
                if dngBasenames.contains(base) { return false }
                // E-prefix match: IMG_E1908.JPG → IMG_1908
                if base.contains("_E"),
                   let range = base.range(of: "_E", options: .backwards) {
                    let stripped = base.replacingCharacters(in: range, with: "_")
                    if dngBasenames.contains(stripped) { return false }
                }
            }
            return true
        }
    }
}
