# SideRoll — AI 开发交接文档

> 本文档是 SideRoll 项目对所有 AI 协作者（Claude Code / Codex / Cursor / Aider 等）的统一开发规范与任务清单。**接手前请完整阅读 §1–§4 + §8 当前状态**，之后从 §5 任务清单中找到第一个状态为 `TODO` 的任务继续。

---

## 1. 项目目标

**SideRoll 是一个 macOS 原生 App**，用于把 iPhone 上"旅行期间"拍的照片自动归档到对应的相机照片文件夹。

### 用户场景

用户是摄影爱好者，旅行时主要用相机拍摄、iPhone 作为补充（相机不方便拿出来时的瞬间记录）。每次旅行结束的工作流是：

1. 把相机的 RAW/JPG 通过 SD 卡导入到一个旅行文件夹（如 `~/Photos/Trips/2026-04-Tokyo/`）
2. 在该文件夹内做后期编辑

**痛点**：iPhone 上当时拍的补充记录目前需要在 Photos.app 里手工按时间翻找、选中、导出，是整个工作流最大的摩擦点。

### SideRoll 要做的事

1. 用户选一个相机照片文件夹
2. App 读取该文件夹所有照片的 EXIF 拍摄时间，计算时间窗口（首末张 ± 缓冲）
3. 通过 USB 直连读取 iPhone，找出落在窗口内的所有照片
4. 显示候选缩略图，让用户预览/勾选/确认
5. 把选中的照片复制到 `<相机文件夹>/iPhone/` 子目录

---

## 2. 已锁定的关键决策

⚠️ 以下决策已与用户确认。如要修改必须先获得用户同意，**不要默认替换**。

| 项 | 决定 | 理由 |
|---|---|---|
| 平台 | macOS 原生 App，SwiftUI | Web app 不能通过浏览器访问 iPhone USB（iOS 屏蔽 WebUSB 的 PTP/MTP），评估后回到原生 |
| iPhone 读取 | USB 直连 + `ImageCaptureCore` | 不依赖 iCloud 同步状态，确保拿到原图 |
| 时间窗口 | 相机首末张 ± 可配置缓冲（默认 ±2 小时） | 简单稳健，覆盖出门到回家 |
| HEIC 格式 | **保留原格式，不转 JPG** | LR/C1 都已支持 HEIC，转 JPG 损失元信息 |
| Live Photo | **连同 .MOV 一起复制**（通过 `ICCameraFile.sidecarFiles`） | 2026-05-05 实测：660 张 HEIC 中 635 张通过 `sidecarFiles` 暴露了配对 .MOV。Image Capture.app 用的也是同一通路。早期 T3.2 错误地从 `mediaFiles` 顶层数 .MOV 数量后下结论"iOS 不暴露"——这属于查错了 API 入口（详见 §5 T3.2）|
| 文件命名 | **保留 iPhone 原文件名** | 不加时间戳前缀 |
| 导入前预览 | **必须有，强制确认** | 避免误导入大量非旅行照片 |
| 主力 RAW 格式 | Nikon NEF | 用户主力相机品牌 |

### 显式不做的事（v1 范围外）

- iCloud 共享相册 / Photos 图库读取（已被 USB 直连方案替代）
- HEIC 转 JPG
- 时间戳前缀重命名
- 多设备并行（一次只服务一台 iPhone）
- 自动检测时区错误并平移窗口（v1 用 ±缓冲足够）
- **从 iPhone 远程删除文件**（iOS PTP 不宣布 `ICCameraDeviceCanDeleteOneFile` capability。2026-05-05 用 macOS 自带"图像捕捉"反向验证：连 Apple 自己工具的 Delete 菜单都置灰）
- **Photos.app 编辑指令保留**（`.AAE` sidecar 文件不导入——只对 Photos.app 有意义）

---

## 3. 项目环境

| 项 | 值 |
|---|---|
| 项目根 | `/Volumes/雷电3/Projects/SideRoll/` |
| Xcode | 26.4.1 |
| macOS Deployment Target | 26.4 |
| Swift | 5.0 |
| Bundle ID | `nbhd.SideRoll` |
| App Sandbox | 已开启 (`ENABLE_APP_SANDBOX = YES`) |
| Default Actor Isolation | `MainActor`（`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`，注意 ImageCaptureCore delegate 的 actor 隔离问题） |
| 文件同步模式 | `PBXFileSystemSynchronizedRootGroup`（Xcode 自动同步源文件夹下所有内容，无需手动加 `.pbxproj` 引用） |

### 仓库结构（当前）

```
SideRoll/
├── AGENTS.md                    ← 本文档
├── CLAUDE.md                    ← 指向本文档（Claude Code 自动加载）
├── SideRoll.xcodeproj/
├── SideRoll/                    ← 主 target 源代码（Xcode 自动同步）
│   ├── SideRollApp.swift
│   ├── ContentView.swift        ← 主布局：HSplitView(sidebar + grid) + BottomBar
│   ├── Models/
│   │   └── CameraPhoto.swift
│   ├── Services/
│   │   ├── DeviceBrowser.swift
│   │   ├── PhotoEnumerator.swift  ← 含 requestThumbnail / requestMetadata 续延
│   │   ├── ThumbnailLoader.swift
│   │   ├── CameraFolderScanner.swift  ← 含 excludingSubfolders + cameraRAWExtensions
│   │   ├── TimeWindowResolver.swift
│   │   ├── ImportEngine.swift
│   │   └── LivePhotoPairing.swift
│   ├── Views/
│   │   ├── SidebarView.swift      ← 文件夹卡片 + 缓冲滑块 + 目标路径 + 选项
│   │   ├── DeviceBar.swift         ← 顶部设备状态栏（电量 + 锁屏检测）
│   │   ├── GridHeaderView.swift    ← 候选照片标题 + 全选/反选
│   │   ├── CandidateGridView.swift ← LazyVGrid 缩略图网格
│   │   ├── BottomBar.swift         ← 底部状态栏 + 开始传送按钮
│   │   └── Theme.swift             ← 主题色定义（amber）
│   ├── Assets.xcassets/
│   └── SideRoll.entitlements
├── SideRollTests/
│   ├── SideRollTests.swift
│   └── TimeWindowResolverTests.swift
└── SideRollUITests/
    └── SideRollUITests.swift
```

