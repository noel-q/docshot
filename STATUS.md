# STATUS: DocShot

- ID: P05
- Tier: C
- Status: Active
- Last updated: 2026-11-24
- Definition of done: Local-only macOS menu bar tool for Noel: screenshots with annotation, recording with editing, bounded clipboard history in one on-demand window. Meets the six-point stability bar (plan §8). Windows parity only after that.

## Done so far
- 2026-11-24: Quiet restyle of the clipboard window (pilot step 1) built on feature/quiet-clipboard; Fable review fixed; swift test 352, xcodebuild test 353, ClipboardKit 76; Noel: "Looks good", clicks work. Verified (agent snapshots) and user-reported.
- 2026-11-24: C3 paste, search, keys, pins, editable limits and excluded apps committed as 9ef04d1 on feature/c3-paste. Fable review, re-review and a final check; all fixes in. swift test 339, xcodebuild test 340, ClipboardKit 76; parity OK. Device: paste verified in TextEdit (agent, screenshot) and user-reported in Chrome, the Claude app and Terminal; pin, delete, Escape agent-run via a DEBUG-only hook. Verified.
- 2026-11-24: C2 clipboard window committed as b89d700 on feature/c2-clipboard-window, local only. Fable review and re-review: seven defects found and fixed. swift test 316, xcodebuild test 317, ClipboardKit 69 pass with the hotkey suites skipped; parity audit OK. Device checks: recording, skips, idle CPU, relaunch and off agent-run in the app (verified by reading the store); window, copy-back, Escape, menu and Clear user-reported. Pause tests only. Noel likes the behaviour, not the look.
- 2026-11-23: C1 ClipboardKit core committed as ff490d2 on feature/c1-clipboardkit, local only. Verified.
- 2026-11-17: Plan approved; all §10 decisions settled (plan §§2, 4.2, 4.5, 5, 6, 7, 10). Build lane: Opus 5.5 High builds, Fable reviews. Verified in session.
- 2026-11-17: Handoff files, plan and progress log committed as f3be4d4, local only. Verified.
- 2026-11-14: Redefinition plan agreed: docs/DOCSHOT_REDEFINITION_PLAN.md. Verified.
- 2026-11-17: C0.5 shortcut rework committed as e5288d4 on feature/c0.5-shortcuts, local only, not merged or pushed. Tests passed on the last run; all device checks now pass (the last 18 user-reported on 17 Nov). Verified.
- 2026-11-14: Settings window clipping fixed on the branch. Tests only, not yet seen in the app.
- 2026-11-17: Noel looked at the fixed build: shortcuts look good, Settings liked. No row-by-row results. Inherited.
- 2026-11-17: C0.6 preview thumbnail committed on feature/c0.6-preview-thumbnail, local only. Fable review and re-review: no check contradicted; six defects found and fixed. swift test 278 and xcodebuild test 279 pass with the three hotkey suites skipped; parity audit OK. Noel ran the 18 device checks: all pass (user-reported).
- 2026-11-17: C0.7 colour themes committed on feature/c0.7-themes, local only. Fable review: one defect found and fixed. swift test 290 and xcodebuild test 291 pass with the hotkey suites skipped; parity audit OK. Noel ran the 10 device checks: all pass (user-reported).
- 2026-11-17: Colour themes added as C0.7 on Noel's say: Graphite (default), Slate, Moss, Ember; interface only; light and dark; picked in Settings. Plan only. Verified in session.
- 2026-11-17: Preview thumbnail added to the plan as C0.6 on Noel's say (plan §§2, 6, 7, 12). Short plan agreed by Noel the same day (six answers, plan §7). Verified.
- macOS V1 done; origin/main 291a4a4, tag macos-v1.0.0. Inherited.

## Left
- C3 to C4, C4a OCR, C4b Float, freeze, C5 (plan §6).
- Merge the three windows/* branches into main; Windows work stays paused.
- Update PRODUCT_BRIEF.md, README.md and BACKLOG.md (plan §11), after the C0.5 commit.

## Blocker
- None.

## Next action
- Quiet restyle of the clipboard window done on feature/quiet-clipboard (from C3's 9ef04d1), uncommitted: Noel says it looks good; tests pass. Next: commit with Noel's yes. After that, per the Quiet migration plan: step 2 (DocShot tokens and themes as accent swaps, needs Noel's theme-name decision), then the other screens. Do not merge or push without Noel's say.
- Due: none

## Human-only tail
- Approve any commit, push, deploy, publish or spend.
- Confirm whether the LinkedIn post is dropped.
- Delete STATUS.md.bak-2026-11-14 (the one-page STATUS.md was accepted on 2026-11-16).
