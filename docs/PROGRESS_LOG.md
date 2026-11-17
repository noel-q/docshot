# DocShot progress log

Dated detail that does not fit on the one-page STATUS.md. Newest first. Each entry keeps
its original evidence label (verified, inherited, assumed, unknown).

## 2026-11-16

- STATUS.md cut to one page; the detail below moved here from it. Verified in session.
- State check found: local `main` at 32c1f8d is 2 ahead of and 4 behind `origin/main`
  (291a4a4); three prunable `/tmp/docshot-v1-*` worktrees; two Codex worktrees still hold
  `codex/launch-at-login-opt-in` and `codex/opaque-redaction`. Verified (git rev-list,
  git worktree list). Whether anything is active in them: unknown.
- `handoff.config.json` runs `pytest`, which does not apply to this Swift project.
  `swift test` is not a safe swap because `HotkeyServiceTableTests` touches the real
  system hotkey table; `Scripts/audit-test-parity.sh` proposed instead. Not changed.
- STATUS.md recorded `swift test` as both 291 and 292 tests. Which is current: unknown
  (292 likely, after `SettingsLayoutTests`).

## 2026-11-14

### Redefinition plan
Saved to docs/DOCSHOT_REDEFINITION_PLAN.md (also in the DocShot Claude project). Decided
by Noel: personal use only; no Apple Developer membership or notarisation; recorder
stays; clipboard manager built into DocShot as its own module; password manager is a
separate project (DevVault); Windows full parity after macOS is stable; configurable
Clear cache (keep last 5, last 10, pinned only, nothing); three rebindable global
shortcuts on Control+Option+Command plus single-key editor tools. Verified in session.

### GitHub review
`origin/main` is at 291a4a4, tagged macos-v1.0.0 (23 Sep), with launch-at-login (PR #11)
and opaque redaction merged. Three `windows/*` branches unmerged since 29 Jul. Verified
from a fresh clone; PR numbers inherited.

### Notarised release script
Release script and CI workflow drafted in a cloud sandbox, never run, not committed.
Parked because distribution is no longer a goal. Unverified.

### C0.5 shortcut rework
Built on `feature/c0.5-shortcuts` (cut from `origin/main` 291a4a4), uncommitted.

- Scope: one table of three actions (screenshot ⌃⌥⌘S, record ⌃⌥⌘R, openWindow ⌃⌥⌘V
  defined but unregistered); recorder plus reset per action in Settings; preset list
  removed; legacy migration; image editor tool keys; Return to copy and close.
- Tests: `swift test` (291, later 292), `xcodebuild test` (280) and
  `Scripts/audit-test-parity.sh` all pass, including `HotkeyServiceTableTests`, which
  rebinds, resets and rolls back against the real system hotkey table over scratch
  preferences. Inherited.
- In-app run: Noel launched the debug build and Claude Code drove it through
  accessibility. Passed: migration of the real preferences (preset 2 kept as ⇧⌘7),
  Settings rows, three-modifier rebind, duplicate-chord error, reset, onboarding text,
  tool keys R/X/T, tooltips, the typing guard and Return. Not verified: any global chord
  actually firing, export size fields, ⌘C, video editor and overlay. Row-by-row detail in
  docs/DEVICE_VERIFICATION.md ("C0.5 Shortcut Rework"). Inherited.
- Side effects of that run: both shortcuts are now on the new defaults in
  `com.docshot.app` (the ⇧⌘7 binding was reset as part of the check), and the clipboard
  was overwritten by the Return check.
- Settings window clipping (header and privacy notice cut off, same on `origin/main`)
  fixed on this branch by scrolling the content in a 520 × 620 window, approved by Noel.
  Verified by tests only; not yet seen in the running app.

### Departures from plan section 13 (approved by Noel in session)
1. The recorder allows three modifiers and takes a title.
2. Saved preset 0 (old default ⌘⇧6) migrates to the new default, because launch always
   wrote a preset ID.
3. The onboarding preset picker is replaced by a read-only display.
4. Return copies then closes only on success.

### Handoff files
The handoff commits (cbf9581, cf4fa3f) also exist on `codex/launch-at-login`. Their
AGENTS.md, CLAUDE.md, tools/handoff.mjs and handoff.config.json are byte-identical to the
working-tree copies on `feature/c0.5-shortcuts` (verified by diff, 2026-11-16).
