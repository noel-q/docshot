# DocShot.App

Empty on purpose. This is the WPF shell: tray icon (`NotifyIcon`), one borderless transparent
overlay window per monitor for selection, the annotation canvas, the recording status HUD, and
the settings window.

Owner: Google Antigravity - this layer needs eyes on a real, ideally multi-monitor / mixed-DPI
Windows machine to verify, which is exactly what makes it the wrong lane for Claude (no Windows
display in this sandbox) and a slower fit for Codex (mechanical interop work, not visual
judgement). Task breakdown, branch naming, and dependency order are in
[`windows/docs/WORKSTREAMS.md`](../../docs/WORKSTREAMS.md).

`ApplicationHighDpiMode=PerMonitorV2` is already set in the csproj - do not remove it. Mixed-DPI
multi-monitor correctness is flagged as risk spike W0-1 in `docs/WINDOWS_PORT_PLAN.md` and should
be proven before this project grows much further.
