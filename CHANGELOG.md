# Changelog

All notable changes to SideRoll are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1] — 2026-05-08

### Added
- **Manual time window mode** — pick the import range yourself instead of deriving it from camera EXIF. Useful for iPhone-only trips, days when the camera clock was wrong, or pulling a single segment out of a multi-day trip.
- Four quick presets — **Today / Yesterday / Last 7 days / Custom** — with mode choice persisted across launches via `@AppStorage`.
- Custom mode opens two compact `DatePicker`s with start-before-end validation.

### Changed
- Time window UI redesigned with an **Auto / Manual** segmented picker in the section header. The two modes now have matched visual weight (the previous oversized "±2 hours" text is gone).
- Sidebar restructured: camera folder + target subfolder merged into one section; **options pinned to the sidebar bottom**, following the standard macOS sidebar convention.
- `ContentView` slimmed from 358 to 307 lines by extracting `ImportCoordinator`.

### Internal
- New `ManualWindowPreset` enum encapsulates window resolution (single source of truth, used by both UI and `ContentView.timeWindow`).
- 10 new localization keys covering both modes, EN + 中文.

## [1.0] — 2026-05-06

First public release.

### Highlights
- USB-direct iPhone reading via `ImageCaptureCore` (no iCloud dependency).
- Time-window candidate matching from camera EXIF `DateTimeOriginal`, with a configurable buffer.
- Full Live Photo support — `.HEIC` + `.MOV` companion imported together via `ICCameraFile.sidecarFiles`.
- ProRAW de-duplication: when both `.DNG` and a paired `.JPG` / `.HEIC` (including `IMG_E*` edited variants) are present, only the `.DNG` is shown for import.
- Already-imported files automatically dimmed and deselected.
- Double-click to preview the full-resolution original in a lightbox.
- Bilingual UI (EN / 中文) with instant switching, persisted via `@AppStorage`.
- 11 camera RAW formats supported with fallback to top-level JPG/HEIC/DNG/TIFF when no RAW is present.
- Forced Dark Mode for a consistent visual workflow.
- Ad-hoc signed DMG distribution with drag-to-install layout.
