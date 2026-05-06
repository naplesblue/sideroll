//
//  PreviewOverlay.swift
//  SideRoll
//

import SwiftUI

/// Full-resolution lightbox preview overlay.
struct PreviewOverlay: View {
    let image: NSImage?
    let isLoading: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(40)
            } else {
                ProgressView("Loading full resolution…")
                    .foregroundStyle(.white)
            }

            // Close button — top right
            VStack {
                HStack {
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
                Spacer()
            }

            // Hint text at bottom
            VStack {
                Spacer()
                Text("Click anywhere or press ESC to close")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 16)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .onKeyPress(.escape) { onDismiss(); return .handled }
    }
}
