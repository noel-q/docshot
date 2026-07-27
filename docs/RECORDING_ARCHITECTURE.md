# Recording Architecture

This document is the implementation contract for DocShot's first native macOS
recording milestones. It extends the product brief's selection-first recording
contract; it does not change the completed screenshot workflow.

## Scope and delivery order

The implementation ships in narrow milestones:

1. **R1 — video-only MP4:** select a window or a region, confirm, record, stop,
   and explicitly save or discard an MP4.
2. **R2 — recording UX and failure hardening:** persistent status, interruption
   handling, and manual device verification.
3. **R3 — opt-in audio:** system audio first, then microphone where the OS and
   permission state permit it.
4. **R4 — short GIF export:** create a GIF from a completed temporary MP4 only.

Do not start a later milestone while its predecessor has failing automated or
manual acceptance checks. In particular, do not combine audio or GIF encoding
with R1.

## Product contract

- The user invokes **Capture Recording**, then selects a detected window or a
  single-display region using the existing selection interaction.
- Selection presents a compact **Record / Cancel** confirmation control. No
  stream begins before Record.
- Stop finishes into a local, temporary MP4 and opens an output choice. Saving
  always uses a native save panel; Discard deletes the temporary result.
- Nothing is auto-saved, auto-copied, uploaded, retained in a clip library, or
  used for analytics. A recording exists outside temporary storage only after
  the user explicitly chooses Save.
- GIF is a post-stop export option only. It has no audio. It is offered only to
  clips at most 15 seconds and only if its actual encoded size is within the
  configured size guard. MP4 remains the fallback.

## Isolation from screenshot capture

`CaptureCoordinator`, `CaptureState`, `ScreenCaptureService`, and the editor
remain screenshot-specific. They use a one-shot image API and currently own
selection snapshots, temporary Escape handling, and editor transitions.

Add a parallel recording subsystem rather than adding recording cases to those
types:

```text
DocShotApp / menu action
  RecordingCoordinator (@MainActor)
    RecordingSelectionAdapter
    RecordingService
      ScreenCaptureKit SCStream
      RecordingWriter (AVFoundation)
    RecordingOutputService
    RecordingExportService (GIF, R4)
```

The existing overlay drawing and window discovery may be reused through a small
adapter, but ownership stays separate: `RecordingCoordinator` owns its overlay
windows, monitors, generation token, and temporary recording session. Only one
DocShot capture activity may exist at a time; the app-level menu disables the
other capture action while either coordinator is non-idle.

## Types and seams to add

Place pure models under `Sources/DocShot/Models`, recording services under
`Sources/DocShot/Services`, and coordinator/UI adapters under a new
`Sources/DocShot/Recording` group.

### Pure, hostless-testable models

```swift
enum RecordingTarget: Equatable, Sendable {
    case window(id: CGWindowID, boundsInCG: CGRect)
    case region(displayID: CGDirectDisplayID, rectInDisplay: CGRect,
                outputSize: CGSize)
}

enum RecordingAudioMode: Equatable, Sendable {
    case none
    case system
    case microphone(deviceID: String?)
    case systemAndMicrophone(deviceID: String?)
}

struct RecordingOptions: Equatable, Sendable {
    var audio: RecordingAudioMode
    var showsCursor: Bool
    var maximumFrameRate: Int       // R1 default: 30
}

enum RecordingState: Equatable, Sendable {
    case idle
    case permissionRequired
    case selecting
    case awaitingConfirmation(RecordingTarget)
    case starting(RecordingTarget)
    case recording(RecordingTarget, startedAt: Date)
    case stopping
    case awaitingOutput(TemporaryRecording)
    case exportingGIF(TemporaryRecording)
    case failed(RecordingFailure)
}
```

`TemporaryRecording` is a value containing a private temporary URL, duration,
pixel size, and whether audio tracks are present. It is not a user-facing
history item. `RecordingFailure` must distinguish permission, invalid target,
stream start/stop, writer, output-save, and GIF-export failures so the UI can
give an actionable message.

Use a deterministic `RecordingStateReducer` (or equivalent transition methods)
for all state transitions. It must reject duplicate start/stop requests and
ignore late callbacks whose session generation differs from the active one.

### Platform seams

