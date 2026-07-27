# DocShot Technical Brief

## Delivery choice

Build a native macOS app first using Swift 6, SwiftUI and AppKit where necessary. This is an interaction-heavy OS utility; native APIs are the shortest reliable path to global hotkeys, capture permissions, overlays, clipboard integration and correct multi-display behaviour.

Do not use Electron, a browser extension, a web app, a remote backend, or a database. Avoid third-party dependencies unless they remove a clearly demonstrated platform limitation.

Windows is a later native port. Keep product concepts and data structures platform-neutral, but do not create speculative cross-platform abstraction layers before the macOS workflow is proven.

## macOS platform capabilities

| Concern | Preferred approach |
| --- | --- |
| App lifecycle | SwiftUI `MenuBarExtra` plus a minimal settings window |
| Global hotkey | Carbon hotkey registration or a small, maintained native wrapper if required |
| Permission | `CGPreflightScreenCaptureAccess` and `CGRequestScreenCaptureAccess` with clear explanatory UI |
| Window discovery | `CGWindowListCopyWindowInfo`, filtering hidden, tiny, system and DocShot windows |
| Still capture | ScreenCaptureKit, using the selected `SCWindow` where possible; Core Graphics fallback only if necessary |
| Later recording | A recording-specific ScreenCaptureKit pipeline and state machine; AVFoundation/`AVAssetWriter` for local MP4 output |
| Selection UI | Borderless transparent AppKit `NSPanel`/`NSWindow` above each display, coordinated by one capture controller |
| Annotation | SwiftUI canvas/view model with serialisable annotation objects and a single flattened render pipeline |
| Clipboard | `NSPasteboard` using PNG data |
| Save | `NSSavePanel` with an explicit PNG destination |

## Architecture

Keep the first version compact and testable:

```text
DocShotApp
  AppState
  Capture
    CaptureCoordinator
    WindowDiscovery
    SelectionOverlay
    ScreenImageProvider
  Editor
    EditorViewModel
    CanvasView
    Annotation models
    ImageRenderer
  Platform
    HotkeyService
    PermissionService
    ClipboardService
    SavePanelService
  Settings
```

The capture flow is a small explicit state machine:

```text
idle → permissionRequired → selecting → capturing → editing → idle
                         └→ cancelled ───────────────────────→ idle
```

No capture should produce a file or clipboard write until the editor asks an output service to do so.

## Technical requirements

- macOS 14 Sonoma minimum, optimised for current macOS releases.
- Support one or more displays with different backing scales.
- Keep image coordinate transformations in one tested module. Never scatter scale-factor maths through views.
- Present human-readable errors for missing permission, failed capture, invalid selection and save failure.
- The overlay must close before capture so the overlay itself is absent from the image.
- Capture should avoid the cursor unless a later explicit preference adds it.
- All UI operations remain on the main actor; image rendering/export happens off the main thread where safe.
- Use no telemetry, network calls, backend, login, or persistence database.

## Quality gates

- Build cleanly with Xcode's standard build command.
- Unit-test annotation model mutations, undo/redo and coordinate conversion.
- Manually verify window and region capture on a Retina display and a mixed-scale external display if available.
- Verify Escape cancellation at selection and editor stages.
- Verify no file or clipboard entry exists after a cancelled capture.
- Verify copied PNG pastes into Preview, Messages/Slack equivalent, and a browser-based issue tracker.

## Scheduled post-V1 recording implementation

Recording is deliberately separate from the still-capture coordinator: use a recording-specific
state machine for selection, permission preflight, armed, recording, stopping, export choice,
cancelled, and failure. Use ScreenCaptureKit for window/display video and crop region
recordings in the pipeline. Write local MP4 first with AVFoundation/`AVAssetWriter`; do not add
GIF encoding until MP4 lifecycle, timing, interruption recovery, and explicit output are proven.

The audio setting defaults to **Off**. **System Audio**, **Microphone**, and **Both** are
selectable only when their distinct macOS permission and capture capabilities are available;
the UI must explain unavailable choices and record no unselected track. The exact ScreenCaptureKit
system-audio API and entitlement/permission behaviour must be prototyped before a delivery
promise is made.

GIF is silent and available only for clips of 15 seconds or less that satisfy a clearly labelled,
yet-to-be-finalised file-size guard; all other clips offer MP4. Stop must lead to an explicit
output choice. Cancel, denied permission, interruption, and failure must leave no silent save,
clipboard write, capture history, cloud upload, account, or analytics event.
