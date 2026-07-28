# W0 Platform Risk Spikes

Throwaway native Windows proofs for the DocShot Windows port platform lane. These are not
production `DocShot.Platform` code and should be deleted or ignored after the architecture
decisions are recorded.

## Build

Run from this folder:

```powershell
.\build.ps1
```

The script uses the installed Visual Studio Build Tools C++ compiler and Windows 10 SDK.

## Probes

- `wgc_capture_probe.exe`: captures visible top-level hardware-accelerated windows through
  Windows Graphics Capture, copies an odd-sized crop from each frame, and reports whether the
  frame is non-black and dimension-exact.
- `wasapi_mf_sync_probe.exe`: records 60 seconds of desktop video plus WASAPI loopback audio to
  MP4 with all video and audio sample timestamps based on one `QueryPerformanceCounter` clock.
- `clipboard_png_probe.exe`: writes a transparent test image as a registered `"PNG"` clipboard
  format and as a `CF_DIB` fallback, then reads both back to verify the formats are present.

These probes intentionally print plain diagnostic output rather than exposing reusable APIs.
