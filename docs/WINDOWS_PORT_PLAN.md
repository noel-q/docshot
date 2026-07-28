# DocShot Windows Port — Plan

Status: proposed, not yet started. Written for three builders working from the same brief:
Claude (this assistant), Codex, and Google Antigravity. Each has a different real environment
(see "Who does what" below) — the plan is split along those lines, not arbitrarily.

This plan assumes the reader has **not** read the macOS repo. It restates what's being ported,
proposes the Windows equivalent of every macOS-only API the app depends on, lays out a `.NET`
solution shape that mirrors the existing testability split, and sequences the work in the same
staged, gated order the macOS build used (each milestone must pass before the next starts —
that discipline is why the macOS app has almost no untested state-machine edge cases, and it's
worth carrying over rather than rewriting from a clean slate).

---

## 1. What's being ported

DocShot is a menu-bar screenshot/recording/annotation utility. On macOS it is Swift 6 +
SwiftUI/AppKit + ScreenCaptureKit + AVFoundation, deliberately native with no Electron, browser
runtime, backend, accounts, telemetry, or cloud upload. That product policy carries over to
Windows unchanged — it's not platform-specific, it's the product.

Feature set to reach parity on, in the order the macOS app built it (see §4 for why the order
matters):

1. **Screenshots (shipped on macOS):** global hotkey → full-screen overlay → hover-detect a
   window or drag a region → annotate (select/move, arrow, rectangle, ellipse, text, freehand
   highlighter, blur/pixelate redaction, crop, undo/redo) → Copy PNG / Save via native dialog /
   Discard. Multi-display and per-monitor scaling must land pixel-accurate. Also: a colour
   picker with live Hex/RGB/HSL readout and a drag-only magnifier loupe.
2. **Recording R1 (shipped):** select window/region → Record/Cancel confirm → record → Stop →
   Save MP4 (via native dialog) / Discard. Video-only, no audio, one MP4 writer per session,
   temp-file lifecycle that survives crashes/quits with no orphans.
3. **Recording R2 (shipped):** persistent status HUD with elapsed time and a Stop control that
   isn't itself captured; interruption hardening (sleep, display disconnect, permission loss).
4. **Recording R3 (shipped):** opt-in system audio and microphone, off by default, each gated on
   its own permission/availability check with an explained-not-hidden unavailable state.
5. **Recording R4 (shipped):** GIF export from a *finished* MP4 only — 10 fps, ≤960px long edge,
   ≤15s clips, 10 MB encoded-size guard, silent, MP4 fallback if the guard is missed.
6. **Video editor core (shipped, model + export service only, no UI yet on macOS either):**
   non-destructive trim/split/reorder/delete of segments, annotations anchored to source time
   and scoped to a segment, snapshot-based undo, export via composition + per-frame overlay pass.

Everything here is local-only. No feature on this list gets a cloud/account/telemetry dimension
added during the port — if that changes, it's a separate product decision, not something either
of us should infer from "well Windows apps usually have one."

---

## 2. Platform API mapping

This is the load-bearing table. Every row is a macOS API DocShot depends on and the Windows
equivalent, with the parity risk called out where it isn't a clean 1:1.

