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
            Text("候选照片")
                .font(.system(size: 15, weight: .semibold))

            Text("窗口内 \(totalCount) 张 · 已选 \(selectedCount)")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Button("全选", action: onSelectAll)
                .font(.system(size: 13))
            Button("反选", action: onInvertSelection)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
