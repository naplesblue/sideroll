# Contributing to SideRoll

Thanks for your interest in contributing! This document covers the architecture and conventions you need to know.

## Architecture

### Data Flow

```
User selects camera folder (NSOpenPanel / drag & drop)
        ↓
CameraFolderScanner (ImageIO EXIF, camera RAW formats → fallback to top-level JPG/HEIC)
        ↓
TimeWindowResolver (first/last photo ± buffer) → Date range [start, end]
        ↓
DeviceBrowser (ICDeviceBrowser discovers iPhone via USB)
        ↓
PhotoEnumerator (enumerates ICCameraDevice.mediaFiles)
        ↓
EXIF date resolution (rough ±24h filter → requestMetadata → DateTimeOriginal)
        ↓
CandidateFilter (time window + ProRAW dedup with E-prefix matching)
        ↓
CandidateGridView (LazyVGrid thumbnails with DNG→JPG/HEIC fallback)
        ↓
ImportEngine (requestDownloadFile → target subfolder)
```

### Project Structure

```
SideRoll/
├── SideRollApp.swift          — App lifecycle + NSApplicationDelegateAdaptor
├── ContentView.swift          — Main layout: sidebar + grid + bottom bar + preview overlay
├── Models/
│   └── CameraPhoto.swift      — (URL, captureDate) pair
├── Services/
│   ├── DeviceBrowser.swift    — ICDeviceBrowser wrapper
│   ├── PhotoEnumerator.swift  — PTP session + mediaFiles + thumbnail/metadata continuations
│   ├── CandidateFilter.swift  — Time window filtering + ProRAW dedup
│   ├── CameraFolderScanner.swift — EXIF scanning with RAW→JPG fallback
│   ├── TimeWindowResolver.swift  — min/max date ± buffer
│   ├── ImportEngine.swift     — File download + skip/overwrite + date preservation
│   ├── LivePhotoPairing.swift — sidecarFiles expansion (.AAE excluded)
│   └── ThumbnailLoader.swift  — CGImage → NSImage wrapper
└── Views/
    ├── SidebarView.swift      — Folder picker + buffer slider + options
    ├── DeviceBar.swift        — iPhone status + battery
    ├── GridHeaderView.swift   — Candidate count + select/invert
    ├── CandidateGridView.swift — Thumbnail grid with fallback
    ├── BottomBar.swift        — Import button + progress
    ├── PreviewOverlay.swift   — Lightbox full-res preview
    └── Theme.swift            — Amber color + typography
```

### Key APIs

| Purpose | API |
|---|---|
| Device discovery | `ICDeviceBrowser` + `ICDeviceBrowserDelegate` |
| iPhone file list | `ICCameraDevice.mediaFiles: [ICCameraFile]` |
| Thumbnails | `ICCameraFile.requestThumbnail()` → delegate callback |
| EXIF metadata | `ICCameraItem.requestMetadata()` → `{Exif}.DateTimeOriginal` |
| File download | `ICCameraDevice.requestDownloadFile(_:options:downloadDelegate:didDownloadSelector:contextInfo:)` |
| Camera EXIF | `ImageIO`: `CGImageSourceCreateWithURL` → `kCGImagePropertyExifDateTimeOriginal` |

## Coding Conventions

### Swift Style

- Default actor isolation is `@MainActor` (project-level setting)
- Service layer uses `nonisolated` or explicit actor isolation
- ImageCaptureCore delegates use `nonisolated` methods with `Task { @MainActor in ... }` for state updates
- Async/await preferred; old callback APIs wrapped with `withCheckedThrowingContinuation`

### File Organization

- One primary type per file
- Extensions at the end of the same file
- View files should stay under ~300 lines; extract subviews when larger

### Error Handling

- User-facing errors must have human-readable messages
- Internal errors go to `print()` logs (future: `os.Logger`)
- Never `fatalError` in production paths

## Important Gotchas

- **PTP metadata sub-dict is `[AnyHashable: Any]`**, not `[String: Any]` — casting to the wrong type silently fails
- **`[String: Date?]` dictionary trap**: assigning `nil` deletes the key instead of storing nil. Use separate `Set<String>` to track fetched state
- **iPhone ProRAW naming**: edited exports use `IMG_E` prefix (e.g., `IMG_E1908.JPG` pairs with `IMG_1908.DNG`)
- **DNG thumbnails**: PTP support is unreliable for DNG. The fallback map must be built from `enumerator.availableFiles` (full list), not filtered candidates
- **Videos**: PTP doesn't return EXIF for video files. Use `creationDate` instead
- **DeviceBrowser/PhotoEnumerator**: Must be idempotent — window close/reopen must not create duplicate PTP sessions

## License

[MIT](LICENSE)