| Concern | macOS (current) | Windows equivalent | Notes / risk |
|---|---|---|---|
| App lifecycle / menu bar | `MenuBarExtra` + settings window | `NotifyIcon` tray icon (via a small WPF-friendly wrapper, e.g. `H.NotifyIcon.Wpf`) + a normal WPF `Window` for settings | Low risk, well trodden. |
| Global hotkey | Carbon `RegisterEventHotKey` | Win32 `RegisterHotKey`/`UnregisterHotKey` on a hidden `HwndSource` message-only window, handling `WM_HOTKEY` | Direct equivalent, ~1:1 with `HotkeyService`. |
| Screen-capture permission | `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`, explained in onboarding UI | **No equivalent gate exists for a Win32 desktop app.** `Windows.Graphics.Capture` shows a one-time OS picker only if you use `GraphicsCapturePicker`; capturing a window/monitor you already have a handle/ID for needs no runtime consent at all. | This *simplifies* the port — `PermissionService`/onboarding shrinks to "is the OS new enough" rather than a TCC dance. Don't invent a permission screen that doesn't need to exist. |
| Window discovery | `CGWindowListCopyWindowInfo`, filtered by layer/alpha/owner/size, excluding DocShot's own PID | `EnumWindows` + `GetWindowRect` + `IsWindowVisible` + `GetWindowThreadProcessId` (exclude own PID) + `DwmGetWindowAttribute(DWMWA_CLOAKED)` to drop cloaked/virtual-desktop windows + a title/class denylist for shell surfaces (`Progman`, `Shell_TrayWnd`, etc.) | `DWMWA_CLOAKED` is the one macOS doesn't need an equivalent for — Windows will otherwise offer invisible UWP suspended windows as capture targets. |
| Still capture | ScreenCaptureKit `SCScreenshotManager`, GDI fallback only if needed | `Windows.Graphics.Capture` (`GraphicsCaptureItem.CreateFromWindowId`/`CreateFromMonitorId`, single frame from a `Direct3D11CaptureFramePool`) preferred; GDI `BitBlt`/`PrintWindow` fallback for pre-1903 or when WGC can't target a specific window | WGC is the honest equivalent of ScreenCaptureKit (composited, DPI-correct, works on hardware-accelerated/UWP content). Pure GDI `BitBlt` silently returns black for some modern-rendered windows — don't let it become the primary path. |
| Recording capture | ScreenCaptureKit `SCStream` | `Windows.Graphics.Capture` `Direct3D11CaptureFramePool` streaming frames | Direct equivalent for video. **Audio is the divergence** — see next row. |
| System/mic audio during recording | `SCStreamConfiguration.capturesAudio` — same stream API as video, one timestamp domain | **No audio in WGC at all.** System audio needs a parallel WASAPI loopback capture client; microphone needs a separate WASAPI capture client. Both must be muxed into the same `SinkWriter` on a shared clock. | This is the single biggest architecture divergence from macOS — flagged again in §5. Treat it as its own spike before promising R3/R4 timelines. |
| MP4 encode/write | AVFoundation `AVAssetWriter`, H.264 High profile | Media Foundation `IMFSinkWriter` (H.264, same encode concerns: bitrate/keyframe interval/profile) | Native OS encoder, no licensing question, no external binary — matches macOS's "no bundled codec" posture. Accessed via COM interop; see §5 on how thin to make that layer. |
| Clipboard PNG | `NSPasteboard.setData(_:forType:.png)`, single canonical representation | `Clipboard.SetDataObject` writing **both** the registered `"PNG"` clipboard format (for alpha-preserving consumers like Slack/Discord) and a CF_DIB/CF_BITMAP fallback (for consumers that only read legacy bitmap formats) | Known Windows gotcha: there's no built-in "PNG" clipboard format constant, it must be registered via `RegisterClipboardFormat("PNG")`. Get this wrong and pasted screenshots either lose transparency or don't paste into some apps at all. |
| Save dialog | `NSSavePanel` | `Microsoft.Win32.SaveFileDialog` (or `CommonSaveFileDialog` from `WindowsAPICodePack` if the modern IFileSaveDialog look matters) | Direct equivalent. |
| Borderless capture overlay, one per display | Transparent `NSPanel` above each screen | `WindowStyle="None"`, `AllowsTransparency="True"`, `Topmost="True"` WPF windows positioned via `EnumDisplayMonitors` | **Second-biggest risk.** WPF's historical per-monitor DPI handling is the platform's worst-trodden path for exactly this scenario (mixed-DPI multi-monitor). Needs an early, isolated spike — see §5. |
| Annotation canvas + flattened render | SwiftUI canvas/view model, `ImageRenderer` | WPF `Canvas` + MVVM view model; flatten via **SkiaSharp** rather than raw WPF `DrawingVisual` | SkiaSharp gives a near 1:1 mapping for blur (`SKImageFilter.CreateBlur`) and pixelate (downsample+upscale) redactions, matching the Core Image filters used on macOS, and the same rendering code can later back GIF/video-frame compositing. |
| GIF export | ImageIO, 10 fps / ≤960px / ≤15s / 10 MB guard | `System.Windows.Media.Imaging.GifBitmapEncoder` (built into WPF, no extra dependency) | This is a genuinely clean parity find — WIC's `GifBitmapEncoder` is the direct platform equivalent of ImageIO's GIF writer. Same guardrails, same "no audio, ever" rule. |
| Local settings persistence | `UserDefaults` | `System.Text.Json`-serialised settings file in `%LOCALAPPDATA%\DocShot`, or `Microsoft.Win32` registry under `HKCU\Software\DocShot` | Prefer the JSON file: easier to inspect/test, easier to wipe in dev, no registry-permission surprises. |
| Temp-file lifecycle | `NSTemporaryDirectory()/DocShot-Recordings`, swept at launch and every terminal path | `%TEMP%\DocShot-Recordings`, same sweep policy | Direct equivalent. |
| Dev packaging | Ad-hoc Apple-Development-signed `.zip`, explicitly not notarised | Unsigned (or self-signed) portable `.zip`/folder for local testing; note it will trigger SmartScreen the same way an unnotarised mac build triggers Gatekeeper | Same caveat, same reason: internal testing doesn't need a paid cert yet. Authenticode signing is a distribution-time decision, out of scope here. |

