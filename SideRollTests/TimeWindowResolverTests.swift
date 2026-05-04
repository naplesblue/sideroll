//
//  TimeWindowResolverTests.swift
//  SideRollTests
//

import Testing
import Foundation
@testable import SideRoll

struct TimeWindowResolverTests {

    private static func photo(at offset: TimeInterval, name: String = "p.jpg") -> CameraPhoto {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return CameraPhoto(
            id: URL(fileURLWithPath: "/tmp/\(name)"),
            captureDate: base.addingTimeInterval(offset)
        )
    }

    @Test
    func emptyArrayReturnsNil() {
        #expect(TimeWindowResolver.resolve(photos: []) == nil)
    }

    @Test
    func singlePhotoStretchesByBufferOnBothSides() {
        let p = Self.photo(at: 0)
        let window = TimeWindowResolver.resolve(photos: [p], buffer: 3600)
        #expect(window?.start == p.captureDate.addingTimeInterval(-3600))
        #expect(window?.end == p.captureDate.addingTimeInterval(3600))
    }

    @Test
    func multiplePhotosUseEarliestAndLatestRegardlessOfOrder() {
        let photos = [
            Self.photo(at: 7200, name: "c.jpg"),
            Self.photo(at: 0, name: "a.jpg"),
            Self.photo(at: 3600, name: "b.jpg"),
        ]
        let window = TimeWindowResolver.resolve(photos: photos, buffer: 1800)
        #expect(window?.start == Self.photo(at: 0).captureDate.addingTimeInterval(-1800))
        #expect(window?.end == Self.photo(at: 7200).captureDate.addingTimeInterval(1800))
    }

    @Test
    func zeroBufferReturnsExactRange() {
        let photos = [Self.photo(at: 0), Self.photo(at: 3600)]
        let window = TimeWindowResolver.resolve(photos: photos, buffer: 0)
        #expect(window?.start == Self.photo(at: 0).captureDate)
        #expect(window?.end == Self.photo(at: 3600).captureDate)
    }

    @Test
    func multiDaySpanIncludesAllPhotos() {
        let oneDay: TimeInterval = 86400
        let photos = [
            Self.photo(at: 0, name: "d1.jpg"),
            Self.photo(at: oneDay, name: "d2.jpg"),
            Self.photo(at: 2 * oneDay, name: "d3.jpg"),
        ]
        let window = TimeWindowResolver.resolve(photos: photos, buffer: 7200)
        #expect(window?.start == Self.photo(at: 0).captureDate.addingTimeInterval(-7200))
        #expect(window?.end == Self.photo(at: 2 * oneDay).captureDate.addingTimeInterval(7200))
    }

    @Test
    func defaultBufferIsTwoHours() {
        let p = Self.photo(at: 0)
        let window = TimeWindowResolver.resolve(photos: [p])
        #expect(window?.start == p.captureDate.addingTimeInterval(-7200))
        #expect(window?.end == p.captureDate.addingTimeInterval(7200))
    }
}
