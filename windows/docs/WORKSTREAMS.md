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

**Important caveat: this has not been compiled or run.** The sandbox this was written in has no
route to the .NET SDK (the installer domains are network-blocked and there's no root to use
`apt-get install dotnet-sdk-8.0`, which is otherwise sitting right there in Ubuntu's package
index). The code was written and reviewed carefully by hand, but `dotnet build` /
`dotnet test` need to be run for real - on Noel's machine, or by whichever of Codex/Antigravity
gets there first - before anyone builds on top of it. Treat the first `dotnet test` run as part of
the bootstrap, not a given.

Not yet ported (tracked here so it isn't silently dropped): `MagnifierGrid`, `DisplaySnapshot`,
`RecordingRegionPlan`, `SnapshotPlan`, `CaptureActivityPolicy`, and the image-dependent halves of
`PixelSampler`/`DisplayGeometry.CropImage` (these need a concrete bitmap type - see the Platform
task list below for where that decision belongs). `DocShot.Platform` and `DocShot.App` are empty
placeholder projects with a `README.md` each - no capture, encode, hotkey, or UI code exists yet.

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

- Port the remaining pure models: `MagnifierGrid`, `DisplaySnapshot`, `RecordingRegionPlan`,
  `SnapshotPlan`, `CaptureActivityPolicy`.
- Decide and document where the image-sampling half of `PixelSampler`/`DisplayGeometry.CropImage`
  lives once Platform picks a bitmap library (almost certainly `DocShot.Platform`, since it needs
  a concrete decoded-image type Core deliberately doesn't depend on - see the doc comments in
  `Models/ColorSample.cs` and `Models/DisplayGeometry.cs`).
- Get `dotnet test` actually green somewhere real and fix whatever the first compile finds -
  treat this as the true "W0 bootstrap done" milestone, not this commit.
- Keep `docs/WINDOWS_PORT_PLAN.md` and this file honest as Platform/App reality diverges from plan.

### Platform (Codex) - W0 risk spikes, then W1-W2 groundwork

1. **Risk spike:** WGC still-frame and streaming capture against real windows, including
   hardware-accelerated ones. Prove pixel dimensions match the selection exactly, odd dimensions
   included - do not round, matching the macOS R1 decision.
2. **Risk spike:** WASAPI loopback + Media Foundation sink writer on one shared clock. This is the
   single biggest architecture gap from macOS (ScreenCaptureKit has no Windows equivalent that
   captures video and audio on one stream) - see §2 and §5 of `docs/WINDOWS_PORT_PLAN.md`.
3. **Risk spike:** clipboard PNG round-trip - register and write the `"PNG"` format plus a
   CF_DIB fallback, verify against a transparency-aware consumer and a legacy bitmap-only one.
4. Implement `IWindowDiscoveryService` (`EnumWindows` + `DwmGetWindowAttribute(DWMWA_CLOAKED)` +
   shell-surface denylist), `IHotkeyService` (`RegisterHotKey`/`WM_HOTKEY` on a message-only
   window), `IScreenCaptureService` (still capture), and pick the bitmap type
   `CapturedImage.Bgra32Pixels` gets wrapped in for actual rendering (SkiaSharp is the leading
   candidate - see `docs/WINDOWS_PORT_PLAN.md` §2).
5. Implement `IRecordingSession`/`IRecordingSessionFactory` (video-only first, matching the macOS
   R1 gate - no audio, no GIF, until video-only start/stop/save/discard is solid).

### App (Antigravity) - W0 risk spike, then W1 UI

1. **Risk spike:** mixed-DPI multi-monitor borderless overlay windows. Two-monitor, mixed-scale
   test rig; prove a drag-selected rectangle round-trips to the correct source pixels on both
   monitors. `ApplicationHighDpiMode=PerMonitorV2` is already set in `DocShot.App.csproj` - don't
   remove it, and don't declare this spike done without an actual mixed-DPI setup to test on.
2. Tray icon (`NotifyIcon`) + minimal settings window shell.
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