---

## 4. 架构

### 数据流

```
用户选择相机文件夹（NSOpenPanel）
        ↓
CameraFolderScanner（ImageIO 读 EXIF，仅扫描相机 RAW 格式：NEF/CR2/CR3/ARW/RAF/ORF/RW2）
        ↓
TimeWindowResolver（首末张 ± buffer）→ Date 区间 [start, end]
        ↓
DeviceBrowser（ICDeviceBrowser 发现 iPhone）
        ↓
PhotoEnumerator（遍历 ICCameraDevice.mediaFiles）
        ↓
fetchEXIFDates（粗筛 ±24h → requestMetadata → {Exif}.DateTimeOriginal / {TIFF}.DateTime）
  ├─ 照片：{Exif}.DateTimeOriginal（精确）
  ├─ 视频：跳过 EXIF，用 creationDate（PTP 不返回视频 EXIF）
  └─ EXIF 解析失败：排除（不回退到 creationDate）
        ↓
candidates 过滤（exifDates + exifFetched 双数据结构，避免 Date? 字典陷阱）
        ↓
ThumbnailLoader（懒加载 + 5s 超时 + 3 次重试）
        ↓
用户在 CandidateGridView 勾选/取消（ForEach 按 name 去重）
        ↓
ImportEngine（requestDownloadFile → 用户可编辑的目标子文件夹）
  ├─ skipExisting：只传送新文件 / 覆盖
  └─ setFileDate：保留原 EXIF 时间到文件系统
```

### 关键 API 速记

| 用途 | API |
|---|---|
| 设备发现 | `ICDeviceBrowser` + `ICDeviceBrowserDelegate.deviceBrowser(_:didAdd:moreComing:)` |
| 过滤设备类型 | `browsedDeviceTypeMask = .camera` |
| iPhone 文件列表 | `ICCameraDevice.mediaFiles: [ICCameraFile]`（含 `name` / `creationDate` / `fileSize` / `uti`） |
| 缩略图（异步） | `ICCameraFile.requestThumbnail()` → delegate `didReceiveThumbnail:for:error:` |
| EXIF 元数据 | `ICCameraItem.requestMetadata()` → delegate `didReceiveMetadata:for:error:` → `{Exif}.DateTimeOriginal`（照片）/ `{TIFF}.DateTime`（视频回退）。**注意：PTP metadata 的 sub-dict 是 `[AnyHashable: Any]`，不是 `[String: Any]`** |
| 下载 | `ICCameraDevice.requestDownloadFile(_:options:downloadDelegate:didDownloadSelector:contextInfo:)`，options 用 `ICDownloadOption` 类型化 key |
| 相机 EXIF | `ImageIO`：`CGImageSourceCreateWithURL` → `CGImageSourceCopyPropertiesAtIndex` → `kCGImagePropertyExifDictionary[kCGImagePropertyExifDateTimeOriginal]` |
| 设备电量 | `ICDevice.batteryLevel` (Int, 0–100) |

### Entitlements — ✅ 已就位

`SideRoll/SideRoll.entitlements` 中已配置：

- `com.apple.security.app-sandbox`
- `com.apple.security.device.usb`（ImageCaptureCore 访问 iPhone）
- `com.apple.security.files.user-selected.read-write`（写入相机文件夹）

### 边界情况清单

| 情况 | 处理 |
|---|---|
| iPhone 锁屏 | `isLocked` 状态追踪，DeviceBar 显示"请解锁 iPhone 屏幕"。拔插后重连需解锁才能重新枚举 |
| iPhone 照片日期 | **照片**：优先用 EXIF `DateTimeOriginal`（`[AnyHashable: Any]` 格式），解析失败则排除。**视频**：跳过 EXIF 检查，用 `creationDate`（PTP 不返回视频 EXIF）|
| 相机文件夹扫描 | **仅扫描相机 RAW 格式**（`cameraRAWExtensions`），排除 DNG/JPG/HEIC 后期导出文件（日期可能被修改），排除导入目标子文件夹 |
| 时区 | `Date` 是绝对时刻，相机/iPhone 时区不同也不影响。但用户的相机时区设错时窗口会偏（v2 再做平移 UI） |
| 大量照片性能 | `mediaFiles` 在 iPhone 上可能上万。先用 `creationDate` 粗筛（±24h），对粗筛结果拉 EXIF 精确过滤，再按需拉缩略图（懒加载 + 5s 超时 + 3 次重试） |
| 重复导入 | `onlyNewFiles` 开：跳过已存在同名文件。关：覆盖 |
| 单张下载失败 | 不中断批量，最后聚合 |
| Live Photo .MOV 配对 | 通过 `ICCameraFile.sidecarFiles` 取得（不在 `mediaFiles` 顶层）。`LivePhotoPairing.filesToImport(for:)` 自动展开 [HEIC] → [HEIC, MOV]。`.AAE` sidecar 跳过（Photos.app 编辑元数据，对 LR/C1 无用）|
| 中途拔 iPhone | 剩余文件标记 failed，不 crash |
| 导入完成 | 弹出 alert 对话框，显示结果摘要。若"完成后退出"开启，按钮变为"完成并退出" |
| DCIM 重名文件 | iPhone 不同 DCIM 子文件夹可能有同名文件，`CandidateGridView` 按 name 去重避免 ForEach ID 冲突 |
| PTP metadata 格式 | sub-dict 是 `[AnyHashable: Any]`，cast 成 `[String: Any]` 会**静默失败** |

---

## 5. 任务清单

> **状态字段约定**：`TODO` / `IN_PROGRESS` / `DONE` / `BLOCKED`（带原因）。AI 接手时把"开始做"的任务标 `IN_PROGRESS`，完成后标 `DONE` 并填写完成时间和提交 commit hash（如有）。

### Phase 0 · 项目脚手架

#### T0.1 · Xcode 项目骨架 — `DONE` (2026-05-03)