```swift
protocol RecordingSession: Sendable {
    func start(target: RecordingTarget, options: RecordingOptions) async throws
    func stop() async throws -> TemporaryRecording
    func cancel() async
}

protocol RecordingSessionFactory: Sendable {
    func makeSession() -> any RecordingSession
}

protocol TemporaryRecordingStore: Sendable {
    func makeMP4URL() throws -> URL
    func removeIfPresent(_ url: URL)
    func move(_ source: URL, to destination: URL) throws
}

protocol MovieSaving: Sendable {
    @MainActor
    func save(_ recording: TemporaryRecording, parent: NSWindow?) async -> SaveResult
}

protocol GIFExporting: Sendable {
    func exportGIF(from recording: TemporaryRecording, profile: GIFProfile) async throws -> TemporaryRecording
}
```

Production implementations use ScreenCaptureKit, AVFoundation, FileManager,
and the existing default-folder/save-panel mechanism. Fakes exercise all state
and cleanup paths without screen permission, a global hotkey, or a test host.

All new pure types must be added to the Xcode hostless test subset and
`Tests/target-parity.json`; then run `./Scripts/audit-test-parity.sh`. Keep
AppKit window code and live `SCStream` ownership app-only.

## R1: video-only MP4 foundation

### Selection and stream construction

Use existing `WindowDiscoveryService` eligibility rules so DocShot windows are
not targets. For a window target, resolve its current `SCWindow` immediately
before start and use `SCContentFilter(desktopIndependentWindow:)`.

For a region target, first restrict R1 to a region wholly contained by one
display. Convert the selected global rectangle once with the existing tested
display-coordinate helpers into a display-relative `sourceRect`; use an
`SCContentFilter` for that display and configure `SCStreamConfiguration` with
that source rectangle and its exact output pixel width and height. Mixed-scale,
multi-display recording is expressly deferred; the UI must explain this rather
than silently cropping or stretching.

Before `SCStream.startCapture`, order out every selection/confirmation overlay,
flush the transaction, and keep the target immutable for the session. For a
display filter, exclude DocShot's running application where the selected filter
allows it so the recording HUD is not captured. A recording indicator may be
shown outside the target only when exclusion is reliable.

### Writing

`ScreenCaptureKitRecordingSession` owns exactly one `SCStream`, one serialized
video writer queue, and a temporary MP4 URL. It supplies screen samples through
`SCStreamOutput` to an `AVAssetWriter`/video input configured for H.264 MP4.
For R1 video-only recording, it begins the writer session at the first valid video presentation
timestamp. When R3 system audio is enabled, it begins at the first valid audio or video sample
presentation timestamp; never use wall-clock time as the media clock. It appends only while the writer
input is ready and exposes back-pressure/drop counts for diagnostics, not user
analytics.

R1 defaults are SDR, 30 fps maximum, native selected-region pixel dimensions,
and the existing cursor preference. Configure a bounded stream queue depth (5;
do not exceed 8 without measured justification). Do not perform encoding,
thumbnail extraction, or GIF work on the main actor or on ScreenCaptureKit's
sample-handler queue.

Stopping is a single-flight asynchronous operation: stop the stream, mark the
writer input finished, await `finishWriting`, verify a playable/finite asset,
then transition to `awaitingOutput`. A stream delegate failure, write failure,
or cancellation must invalidate the generation and remove the temporary file.

### R1 as implemented

The types above are in place, with these decisions recorded rather than left implicit:

- **`RecordingSession.start` takes the output URL** the coordinator minted from
  `TemporaryRecordingStore`, instead of the session minting its own. The coordinator therefore
  always knows which file a session owns, so cleanup after a start failure, a stream error, or a
  late callback never depends on the session surviving long enough to clean up after itself.
- **Permission strictly precedes any overlay.** `requestRecording` emits only
  `preflightPermission`; the reducer emits `beginSelection` — the sole effect that creates
  overlays — on `permissionResolved(granted: true)`.
- **The selected pixel size is preserved exactly**, odd dimensions included. Nothing is rounded
  to even; H.264's behaviour with odd dimensions is a device-QA question, and padding or
  clean-aperture handling will be added only if a real failure appears.
- **The R1 output surface is a modal Save MP4 / Discard choice.** The persistent status HUD with
  elapsed time is R2; R1 ships the menu-bar **Stop Recording** action so a take can always be
  ended.
