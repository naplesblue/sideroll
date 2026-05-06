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
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.en.rawValue
    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        HStack {
            Text(L.candidates(lang))
                .font(.system(size: 15, weight: .semibold))

            Text(L.foundSelected(lang, totalCount, selectedCount))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()

            Button(L.selectAll(lang), action: onSelectAll)
                .font(.system(size: 13))
            Button(L.invert(lang), action: onInvertSelection)
                .font(.system(size: 13))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}
