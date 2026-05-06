//
//  CameraFolderScanner.swift
//  SideRoll
//

import Foundation
import ImageIO

enum CameraFolderScanner {
    /// Camera vendor-specific RAW formats — ONLY these are used for TimeWindow
    /// calculation. DNG/JPG/HEIC are excluded because they may be post-processing
    /// exports with modified EXIF dates.
    nonisolated static let cameraRAWExtensions: Set<String> = [
        // Nikon
        "nef", "nrw",
        // Canon
        "cr2", "cr3", "crw",
        // Sony
        "arw", "srf", "sr2",
        // Fujifilm
        "raf",
        // Olympus / OM System
        "orf",
        // Panasonic
        "rw2",
        // Pentax (newer models output DNG natively — handled by fallback scan)
        "pef",
        // Leica
        "rwl",
        // Hasselblad
        "3fr", "fff",
        // Phase One
        "iiq",
        // Samsung
        "srw",
        // Sigma
        "x3f",
    ]

    nonisolated static let supportedExtensions: Set<String> =
        Set(["jpg", "jpeg", "heic", "heif", "dng", "tif", "tiff"])
            .union(cameraRAWExtensions)

    nonisolated static func scan(folder: URL, excludingSubfolders: [String] = ["iPhone"]) async throws -> [CameraPhoto] {
        try await Task.detached(priority: .userInitiated) {
            try scanSync(folder: folder, excludingSubfolders: excludingSubfolders)
        }.value
    }

    nonisolated private static func scanSync(folder: URL, excludingSubfolders: [String]) throws -> [CameraPhoto] {
        // Primary: scan for camera vendor RAW files (recursive)
        let rawResults = try scanFiles(
            folder: folder,
            extensions: cameraRAWExtensions,
            excludingSubfolders: excludingSubfolders,
            recursive: true
        )
        if !rawResults.isEmpty {
            return rawResults
        }

        // Fallback: no RAW found — scan top-level image files (JPG/HEIC/DNG etc.)
        print("[CameraFolderScanner] No RAW files found, falling back to top-level images")
        let fallbackExts: Set<String> = ["jpg", "jpeg", "heic", "heif", "dng", "tif", "tiff"]
        return try scanFiles(
            folder: folder,
            extensions: fallbackExts,
            excludingSubfolders: excludingSubfolders,
            recursive: false
        )
    }

    nonisolated private static func scanFiles(
        folder: URL,
        extensions: Set<String>,
        excludingSubfolders: [String],
        recursive: Bool
    ) throws -> [CameraPhoto] {
        let fm = FileManager.default

        let urls: [URL]
        if recursive {
            guard let enumerator = fm.enumerator(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                throw ScannerError.cannotEnumerate(folder)
            }
            urls = enumerator.compactMap { $0 as? URL }
        } else {
            // Top-level only — no recursion
            urls = (try? fm.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
        }

        let formatter = exifDateFormatter()
        var results: [CameraPhoto] = []
        var skipped = 0

        for url in urls {
            // Skip files inside excluded subdirectories
            let relative = url.path.replacingOccurrences(of: folder.path + "/", with: "")
            let topDir = relative.components(separatedBy: "/").first ?? ""
            if excludingSubfolders.contains(where: { $0.caseInsensitiveCompare(topDir) == .orderedSame }) {
                continue
            }

            let ext = url.pathExtension.lowercased()
            guard extensions.contains(ext) else { continue }

            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }

            guard let date = readCaptureDate(at: url, formatter: formatter) else {
                skipped += 1
                print("[CameraFolderScanner] No EXIF DateTimeOriginal: \(url.lastPathComponent)")
                continue
            }

            results.append(CameraPhoto(id: url, captureDate: date))
        }

        if skipped > 0 {
            print("[CameraFolderScanner] Skipped \(skipped) file(s) without EXIF date")
        }
        return results
    }

    nonisolated private static func readCaptureDate(at url: URL, formatter: DateFormatter) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        guard let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        guard let dateString = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        return formatter.date(from: dateString)
    }

    nonisolated private static func exifDateFormatter() -> DateFormatter {
        // EXIF DateTimeOriginal format: "yyyy:MM:dd HH:mm:ss" (colon-separated)
        // Recorded in the camera's local time without timezone offset; treat
        // as the local timezone the user is in when scanning.
        let f = DateFormatter()
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        return f
    }

    enum ScannerError: Error {
        case cannotEnumerate(URL)
    }
}