- **Initial encoder policy** (`RecordingVideoWriter`), to be validated during device QA rather
  than assumed correct: average bitrate = `width × height × fps × 0.15`, clamped to 2–40 Mbps,
  two-second keyframe interval, H.264 High profile, no frame reordering. There is no fixed
  free-space threshold and no duration cap.
- **`RecordingState` keeps every documented case**, including the R4 `exportingGIF`. No R1 event
  reaches it, and `RecordingStateReducerTests` asserts that.
- **Temporary media** lives in `NSTemporaryDirectory()/DocShot-Recordings`. The store only ever
  deletes `.mp4` files sitting directly inside that directory, so a destination the user chose in
  the save panel cannot be removed through it. Orphans from an abnormal exit are swept at launch
  and on every terminal path.

### R1 acceptance

- A window and a single-display Retina region record at their selected bounds;
  window recording remains independent of later movement/occlusion according to
  the selected ScreenCaptureKit filter.
- Record does not start before confirmation. Escape/Cancel before start creates
  no temporary or output file.
- Stop produces no user-selected file until Save MP4 is confirmed; Discard
  deletes the temporary file and does not touch the clipboard.
- A saved MP4 opens in QuickTime Player, has finite duration, expected pixel
  dimensions, and no audio tracks in R1.
- Repeated Stop, start failure, stop failure, display removal, app termination,
  and a late stream callback leave the state idle and no orphan temporary file.
- Screenshot capture, annotation export, and its shortcut still work before,
  after, and following a failed recording.
- Shared model/reducer/store tests pass under both test toolchains; both build
  commands and the parity audit pass.

## R2: interaction and interruption hardening

Add a non-captured recording status/control surface with elapsed time and a
visible Stop action, plus equivalent menu-bar Stop Recording action. Starting,
recording, stopping, and output states must disable both screenshot and recording
capture actions. The user can cancel selection with Escape; while recording,
Escape must not silently discard a clip—offer Stop/Discard confirmation or use
the explicit Stop control.

Handle `SCStreamDelegate` errors, display disconnect, sleep/wake, app
termination, Save panel cancellation, and output move failure. The coordinator
must call `cancel()`/cleanup exactly once even if multiple notifications arrive.

### R2 acceptance

- The user can always see whether recording is starting, active, stopping, or
  awaiting output, and can reach Stop without relying on the original window.
- The stop/control surface is absent from recorded pixels, or the limitation is
  documented and verified for every target type.
- Sleep, display disconnect, and screen-permission revocation stop safely,
  report a recoverable error, and remove temporary data.
- A five-minute 30 fps recording remains responsive, completes, and uses bounded
  memory; dropped-frame behaviour is measured and reported during device QA.

## R3: opt-in audio policy

Audio settings are persisted locally only and default to Off:

- System audio: Off/On.
- Microphone: Off/On and selected input device, with the system default when no
  device ID is saved.

Do not prompt merely because a preference control is displayed. Resolve current
availability and request consent only after the user enables the relevant option
and presses Record. Clearly state the effective recording configuration before
confirmation. Enabling either audio source must never cause an automatic save.

ScreenCaptureKit's `capturesAudio` supports stream audio; set it only for
system-audio modes, choose a documented sample rate/channel count, and exclude
DocShot's own process audio. Add `NSAudioCaptureUsageDescription` before using a
system-audio capture path that requires it. Add `NSMicrophoneUsageDescription`
before any microphone access, and preflight/request microphone access through
AVFoundation.

Microphone capture through ScreenCaptureKit's `captureMicrophone`,
`microphoneCaptureDeviceID`, and `.microphone` output is a newer API. Keep the
application's macOS 14 minimum for screenshots and video-only recording; gate
the native microphone path with `#available(macOS 15.0, *)` and show it as
unavailable on macOS 14. Do not add an AVFoundation microphone side-channel and
manual A/V muxing merely to emulate it on macOS 14 without a separate approved
design; timestamp synchronisation and device-change recovery make that a
different risk class.

When both sources are enabled, explicitly decide in implementation whether the
deliverable contains separate tracks or a mix. The initial recommendation is
separate `SCStream` audio and microphone writer inputs only if the writer can
preserve their timestamps and QuickTime playback is verified; otherwise defer
the combined mode and expose one source at a time. Never guess a user’s desired
mix.