**目标**：可运行的 SwiftUI macOS App 骨架。

**当前状态**：已由用户在 Xcode 26.4.1 GUI 中创建。`SideRollApp.swift` + `ContentView.swift` 是默认 Hello World 模板。`PBXFileSystemSynchronizedRootGroup` 模式（自动同步文件夹）。

**验收**：✅ 在 Xcode 中能 Build & Run，看到 "Hello, world!" 窗口。

---

#### T0.2 · Entitlements 与 Capabilities 配置 — `DONE` (2026-05-03)

**目标**：让 App 拥有访问 USB 设备和写入用户选择文件夹的权限。

**实现**：
1. 创建 `SideRoll/SideRoll.entitlements` 显式声明三项：
   - `com.apple.security.app-sandbox`
   - `com.apple.security.device.usb`
   - `com.apple.security.files.user-selected.read-write`
2. `.pbxproj` 主 target Debug + Release 配置加 `CODE_SIGN_ENTITLEMENTS = SideRoll/SideRoll.entitlements;`
3. `ENABLE_USER_SELECTED_FILES` 从 `readonly` 改为 `readwrite`（与 entitlements 保持一致，避免冲突）

**验收结果**：
- ✅ `xcodebuild build` SUCCEEDED
- ✅ `codesign -d --entitlements -` 输出包含三项目标 entitlement（外加 Debug 自动添加的 `get-task-allow`）
- ⏳ 启动时"选择文件夹"系统弹窗待 UI 实现后真机验证（T4.2）

**坑（实际遇到的）**：
- 没有走 Xcode GUI 而是直接编辑 `.pbxproj`，对 `PBXFileSystemSynchronizedRootGroup` 模式来说没问题，因为 `.entitlements` 文件放在 source 同步文件夹下会被自动 pick up
- macOS 26 首次访问 USB 设备会另有"图像捕捉"系统权限弹窗，需要用户在系统设置中批准（Phase 1 实测时遇到要确认）

---

#### T0.3 · Git 仓库初始化 — `DONE` (2026-05-03, commit `9820e99`)

**目标**：项目纳入 git 版本控制。

**实现要点**：
```bash
cd "/Volumes/雷电3/Projects/SideRoll"
git init
```

`.gitignore` 内容（基于 GitHub 标准 Swift/Xcode 模板）：
```
# macOS
.DS_Store

# Xcode
build/
DerivedData/
*.pbxuser
!default.pbxuser
*.mode1v3
!default.mode1v3
*.mode2v3
!default.mode2v3
*.perspectivev3
!default.perspectivev3
xcuserdata/
*.moved-aside
*.xccheckout
*.xcscmblueprint
*.hmap
*.ipa
*.dSYM.zip
*.dSYM

# Swift Package Manager
.build/
Packages/
Package.pins
Package.resolved
.swiftpm/

# CocoaPods (未使用但预留)
Pods/

# Carthage (未使用但预留)
Carthage/Build
```

**验收**：
- `git status` 不报错
- `xcuserdata/` 不在追踪列表
- 首次 commit 包含主 target 源文件、tests 目录、`.xcodeproj`（除 `xcuserdata`）

---

### Phase 1 · iPhone USB 通信打通（最高风险）

> ⚠️ Phase 1 是整个项目最容易卡死的部分。建议先做 CLI 验证（在 main app 里临时加个按钮触发，把结果打到 stdout），脱离 SwiftUI 把 ImageCaptureCore 完全打通后再往 UI 上接。

#### T1.1 · DeviceBrowser — `DONE` (2026-05-03)

**目标**：能发现并打印连接的 iPhone 设备名。

**文件**：`SideRoll/Services/DeviceBrowser.swift`

**实现**：
- `final class DeviceBrowser: NSObject, ObservableObject` 持有 `ICDeviceBrowser`，`@Published private(set) var connectedDevice: ICCameraDevice?`
- `browsedDeviceTypeMask = ICDeviceTypeMask.camera ∪ ICDeviceLocationTypeMask.local`（OR rawValues 后包成 `ICDeviceTypeMask`，单 `.camera` 不够，需要带上位置 mask）
- delegate 方法标 `nonisolated`，因为 ImageCaptureCore 的 callback 与 `@MainActor` 默认隔离不兼容；状态写入用 `Task { @MainActor in ... }` 跳回主 actor
- 在 `SideRollApp` 中 `@StateObject` 实例化，`.task { browser.start() }` 启动

**验收结果**：
- ✅ 插上 iPhone：`[DeviceBrowser] Found device: NaplesIP17Pro (moreComing=false)`
- ✅ 拔掉 iPhone：`[DeviceBrowser] Device removed: NaplesIP17Pro`
- ✅ 编译通过，App 沙箱+USB entitlement 在 T0.2 已就位，无需额外系统授权

**坑（实际遇到的）**：
- `ObservableObject` / `@Published` 属于 Combine 框架，`import Foundation` 不够，必须 `import Combine`（首次编译报 "type does not conform to protocol ObservableObject"）

**坑（沿 Apple 示例预防的，未实证另一条路）**：
- `browsedDeviceTypeMask` 没单试 `.camera`，直接按 Apple Sample 的 OR 写法（`ICDeviceTypeMask.camera ∪ ICDeviceLocationTypeMask.local` 的 rawValues）。如要简化为单 `.camera` 可后续验证
- 必须保留 `ICDeviceBrowser` 强引用，否则会被释放、回调永远不触发

---

#### T1.2 · PhotoEnumerator v0 — `DONE` (2026-05-04)

**目标**：开 session 后能列出 iPhone 上前 10 张照片的 `name` / `creationDate` / `fileSize` / `uti`。

**文件**：`SideRoll/Services/PhotoEnumerator.swift`

**实现**：
- `final class PhotoEnumerator: NSObject, ObservableObject`，由 `SideRollApp` 通过 `.onReceive(deviceBrowser.$connectedDevice)` 在设备就绪时实例化并 `start()`
- `start()` 设置 `device.delegate = self` 后调用 `requestOpenSession()`
- 用 `deviceDidBecomeReady(withCompleteContentCatalog:)` 作为"枚举完成"的可靠信号触发 `reportFirstTen()`，避开"延时等待"的不可靠
- `mediaFiles` 元素在 macOS 26 SDK 中是 `[ICCameraItem]`，`fileSize` 在 `ICCameraFile` 子类——需 `compactMap { $0 as? ICCameraFile }`

