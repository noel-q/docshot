# Test Architecture

DocShot's unit tests run under two toolchains, and they do not run the same number of
tests. That difference is deliberate and is recorded here and in
[`Tests/target-parity.json`](../Tests/target-parity.json), which
[`Scripts/audit-test-parity.sh`](../Scripts/audit-test-parity.sh) enforces.

```bash
swift test
xcodebuild test -project DocShot.xcodeproj -scheme DocShot -destination 'platform=macOS'
./Scripts/audit-test-parity.sh
```

## The two toolchains

**SwiftPM (`swift test`)** builds the whole `DocShot` executable target and links the test
target against it. Every production file and every file in `Tests/DocShotTests` is compiled,
with no manual bookkeeping: adding a file is enough for it to be built and run.

**Xcode (`xcodebuild test`)** builds a *hostless* `DocShotTests` bundle. It sets neither
`TEST_HOST` nor `BUNDLE_LOADER`, so it does not launch or link the app. Instead it compiles a
curated subset of production sources directly into the test bundle. Membership of that subset
is hand-maintained in `project.pbxproj`.

## What "hostless" actually means here

The test bundle links no part of the app at all:

```
otool -L DocShotTests.xctest  → XCTest and system frameworks only
nm     DocShotTests.xctest    → all symbols mangled under the DocShotTests module
nm -u  DocShotTests.xctest    → no undefined DocShot symbols
```

Two consequences follow, and both matter when reading a green Xcode run.

**Source shadowing.** The test files say `@testable import DocShot`. That import resolves
against the app's `.swiftmodule` (which exists because the test target depends on the app
target), but every unqualified type name resolves to the *copy compiled into the test module*,
which shadows the imported one. Under `xcodebuild`, `PendingEscapeSessionTests` exercises
`DocShotTests.PendingEscapeSession`, not the app's. Both copies are compiled from the same
file, so behaviour is identical — but an Xcode run is evidence about the source, not about the
symbols in `DocShot.app`. `swift test` is what exercises the real module.

**A hard boundary at the subset edge.** A duplicated file may not reference an app-only type;
the Xcode build breaks if it does. Today the boundary is clean — the only mentions of app-only
types inside duplicated files are doc comments — but nothing in Xcode enforces it. Keeping
testable logic free of view and window dependencies is what keeps the boundary cheap, and is
why `PendingEscapeSession` was extracted from `CaptureCoordinator` in the first place.

## Why the bundle is hostless

A hosted app-test bundle would launch `DocShot.app` before every test run. The app's launch
path registers a real system-wide Carbon hotkey and can open the onboarding window
(`applicationDidFinishLaunching` in `DocShotApp.swift`), and the tests would then share
`CaptureCoordinator.shared` and `HotkeyService.shared` with a live menu-bar app instead of
getting a fresh process. A hosted bundle would also require a signed, injectable host: today
the Xcode suite builds and runs with **no code-signing identity at all**
(`CODE_SIGNING_ALLOWED=NO` succeeds end to end), which a hardened-runtime host would end.

The hostless bundle trades away three tests for process isolation and an identity-free build.
That trade is revisitable, but it should be revisited with measurements, in a throwaway
configuration, not by degrees.

## The intentional delta

| Run | Tests |
| --- | --- |
| `swift test` | full suite |
| `xcodebuild test` | full suite minus the SwiftPM-only suites below |

One suite is SwiftPM-only:

- **`CaptureCoordinator Escape Lifecycle Tests`** (3 tests, in
  `Tests/DocShotTests/TemporaryEscapeHotkeyTests.swift`, behind `#if SWIFT_PACKAGE`).
  `CaptureCoordinator` is app-only, so the hostless bundle has no symbols to link against.

**Raw test-count equality is not the acceptance criterion.** Forcing the counts to match would
mean either pulling `CaptureCoordinator` — and transitively the overlay windows, the editor
window controller, and the capture services — into the test bundle, or adopting a hosted bundle
with the costs above. Neither buys coverage; both buy fragility. The criteria that *do* apply:

1. Both toolchains build and pass.
2. Every divergence is declared in `Tests/target-parity.json` with a reason.
3. Anything guaranteed only by a SwiftPM-only test also has a shared-suite test asserting the
   same behaviour at the level that both toolchains can reach.

