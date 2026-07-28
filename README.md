# DocShot

<p align="center">
  <img src="Sources/DocShot/Resources/Assets.xcassets/AppIcon.appiconset/icon_1024x1024.png" alt="DocShot app icon" width="128">
</p>

<p align="center">
  A fast, local-first macOS utility for screenshots, recordings, and lightweight annotation.
</p>

<p align="center">
  <strong>Swift 6</strong> · <strong>SwiftUI</strong> · <strong>AppKit</strong> · <strong>ScreenCaptureKit</strong>
</p>

## What it does

DocShot lives in the menu bar and keeps the capture flow intentionally explicit: select exactly
what to capture, make any edits locally, then choose whether to copy, save, export, or discard.
It has no account, cloud upload, history library, analytics, or background sync.

### Screenshots

- Global capture shortcut: `⌘⇧6` by default, configurable in Settings.
- Detect an application window on hover or drag an exact region across displays.
- Add arrows, shapes, text, highlights, blur/pixelate redactions, crop, undo, and redo.
- Copy PNG, Save with a native panel, or Discard without touching disk or clipboard.
- Export at native, 50%, 200%, or a custom aspect-locked size.

### Screen recordings

- Start recording with `⌘⇧8` or the menu-bar action.
- Select a window or a single-display region, then explicitly confirm before the stream starts.
- Save H.264 MP4 locally, or discard the temporary take.
- System audio is opt-in and off by default; cursor capture has its own recording preference.
- Export a silent GIF for clips up to 15 seconds, at 10 fps and a 960 px maximum long edge. GIFs
  over 10 MB fall back to the MP4 flow.
- Edit a completed recording before export: trim, split, annotate, redact, and render a separate
  output while preserving the original MP4.

## Privacy by design

Everything happens on the Mac. Screen capture permission is used only for the selected capture
or recording. Output exists only after an explicit Copy or Save action; temporary recordings are
removed on cancel, discard, failure, quit, and next launch cleanup.

## Demo media

These are captured from the signed development build using a synthetic local document; no product
mockups or personal content are used.

### Recording controls

![DocShot recording settings](docs/media/menu-and-settings.png)

### Screenshot annotation

![DocShot screenshot editor](docs/media/screenshot-editor.png)

### Post-stop video editor

![DocShot video editor](docs/media/video-editor.png)

The repeatable capture checklist, including the optional 20–30 second walkthrough video, is in
[docs/README_MEDIA_CAPTURE.md](docs/README_MEDIA_CAPTURE.md).

## Run locally

### Requirements

- macOS 14 or later
- Xcode 16 or later / Swift 6

Open `DocShot.xcodeproj`, choose the **DocShot** scheme, run on **My Mac**, and grant Screen
Recording permission when macOS asks. The app is Apple Development-signed for local development;
it is not notarised or distributed as a public installer.

### Create a local test package

On a Mac with Xcode and the configured Apple Development signing identity, create a release-build
drag-to-Applications DMG with:

```bash
./Scripts/package-development-dmg.sh
```

The result is `dist/DocShot-macos-development.dmg`. Open it, drag **DocShot** to the Applications
shortcut, then eject the disk image. Testers do **not** need Xcode.

For a ZIP instead, use:

```bash
./Scripts/package-development-app.sh
```

The package is written to `dist/DocShot-macos-development.zip` and contains `DocShot.app`.
Both scripts refuse to overwrite an existing package and verify the app's code signature before
creating it. Use a fresh `dist/` directory or pass a custom output directory:

```bash
./Scripts/package-development-dmg.sh /path/to/output
./Scripts/package-development-app.sh /path/to/output
```

These are **development testing packages**, not public releases. They are signed with an Apple
Development identity and are not notarised. A recipient may need to use Finder's **Open** action to
accept macOS's warning. A DMG improves installation, but does not remove that warning. Avoid
redistributing either package as a production installer; warning-free public distribution requires
Developer ID signing, notarisation, and a release process that has not yet been added.

## Verify

```bash
swift test
xcodebuild test -project DocShot.xcodeproj -scheme DocShot -destination 'platform=macOS'
./Scripts/audit-test-parity.sh
```

The current suite covers the pure capture, recording, output, editor, cleanup, and timing logic
through both SwiftPM and Xcode test paths. Device-level checks are tracked in
[docs/DEVICE_VERIFICATION.md](docs/DEVICE_VERIFICATION.md).

## Architecture

- [Recording architecture](docs/RECORDING_ARCHITECTURE.md)
- [Video editor architecture](docs/VIDEO_EDITOR_ARCHITECTURE.md)
- [Test architecture](docs/TEST_ARCHITECTURE.md)
- [Product brief](docs/PRODUCT_BRIEF.md)

## Status

DocShot is an actively developed native macOS project. The screenshot workflow, MP4 recording,
opt-in system audio, bounded GIF export, and post-stop editor are implemented. A local development
package is supported; notarisation and public distribution remain deliberately out of scope.