### R3 system audio as implemented

- `RecordingOptions.capturesSystemAudio` and `excludesOwnProcessAudio` are the single
  source of truth for both the stream configuration and the writer's audio input, so
  the two cannot drift. Audio off means: no `capturesAudio`, no `.audio` stream output
  registered, no audio writer input, and therefore no audio track in the file.
- Self-audio exclusion is `SCStreamConfiguration.excludesCurrentProcessAudio`, which
  defaults to `false` and must be set explicitly. Excluding DocShot's applications from
  the *content filter* does not exclude its audio: system audio is captured globally,
  for a window target as much as a display one. Without this, DocShot's own error beeps
  and alert sounds land in the user's recording.
- The audio input is AAC, 48 kHz, stereo, 192 kbps. The writer session is anchored on the
  first valid sample of *either* type, so audio arriving before the first video frame is
  kept rather than falling before the session start and being discarded.
- `RecordingVideoWriter` is compiled into both test targets. `RecordingAudioTrackTests`
  writes real MP4s from synthesised samples and inspects their tracks, which is what makes
  the first, second, and fourth acceptance criteria below partly assertable without a
  device. Audible capture and perceptual sync remain device-only.

### R3 acceptance

- With both audio options off, saved output has no audio track and macOS never
  shows a microphone prompt.
- System audio on records a known audible source, while DocShot's own sounds are
  excluded.
- Microphone permission allow, deny, not-determined, unavailable device, and
  device loss all result in an explicit state; video-only recording remains
  available where appropriate.
- On supported macOS, a five-minute mic recording and any approved combined mode
  remain synchronised to video through start, stop, sleep/wake, and interruption.
- Device QA records OS version, selected audio options, device, and measured
  A/V offset. It does not retain the recording beyond the test unless explicitly
  saved as evidence.

## R4: short GIF export

GIF export consumes a finished `TemporaryRecording`, never a live stream. First
inspect the asset duration. Do not offer GIF above 15 seconds. For eligible
clips, export off-main-actor through AVFoundation/ImageIO using a fixed,
documented profile: 10 fps, no audio, maximum 960-pixel long edge, and a
configured encoded-size guard. The owner-approved guard is **10 MB** (10,000,000 bytes) and
must be declared in code and UI before implementation.

The exporter writes to another unique temporary URL. Only after ImageIO finalizes
successfully and the actual byte size is within the guard may it transition to a
Save GIF panel. If it is too large, remove the GIF temporary file and retain the
MP4 for Save MP4 or Discard. A failed or cancelled GIF attempt must leave the MP4
available and must not create a user-visible output file.

### R4 acceptance

- A short supported MP4 exports a valid animated GIF with expected dimensions,
  frame cadence, loop behaviour, and no audio.
- A 15.01-second clip never offers GIF. A clip that encodes above the size guard
  gives a clear MP4 fallback and leaves no GIF temporary file.
- GIF conversion does not stall the recording UI, corrupt the source MP4, or
  create an output until Save GIF is confirmed.
- Discard from every post-stop path removes all temporary MP4/GIF artifacts.

## Risks and non-goals

Primary technical risks are ScreenCaptureKit/TCC permission changes, stream
errors during display or sleep transitions, `AVAssetWriter` back-pressure,
timestamp alignment when audio is enabled, temporary-file leaks, and CPU/memory
cost during GIF encoding. Every risk maps to a state/cleanup test and a manual
device check above.

The following are not part of these milestones:

- Windows support, cloud upload/sharing, accounts, analytics, a backend, or a
  capture/recording history library.
- Webcam, camera, picture-in-picture, presenter overlay, OCR, transcription,
  AI processing, editing video, or live GIF recording.
- Multi-display region recording, HDR recording, variable frame-rate tuning,
  annotations during recording, and an AVFoundation mic-mux fallback for
  macOS 14.
- Automatic clipboard writes, automatic output files, or retaining temporary
  recordings after the user discards them.

## Verification commands

After every implementation milestone, run:

```bash
./Scripts/audit-test-parity.sh
swift test
xcodebuild test -project DocShot.xcodeproj -scheme DocShot -destination 'platform=macOS'
```

The automated tests are necessary but cannot prove TCC prompts, real stream
audio, display removal, or A/V sync. Record those results separately in the
device-verification document when the milestone reaches manual QA.
