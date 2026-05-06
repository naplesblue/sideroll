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

## Continuous Integration

`.github/workflows/ci.yml` runs on every push to `main` and on PRs:

- `xcodebuild build` against the `SideRoll` scheme (Debug)
- `xcodebuild test -only-testing:SideRollTests/TimeWindowResolverTests` (the only stable unit test today)

If you add tests, register the new bundle in the workflow's `-only-testing` filter (or drop the filter once UI tests pass on macOS runners).

## Release Process

Releases are produced by `.github/workflows/release.yml`, which fires on any `v*` tag push.

### Cutting a release

1. Bump `MARKETING_VERSION` in `SideRoll.xcodeproj/project.pbxproj` if the version has changed
2. Commit any pending changes
3. Tag and push:
   ```bash
   git tag -a v0.1.0 -m "v0.1.0"
   git push origin v0.1.0
   ```
4. The workflow will:
   - Build a Release `.app`
   - Ad-hoc sign it (`codesign -s -`)
   - Bundle into `dist/SideRoll-<version>.dmg` via `hdiutil`
   - Compute a SHA256 sum
   - Create a GitHub Release with the DMG and `SHA256SUMS.txt` attached, auto-generated release notes from commits

### Building a DMG locally

```bash
scripts/build-dmg.sh           # version from MARKETING_VERSION
scripts/build-dmg.sh 0.2.0     # override version
```

Output: `dist/SideRoll-<version>.dmg` plus its SHA256 on stdout.

### Gatekeeper note

The DMG is **ad-hoc signed only**. First-time users will need to right-click → Open, or run:

```bash
xattr -dr com.apple.quarantine /Applications/SideRoll.app
```

For Gatekeeper-friendly distribution, enroll in Apple Developer Program ($99/yr) and replace the `codesign --sign -` step with a Developer ID certificate plus a notarization step.

## Recording the Demo GIF

`README.md` reserves an `assets/demo.gif` slot. Recording recipe:

1. Tool: [Kap](https://getkap.co/) or [CleanShot X](https://cleanshot.com/) — both export GIF directly. Or QuickTime → screen recording → convert with [Gifski](https://gif.ski/)
2. Resolution: 800–1000 px wide, 15–20 fps, ≤10 seconds total
3. Sequence to capture:
   - App window open with no folder picked (1s)
   - Click **选择文件夹** → pick a real trip folder (folder appears in sidebar with first/last time)
   - Wait for candidate grid to populate (1–2s — show the auto-fill happening)
   - Adjust the buffer slider (show window range updating)
   - Double-click a thumbnail to show preview overlay, ESC to dismiss
   - Click **开始传送**, show the progress bar finishing
   - Final state: 完成 alert dialog
4. Save as `assets/demo.gif`, commit, then uncomment the `![]()` line in both READMEs

Target: ≤2 MB for fast README rendering on slow connections.

## License

[MIT](LICENSE)