---

## 3. Proposed architecture

Mirror the macOS split, not because it's macOS's idea but because `.NET` makes the same split
*cheaper* than Swift did: macOS needed a hand-maintained "hostless Xcode test target subset"
(`Tests/target-parity.json` + `Scripts/audit-test-parity.sh`) to keep pure logic separately
testable from AppKit/`SCStream`-owning code, because Xcode's test bundle either links the whole
app or none of it. `.NET` gets that separation for free from project references: a
`net8.0`-plain library can't accidentally reference WPF or Win32 types, the compiler enforces it,
and nothing needs an audit script.

Proposed repo layout, as a `windows/` folder alongside the existing `docshot/` macOS folder:

```text
windows/
  DocShot.sln
  src/
    DocShot.Core/              # net8.0, zero WPF/Win32 references
      Models/                  # Annotation, AnnotationTool, CaptureState, RecordingTarget,
                                # RecordingOptions, RecordingState, RecordingStateReducer,
                                # VideoProject, VideoTimeRange, ExportSize, DisplayGeometry,
                                # PixelSampler, ColorSample, WindowInfo, TemporaryRecording, ...
      Services/                # interfaces only: IPasteboardWriter, IFileWriter,
                                # IRecordingSession, ITemporaryRecordingStore, IGifExporter,
                                # IHotkeyService, IWindowDiscoveryService, IScreenCaptureService
    DocShot.Platform/          # net8.0-windows, Win32/WinRT interop implementations of the
                                # Core interfaces — RegisterHotKey wrapper, EnumWindows wrapper,
                                # WGC capture, Media Foundation sink writer, WASAPI loopback,
                                # clipboard PNG writer, SaveFileDialog wrapper
    DocShot.App/                # net8.0-windows WPF app: tray icon, overlay windows, canvas
                                # editor, recording HUD, settings window, DesignTokens-equivalent
                                # style resources
  tests/
    DocShot.Core.Tests/        # xUnit. Builds and runs anywhere, including this Linux sandbox —
                                # no Windows machine needed to prove the model/reducer logic.
  docs/
    WINDOWS_TECHNICAL_BRIEF.md
    WINDOWS_RECORDING_ARCHITECTURE.md
    WINDOWS_TEST_ARCHITECTURE.md
    WINDOWS_DEVICE_VERIFICATION.md
  Scripts/
    package-development-build.ps1   # equivalent of package-development-app.sh
```

