//
//  TimeWindowResolver.swift
//  SideRoll
//

import Foundation

struct TimeWindow: Hashable, Sendable {
    let start: Date
    let end: Date
}

enum TimeWindowResolver {
    nonisolated static let defaultBuffer: TimeInterval = 7200  // 2 hours

    nonisolated static func resolve(
        photos: [CameraPhoto],
        buffer: TimeInterval = defaultBuffer
    ) -> TimeWindow? {
        guard !photos.isEmpty else { return nil }
        let dates = photos.map(\.captureDate)
        guard let earliest = dates.min(), let latest = dates.max() else { return nil }
        return TimeWindow(
            start: earliest.addingTimeInterval(-buffer),
            end: latest.addingTimeInterval(buffer)
        )
    }
}
