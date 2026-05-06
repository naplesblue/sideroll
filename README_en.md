<p align="center">
  <img src="assets/icon.png" width="128" alt="SideRoll" />
</p>

<h1 align="center">SideRoll</h1>

<p align="center">
  <strong>English</strong> · <a href="README.md">中文</a>
</p>

<p align="center">
  <a href="https://github.com/naplesblue/sideroll/actions/workflows/ci.yml"><img src="https://github.com/naplesblue/sideroll/actions/workflows/ci.yml/badge.svg" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <img src="https://img.shields.io/badge/macOS-15.4%2B-lightgrey" alt="macOS 15.4+" />
</p>

**Import iPhone photos into your camera trip folders — automatically matched by shooting time.**

SideRoll is a macOS utility for photographers who shoot with a camera and use their iPhone as a supplement. After a trip, it finds iPhone photos taken during the same time period as your camera shots and copies them into the camera folder — no more hunting through Photos.app.

## Demo

![SideRoll demo](assets/demo.gif)

## How It Works

1. **Select a camera folder** — drag & drop or browse to your trip's RAW folder
2. **Auto time matching** — SideRoll reads EXIF dates from your camera files, builds a time window (± configurable buffer), and finds matching iPhone photos via USB
3. **Preview & select** — browse candidates with thumbnails, double-click to preview full resolution
4. **Import** — selected photos are copied to a subfolder (default: `iPhone/`) preserving original filenames and EXIF timestamps

## Features

- 📱 **USB direct connection** — reads iPhone via ImageCaptureCore (PTP), no iCloud dependency
- 🕐 **Smart time matching** — EXIF-based with adjustable ±buffer (default ±2 hours)
- 📸 **ProRAW support** — DNG files prioritized, paired JPG/HEIC automatically hidden
- 🎞️ **Live Photo support** — `.MOV` sidecar files imported alongside `.HEIC` via `sidecarFiles` API
- ✅ **Duplicate detection** — already-imported files dimmed and auto-deselected
- 🔍 **Full-res preview** — double-click any thumbnail for a lightbox view
- 🗂️ **RAW format fallback** — if no camera RAW found, scans top-level JPG/HEIC for time matching
- 🌙 **Dark mode** — designed for dark mode workflows
- 🌐 **Bilingual UI** — built-in EN/中文 toggle, instant switch

## System Requirements

- macOS 15.4+
- iPhone connected via USB cable
- iPhone must be unlocked for photo access

## Supported Camera RAW Formats

NEF/NRW (Nikon) · CR2/CR3/CRW (Canon) · ARW/SRF/SR2 (Sony) · RAF (Fujifilm) · ORF (Olympus/OM System) · RW2 (Panasonic) · PEF (Pentax) · RWL (Leica) · 3FR/FFF (Hasselblad) · IIQ (Phase One) · SRW (Samsung) · X3F (Sigma)

Fallback: JPG, HEIC, DNG, TIFF (when no RAW files found)

## Installation

### From Source

```bash
git clone https://github.com/naplesblue/sideroll.git
cd sideroll
xcodebuild build -scheme SideRoll -configuration Release -destination 'platform=macOS'
```

The built `.app` will be in `DerivedData/Build/Products/Release/`.

### Pre-built

Download the latest DMG from the [Releases](https://github.com/naplesblue/sideroll/releases) page.

### First Launch

SideRoll is ad-hoc signed (not notarized by Apple), so macOS Gatekeeper will block it on first open. Use either method below:

**Option A: Right-click to open (recommended)**

1. Open Finder and navigate to `Applications` (or wherever you placed SideRoll.app)
2. **Right-click** SideRoll.app → select **Open**
3. Click **Open** in the dialog — only needed once, after that you can double-click normally

**Option B: Remove quarantine via Terminal**

```bash
xattr -dr com.apple.quarantine /Applications/SideRoll.app
```

After running this, you can double-click to launch without any prompts.

## Usage Tips

- **iPhone not showing?** Make sure it's unlocked and you've tapped "Trust" on the iPhone when prompted
- **Buffer adjustment**: Use the sidebar slider to widen/narrow the time window. ±2h works well for most day trips; increase for multi-day trips
- **Subfolder name**: Editable in the sidebar — default is `iPhone`

## Known Limitations

- USB connection only (no wireless/iCloud)
- Single iPhone at a time
- PTP does not support deleting files from iPhone
- DNG thumbnails may not load via PTP — falls back to paired JPG/HEIC thumbnails
- Video EXIF not available via PTP — uses file creation date instead

## License

[MIT](LICENSE)
