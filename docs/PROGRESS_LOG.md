# DocShot progress log

Dated detail that does not fit on the one-page STATUS.md. Newest first. Each entry keeps
its original evidence label (verified, inherited, assumed, unknown).

## 2026-11-23

- Spike cleanup with Noel's yes: `spikes/` (app, build, log), the `spike/c0d-package`
  worktree and branch removed. No `com.docshot.spike` preferences existed; nothing for Noel
  to remove from System Settings. Other old worktrees left untouched. Verified (git, ls).

## 2026-11-18

- C0 spikes plan agreed by Noel ("Yes to all"), seven answers: one throwaway menu bar app
  `DocShotSpike` (`com.docshot.spike`) in a git-ignored `spikes/` folder, separate from DocShot,
  with menu entries for (a) polling and the privacy prompt, (b) paste into another app and
  (c) main window focus; Noel runs (a)-(c) from a checklist, the agent builds and reads the
  log; the log holds type names, sizes, times, app names and permission states, never
  clipboard content; if no alert appears, (a) is repeated with the pasteboard privacy preview
  set on the spike's own ID only; answers go into the plan and DEVICE_VERIFICATION.md, spike
  code and the (d) branch are not committed; Noel removes the spike from Accessibility and the
  pasteboard list, the agent deletes the build, the spike prefs and the (d) branch with his yes.
  (d) package versus folder is a build-only spike in a throwaway worktree.
- Found while planning (verified from the macOS 26.6 SDK header `NSPasteboard.h`): the general
  pasteboard's default access behaviour is to ask on programmatic access; user-started paste is
  exempt. Whether macOS 26.5.2 enforces it: unknown until spike (a). `/Applications/DocShot.app`
  and the debug builds share `com.docshot.app`; builds are signed with team DVV9Z7Q7B9.
- Spike (d) package versus folder, run in a throwaway worktree on branch
  `spike/c0d-package` (not committed): a local package `Packages/ClipboardKit` (one type, one
  test) wired into `Package.swift` and, by hand, into the Xcode project using the pre-Xcode-15
  form (folder reference plus `XCSwiftPackageProductDependency`), so `objectVersion` stays 56.
  Both the app and the hostless test target link it; an app file importing `ClipboardKit` is
  also compiled into the test target. Results: `swift test` 291 (290 + 1 link test), the
  package's own `swift test` 1, `xcodebuild test` 292 (291 + 1), all passing with the hotkey
  suites skipped; parity audit OK; the package links statically. Verified (tests only).
  One cost: the root `swift test` does not run the package's own tests, so they need
  `swift test --package-path Packages/ClipboardKit` as a second command (or a test file in
  `Tests/DocShotTests`). Recommendation: package.
- `DocShotSpike` built for (a)-(c) in `spikes/DocShotSpike` (git-ignored), signed with the
  same team. Not launched; Noel runs it from the "C0 Spikes" rows in DEVICE_VERIFICATION.md.
- Noel ran part (a): no alert with counter-only or full-read polling; the log shows
  `accessBehavior` "always allow" from launch and three text copies read (types and sizes
  only). Image, file, password and idle-CPU steps were not run. Noel found the manual
  checklist too heavy for a spike: (b) moved to C3, password marker, idle CPU, menu opening
  and the Escape key moved to C2, and the agent ran (c) itself.
- (c) agent-run with full-screen control approved by Noel: a self-test build (window closes
  after 3 s, alternating activation method) opened by real ⌃⌥⌘J presses in TextEdit. Both
  `NSApp.activate()` and the old forced call made the window key with focus in its field;
  closing returned TextEdit to the front and typing continued there; activation policy stayed
  accessory. Verified (log, TextEdit text). The test document was discarded unsaved and the
  spike quit.
- C0 answers written into the plan: section 4.1 (package decided), 4.3 (privacy note),
  a "C0 findings" subsection in section 6, and the carried checks added to the C2 row.

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
- C0.6 committed as bc269ce on `feature/c0.6-preview-thumbnail`, local only.
- Colour themes agreed as C0.7 (six answers): after C0.6 and before the C0 spikes;
  four themes (Graphite default, Slate, Moss, Ember); interface colours only; light and
  dark mode following macOS; chosen in a new Appearance section in Settings; second
  exception to the freeze rule; Windows must match. Written into plan sections 6, 7, 9
  and 12. Proposed colour values shown to Noel as swatches; not yet confirmed.
- C0.7 colour themes built on `feature/c0.7-themes` (cut from bc269ce), uncommitted.
  New: `Models/ColorTheme.swift` (palettes, contrast maths, store), `Design/ThemeController.swift`
  (current theme; a lock-guarded copy read by the dynamic colours), `ColorThemeTests`
  (25 cases). The five interface tokens in `DesignTokens` now follow theme and mode; Graphite
  resolves to the old values. Eleven views observe the controller, plus the preview thumbnail,
  whose background moved from a frosted material to the theme card colour. Settings has an
  Appearance section with four swatches.
- Fable reviewed C0.7: checks 1, 4, 6, 7 proven in code; 2 and 5 proven in code but need a look
  on device; 3 partly questioned because the scrubber and selected segment follow the accent,
  which matches decision 5 (only media backdrops and the track stay neutral). One defect,
  confirmed and fixed: themed grey text on fixed graphite tiles lost contrast in light mode
  (Settings and onboarding folder path, timeline "Src:" line); those now use a fixed text
  colour, with a test. Noted, not fixed: a test writes the process-wide current theme (it
  restores it); unselected timeline segments already used standard text colours on the dark
  tile before C0.7, which is low-contrast in light mode.
- After the fix: `swift test` 290 and `xcodebuild test` 291 pass with the hotkey suites
  skipped; parity audit OK. The fix itself is not re-reviewed. Not run in the app.
- Noel ran the 10 C0.7 device checks on the debug build and reported all passing
  (user-reported).
- C0.7 committed as 5fb8e7f on `feature/c0.7-themes`, local only.
- Noel ran the 18 remaining C0.5 device checks on the C0.7 debug build: all pass
  (user-reported). Every C0.5 row is now passed.
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