**验收结果**（NaplesIP17Pro 真机）：
- ✅ 1712 张照片完整枚举
- ✅ 首 10 张按 `creationDate` ASC 排序输出 `name | date | size | uti` 全字段
- ✅ 锁屏边界情况实测通过：session 初次 open 失败（"Please unlock"）→ 用户解锁 → `cameraDeviceDidRemoveAccessRestriction` → `didAdd` 批量到达 → `deviceDidBecomeReady(withCompleteContentCatalog:)` 触发汇报，全程不需手动重试

**实战发现**：
- macOS 26 SDK 的 `ICCameraDeviceDelegate` 多个方法签名都改了：
  - 旧 `didAddItems:` → 新 `didAdd:`（直接覆盖原单项 `didAdd:item:`）
  - 旧 `didReceiveThumbnailFor:` → 新 `didReceiveThumbnail:for:error:`（增加 thumbnail 和 error 参数）
  - 旧 `didReceiveMetadataFor:` 同理
  - 多了一个必须实现的 `deviceDidBecomeReady(withCompleteContentCatalog: ICCameraDevice)`
- iPhone 通过 ImageCaptureCore 报告的 `uti` 是泛化的 `public.image`，**不是** `public.heic` / `public.jpeg`——后续区分文件类型必须用扩展名（`.HEIC`、`.JPG`、`.MOV`），不能依赖 UTI。这影响 T3.2 LivePhotoPairing 的实现策略（已经按扩展名匹配，所以不影响）
- ICDeviceDelegate.`device(_:didReceiveStatusInformation:)` 的 dict key 类型是 `ICStatusNotificationKeys` 而非 `String`，目前留作 no-op 带个 warning，不影响功能

---

#### T1.3 · ThumbnailLoader — `DONE` (2026-05-04)

**目标**：异步拉一张照片的缩略图，落到 `NSImage`。

**文件**：`SideRoll/Services/ThumbnailLoader.swift`

**实现**：
- `PhotoEnumerator` 持有 `pendingThumbnails: [ObjectIdentifier: CheckedContinuation<CGImage, Error>]` 注册表，暴露 `requestThumbnail(for:) async throws -> CGImage`
- `requestThumbnail` 用 `withCheckedThrowingContinuation` + `item.requestThumbnail()` 触发，等 delegate 的 `didReceiveThumbnail:for:error:` 回调用 `ObjectIdentifier(item)` 找到对应 continuation 续延
- `ThumbnailLoader` 是无状态 enum，提供 `loadThumbnail(for:via:)` 把 `CGImage` 包成 `NSImage`，外加 `dumpJPEG(_:)` 便于验证

**验收结果**：
- ✅ 在 `reportFirstTen` 末尾插了 verification trigger，针对首张文件 dump 缩略图到沙箱 `tmp/sideroll-thumb.jpg`
- ✅ 用户肉眼确认图是真实照片缩略图，非占位符

**实战发现**：
- `ICCameraItem.thumbnailIfAvailable` 在 macOS 10.15 起 deprecated。modern API 直接 `item.requestThumbnail()` 触发，框架内部自带缓存，不必自己 short-circuit
- `requestThumbnail` 不返回 Future，是 fire-and-forget，结果在 delegate `didReceiveThumbnail:for:error:` 里以 `(CGImage?, Error?)` 形式给到——比老的 `didReceiveThumbnailFor:` callback + 二次属性读取干净一档
- verification trigger 现在嵌在 `PhotoEnumerator.reportFirstTen` 末尾，**Phase 4 实现 `CandidateGridView` 时应迁移到 UI 层并移除**

---

### Phase 2 · 相机文件夹解析

#### T2.1 · CameraPhoto 模型 — `DONE` (2026-05-04)

**文件**：`SideRoll/Models/CameraPhoto.swift`

```swift
struct CameraPhoto: Identifiable, Hashable, Sendable {
    let id: URL
    let captureDate: Date
    var url: URL { id }
}
```

**验收结果**：✅ 编译通过，`CameraFolderScanner.scan(folder:)` 正确返回 `[CameraPhoto]`。`Sendable` 显式标注便于跨 actor 传递。

---

#### T2.2 · CameraFolderScanner — `DONE` (2026-05-04)

**目标**：扫描相机文件夹，返回每张照片的 `(URL, captureDate)`。

**文件**：`SideRoll/Services/CameraFolderScanner.swift`

**实现**：
- `nonisolated static func scan(folder:) async throws -> [CameraPhoto]` 在 `Task.detached(priority: .userInitiated)` 上执行同步扫描，避免阻塞主线程
- `FileManager.enumerator(at:includingPropertiesForKeys:options:[.skipsHiddenFiles, .skipsPackageDescendants])` 递归遍历
- 扩展名白名单：`jpg/jpeg/heic/heif/nef/cr2/cr3/arw/raf/dng/orf/rw2`
- ImageIO 读 EXIF：`CGImageSourceCreateWithURL` → `CGImageSourceCopyPropertiesAtIndex` → `kCGImagePropertyExifDictionary[kCGImagePropertyExifDateTimeOriginal]`
- EXIF 时间字符串格式 `"yyyy:MM:dd HH:mm:ss"`，按本地时区解析（用户在哪里扫，按那个时区解读，符合"绝对时刻"的语义）
- 解析失败的文件跳过 + 控制台 warn

**验收结果**（真实 Nikon Z 旅行文件夹 `20260429 华严寺·善化寺`）：
- ✅ 121 张 NEF 全部解析成功，0.52s 完成
- ✅ 时间范围 `2026-04-29 10:09:49 → 12:46:24` 与文件夹名日期完全吻合
- ✅ 前 10 张时间戳呈自然连续（连拍 + 移动间隙），与拍摄行为一致

