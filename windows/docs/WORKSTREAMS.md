# Windows Workstreams

Three lanes, one per collaborator, matching the `windows/src/*` project split in
`docs/WINDOWS_PORT_PLAN.md` §3 and §6. Each lane maps to exactly one project, which is what keeps
three people/agents editing the same repo on the same day from colliding: if you're touching files
outside your project, check whether the work actually belongs in someone else's lane before
committing to it.

| Lane | Owner | Project | Verifiable from |
|---|---|---|---|
| Core | Claude | `DocShot.Core`, `DocShot.Core.Tests` | Anywhere with a .NET 8 SDK - no Windows display needed |
| Platform | Codex | `DocShot.Platform` | Needs a Windows target to actually run capture/hotkey/encoder code, though it compiles anywhere with the Windows SDK reachable |
| App | Antigravity | `DocShot.App` | Needs a real, ideally multi-monitor / mixed-DPI Windows machine |

## Status as of the bootstrap commit

`DocShot.Core` and `DocShot.Core.Tests` are scaffolded with a first real slice ported from the
macOS Swift source: `Annotation`/`AnnotationShape`/`AnnotationTool`, `CaptureState`,
`ColorSample`, `DisplayGeometry` (pure subset), `ExportSize`, `RecordingFailure`,
`RecordingOptions`/`RecordingAudioMode`/`GifProfile`, `RecordingTarget`/`RecordingTargetRejection`,
`RecordingState`/`RecordingEvent`/`RecordingEffect`/`RecordingStateReducer`, `TemporaryRecording`,
`VideoTimeRange`, `VideoProject`/`VideoSegment`/`VideoAnnotation`/`VideoProjectHistory`,
`VideoProjectError`, and `WindowInfo`, plus the `DocShot.Core.Services` interfaces every platform
implementation will need to satisfy. xUnit tests exist for the highest-value pieces: the full
`RecordingStateReducer` transition table, `VideoProject`'s mutation/undo semantics, `ExportSize`,
`ColorSample`, `DisplayGeometry`, and `AnnotationShape`.

