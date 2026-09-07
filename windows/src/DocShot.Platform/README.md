# DocShot.Platform

Empty on purpose. This is where the Win32/WinRT interop implementations of the `DocShot.Core`
service interfaces live: hotkey registration, window enumeration, `Windows.Graphics.Capture`
capture, the Media Foundation sink writer, WASAPI loopback audio, and clipboard PNG format
registration.

Owner: Codex. Task breakdown, branch naming, and dependency order are in
[`windows/docs/WORKSTREAMS.md`](../../docs/WORKSTREAMS.md).

Do not add product logic here that has no Win32/WinRT dependency - if it can be tested without a
Windows display, it belongs in `DocShot.Core` instead.
