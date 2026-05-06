//
//  GridHeaderView.swift
//  SideRoll — Header above thumbnail grid: title + counts + select/invert buttons
//

import SwiftUI

struct GridHeaderView: View {
    var totalCount: Int
    var selectedCount: Int
    var onSelectAll: () -> Void
    var onInvertSelection: () -> Void

    var body: some View {
        HStack {
            Text("Candidates")
                .font(.system(size: 15, weight: .semibold))

            Text("\(totalCount) found · \(selectedCount) selected")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Select All", action: onSelectAll)
                .font(.system(size: 13))
            Button("Invert", action: onInvertSelection)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
