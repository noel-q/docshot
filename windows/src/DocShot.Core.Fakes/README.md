# DocShot.Core.Fakes

In-memory implementations of every interface in `DocShot.Core.Services`. No Win32, no WinRT, no
real capture/encode/clipboard access.

## Why this exists

Added 2026-07-28 so `DocShot.App` doesn't have to wait on `DocShot.Platform`'s real
implementations to start real W1+ UI work. See the "Parallelization" section of
`windows/docs/WORKSTREAMS.md`.

## What's here

| Interface | Fake | Notes |
|---|---|---|
| `IWindowDiscoveryService` | `FakeWindowDiscoveryService` | fixed set of 3 synthetic windows |
| `IScreenCaptureService` | `FakeScreenCaptureService` | synthetic checkerboard BGRA32, exact-dimension |
| `IPermissionService` | `FakePermissionService` | always granted |
| `IHotkeyService` | `FakeHotkeyService` | in-memory; `SimulateConflictForId` to test the conflict/failure state from `PARITY_CHECKLIST.md` §3 |
| `IRecordingSession` / `IRecordingSessionFactory` | `FakeRecordingSession` / `FakeRecordingSessionFactory` | real wall-clock duration, zero-byte placeholder file, not playable media |
| `ITemporaryRecordingStore` | `FakeTemporaryRecordingStore` | real files under `%TEMP%\DocShot-Fakes` |
| `IMovieSaving` | `FakeMovieSaving` | `AlwaysCancel`/`AlwaysFail` to test both non-happy paths |
| `IGifExporting` | `FakeGifExporting` | relabels the file; does **not** enforce `GifProfile` guardrails - don't use this to test guardrail logic itself |
| `IPasteboardWriter` | `FakePasteboardWriter` | captures last-written bytes instead of touching the real clipboard |
| `IFileWriter` | `FakeFileWriter` | writes to a real file, just never the user's actual chosen path in a test run |

## How to use from DocShot.App

Reference this project only in Debug, and swap to real Platform-backed implementations before any
milestone is actually verified - fakes prove the UI wiring works, not that the feature works.
Suggested pattern in `DocShot.App.csproj`:

```xml
<ItemGroup Condition="'$(Configuration)'=='Debug'">
  <ProjectReference Include="..\DocShot.Core.Fakes\DocShot.Core.Fakes.csproj" />
</ItemGroup>
```

Then register services conditionally at startup (e.g. in `App.xaml.cs`) rather than hard-coding a
choice anywhere UI code can see it, so flipping between fake and real is a one-line change, not a
re-wire.

## What this is not

Not a replacement for `docs/DEVICE_VERIFICATION.md`-style real-device testing, and not a place to
validate guardrail/business logic that already has real coverage in `DocShot.Core.Tests` - these
fakes intentionally skip that logic (see `FakeGifExporting`, `FakeHotkeyService`) so App can build
its UI against a shape that matches production without also re-implementing production behaviour
twice.
