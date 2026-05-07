//
//  Localization.swift
//  SideRoll — In-app language toggle (English / 中文)
//

import Foundation

enum AppLanguage: String, CaseIterable {
    case en = "en"
    case zh = "zh"

    var displayName: String {
        switch self {
        case .en: return "EN"
        case .zh: return "中"
        }
    }
}

// swiftlint:disable type_name
/// Lightweight localizer — `L.candidates(lang)` returns the right string.
enum L {
    // MARK: - DeviceBar
    static func noDevice(_ l: AppLanguage) -> String {
        l == .zh ? "未连接 iPhone" : "No iPhone connected"
    }
    static func photoCount(_ l: AppLanguage, _ n: Int) -> String {
        l == .zh ? "· \(n) 张" : "· \(n) photos"
    }
    static func ready(_ l: AppLanguage) -> String {
        l == .zh ? "就绪" : "Ready"
    }
    static func unlockiPhone(_ l: AppLanguage) -> String {
        l == .zh ? "请解锁 iPhone 屏幕" : "Please unlock your iPhone"
    }
    static func connecting(_ l: AppLanguage) -> String {
        l == .zh ? "连接中…" : "Connecting…"
    }

    // MARK: - GridHeaderView
    static func candidates(_ l: AppLanguage) -> String {
        l == .zh ? "候选照片" : "Candidates"
    }
    static func foundSelected(_ l: AppLanguage, _ total: Int, _ selected: Int) -> String {
        l == .zh ? "窗口内 \(total) 张 · 已选 \(selected)" : "\(total) found · \(selected) selected"
    }
    static func selectAll(_ l: AppLanguage) -> String {
        l == .zh ? "全选" : "Select All"
    }
    static func invert(_ l: AppLanguage) -> String {
        l == .zh ? "反选" : "Invert"
    }

    // MARK: - SidebarView
    static func cameraFolder(_ l: AppLanguage) -> String {
        l == .zh ? "相机文件夹" : "Camera Folder"
    }
    static func timeBuffer(_ l: AppLanguage) -> String {
        l == .zh ? "时间窗口缓冲" : "Time Buffer"
    }
    static func destination(_ l: AppLanguage) -> String {
        l == .zh ? "目标" : "Destination"
    }
    static func options(_ l: AppLanguage) -> String {
        l == .zh ? "选项" : "Options"
    }
    static func chooseFolder(_ l: AppLanguage) -> String {
        l == .zh ? "选择文件夹…" : "Choose Folder…"
    }
    static func photosCount(_ l: AppLanguage, _ n: Int) -> String {
        l == .zh ? "\(n) 张照片" : "\(n) photos"
    }
    static func hours(_ l: AppLanguage, _ h: String) -> String {
        l == .zh ? "±\(h) 小时" : "±\(h) hours"
    }
    static func subfolder(_ l: AppLanguage) -> String {
        l == .zh ? "子文件夹" : "Subfolder"
    }
    static func notSelected(_ l: AppLanguage) -> String {
        l == .zh ? "未选择" : "Not selected"
    }
    static func newFilesOnly(_ l: AppLanguage) -> String {
        l == .zh ? "只传送新文件" : "New files only"
    }
    static func preserveEXIF(_ l: AppLanguage) -> String {
        l == .zh ? "保留原 EXIF 时间" : "Preserve EXIF dates"
    }
    static func quitAfterImport(_ l: AppLanguage) -> String {
        l == .zh ? "完成后退出" : "Quit after import"
    }
    static func choose(_ l: AppLanguage) -> String {
        l == .zh ? "选择" : "Choose"
    }
    static func timeWindow(_ l: AppLanguage) -> String {
        l == .zh ? "时间窗口" : "Time Window"
    }
    static func modeAuto(_ l: AppLanguage) -> String {
        l == .zh ? "自动" : "Auto"
    }
    static func modeManual(_ l: AppLanguage) -> String {
        l == .zh ? "手动" : "Manual"
    }
    static func presetToday(_ l: AppLanguage) -> String {
        l == .zh ? "今日" : "Today"
    }
    static func presetYesterday(_ l: AppLanguage) -> String {
        l == .zh ? "昨日" : "Yesterday"
    }
    static func presetLast7Days(_ l: AppLanguage) -> String {
        l == .zh ? "最近 7 天" : "Last 7 days"
    }
    static func presetCustom(_ l: AppLanguage) -> String {
        l == .zh ? "自定义" : "Custom"
    }
    static func startDate(_ l: AppLanguage) -> String {
        l == .zh ? "开始" : "Start"
    }
    static func endDate(_ l: AppLanguage) -> String {
        l == .zh ? "结束" : "End"
    }
    static func invalidDateRange(_ l: AppLanguage) -> String {
        l == .zh ? "开始时间需早于结束时间" : "Start must be before end"
    }

