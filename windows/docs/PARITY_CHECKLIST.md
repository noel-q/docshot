# Windows Parity Checklist

One page, written for Codex and Antigravity to test against directly. This is a **behaviour
contract**, not a UI brief — nothing here says "make it look like the Mac app." Source: guidance
from the macOS team, 2026-07-28. Required reading alongside this file:
[`docs/RECORDING_ARCHITECTURE.md`](../../docs/RECORDING_ARCHITECTURE.md`),
[`docs/VIDEO_EDITOR_ARCHITECTURE.md`](../../docs/VIDEO_EDITOR_ARCHITECTURE.md),
[`docs/DEVICE_VERIFICATION.md`](../../docs/DEVICE_VERIFICATION.md).

## The three items most likely to diverge

Don't sign off a milestone that touches these without an explicit pass on all three:

1. **Self-audio exclusion.** External audio is captured; DocShot's own alerts/beeps are not. See
   §2 below — this is now flagged as its own risk spike, not something to assume works because
   WASAPI loopback works.
2. **Safe cleanup.** No orphaned temp files across crash/quit/cancel paths, and DocShot never
   deletes a user-selected destination — see §1.
3. **Annotation coordinate/time mapping.** An annotation drawn on frame N stays on frame N through
   trim, split, and reorder. See §4 — the Core model already enforces this by construction, but
   any Platform/App code that bypasses the model (e.g. hand-rolled hit-testing) can reintroduce
   drift.

## 1. Product rules (non-negotiable, ported as-is from macOS)

- **Local-only capture.** No network calls in the capture/recording/export path. Nothing leaves
  the machine unless the user explicitly shares a file afterwards through Windows itself.
- **Explicit save/discard.** Every capture and recording ends at a user decision, never an
  automatic save, an automatic upload, or a silently-retained history.
- **No silent history.** DocShot does not keep a gallery, a "recent captures" list, or any
  persisted record of what was captured, beyond the one temporary file the user is actively
  editing.
- **MP4 first.** Recording output is MP4 (H.264 + AAC where audio is on); GIF is an explicit
  export step from a finished MP4, never a live-capture format.
- **Audio off by default.** `RecordingAudioMode.None` is the default in `RecordingOptions` —
  confirm the App's recording-confirmation UI doesn't quietly flip this.
- **GIF guardrails.** ≤15 seconds, ≤10 MB, ≤960px, ≤10fps, silent (see `GifProfile.DocShotDefault`
  in `DocShot.Core`). Exceeding any guard falls back to keeping the MP4 — never a truncated or
  corrupted GIF, and never an orphaned GIF temp file on failure.
- **Never delete a user-selected destination.** Once the user has picked a save path via the
  native Save dialog, DocShot only ever writes to it — it doesn't overwrite, move, or clean up
  anything at that path on a later run.

## 2. Self-audio exclusion — new risk, treat as urgent

macOS's `ScreenCaptureKit` has a first-class "exclude this app's own audio" capture option.
**Windows WASAPI loopback has no equivalent primitive on general availability APIs** — the
process-exclusive/process-loopback capture surface that would do this (`AUDIOCLIENT_ACTIVATION_
PARAMS` with `PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE`) exists on modern Windows 10/11
but was **not** part of what PR #6's WASAPI spike exercised — that spike proved loopback capture
and Media Foundation muxing work, not self-exclusion specifically.

**Required acceptance test before claiming R3/W4 parity:** play an external audio source (e.g. a
YouTube video) while recording with system audio on, and trigger a DocShot alert/beep during the
recording. Pass condition: the external audio is present in the output, DocShot's own alert is
not. Do not mark W4 done without this test passing. If process-exclusive loopback isn't reliably
available (older Windows builds, or API gaps), the fallback is muting/suppressing DocShot's own
alert sounds during an active recording — document whichever approach is used and why in
`RECORDING_ARCHITECTURE.md`'s Windows notes.

## 3. Architecture separation

Keep capture, audio, encoding, export, and editor models behind interfaces — this is already how
`DocShot.Core.Services` is structured (`IScreenCaptureService`, `IRecordingSession`,
`IMovieSaving`, `IGifExporting`, `IPasteboardWriter`/`IFileWriter`) and should stay that way as
Platform's real implementations land. No Win32/WinRT/WGC/WASAPI type should ever appear in a
`DocShot.Core` signature.

- Capture: **Windows.Graphics.Capture** for window/display capture.
- System audio: **WASAPI loopback** (see §2 for the self-exclusion caveat).
- Hotkey: **`RegisterHotKey`** on a message-only window, `WM_HOTKEY` dispatch. **Do not use a
  low-level keyboard hook** (`SetWindowsHookEx` with `WH_KEYBOARD_LL`) to implement the shortcut —
  it's a wider-reaching, higher-risk API for a job `RegisterHotKey` already does, and it's exactly
  the kind of thing that gets a utility app flagged by security software. Surface a clear
  conflict/failure state when registration fails (another app already owns that combination) —
  don't fail silently.

References: [Windows Graphics Capture](https://learn.microsoft.com/en-us/windows/uwp/audio-video-camera/screen-capture),
[WASAPI loopback recording](https://learn.microsoft.com/en-us/windows/win32/coreaudio/loopback-recording),
[RegisterHotKey](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey).

## 4. Editor data model — portability audit (2026-07-28, Claude)

Checked `DocShot.Core.Models.VideoProject`/`VideoSegment`/`VideoAnnotation`/`AnnotationItem`
against the macOS source (`Sources/DocShot/Models/VideoProject.swift`,
`Sources/DocShot/Services/VideoProjectExportService.swift`). Result: **compatible, no gaps that
block W1/W6.**

- **Annotation type** — `AnnotationShape` closed hierarchy (Arrow/Rectangle/Ellipse/Text/
  Highlighter/Redaction), matches the Swift `enum` case-for-case.
- **Coordinates** — plain `PointD`/`RectD`, consistent with the macOS source-pixel convention;
  whichever concrete space Platform captures in, don't let App silently introduce a second,
  normalized convention on top without updating this note.
- **Source time range, not timeline time** — `VideoAnnotation.SourceRange` is anchored to source
  time exactly like the Mac model, which is *why* an annotation survives a trim/split/reorder
  without drifting onto the wrong frames. This is the mechanism behind checklist item 3 above —
  don't bypass it.
- **Segment ID** — `VideoSegment.Id` / `VideoAnnotation.SegmentId`, same scoping semantics
  (deleting a segment deletes its annotations).
- **Trim/split semantics** — `VideoProject.Trim`/`Split` ported method-for-method, including the
  "leading half keeps the original segment's identity" rule and annotation re-clipping on both
  halves.
- **Export result** — macOS's `VideoProjectExporting.export(...)` returns a `TemporaryRecording`
  on success (already in `DocShot.Core`) and throws `VideoProjectExportError` on failure. Most of
  those error cases (`sourceUnreadable`, `compositionFailed`, `exportFailed`) are genuinely
  encoder-specific and correctly belong in `DocShot.Platform`, not `DocShot.Core` — only
  `emptyTimeline` is pure validation Core could pre-empt cheaply. Not built yet; flagged as a
  small fast-follow in `WORKSTREAMS.md`, not a blocker.

## 5. User-visible settings (match behaviour, not macOS's UI)

- System audio on/off
- Cursor visibility
- Frame rate
- Recording shortcut (with the conflict/failure state from §3)
- Output choice / GIF eligibility
- Clear permission and failure messages — Windows has no TCC-style prompt, so "permission" mostly
  reduces to hotkey-registration failure and capture-target-unavailable states; word these
  honestly rather than reusing macOS's permission copy verbatim.

`DocShot.Core.Models.RecordingOptions` already carries `Audio`, `ShowsCursor`, and
`MaximumFrameRate` — the settings UI's job is to expose exactly these, not invent new ones.

## 6. Distribution path — open decision, not yet made

Two options, not decided yet:

- **ZIP.** Easiest to ship today. Triggers Windows SmartScreen on an unrecognised publisher —
  acceptable for internal/early testing (an explicit "Run anyway" click, matching W7's existing
  gate), not for public distribution.
- **MSIX / App Installer.** Better install/update experience, but warning-free installation still
  needs a trusted code-signing certificate and enough reputation to clear SmartScreen — a cost/
  timeline decision, not an engineering one.

Recommendation: ship W7 as ZIP first (matches the existing gate — "a zip a second machine can run
after an explicit Run anyway"), revisit MSIX once there's a signing certificate story. Flag to
Noel if that assumption is wrong.