`DocShot.Core` is where nearly every macOS "duplicated production source" in
`Tests/target-parity.json` lands — that list is effectively the ready-made spec for what belongs
in the platform-neutral layer. `DocShot.App`'s app-only equivalents (coordinators, overlay
windows, live capture sessions) map to the macOS `appOnlyProductionSources` list the same way.

**One policy amendment to flag, not silently adopt:** the macOS technical brief says "avoid
third-party dependencies unless they remove a clearly demonstrated platform limitation." Worth
keeping as the default, but Windows Media Foundation and WGC are COM/WinRT APIs that are painful
to call raw from C#. Recommend allowing exactly two dependency categories, both effectively
Microsoft's own surface rather than third-party risk: (1) `CsWinRT` projections for
`Windows.Graphics.Capture` types, and (2) `CommunityToolkit.Mvvm` for `ObservableObject`/`ICommand`
boilerplate. Everything else (hotkeys, window enumeration, clipboard, save dialog) is cheap enough
to P/Invoke directly and should stay dependency-free.

---

## 4. Milestones — staged, gated, same order as macOS

Same rule the macOS recording doc states explicitly and that's worth restating here: **do not
start a milestone while its predecessor has failing automated or manual acceptance checks.**

| # | Milestone | Mirrors | Gate to move on |
|---|---|---|---|
| W0 | Risk spikes (§5) — prove the four unknowns before committing UI work on top of them | — | All four spikes have a working, throwaway console/WPF-shell proof |
| W1 | Screenshot capture + annotation + output, full parity | macOS V1 | Region/window select, all 7 annotation tools, undo/redo, Copy/Save/Discard, multi-monitor + mixed-DPI correctness, colour picker + magnifier, configurable global hotkey |
| W2 | Recording, video-only MP4 | R1 | Start/stop/save/discard lifecycle, no orphaned temp files across crash/quit/cancel paths, odd-dimension regions play back correctly |
| W3 | Recording status HUD + interruption hardening | R2 | HUD/Stop reachable and not itself captured; sleep, display-disconnect, and (Windows equivalent of) permission-loss all fail safely with no orphan file |
| W4 | Opt-in system + microphone audio | R3 | Audio off ⇒ zero audio tracks, ever; system audio excludes DocShot's own sounds; mic permission states (allow/deny/no device) each produce an explained state, not a silent failure |
| W5 | GIF export | R4 | ≤15s / 10 MB / 960px / 10fps / silent guardrails enforced exactly; over-guard always falls back to MP4 with no orphan GIF temp file |
| W6 | Video editor core (model + export, no timeline UI required yet — matches macOS's current state) | Video editor architecture | Trim/split/reorder/delete validated as all-or-nothing mutations, annotations stay anchored through edits, snapshot undo, export never mutates the source file |
| W7 | Dev packaging | package-development-app.sh | Unsigned portable build script producing a zip a second machine can run after an explicit "Run anyway" SmartScreen click |

---

## 5. Risk spikes to run before W1 (this is W0)

Four things were genuinely unproven on Windows and shouldn't be discovered mid-milestone. Status
as of 2026-07-28:

1. **Mixed-DPI multi-monitor overlay windows.** Borderless transparent WPF windows, one per
   monitor, each reporting pixel-accurate selection coordinates when monitors have different
   scale factors (100%/125%/150%/200% mixes are common). This is WPF's worst-documented corner.
   **In progress** — Antigravity implemented the spike plus an actual App tray/settings shell on
   `windows/app-dpi-overlay-shell` (`DisplayMonitorHelper`, `OverlayWindowManager`,
   `OverlayWindow`, a `DpiRoundTripTests` suite). Findings not yet written up here; update this
   entry once they're reported.
2. **WGC still-frame and streaming capture against real windows**, including hardware-accelerated
   ones (browsers, other WPF/UWP apps) and DPI-scaled windows — pixel dimensions must match the
   selection exactly, odd dimensions included, never rounded. **Done** — [PR #6](https://github.com/noel-q/docshot/pull/6)
   validated against Edge, animated Chrome, a Calculator/UWP host, and Notepad: no black frames,
   exact odd-dimension crops (`101x99`). **New finding, not anticipated in this plan:** a static
   (non-animating) WGC capture target only emits its *initial* frames and then goes quiet — the
   real `IScreenCaptureService`/`IRecordingSession` implementation needs to handle that (e.g. a
   still-capture path can't just "wait for a frame," and a recording of a static window needs a
   forced-refresh or duplicate-last-frame strategy). Flag this for whoever implements R1 recording.
3. **WASAPI loopback + Media Foundation sink writer, synchronized on one clock.** This is the
   biggest architectural gap from macOS (§2). **Done** — PR #6 produced a playable MP4 (H.264 +
   AAC) with clean decode, 60.000s video against a 60.0275s container duration. **New finding:**
   loopback audio packets start arriving *after* the first video frame, so the writer needs
   explicit initial-silence handling rather than assuming audio and video begin together — a
   real, non-cosmetic difference from how the macOS `RecordingVideoWriter` anchors on "the first
   valid sample of either type" (see `RECORDING_ARCHITECTURE.md`'s R3 section in the macOS docs).
   Worth deciding during the real `DocShot.Platform` recording-session work, not by default.
4. **Clipboard PNG round-trip** into a transparency-aware consumer and a bitmap-only legacy
   consumer, proving both the registered `"PNG"` format and a CF_DIB fallback are needed and
   sufficient. **Partially done** — PR #6 confirmed both formats land on the clipboard correctly
   (registered `"PNG"` plus `CF_DIB`). Still open: real paste verification into a logged-in
   Slack/Discord session, which needs a human, not just a clipboard-format probe.

Spikes 2-4 are throwaway proofs at `windows/spikes/W0Platform` in PR #6 (Codex's worktree,
`docshot-platform-w0`) — not folded into `DocShot.Platform` yet, which still has no
`IWindowDiscoveryService`/`IScreenCaptureService`/`IRecordingSession` implementation. That's
correctly the next Platform-lane step now that the spikes have de-risked it.