    // MARK: - BottomBar
    static func cancel(_ l: AppLanguage) -> String {
        l == .zh ? "取消" : "Cancel"
    }
    static func readyCount(_ l: AppLanguage, _ n: Int, _ mb: String) -> String {
        l == .zh ? "\(n) 张准备就绪 · 约 \(mb) MB" : "\(n) ready · ~\(mb) MB"
    }
    static func importButton(_ l: AppLanguage) -> String {
        l == .zh ? "开始传送" : "Import"
    }

    // MARK: - CandidateGridView
    static func noCandidates(_ l: AppLanguage) -> String {
        l == .zh ? "暂无候选照片" : "No candidates"
    }
    static func selectFolderHint(_ l: AppLanguage) -> String {
        l == .zh ? "选择相机文件夹并连接 iPhone" : "Select a camera folder and connect your iPhone"
    }

    // MARK: - PreviewOverlay
    static func loadingPreview(_ l: AppLanguage) -> String {
        l == .zh ? "正在加载原图…" : "Loading full resolution…"
    }
    static func closeHint(_ l: AppLanguage) -> String {
        l == .zh ? "点击任意位置或按 ESC 关闭" : "Click anywhere or press ESC to close"
    }

    // MARK: - ContentView (import)
    static func importComplete(_ l: AppLanguage) -> String {
        l == .zh ? "传送完成" : "Import Complete"
    }
    static func doneQuit(_ l: AppLanguage) -> String {
        l == .zh ? "完成并退出" : "Done & Quit"
    }
    static func done(_ l: AppLanguage) -> String {
        l == .zh ? "完成" : "Done"
    }
    static func starting(_ l: AppLanguage) -> String {
        l == .zh ? "开始传送…" : "Starting…"
    }
    static func cancelled(_ l: AppLanguage, _ downloaded: Int, _ remaining: Int) -> String {
        l == .zh
            ? "已取消 · \(downloaded) 已传送 · \(remaining) 剩余"
            : "Cancelled · \(downloaded) imported · \(remaining) remaining"
    }
    static func importResult(_ l: AppLanguage, _ downloaded: Int, _ skipped: Int, _ failed: Int) -> String {
        var msg = l == .zh ? "\(downloaded) 张已传送" : "\(downloaded) imported"
        if skipped > 0 {
            msg += l == .zh ? "\n\(skipped) 张已跳过（重复）" : "\n\(skipped) skipped (duplicate)"
        }
        if failed > 0 {
            msg += l == .zh ? "\n\(failed) 张失败" : "\n\(failed) failed"
        }
        return msg
    }
    static func importSummary(_ l: AppLanguage, _ downloaded: Int, _ skipped: Int, _ failed: Int) -> String {
        l == .zh
            ? "完成 · \(downloaded) 已传送 · \(skipped) 已跳过 · \(failed) 失败"
            : "Done · \(downloaded) imported · \(skipped) skipped · \(failed) failed"
    }
    static func cancelledResult(_ l: AppLanguage, _ downloaded: Int, _ remaining: Int) -> String {
        l == .zh
            ? "已取消\n\(downloaded) 张已传送，\(remaining) 张未处理"
            : "Cancelled\n\(downloaded) imported, \(remaining) remaining"
    }
}
