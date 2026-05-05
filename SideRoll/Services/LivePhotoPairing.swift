//
//  LivePhotoPairing.swift
//  SideRoll
//

import Foundation
import ImageCaptureCore

/// Live Photo companion lookup via `ICCameraFile.sidecarFiles`.
///
/// iOS PTP **does** expose Live Photo motion videos — they're not enumerated
/// at the top of `ICCameraDevice.mediaFiles`, they hang off the parent
/// HEIC's `sidecarFiles` property. Image Capture.app uses the same path.
/// (We previously concluded the opposite by counting `.MOV` entries in
/// `mediaFiles`; that was looking in the wrong place.)
enum LivePhotoPairing {
    nonisolated static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    /// Video sidecars (Live Photo motion .MOV) of `file`. Skips non-video
    /// sidecars such as `.AAE` (Photos.app edit instructions — meaningless
    /// outside Photos.app, so we don't drag them along).
    nonisolated static func videoSidecars(of file: ICCameraFile) -> [ICCameraFile] {
        let sidecars = file.sidecarFiles ?? []
        return sidecars.compactMap { item -> ICCameraFile? in
            guard let f = item as? ICCameraFile,
                  let name = f.name else { return nil }
            let ext = (name as NSString).pathExtension.lowercased()
            return videoExtensions.contains(ext) ? f : nil
        }
    }

    /// Full set of files to download when the user selects `file` —
    /// `file` itself plus any video sidecars. For a non-Live photo this
    /// is just `[file]`.
    nonisolated static func filesToImport(for file: ICCameraFile) -> [ICCameraFile] {
        [file] + videoSidecars(of: file)
    }
}