**实战发现**：
- 项目默认 `MainActor` actor isolation 让所有 static 方法和属性默认 main-actor 隔离；从 `Task.detached` 调用会触发 Swift 6 错误。修法：把 scanner 的 `static func`、`static let supportedExtensions` 都标 `nonisolated`
- `NSOpenPanel` 选目录后，沙箱通过 Powerbox 给 App 临时读权限，配合 `com.apple.security.files.user-selected.read-write` entitlement 即可读到任何用户主动选的位置（包括外接卷如 `/Volumes/LightBox/`）

---

#### T2.3 · NEF 兼容性 smoke test — `DONE` (2026-05-04)

**目标**：确认用户主力 Nikon NEF 文件能被 ImageIO 解析出 `captureDate`。

**验收结果**：T2.2 的真实文件夹扫描包含 121 张 .NEF（一次旅行的全量），全部解析成功，时间戳序列自然连续，与文件夹名日期一致 → 隐含验证 NEF 兼容。**ImageIO 原生支持 NEF，无需额外依赖**。

---

#### T2.4 · TimeWindowResolver + 单元测试 — `DONE` (2026-05-04)

**文件**：`SideRoll/Services/TimeWindowResolver.swift`、`SideRollTests/TimeWindowResolverTests.swift`

**API**：
```swift
struct TimeWindow: Hashable, Sendable { let start, end: Date }
enum TimeWindowResolver {
    static let defaultBuffer: TimeInterval = 7200
    nonisolated static func resolve(photos: [CameraPhoto], buffer: TimeInterval = defaultBuffer) -> TimeWindow?
}
```

**验收结果**（Swift Testing，6 个用例全绿）：
- ✅ 空数组返回 nil
- ✅ 单张：start/end = 时间 ∓ buffer
- ✅ 多张乱序：start = min(captureDate) - buffer, end = max(captureDate) + buffer
- ✅ buffer = 0：返回精确 [min, max]
- ✅ 跨 3 天的多张：窗口完整覆盖
- ✅ 默认 buffer 是 7200 秒（2 小时）

**实战发现**：
- 项目用的是 Swift Testing（`import Testing` + `@Test`），不是 XCTest——这是 Xcode 26 默认。`#expect(...)` 替代 `XCTAssertEqual`
- 用 `nonisolated` 标 static 方法，让它能从 detached / 任意 actor 上下文调用，与项目 `MainActor` 默认隔离不冲突

---

### Phase 3 · 导入引擎

#### T3.1 · ImportEngine 基础下载 — `DONE` (2026-05-04)

**目标**：从 iPhone 拷一张 HEIC 到 `<相机文件夹>/iPhone/`。

**文件**：`SideRoll/Services/ImportEngine.swift`

**实现**：
- `final class ImportEngine: NSObject` 持有 `device: ICCameraDevice` + `pending: [ObjectIdentifier: PendingDownload]` 续延注册表
- `download(file:to:) async throws -> URL`：先 `createDirectory(...)` 确保 `<target>/iPhone/` 存在，存好预测的 targetURL，再调用 `device.requestDownloadFile(_:options:downloadDelegate:didDownloadSelector:contextInfo:)`，options 用 `ICDownloadOption` 类型化 key：`.downloadsDirectoryURL` / `.saveAsFilename`
- 实现 `ICCameraDeviceDownloadDelegate.didDownloadFile(_:error:options:contextInfo:)`，按 `ObjectIdentifier(file)` 找到对应续延，成功时返回预存的 targetURL

**验收结果**（外接卷 `/Volumes/LightBox/Nikon Z/2026/20260428 云冈石窟·华严寺夕阳/`）：
- ✅ `IMG_2523.HEIC` 0.05s 拷到 `<target>/iPhone/`
- ✅ 字节级一致：source on device 3,403,583 bytes = size on disk 3,403,583 bytes（无转码、无损）
- ✅ Preview 能正常打开
- ✅ 中文路径 + 外接卷 + 中点分隔符全部正常

**实战发现**：
- macOS 26 SDK：`options` 参数现在是类型化的 `[ICDownloadOption: Any]`（不是 `[String: Any]`），但 protocol 回调里 `options` 仍是 `[String: Any]`——双向不对称
- 不要试图从回调里解 options 字典还原 targetURL（key 类型不一致很麻烦）。**直接在发请求时把预测的 targetURL 存进 pending 字典**，回调时取出更干净
- 别在自己的方法上加 `@objc private` 试图重命名——那会和 protocol 的 optional `didDownloadFile` 方法 selector 冲突。直接实现 protocol 方法，签名严格按 SDK 给的（`options: [String: Any] = [:]`）

---

#### T3.2 · LivePhotoPairing — `DONE` (2026-05-05, **重做**)

**目标**：导入 Live Photo 时同时复制配对 .MOV，保留动效。

**文件**：`SideRoll/Services/LivePhotoPairing.swift`

**实现**（最终版）：
- 单一入口 `filesToImport(for: ICCameraFile) -> [ICCameraFile]`
- 内部用 `file.sidecarFiles` 取配对，过滤到 `videoExtensions`（`mov` / `mp4` / `m4v`），跳过 `.AAE`
- ContentView.startImport 把 `selectedFiles` 用 `flatMap` 展开到 `[(file, parentDate)]`，主图和 .MOV 用同一个 EXIF 时间写入文件系统时间，保证 Finder 排序成对

**验收结果**（NaplesIP17Pro 真机）：
- ✅ 10/10 最近 HEIC 都有 .MOV sidecar，全库 635/1714（≈37%）
- ✅ 出现的 sidecar 类型：`.MOV`（视频，全部包含）、`.AAE`（编辑指令，不导入）
- ⏳ 实际导入回流验证待完整跑一遍后补

**审计：早期错误结论的来龙去脉**（2026-05-04 → 2026-05-05）：

第一次 T3.2 的实施和验证完全跑偏，但跑偏过程留下的诊断数据反而帮助找到正确路径，记录在此防止未来 AI 再走一遍：