Point 3 is why the Escape lifecycle work lives in `PendingEscapeSession`: the coordinator tests
check that `cancelCapture()` and `closeOverlays()` release the registration, while the
`PendingEscapeSession Tests` suite proves the register/release, idempotence, stale-token, and
failed-registration guarantees themselves — and that suite runs in **both** toolchains.

## What the audit catches

`Scripts/audit-test-parity.sh` exits non-zero when:

1. **A test file on disk is not in the Xcode test target.** This is the failure worth the
   script on its own: SwiftPM picks the file up automatically, Xcode silently ignores it, and
   `xcodebuild test` still reports success. Nothing else makes that visible.
2. **Duplicated or app-only source membership differs from the manifest** — including a
   production file that is in no Xcode target at all.
3. **An `#if SWIFT_PACKAGE` suite is not declared** in the manifest with a reason, or its
   declared `testCount` no longer matches the number of `@Test` declarations in that suite.

It also fails if `project.pbxproj` can no longer be parsed, or if a guarded suite's name or body
cannot be identified, rather than passing by finding nothing.

When the audit fails, the fix is usually to update `project.pbxproj` (add the missing file to
the target) — not to edit the manifest. Edit the manifest when the change to the subset is the
intended one, and say why in the same commit.

## Known untested lifecycle edges

Recorded so they are chosen rather than forgotten:

- `CaptureCoordinator.refreshSnapshots` re-registers Escape around the snapshot refresh
  (a second `escapeSession.begin` site). Untested in both toolchains.
- The late-snapshot generation guard in `beginSelection` is verified on-device only; see
  [DEVICE_VERIFICATION.md](DEVICE_VERIFICATION.md).
- `startCapture`'s state guards, including the `.editing` discard confirmation, call
  `NSAlert.runModal()` directly and are not reachable from a test without injection.
- A Carbon-level failure inside `HotkeyService.registerTemporaryEscape` cannot be forced from a
  test. Only the protocol-level failure is covered, via the spy in the shared suite.
- `RecordingCoordinator` is app-only for the same reason `CaptureCoordinator` is, so its effect
  execution — overlay teardown ordering, the Task hops, and the modal output choice — is
  untested in both toolchains. It deliberately owns no transition rules: every decision comes
  from `RecordingStateReducer`, which runs in both toolchains and is where those guarantees are
  asserted. R1 adds no new `#if SWIFT_PACKAGE` suite, so the intentional delta is still the same
  three tests.
- `ScreenCaptureKitRecordingSession` and `RecordingFilterFactory` own a live `SCStream` and are
  verified on device only; see [DEVICE_VERIFICATION.md](DEVICE_VERIFICATION.md).
- `RecordingVideoWriter` is **not** in that category and is compiled into both targets. It is pure
  AVFoundation — no `SCStream`, no AppKit — so the hostless bundle can drive it directly:
  `RecordingAudioTrackTests` feeds it synthesised video and PCM audio, writes real MP4s, and
  inspects the tracks with `AVURLAsset`. That is what makes "audio off yields no audio track" and
  "system audio yields one AAC track on the same session clock" assertable in both toolchains
  instead of resting on a device report. What it cannot cover is a real audible source, perceptual
  A/V sync, or TCC behaviour.
- The writer inputs use `expectsMediaDataInRealTime`, so a test that appends frames as fast as it
  can build them will see most of them shed as back-pressure. `RecordingAudioTrackTests` paces its
  harness to the frame rate for that reason; an unpaced harness measures the encoder's throughput,
  not the writer.
- The video-editor core (`VideoProject` and `AVFoundationVideoProjectExporter`) is compiled into
  both targets for the same reason as the writer: it is AVFoundation and AppKit only. See
  [VIDEO_EDITOR_ARCHITECTURE.md](VIDEO_EDITOR_ARCHITECTURE.md).
- **`VideoProject Export Tests` is `.serialized`.** Each test drives a real `AVAssetWriter` and
  `AVAssetExportSession`; a dozen of those running concurrently starve the hardware encoder and the
  run hangs rather than failing. Its media harness also bounds every
  `isReadyForMoreMediaData` wait — an unbounded wait turns any writer problem into a hung suite
  instead of a readable failure, which is exactly how the audio-track fixture bug was found.
