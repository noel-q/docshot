# DocShot Product Brief

## Product summary

DocShot is a fast, private, macOS-first desktop capture utility. It lets people select a detected window or precise region, annotate a still before committing anything, and explicitly choose copy, save, or discard. Later, separately shipped macOS milestones may add local video and short GIF output.

It should feel as immediate as Lightshot, with ShareX-style window awareness, without the account, cloud-sharing, library-management, or documentation-tool overhead of established alternatives.

## Core problem

Current tools force an awkward compromise:

- Lightshot has the lightweight edit-in-place experience but is ageing and screenshot-only.
- ShareX has excellent selection intelligence but is Windows-only and feature-dense.
- Snagit and Zight are capable but heavier, paid or cloud-oriented.
- CleanShot X is excellent but macOS-only.

Users need a fast capture workflow that preserves control: decide what to capture, annotate it, then decide whether it should be copied, saved, or discarded.

## Target users

- Developers documenting bugs or implementations.
- QA, support, and solutions engineers preparing evidence for tickets.
- Product teams sharing concise visual feedback.
- Privacy-conscious people who do not want screenshots uploaded by default.

## Product principles

1. Selection first, output second.
2. Local-first by default and by design.
3. Fast enough to replace the operating system screenshot shortcut.
4. Deliberately small: no accounts, content feeds, cloud library, or social sharing.
5. Cross-platform product promise, staggered native delivery.

## V1: macOS screenshots

### Capture

- A configurable global shortcut opens an unobtrusive full-screen capture overlay.
- Hovering a visible external application window highlights that window.
- A left-click chooses the highlighted window.
- Click-drag creates a precise rectangular region instead.
- Escape cancels from every state without creating output.
- DocShot's own windows must not be selectable.
- Multi-display and Retina scaling must produce correctly aligned selections.

### Annotation canvas

- Opens after a window or region is selected and before any output action.
- Tools: select/move, arrow, rectangle, ellipse, text, freehand/highlight, blur or pixelated redaction, crop.
- Undo/redo, delete selected object, keyboard shortcuts, tooltips and clear selection state.
- Annotation objects remain editable until copy or save.

### Output

- Copy flattened PNG to the system clipboard.
- Save PNG through a native save dialog; never silently choose a destination.
- Discard closes the canvas without output.
- No cloud uploads, accounts, analytics, history library, or automatic files.

## Scheduled after V1

- Scrolling capture.
- OCR, AI features, integrations and sharing links.
- Windows delivery. It follows the validated macOS interaction model.

## Recording product contract

Recording is a separately approved, local-only post-V1 milestone. It uses the same
selection-first interaction: select a detected window or drag a region, then see a compact
confirmation control with Record and Cancel. The audio setting defaults to **Off** and offers
**System Audio**, **Microphone**, and **Both** only when the relevant permission and macOS
capture capability are available; unavailable choices must explain why.

Stopping opens an explicit export choice. MP4 is the baseline output. A GIF may be
exported only when the clip is 15 seconds or less and is under a clearly labelled,
yet-to-be-finalised file-size guard; otherwise offer MP4. GIF output contains no audio.
Cancellation, permission denial, interruption, and failure must not silently save a file or
leave capture history. Recording has no cloud upload, account, analytics, or automatic
clipboard write.

## Success criteria

The user can invoke DocShot, select a window or exact region, add an arrow and text, and copy or save it in a few seconds without leaving the app, creating an account, or producing unwanted files.
