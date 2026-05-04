//
//  Theme.swift
//  SideRoll
//

import SwiftUI

// Design spec: gold/amber accent color
extension Color {
    static let amber = Color(red: 0.83, green: 0.66, blue: 0.29) // #D4A84B
    static let amberDim = Color(red: 0.83, green: 0.66, blue: 0.29).opacity(0.6)
}

extension Font {
    static let sidebarSection = Font.caption.weight(.semibold)
    static let sidebarBody = Font.callout
}