1. **错误前提**：以为 Live Photo 的 .HEIC + .MOV 都在 `mediaFiles` 顶层用同 basename 出现，写了 basename 匹配版的 `videoCompanion` / `allPairs`
2. **错误验证**：在 1714 个 mediaFiles 项目里只找到 2 对同 basename，错误地把数字偏低归因为"iOS PTP 不暴露 Live Photo 配对"
3. **错误结论**：在 §2 把 Live Photo 动效列入"v1 不做"，写进 memory
4. **触发反思**：用户提到"图像捕捉 App 导入 HEIC 时同时把配对 .MOV 也带过来"——Apple 自己的工具能拿到说明 API 一定存在
5. **正确入口**：查文档发现 `ICCameraFile.sidecarFiles` 属性。诊断 dump（commit `e41beaf`）证实 10/10 HEIC 都有 .MOV sidecar
6. **教训**：当 mediaFiles 数据看着不对时，**先查 ICCameraFile 上有没有别的属性挂着配对信息**，不要直接下"系统不支持"的结论。真正的"系统不支持"应该用 Apple 工具反向验证（Live Photo 没做这步，Delete 做了）

留作活档保存——参见 `~/.claude/projects/.../memory/lesson_check_sidecarfiles_property.md`

---

#### T3.3 · 幂等 — `DONE` (2026-05-04)

**目标**：目标已存在同名文件 → 跳过，不覆盖。

**实现**：
- `download(file:to:)` 返回类型从 `URL` 改为 `DownloadResult` 枚举（`.downloaded(URL)` / `.skipped(URL)`）
- 在发起 `requestDownloadFile` 之前检查 `FileManager.default.fileExists(atPath: targetURL.path)`
- 已存在 → 直接返回 `.skipped(targetURL)`，不调用 download，不触发 continuation

**验收结果**（NaplesIP17Pro 真机）：
- ✅ `IMG_2523.HEIC` 在 T3.1 已导入过 → 再次点击 Import 正确返回 `0 downloaded, 1 skipped, 0 failed` (0.01s)
- ✅ 显示 `⏭ IMG_2523.HEIC — already exists at IMG_2523.HEIC`，未触发下载

---

#### T3.4 · 失败收集 — `DONE` (2026-05-04)

**目标**：单张失败不中断批量，最后给完整失败列表。

**实现**：
- 新增 `ImportReport` 结构体：`downloaded: [(file, url)]` / `skipped: [(file, url)]` / `failed: [(file, error)]` 三桶
- 新增 `importBatch(files:to:) -> ImportReport`：逐文件 `do/catch` 调用 `download()`，失败记入 `failed` 不中断循环
- ContentView 临时 UI 改用 `importBatch` 替代手动 for 循环，输出带 ✅/⏭/❌ 图标区分三种状态

**验收结果**（NaplesIP17Pro 真机，拔线测试）：
- ✅ 批量 10 张导入中途拔 iPhone → `2 downloaded, 0 skipped, 8 failed`（27.62s）
- ✅ 8 张失败全部正确报告 `ImageCaptureCore error -9958`，无遗漏
- ✅ App 不 crash，UI 正常显示完整结果

**实战发现**：
- 拔线后 ImageCaptureCore 回调返回 error code `-9958`（设备断开），continuation 正常 resume throwing
- 发现附带问题：拔线后重新插入 iPhone，`DeviceBrowser` 不能重新更新设备状态——需修复 `didRemove` 中的设备比较逻辑

---

### Phase 4 · SwiftUI 串接

#### T4.1 · ContentView 主布局 — `DONE` (2026-05-04, commits `e0e9837`, `a252b82`)

**文件**：`SideRoll/ContentView.swift`

**布局**（参考 Nikon Transfer 2 + 用户设计图「现代克制」）：
```
┌─ DeviceBar ────────────────────────────────────┐
│ 📱 NaplesIP17Pro · 🟢就绪 · 1,714 张  🔋85%   │
├────────────┬───────────────────────────────────┤
│ SidebarView│  GridHeaderView                   │
│ - 相机文件夹│  候选照片 35 · 已选 35  [全选][反选] │
│   卡片     │  ────────────────────────────────  │
│ - 缓冲滑块  │  CandidateGridView               │
│ - 目标路径  │  (LazyVGrid, 缩略图懒加载)        │
│   (可编辑)  │                                   │
│ - 选项     │                                   │
│   开关列表  │                                   │
├────────────┴───────────────────────────────────┤
│ BottomBar: 35 张准备就绪 · 约 177.5 MB [开始传送] │
└────────────────────────────────────────────────┘
```

**实现**：
- `HSplitView` 左右分栏：Sidebar（200–260pt）+ Grid
- `VStack(spacing: 0)` 垂直叠放 DeviceBar / Divider / HSplitView / Divider / BottomBar
- 窗口最小 900×640

**验收**：✅ 与设计图布局一致，Sidebar 固定在顶部不随内容滚动

---

#### T4.2 · SidebarView（含文件夹选择 + 缓冲 + 目标 + 选项） — `DONE` (2026-05-04)

**文件**：`SideRoll/Views/SidebarView.swift`

**实现**：
- **相机文件夹卡片**：显示文件夹名 + 文件数 + RAW 格式 + 时间范围，点击 "选择文件夹" 触发 `NSOpenPanel`
- **缓冲滑块**：0–12h 范围，步进 30min，amber 主题色，实时显示 `±X.X 小时` 和缓冲后窗口范围（`MM/dd HH:mm` 格式）
- **目标路径**：显示 `…/文件夹名/<子文件夹>/`，子文件夹名可编辑（TextField，默认 `iPhone`），12pt 字体
- **选项区**：3 个 toggle，macOS 设置风格（文字在左，mini switch 靠右对齐），`@AppStorage` 持久化：
  - 只传送新文件（默认开）→ `skipExisting` 参数
  - 保留原 EXIF 时间（默认开）→ 下载后 `setFileDate` 同步文件系统时间
  - 完成后退出（默认关）→ alert 按钮变"完成并退出"，点击后 `NSApplication.shared.terminate`
- **CameraFolderScanner 排除**：扫描时跳过用户设定的导入子文件夹名

**验收**：✅ 布局与设计图一致，选项 toggle 与 macOS 设置风格匹配，状态跨启动持久化