---

## 6. Who does what

Not an arbitrary split — based on what each of the three can actually verify from where it runs.

**Claude (this session):** runs in a Linux sandbox with no Windows display. That's a real
constraint but it lines up cleanly with `DocShot.Core`: pure models, the recording state reducer,
video-project mutation logic, and their xUnit tests are designed to build and run with
`dotnet test` on any OS with a reachable .NET SDK — no Windows machine needed to prove that logic
is correct. **Correction after actually trying it:** *this specific sandbox* turned out to have no
reachable path to the .NET SDK at all (installer domains network-blocked, no root for
`apt-get install dotnet-sdk-8.0`), so the bootstrap commit's Core code is written and hand-reviewed
but not yet compiler-verified — see §7. The architectural claim still holds ("Core needs no
Windows machine, just a .NET SDK somewhere"); it just wasn't provable in this particular
environment that day — confirmed right afterwards when Antigravity built it for real; see §7.
Also best placed to keep architecture docs, the milestone/gate discipline, and
the platform-mapping table (§2) up to date as reality diverges from plan, since that's
read-and-reason-heavy work rather than click-and-observe work. Will not touch `DocShot.Platform` or
`DocShot.App` beyond scaffolding project files and interfaces, since neither can be run or visually
verified here.

**Codex:** best suited to `DocShot.Platform` — the P/Invoke and WinRT interop grind (hotkey
registration, `EnumWindows` filtering, WGC frame capture, Media Foundation sink writer, WASAPI
loopback, clipboard format registration). This is mechanical, tight edit-compile-run-against-real-
APIs work where a fast iteration loop matters more than visual judgement. Assumes Codex is run
from an environment with a Windows target (or WSL cross-compiling against Windows SDK headers) —
confirm that before assigning W0 spike 2 and 3 specifically, since both need a running capture
session to validate, not just a compile.

**Google Antigravity:** best suited to `DocShot.App` — the WPF shell, overlay windows, canvas
editor, recording HUD, settings UI — anything that needs to be *looked at* to know if it's right.
Mixed-DPI multi-monitor correctness (W0 spike 1) and general visual polish are squarely
Antigravity's job if it has an actual Windows machine with multiple/scaled displays to test
against, which is the one thing neither Claude nor (necessarily) Codex can verify. Also the
natural owner of a Windows equivalent of `docs/DEVICE_VERIFICATION.md` — manual, on-device
checklists per milestone.

**Cross-cutting:** whoever lands a change to `DocShot.Core` should not need Windows to prove it
works — if a Core change can only be verified by running the WPF app, it's in the wrong project.
That single rule is what keeps this three-way split from turning into a merge-conflict problem.

---

## 7. Status

`windows/` now exists in the repo with `DocShot.Core` and `DocShot.Core.Tests` scaffolded and a
first slice of models ported (the recording state reducer and the video-project editor core, both
fully pure Foundation-equivalent logic on macOS, plus `Annotation`, `ExportSize`, `ColorSample`,
`DisplayGeometry`'s pure subset, and the `DocShot.Core.Services` interface layer everything else
builds against). `DocShot.Platform` and `DocShot.App` are placeholder projects with a `README.md`
each, pointing at §9's workstream doc.

**Update: compiled and green.** It was written in a sandbox with no reachable path to the .NET SDK
(installer domains network-blocked, no root for `apt-get install dotnet-sdk-8.0`), so it went
unverified through the bootstrap commit. Antigravity built it for real on 2026-07-28: three C#
compiler errors, all record-property name collisions —
[`RgbaColor`](../windows/src/DocShot.Core/Models/Annotation.cs)'s positional parameters
(`Red`/`Green`/`Blue`/`Alpha`) collided with its own static swatch fields of the same names, and
several `RecordingEvent`/`RecordingState` nested records' positional `Session`/`Recording`
parameters hid the abstract base's same-named computed properties without the required `new`
keyword. Both are the same underlying lesson: **a sealed record nested inside a closed hierarchy
must not reuse a name already used by a static member or a base property in that hierarchy** —
worth remembering before porting the remaining models in §"Not yet ported" below. Fixed in
`ccf937e`; `dotnet test` now reports **67 passed, 0 failed** for `DocShot.Core.Tests`. Branch
pushed, [PR #5](https://github.com/noel-q/docshot/pull/5) open against `main`.

Full task breakdown per lane, including exactly what's ported vs. not yet, is in
[`windows/docs/WORKSTREAMS.md`](../windows/docs/WORKSTREAMS.md).

## 8. GitHub organisation

The repo is a single GitHub project, `noel-q/docshot`, already on its second real contributor
pattern: manual commits from Noel plus `codex/<slug>` branches merged to `main` through ordinary
GitHub PR merge commits. There's no CI configured today — verification is the manual
`swift test` / `xcodebuild test` / `audit-test-parity.sh` sequence in the macOS README, run and
reported by hand. Windows should extend this pattern, not replace it with a heavier one.

**Monorepo, not a second repo.** Keeping `windows/` inside `noel-q/docshot` alongside the existing
macOS layout keeps one issue tracker, one PR history, and one place for the docs that are already
product-wide rather than macOS-specific (`docs/PRODUCT_BRIEF.md`, `docs/BACKLOG.md`, and now this
file). A second repo would fragment all of that for no real benefit — the two platforms don't share
code today and aren't expected to.

**Branching:** `windows/core-<slug>`, `windows/platform-<slug>`, `windows/app-<slug>` — see
`windows/docs/WORKSTREAMS.md` §"Branch naming" for the full reasoning. All branches merge straight
to `main`; there's no risk to the shipped macOS app since nothing under `windows/` is referenced by
`DocShot.xcodeproj` or `Package.swift`.

**Docs placement:** cross-cutting, product-wide docs (this file, and any future one that talks
about both platforms) stay in the shared `docs/` folder at the repo root, next to
`PRODUCT_BRIEF.md`. Windows-implementation-specific docs (a future `WINDOWS_TECHNICAL_BRIEF.md`,
`WINDOWS_RECORDING_ARCHITECTURE.md`, `WINDOWS_DEVICE_VERIFICATION.md` — Windows equivalents of the
macOS docs living in `docshot/docs/`) belong under `windows/docs/` instead, mirroring how the macOS
implementation docs sit next to `Sources/`. `windows/docs/WORKSTREAMS.md` already follows that rule.

**CI:** the repo has none today for macOS either, so adding a heavy Windows pipeline first would be
backwards. One thing is genuinely free, though — `DocShot.Core.Tests` needs no Windows machine, so
a GitHub Actions job running `dotnet test` on `ubuntu-latest` for any PR touching `windows/src/DocShot.Core/**`
or `windows/tests/**` costs nothing and catches a real class of regression before a human looks at
the diff. That workflow (`.github/workflows/windows-core-tests.yml`) is included in this bootstrap.
Platform/App verification stays manual (device-verification notes in the PR description, per
`windows/docs/WORKSTREAMS.md` §"PR expectations") until there's a Windows runner worth paying for —
not a decision to make speculatively now.

**PR review:** with three agents plus Noel potentially committing on the same day, the lane
boundary (§6) is what actually prevents collisions, not process — a PR that only touches its own
project (`DocShot.Core`, `DocShot.Platform`, or `DocShot.App`) has nothing to conflict with a
same-day PR from another lane. A PR that touches more than one project's folder is worth a second
look before merging.

## 9. Local structure

The macOS checkout is unchanged: `DocShot.xcodeproj`, `Package.swift`, `Sources/`, `Tests/`,
`Scripts/`, `docs/` all stay exactly where they are at the repo root. `windows/` is the only
addition, laid out as in §3.

**For running up to three agents against one local clone without them fighting over the checked-out
branch, use `git worktree` rather than three full clones:**

```text
docshot/                    # main clone — macOS work, main branch, what Xcode opens
docshot-windows-core/       # git worktree add ../docshot-windows-core windows/core-<slug>
docshot-windows-platform/   # git worktree add ../docshot-windows-platform windows/platform-<slug>
docshot-windows-app/        # git worktree add ../docshot-windows-app windows/app-<slug>
```

Each worktree is a real, independent working directory — its own checked-out branch, its own
uncommitted changes — but they all share one `.git` object store, so there's no re-clone cost and
no risk of one agent's `git checkout` yanking the branch out from under another mid-edit. This
applies to whichever of Codex/Antigravity run locally on Noel's machine; this session works
directly in the mounted `windows/` folder inside the main checkout, on `windows/core-bootstrap`,
since it isn't a second local process competing for the same working directory.

**A caveat worth stating plainly:** this sandbox has no push credentials for `origin` (confirmed —
`git push --dry-run` fails with no way to authenticate). Everything committed here lands as local
commits in the mounted folder on Noel's machine, on branch `windows/core-bootstrap`, exactly as if
Noel had run `git commit` himself — but getting them onto GitHub is a `git push` Noel needs to run,
or something a future session could do directly if the GitHub connector gets authorised.
