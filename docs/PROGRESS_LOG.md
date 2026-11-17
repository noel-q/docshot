# DocShot progress log

Dated detail that does not fit on the one-page STATUS.md. Newest first. Each entry keeps
its original evidence label (verified, inherited, assumed, unknown).

## 2026-11-17

- C0.6 preview thumbnail built by this session (Opus 5.5) on
  `feature/c0.6-preview-thumbnail`, cut from `feature/c0.5-shortcuts` at c7389af.
  Uncommitted. New: `Models/PreviewThumbnail.swift` (key map, button order, layout;
  in both test targets), `Capture/PreviewThumbnailController.swift` (non-activating
  panel; app-only), `PreviewThumbnailTests` (11 tests). `CaptureCoordinator` now shows
  the thumbnail instead of the editor and keeps the state `editing` until it is resolved.
  Tests: `swift test` 278 and `xcodebuild test` 279 passed with
  `HotkeyServiceTableTests`, `TemporaryEscapeHotkeyTests` and
  `CaptureCoordinatorEscapeLifecycleTests` skipped, because they register real system
  hotkeys. Parity audit OK. Not run in the app. Verified (tests only).
- Fable reviewed the C0.6 diff (read-only subagent, review-against-diff). Proven in code:
  checks 1-6, 9, 10 (tests not run by the reviewer); not proven until a device run: 7 (focus)
  and 8 (placement); contradicted: none. Four defects found, all confirmed in the code and
  fixed: a capture hotkey during the thumbnail's save panel could let the old save finish the
  new capture (now beeps); the discard prompt could stack (now beeps); a stale focus target
  when DocShot itself was in front (now cleared); Cancel on the prompt left DocShot in front
  (now hands focus back). After the fixes: `swift test` 278 and `xcodebuild test` 279 pass
  with the hotkey suites skipped; parity audit OK. The fixes themselves are not re-reviewed.
- Fable re-reviewed the four fixes: all four fixed. It found two new defects, both
  confirmed and fixed: a blocked (beeping) capture press could wipe the app focus returns
  to (now recorded only on paths that start a capture or show the prompt); the error alert
  did not count as busy (now it does). A third finding is accepted as known behaviour: a
  capture started from the editor leaves DocShot active after Copy, as today's editor flow
  does. After these fixes: `swift test` 278 and `xcodebuild test` 279 pass with the hotkey
  suites skipped; parity audit OK. These last two fixes are not re-reviewed.
- Noel ran the 18 C0.6 device checks on the debug build and reported all passing
  (user-reported; one screenshot shows the thumbnail in place). He then asked for a few
  colour themes besides the default; not yet scoped.
- A Fable session also wrote here this morning (commits e5288d4 and c7389af, plus an
  uncommitted STATUS.md line). Noel made this session the only writer.

- Commit 1 made on `feature/c0.5-shortcuts`: f3be4d4, handoff files, plan and this log.
  Local only, not pushed. Verified (git log).
- Plan approved after two grilling rounds; all section 10 decisions settled and written
  into plan sections 2, 4.2, 4.5, 5, 6, 7 and 10. Verified in session. In short:
  - Retention stays 200 items / 30 days / 500 MB. Pinned items count towards storage
    and are never removed automatically. Captures share the limits, capped at 20.
  - OCR (C4a) feeds history search and "Copy text" only, with history on.
    Pin-to-screen renamed Float (C4b) and works with history off. Principle 6
    reworded to allow it. The freeze follows C4a and C4b.
  - Name stays DocShot. Tier stays C, no due date.
  - One lane: Opus 5.5 at High effort orchestrates and builds; Fable reviews each unit
    from the diff. Codex and Antigravity are not used on the Mac work. Noel changed this
    from the proposed Sonnet/Opus split with Codex review; it overrides the general
    split in the handoff skill for this project.
  - Testing rules: private pasteboard and scratch preferences in tests; warn Noel
    before driving the app against real clipboard, preferences or hotkeys; clipboard
    device checks are Noel's.

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

- 2026-11-17: Noel launched the fixed build and reported "The shortcut looks good" and
  that the minimal Settings are liked. No row-by-row device results given. Inherited from
  Noel's message.
- 2026-11-17, proposed by Noel, not decided: (a) the four-key defaults (⌃⌥⌘S, ⌃⌥⌘R) may be
  too long; plan 13.3 chose that family to avoid the ⌘⇧number and ⌃⌥letter collisions, and
  both actions are already rebindable. (b) A preview thumbnail after capture: a small
  window with icon buttons for Copy, Discard, Edit and Save, where only Edit opens the full
  editor. Not in plan section 7, and plan section 12 says anything new waits until after
  the freeze, so it needs Noel's scope decision before any build.

- 2026-11-17: Noel approved the preview thumbnail ("Yes, add it"). Plan amended: principle
  2.6 reworded, C0.6 added to section 6, feature and scope added to section 7, exception
  noted in section 12. Details beyond the four buttons and "only Edit opens the editor"
  are marked proposed in the plan. Nothing built. The chord-length question is still open.

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
