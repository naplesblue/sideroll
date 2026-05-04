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

    var body: some View {
        HStack(spacing: 12) {
            if isImporting {
                ProgressView(value: progress)
                    .tint(.amber)
                    .frame(maxWidth: .infinity)
                Text(progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("取消") { onCancel() }
                    .controlSize(.small)
            } else {
                Text("\(selectedCount) 张准备就绪 · 约 \(String(format: "%.1f", totalSizeMB)) MB")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: onImport) {
                    Text("开始传送")
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
