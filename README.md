# DocShot

DocShot is a local-first desktop capture utility. It combines Lightshot's immediate annotation flow with smart window selection, then makes output an explicit choice: copy, save, export GIF, or export video.

## Product direction

The first release is macOS-first, built around a selection-first screenshot workflow. It must never auto-save, auto-copy, upload, or require an account.

Read `docs/PRODUCT_BRIEF.md`, `docs/TECHNICAL_BRIEF.md`, and `docs/BUILD_PROMPT_V1.md` before implementation.

## Planned delivery sequence

1. macOS screenshots: hotkey, smart window selection, custom region, annotation, copy/save.
2. Window-detection polish and multi-display/DPI testing.
3. Window/region recording with explicit MP4 export.
4. GIF export for short clips.
5. Windows implementation, matching the established interaction model.

## Non-negotiables

- Native desktop application, not a browser or web app.
- Local-first. No accounts, analytics, remote upload, or capture library in V1.
- Selection and annotation happen before any output action.
- Accessibility, privacy permissions, and reliable cancellation are part of the feature.
