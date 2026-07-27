# DocShot V1: Native macOS Screenshot & Annotation Utility

DocShot is a fast, local-first macOS menu-bar screenshot capture and annotation utility built using Swift 6, SwiftUI, AppKit, and ScreenCaptureKit.

---

## Key Features & Scope

- **Menu Bar Utility**: Runs in the macOS menu bar with instant global hotkey access (`⌘⇧6` default, configurable in Settings, including a custom shortcut of up to three keys).
- **Smart Window & Region Capture**: Full-screen transparent overlay across all displays. Hovering detects and highlights individual application windows; click-dragging selects custom pixel-precise regions.
- **Multi-Display Compositing**: Exact `CGDirectDisplayID` matching per `NSScreen`. Multi-display region captures composite intersecting segments onto a unified canvas normalized to a single target output pixel scale.
- **Annotation & Redaction Editor**: Vector arrows, shapes, text, highlighters, CIFilter blur/pixelate redactions, crop, and single-transaction `UndoManager` (⌘Z / ⇧⌘Z).
- **Off-Main-Thread Render & Export**: Heavy image flattening, CIFilter processing, and PNG encoding run on background threads (`Task.detached`), keeping UI responsive.
- **Explicit Export Sizing**: Copy and Save support native, 50%, 200%, and aspect-locked custom PNG dimensions.
- **Explicit Output Controls**:
  - **Copy PNG (⌘C)**: Flattens to `NSPasteboard.general`.
  - **Save... (⌘S)**: Exports PNG via native `NSSavePanel`.
  - **Discard (Esc)**: Exits without touching clipboard or disk.
- **First-Launch Onboarding Guide**: Interactive multi-step guide explaining capture shortcuts, smart selection, annotation tools, and setup options.
- **Cursor Capture Preference**: Option to include the mouse cursor in ScreenCaptureKit screenshots (default: off).

### Post-V1 recording (R1: video-only MP4)

Screen recording ships as a separate, local-only capability alongside the screenshot workflow.
The first milestone (**R1**) is implemented and awaiting manual device verification:

- **Record Screen...** in the menu bar selects an eligible window or a region lying wholly
  within one display, then shows a compact **Record / Cancel** confirmation. No stream starts
  before Record.
- Capture uses a recording-specific ScreenCaptureKit pipeline and writes H.264 MP4 through
  `AVAssetWriter` to a private temporary file. Screenshot capture is untouched: recording adds
  no cases to `CaptureCoordinator`, `CaptureState`, or `ScreenCaptureService`.
- **Stop Recording** in the menu bar ends the take and opens an explicit **Save MP4 / Discard**
  choice. Nothing is saved, copied, retained, uploaded, or measured unless the user saves.
- Cancel, Discard, stream or writer failure, interruption, and quitting all remove the
  temporary media; DocShot's own temporary recordings folder is also swept at launch.
- R1 is video only: no audio, no GIF, no multi-display region, no webcam, no annotations.
  Video defaults are SDR, 30 fps maximum, the selected pixel dimensions preserved exactly, and
  the existing "include cursor" preference.

Later milestones add the persistent recording HUD and interruption hardening (R2), opt-in audio
(R3), and short GIF export (R4). See [docs/RECORDING_ARCHITECTURE.md](docs/RECORDING_ARCHITECTURE.md).

---

## Build & Test Instructions

### Requirements
- macOS 14.0+
- Xcode 16.0+ / Swift 6.0 toolchain

### Running Unit Tests
```bash
swift test
xcodebuild test -project DocShot.xcodeproj -scheme DocShot -destination 'platform=macOS'
```

### Building Locally

- **CLI Executable Binary**:
  ```bash
  swift build -c release
  # Binary produced at: .build/release/DocShot
  ```
  *Note*: `swift build -c release` produces a standalone command-line executable binary, which can be run directly from terminal or development environments.

- **Development app bundle**:
  1. Open `DocShot.xcodeproj` in Xcode.
  2. Select the `DocShot` scheme and run it on **My Mac**.
  3. Grant Screen Recording permission when macOS requests it.

### Distribution status

DocShot is currently signed for Apple Development only. A Developer ID Application certificate is not available, so notarisation and public macOS distribution are intentionally deferred. Do not describe a local build as notarised or publicly signed.

Private-beta ZIP/DMG packaging and the project licence remain decisions for the project owner.
