//
//  CameraPhoto.swift
//  SideRoll
//

import Foundation

struct CameraPhoto: Identifiable, Hashable, Sendable {
    let id: URL
    let captureDate: Date

    var url: URL { id }
}
