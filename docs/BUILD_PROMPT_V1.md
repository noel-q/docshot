# Antigravity Build Prompt: DocShot V1

You are building inside the `docshot` repository. Read `README.md`, `docs/PRODUCT_BRIEF.md`, and `docs/TECHNICAL_BRIEF.md` in full before making changes. If documents conflict, the technical brief decides implementation and the product brief decides user behaviour.

Build the first usable macOS version of DocShot: a local-first screenshot capture and annotation utility. Do not implement recording or GIF/MP4 export **in this V1 milestone**; recording is a separately approved post-V1 milestone. Do not implement Windows support, cloud sharing, accounts, history, OCR, analytics, a backend, or a database.

## Technology constraints

- Native macOS application only.
- Swift 6, SwiftUI, AppKit where it is the correct system integration layer, ScreenCaptureKit and Quartz/Core Graphics.
- Target macOS 14+.
- Do not use Electron, Tauri, React, a webview, browser APIs, or a remote service.
- Keep dependencies at zero unless one has a concrete, unavoidable native limitation and is well maintained.

## Implement this vertical slice

1. A menu bar utility with a clear `Capture Screenshot` action and a configurable global hotkey. Choose a sensible default such as Command-Shift-5 only if it does not conflict unreliably with macOS; otherwise use Command-Shift-6 and make it clear in Settings.
2. On first capture, check Screen Recording permission. Explain why it is needed and send the user to system settings if access is not granted. Do not pretend capture can work without it.
3. A full-screen selection overlay over every connected display. Hover an eligible application window to highlight it. Click captures the window. Click-drag selects a rectangle instead. Escape cancels with no output.
4. Close/hide every overlay before taking the image so DocShot never captures itself.
5. Open an annotation editor with the captured image. Implement arrow, rectangle, ellipse, text, highlighter/freehand stroke, blur or pixelated redaction, crop, select/move, undo/redo and delete selection.
6. A restrained editor action bar: Copy, Save, Discard. Copy places a flattened PNG on the macOS clipboard. Save uses an `NSSavePanel` and defaults to PNG. Discard creates no file and writes nothing to the clipboard.
7. A minimal Settings screen for the hotkey and basic app information. Do not build preferences unrelated to V1.

## Interaction quality

- The app should feel calm, fast and deliberate, not like a generic AI dashboard.
- Use native macOS conventions: comfortable spacing, compact toolbar, clear hover/selection states, standard controls where they work well.
- The capture overlay and editor are the product. Prioritise their reliability and polish over menu-bar decoration.
- Correct mixed-display scale conversion is a requirement, not a later nice-to-have.
- Filter out desktop elements, invisible/tiny windows, system windows and all DocShot windows from smart selection.
- If reliable smart selection is blocked by a platform limitation, region selection must still be fully functional; document the limitation rather than inventing brittle behaviour.

## Engineering standards

- Create a clean Xcode project structure under source control.
- Prefer small focused types and clear state transitions over a large manager object.
- Keep capture, selection coordinates, annotations, editor state, clipboard and file saving separate.
- Make output explicit. There must be no auto-save, auto-copy or network upload anywhere in the app.
- Include unit tests for coordinate conversion, annotation mutations and undo/redo.
- Add a concise README section covering local build/run, permission setup, current scope and known limitations.

## Verification before hand-off

Run the clean build and tests. Then manually verify:

1. Region capture → add text/arrow → Copy → paste as an image.
2. Region capture → add redaction → Save → choose location → valid PNG exists.
3. Cancel during selection and discard in editor leave no file and do not replace clipboard contents.
4. Smart window selection does not select DocShot's own overlay/editor.
5. Permission-denied state is understandable and recoverable.

At hand-off, report the files created or changed, core design decisions, verification performed, known limitations and exact run instructions. Do not claim recording or Windows support is complete for V1. A later recording milestone is local-only: it starts with MP4, keeps audio Off by default, offers System Audio, Microphone, or Both only when available and permitted, and permits silent GIFs only at 15 seconds or less and under a clearly labelled, yet-to-be-finalised file-size guard.
