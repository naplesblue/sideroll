//
//  CameraFolderScanner.swift
//  SideRoll
//

import Foundation
import ImageIO

enum CameraFolderScanner {
    nonisolated static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif",
        "nef", "cr2", "cr3", "arw", "raf", "dng", "orf", "rw2",
    ]

    nonisolated static func scan(folder: URL) async throws -> [CameraPhoto] {
        try await Task.detached(priority: .userInitiated) {
            try scanSync(folder: folder)
        }.value
    }

    nonisolated private static func scanSync(folder: URL) throws -> [CameraPhoto] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .nameKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScannerError.cannotEnumerate(folder)
        }

        let formatter = exifDateFormatter()
        var results: [CameraPhoto] = []
        var skipped = 0

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard supportedExtensions.contains(ext) else { continue }

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