**Update 2026-07-28: builds clean, 67/67 passing.** The bootstrap commit went unverified (the
sandbox that wrote it had no route to the .NET SDK). Antigravity ran the first real build, fixed
three record-property name collisions (see `docs/WINDOWS_PORT_PLAN.md` §7 for the exact pattern to
avoid when porting the remaining models below), pushed `windows/core-bootstrap`, and opened
[PR #5](https://github.com/noel-q/docshot/pull/5). `DocShot.Platform`/`DocShot.App` work can now
build against a Core that's actually known to compile, not just carefully reviewed.

**Update 2026-07-28 (second pass):** the rest of the pure model layer is now ported too -
`MagnifierGrid`, `DisplayDescriptor` (the pure half of macOS's `DisplaySnapshot.swift`),
`SnapshotPlan`, `RecordingRegionPlan`, and `CaptureActivityPolicy`, each with its own test file.
That's every macOS `duplicatedProductionSource` model except the genuinely image-dependent ones.

Not yet ported, and not expected to be — these need a concrete decoded-image/bitmap type, which is
a `DocShot.Platform` decision (SkiaSharp is the leading candidate; see
`docs/WINDOWS_PORT_PLAN.md` §2): the macOS `DisplaySnapshot` struct itself (image + descriptor -
`DisplayDescriptor` above is its portable half), and the image-sampling halves of `PixelSampler`
and `DisplayGeometry.CropImage`.

**Update 2026-07-28: Platform and App are no longer empty.** Codex opened
[PR #6](https://github.com/noel-q/docshot/pull/6) (`windows/platform-w0-spikes`, draft) — W0
spikes 2-4 (WGC capture, WASAPI+Media Foundation, clipboard PNG) run against real APIs, throwaway
proofs at `windows/spikes/W0Platform`, not yet folded into `DocShot.Platform` itself. Two genuine
new risks surfaced, not in the original plan: a static (non-animating) WGC capture target stops
emitting frames after its initial burst (needs a forced-refresh/duplicate-last-frame strategy),
and WASAPI loopback audio packets arrive *after* the first video frame (needs explicit
initial-silence handling in the sink writer). Both are flagged for whoever writes the real
`IRecordingSession` — see `docs/WINDOWS_PORT_PLAN.md` §5 for full detail.

Antigravity opened [PR #7](https://github.com/noel-q/docshot/pull/7)
(`windows/app-dpi-overlay-shell`) — W0 spike 1 done (`DisplayMonitorHelper`,
`OverlayWindowManager`, `OverlayWindow`, `DpiRoundTripTests`, 0.00px DIP↔physical round-trip error
across all tested scale factors) plus a real App shell: tray icon (`H.NotifyIcon.Wpf`), settings
window, `DocShot.App.Tests` project. Solution-wide `dotnet test` is now **100 passing, 0 failed**
(Core 93 + App 7).

## Branch naming

Continue the existing `codex/<slug>` convention visible in the repo's history
(`codex/development-package`, `codex/video-editor`, etc.) rather than inventing a new scheme, but
prefix by lane so ownership is legible from the branch list alone and collisions between three
concurrent agents are structurally unlikely:

- `windows/core-<slug>` - Claude
- `windows/platform-<slug>` - Codex
- `windows/app-<slug>` - Antigravity

All branches target `main` directly. There's no need for a staging/integration branch: nothing
under `windows/` is built or referenced by the macOS Xcode project, so merging Windows work carries
zero risk of breaking the shipped macOS app, whatever state it's in.

## Dependency order

`DocShot.Platform` and `DocShot.App` both consume `DocShot.Core`'s service interfaces
(`IRecordingSession`, `IWindowDiscoveryService`, `IHotkeyService`, etc.). Interface churn after
Platform/App have started building against them is exactly the kind of thing that turns three
parallel lanes into a merge headache, so:

1. **This bootstrap PR lands first.** Once `windows/core-bootstrap` is merged to `main`, the
   interface shapes in `DocShot.Core.Services` are the contract - changing one becomes a
   cross-lane conversation, not a unilateral edit.
2. Only then do Platform and App branches open. Both can start immediately after step 1 and run
   fully in parallel with each other - they don't share files.
3. Claude's Core lane continues in parallel too, but stays additive (porting the not-yet-ported
   models listed above, adding tests) rather than reshaping the service interfaces once Platform/
   App depend on them, unless a real gap forces it - in which case, flag it before changing the
   interface, not after.

## Task breakdown

### Core (Claude) - ongoing

- ~~Port the remaining pure models~~ — done: `MagnifierGrid`, `DisplayDescriptor`,
  `RecordingRegionPlan`, `SnapshotPlan`, `CaptureActivityPolicy` all landed with tests. Still
  unverified by a real `dotnet test` run as of this commit — same caveat as the bootstrap; check
  the PR before trusting it compiles.
- Decide and document where the image-sampling half of `PixelSampler`/`DisplayGeometry.CropImage`
  lives once Platform picks a bitmap library (almost certainly `DocShot.Platform`, since it needs
  a concrete decoded-image type Core deliberately doesn't depend on - see the doc comments in
  `Models/ColorSample.cs` and `Models/DisplayGeometry.cs`).
- Get `dotnet test` actually green somewhere real and fix whatever the first compile finds -
  treat this as the true "W0 bootstrap done" milestone, not this commit.
- Keep `docs/WINDOWS_PORT_PLAN.md` and this file honest as Platform/App reality diverges from plan.

### Platform (Codex) - W0 risk spikes, then W1-W2 groundwork

1. ~~**Risk spike:** WGC still-frame and streaming capture~~ — done, [PR #6](https://github.com/noel-q/docshot/pull/6).
2. ~~**Risk spike:** WASAPI loopback + Media Foundation sink writer~~ — done, PR #6. Two new
   risks flagged for the real implementation (see above): static-target frame starvation, audio
   initial-silence handling.
3. **Risk spike (partially done):** clipboard PNG round-trip - `"PNG"` format + `CF_DIB` fallback
   both verified landing on the clipboard in PR #6; real paste into a logged-in Slack/Discord
   session still needs a human, not just a format probe.
4. Implement `IWindowDiscoveryService` (`EnumWindows` + `DwmGetWindowAttribute(DWMWA_CLOAKED)` +
   shell-surface denylist), `IHotkeyService` (`RegisterHotKey`/`WM_HOTKEY` on a message-only
   window), `IScreenCaptureService` (still capture), and pick the bitmap type
   `CapturedImage.Bgra32Pixels` gets wrapped in for actual rendering (SkiaSharp is the leading
   candidate - see `docs/WINDOWS_PORT_PLAN.md` §2).
5. Implement `IRecordingSession`/`IRecordingSessionFactory` (video-only first, matching the macOS
   R1 gate - no audio, no GIF, until video-only start/stop/save/discard is solid).

### App (Antigravity) - W0 risk spike, then W1 UI

1. ~~**Risk spike:** mixed-DPI multi-monitor borderless overlay windows~~ — done,
   [PR #7](https://github.com/noel-q/docshot/pull/7). Tested on a real two-monitor, mixed-scale
   rig (150%/100%); DIP↔physical round-trip error 0.00px across tested scale factors. Watch out
   for the `SetProcessDpiAwarenessContext` gotcha noted in `docs/WINDOWS_PORT_PLAN.md` §5 in any
   new code that queries monitor geometry off the WPF UI thread.
2. ~~Tray icon (`NotifyIcon`) + minimal settings window shell.~~ — done, PR #7
   (`H.NotifyIcon.Wpf`).
3. Per-monitor selection overlay windows wired to `IWindowDiscoveryService`/`IScreenCaptureService`
   once Platform lands them.
4. Annotation canvas rendering `AnnotationItem`/`AnnotationShape` from `DocShot.Core` - decide the
   WPF drawing approach (SkiaSharp is recommended in `docs/WINDOWS_PORT_PLAN.md` §2 for parity with
   the blur/pixelate redaction filters; raw `DrawingVisual` is the fallback if that adds too much
   surface for a first pass).
5. Recording confirmation UI and status HUD, once Platform's `IRecordingSession` exists.

## PR expectations

There's no CI on this repo yet for the macOS side either (see `docs/WINDOWS_PORT_PLAN.md` §6/§8) -
manual verification against the documented commands is the existing norm, not a gap specific to
Windows. Match it:

- **Core PRs:** paste the actual `dotnet test` output (pass count, not just "tests pass") in the
  PR description.
- **Platform/App PRs:** a short device-verification note in the PR description - what was run, on
  what Windows build/monitor setup, what passed - mirroring the macOS
  `docs/DEVICE_VERIFICATION.md` format. Start a `windows/docs/WINDOWS_DEVICE_VERIFICATION.md` the
  first time there's something real to record; don't create it empty.
