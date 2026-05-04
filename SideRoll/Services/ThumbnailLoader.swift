//
//  ThumbnailLoader.swift
//  SideRoll
//

import Foundation
import AppKit
import ImageCaptureCore

@MainActor
enum ThumbnailLoader {
    static func loadThumbnail(
        for item: ICCameraItem,
        via session: PhotoEnumerator
    ) async throws -> NSImage {
        let cgImage = try await session.requestThumbnail(for: item)
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }

    @discardableResult
    static func dumpJPEG(_ image: NSImage, named name: String = "sideroll-thumb.jpg") throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name)
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [:])
        else {
            throw ThumbnailLoaderError.encodingFailed
        }
        try jpeg.write(to: url)
        return url
    }

    enum ThumbnailLoaderError: Error {
        case encodingFailed
    }
}