---

#### T4.3 · DeviceBar（设备状态 + 电量 + 锁屏检测） — `DONE` (2026-05-04)

**文件**：`SideRoll/Views/DeviceBar.swift`

**实现**：
- 三态显示：未连接（灰色）/ 连接中 or 锁屏（amber "请解锁 iPhone 屏幕"）/ 就绪（绿色 + 文件数）
- 电量显示：`ICDevice.batteryLevel` + 系统电池图标（`battery.0` ~ `battery.100.bolt`）
- `PhotoEnumerator.isLocked` 状态追踪：通过 `cameraDeviceDidEnableAccessRestriction` / `didRemoveAccessRestriction` delegate 方法

**验收**：✅ 插拔 iPhone / 锁屏解锁状态切换正常反映，电量实时显示

**实战发现**：
- 拔插 iPhone 后重新连接，必须先解锁才能重新枚举（`hasScheduledReport` 需要重置为 false，否则阻塞重新枚举）
- `ICDevice.batteryLevel` 直接可用，无需额外权限

---

#### T4.4 · CandidateGridView（缩略图网格 + EXIF 日期过滤） — `DONE` (2026-05-04)

**文件**：`SideRoll/Views/CandidateGridView.swift`、`SideRoll/Views/GridHeaderView.swift`

**实现**：
- `LazyVGrid` 自适应列宽（110–150px），4:3 宽高比
- 缩略图懒加载：`.task(id: file.name)` 触发，5s 超时 + 3 次重试（PTP 并发请求多时偶尔超时）
- 每格：缩略图 + amber 勾选角标 + 时间标签（`MM/dd HH:mm`）+ 格式标签
- GridHeaderView：标题 "候选照片"（15pt semibold）+ 计数（13pt）+ 全选/反选按钮（13pt）
- **EXIF 日期解析**：`exifCaptureDate(from:)` 提取 `{Exif}.DateTimeOriginal`（照片）/ `{TIFF}.DateTime`（视频回退）。**关键：sub-dict 必须 cast 为 `[AnyHashable: Any]`**
- **两阶段过滤**：先用 `creationDate` 粗筛（±24h），对粗筛结果拉 EXIF 精确过滤。视频跳过 EXIF 检查，用 `creationDate`
- **双数据结构**：`exifDates: [String: Date]`（成功日期）+ `exifFetched: Set<String>`（已请求文件）。避免 Swift `[String: Date?]` 字典赋值 nil 会删 key 的陷阱
- **去重**：`deduplicatedByName()` 处理 DCIM 子文件夹同名文件

**验收**：✅ 候选照片正确过滤，缩略图懒加载流畅，勾选/取消/全选/反选均正常

**实战发现（重要 bug 修复）**：
- `ICCameraFile.creationDate` 是文件系统日期，**不是** EXIF 拍摄日期。被编辑、iCloud 同步、AirDrop 等操作会改变
- `CameraFolderScanner` 只扫描相机 RAW 格式（`cameraRAWExtensions`），排除 DNG/JPG/HEIC 后期导出文件（日期可能被修改）
- PTP metadata sub-dict 是 `[AnyHashable: Any]`，cast 成 `[String: Any]` **静默失败**。这导致所有 HEIC 的 EXIF 解析失败，回退到不可靠的 `creationDate`
- Swift `[String: Date?]` 字典的 `dict[key] = nil` 不是存 nil 值，而是删除 key。必须用独立的 `Set<String>` 追踪已请求文件
- `.onReceive(fileCountPublisher)` 因 computed property 每次 render 创建新 publisher 实例，导致 `autoSelectAll()` 覆盖用户手动选择。修复：只在 `deviceFileCount` 从 0→N 时触发

---

#### T4.5 · BottomBar + 导入流程 + 完成对话框 — `DONE` (2026-05-04)

**文件**：`SideRoll/Views/BottomBar.swift`

**实现**：
- 底部栏：`X 张准备就绪 · 约 X.X MB` + amber "开始传送" 按钮
- 导入中：进度条 + `[N/total] filename` 实时文本 + 取消按钮
- 导入完成：弹出 `alert` 对话框，显示结果摘要（已传送 / 已跳过 / 失败），需用户点击 "完成" 确认
- 取消：立即停止后续下载，对话框显示 "已取消" + 已传送/未处理数量
- **目标子文件夹可编辑**：默认 `iPhone`，用户可在 sidebar 修改，为空时回退到 `iPhone`

**验收**：✅ 导入 + 跳过 + 取消全流程正常，完成弹窗显示正确结果

---

### Phase 5 · 端到端验收与调优

#### T5.1 · 真实旅行验收 — `TODO`

**目标**：用最近一次真实旅行完整跑一遍，对比手工选片。

**记录指标**：
- 漏选数（应该被选中但没出现在候选里的）
- 多选数（不该选中但出现的）
- HEIC EXIF 拍摄时间一致性
- 总耗时（vs 手工流程）

注：原计划的"Live Photo 配对正确率"指标已移除——iOS PTP 不暴露 Live Photo 配对视频（详见 §2 / T3.2）

**验收**：完成报告，记录数据。

---

#### T5.2 · 默认缓冲值调优 — `TODO`

**目标**：根据 T5.1 漏选/多选数据，调整默认缓冲值。

**思路**：
- 漏选多 → 缓冲偏小，调大默认值（如 4h）
- 多选多 → 缓冲偏大，调小默认值（如 1h）
- 极端情况（清晨摸黑出门、深夜返程）考虑提供"按相机日期整天"模式作为备选

**验收**：默认值更新到代码 + 验证逻辑通过。

---

#### T5.3 · README — `TODO`

**目标**：使用说明 + 已知限制。

**内容**：
- 一句话项目介绍
- 使用步骤（截图）
- 系统要求（macOS 26.4+）
- 已知限制（仅 USB 直连、不支持 iCloud 同步未下载的照片等）
- 故障排查（iPhone 不显示、mediaFiles 为空等）

---

## 6. 端到端验证协议

每个 Phase 完成后必跑的 smoke test：

