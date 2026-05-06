//
//  BottomBar.swift
//  SideRoll — Bottom bar: ready count + size + import button
//

import SwiftUI

struct BottomBar: View {
    var selectedCount: Int
    var totalSizeMB: Double
    var isImporting: Bool
    var progress: Double
    var progressText: String
    var onImport: () -> Void
    var onCancel: () -> Void
    @AppStorage("appLanguage") private var languageRaw = AppLanguage.en.rawValue
    private var lang: AppLanguage { AppLanguage(rawValue: languageRaw) ?? .en }

    var body: some View {
        HStack(spacing: 12) {
            if isImporting {
                ProgressView(value: progress)
                    .tint(.amber)
                    .frame(maxWidth: .infinity)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(L.cancel(lang)) { onCancel() }
                    .controlSize(.small)
            } else {
                Text(L.readyCount(lang, selectedCount, String(format: "%.1f", totalSizeMB)))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onImport) {
                    Text(L.importButton(lang))
                        .fontWeight(.medium)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.amber)
                .disabled(selectedCount == 0)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
