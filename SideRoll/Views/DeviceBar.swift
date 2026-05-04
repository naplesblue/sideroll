//
//  DeviceBar.swift
//  SideRoll — Top bar: device name + status + file count + battery
//

import SwiftUI
import Combine
import ImageCaptureCore

struct DeviceBar: View {
    var enumerator: PhotoEnumerator?
    var deviceFileCount: Int
    @State private var isLocked: Bool = true

    private var lockPublisher: AnyPublisher<Bool, Never> {
        if let enumerator {
            return enumerator.$isLocked.eraseToAnyPublisher()
        }
        return Just(true).eraseToAnyPublisher()
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "iphone")
                .foregroundStyle(.secondary)

            if let enumerator {
                Text(enumerator.device.name ?? "iPhone")
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .foregroundStyle(.secondary)
                }

                if deviceFileCount > 0 {
                    Text("· \(deviceFileCount) 张")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("未连接 iPhone")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Battery level from ICDevice
            if let enumerator {
                let level = enumerator.device.batteryLevel
                if level > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: batteryIcon(level: level))
                            .foregroundStyle(level <= 20 ? .red : .secondary)
                        Text("\(level)%")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onReceive(lockPublisher) { locked in
            isLocked = locked
        }
    }

    private var statusColor: Color {
        if deviceFileCount > 0 { return .green }
        if isLocked { return .orange }
        return .yellow
    }

    private var statusText: String {
        if deviceFileCount > 0 { return "就绪" }
        if isLocked { return "请解锁 iPhone 屏幕" }
        return "连接中…"
    }

    private func batteryIcon(level: Int) -> String {
        switch level {
        case 0...12: return "battery.0percent"
        case 13...37: return "battery.25percent"
        case 38...62: return "battery.50percent"
        case 63...87: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