| 检验点 | 操作 | 通过标准 |
|---|---|---|
| 设备发现 | 插上 iPhone 后启动 App | ≤5s 显示设备名 |
| 窗口计算 | 拖入真实多日旅行文件夹 | 打印的 [start, end] 肉眼覆盖整次旅行 |
| 候选准确性 | iPhone 上人为准备 N 张旅行内 + M 张旅行外照片 | 候选列表数量 = N（允许 ±缓冲带来的边界波动） |
| Live Photo 配对 | 选一张 iPhone Live Photo 导入 | 目标目录同时出现 `IMG_xxxx.HEIC` 和 `IMG_xxxx.MOV`（通过 `sidecarFiles`，详见 §5 T3.2） |
| HEIC 完整性 | 导入后用 Preview 打开 + `exiftool` 对比 | 可正常显示，DateTimeOriginal 与原始一致 |
| 幂等 | 连续点两次"导入" | 第二次全部 skipped，文件 mtime 不变 |
| 失败恢复 | 导入中途拔 iPhone | 不 crash，剩余标 failed |
| 最终验收 | 真实旅行完整跑 | 漏选 ≤ 5%、多选 ≤ 10%（实际数据，可调） |

---

## 7. 编码规范

### Swift 风格

- 默认所有 UI 相关代码 `@MainActor`（项目级默认已开）
- Service 层用 `actor` 或显式 `nonisolated`，避免不必要的主线程阻塞
- ImageCaptureCore delegate 类用 `final class XxxDelegate: NSObject, ICDeviceBrowserDelegate`，并视情况 `@preconcurrency` 兼容
- 异步优先用 `async/await`，老式 callback API 包装成 async
- 错误用 `enum XxxError: Error`，不要 throw `NSError`

### 文件组织

- 一个 file 一个主类型（class/struct/enum）
- 同类型扩展放同 file 末尾
- View 文件不超过 300 行，超过就拆 subview

### 注释

- 默认不写注释。代码自说明。
- 唯一例外：**为什么**这么写而不是别的（API 行为坑、性能权衡、隐藏约束）

### 错误处理

- 用户可见错误必须有人话描述（"请解锁 iPhone"，不是 "ICError code 12"）
- 内部错误打 log（`os.Logger`），不要 fatalError

---

## 8. 当前状态 / 接手须知

> **本节是接手 AI 必读**。每次有 token 用尽切换、或长时间会话压缩前，应更新本节。

### 整体进度

| Phase | 状态 |
|---|---|
| 0 · 脚手架 | ✅ 3/3 完成 |
| 1 · iPhone USB | ✅ 3/3 完成 |
| 2 · 相机解析 | ✅ 4/4 完成 |
| 3 · 导入引擎 | ✅ 4/4 完成 |
| 4 · SwiftUI | ✅ 5/5 完成（含选项接入 + bug 修复） |
| 5 · 验收 | 0/3 |

### 下一步

**第一个待做任务：T5.1 · 真实旅行验收**

App 核心功能已全部实现并真机验证通过。Sidebar 选项已接入实际逻辑。下一步是用完整旅行数据跑端到端验收。

### 已完成的功能接入（2026-05-05）

- ✅ **只传送新文件**：`download(skipExisting:)` 控制跳过/覆盖
- ✅ **保留原 EXIF 时间**：下载后 `setFileDate(url, to: exifDate)` 同步文件系统时间
- ✅ **完成后退出**：alert 按钮变"完成并退出"，点击后 `NSApplication.shared.terminate`
- ✅ **选项持久化**：`@AppStorage` 存储，重启保留
- ❌ **删除 iPhone 原文件**：iOS PTP 不支持（`requestDeleteFiles` 返回 "Delete files failed"），功能已移除
- ❌ **自动断开设备**：`requestEjectOrDisconnect` 无效果，改为"完成后退出"

### 已修复的重要 bug（2026-05-05）

- ✅ PTP metadata sub-dict cast：`[AnyHashable: Any]` 不是 `[String: Any]`，导致所有 HEIC 的 EXIF 解析静默失败
- ✅ Swift `[String: Date?]` 陷阱：赋值 nil 删 key 而非存 nil。改用 `exifDates` + `exifFetched` 双数据结构
- ✅ 相机文件夹仅扫描 RAW 格式，排除后期导出文件（DNG/JPG/HEIC）的日期污染
- ✅ 视频文件跳过 EXIF 检查（PTP 不返回视频 EXIF），用 `creationDate`
- ✅ 缩略图加载超时 + 重试（5s timeout + 3 retries）
- ✅ DCIM 子文件夹重名文件去重

### 待还的技术债

- `device(_:didReceiveStatusInformation:)` 的 dict key 类型 warning 仍在，留作 no-op，不影响功能
- 性能：>1000 候选照片时的 EXIF metadata 批量请求可能较慢（当前顺序请求），可改为 TaskGroup 并发

### 已知问题 / 开放问题

- PTP metadata 格式依赖 macOS 26 行为，未来版本可能变化
- 首次运行时系统可能弹出"图像捕捉"权限弹窗
- 视频日期用 `creationDate`（文件系统日期），可能不如 EXIF 精确，但视频文件通常不被编辑器修改日期

### 接手 checklist

1. 读完 §1–§4 + §8（本节）
2. 跑 `xcodebuild -scheme SideRoll build` 确认当前能 build
3. 找到第一个 `TODO` 任务（T5.1），把它标 `IN_PROGRESS`
4. 完成后标 `DONE` + 日期 + commit hash（如已 git）
5. 更新 §8 整体进度表

### 与用户沟通的边界

用户已在 §2 锁定关键决策。**未经用户同意不要改：**

- 不要默认加 HEIC→JPG 转换
- 不要默认加时间戳前缀重命名
- 不要换走 USB 路径（比如改用 Photos 图库）
- 不要把 SwiftUI 拆成多 target / 引入大型依赖（如 RxSwift、SnapKit）

如遇到这些场景认为有必要打破约束，**先停下来问用户**，不要默默改。

---

**最后更新**：2026-05-05 by Antigravity (选项接入 + EXIF/日期 bug 修复)
