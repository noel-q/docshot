# STATUS: DocShot

- ID: P05
- Tier: C
- Status: Active
- Last updated: 2026-11-25
- Definition of done: Local-only macOS menu bar tool for Noel: screenshots with annotation, recording with editing, bounded clipboard history in one on-demand window. Meets the six-point stability bar (plan §8). Windows parity only after that.

## Done so far
- 2026-11-25: Clear works while history is off (07ed1ac on feature/clear-while-off): stored items and captures counted at launch and on switching off; Clear offered in Settings and the menu; the store opens only if history was ever kept. swift test 384, xcodebuild test 384, parity OK. Verified in the app on scratch data (Settings both themes, relaunch count, Clear removed 13, kept the pinned one, screenshot files gone); the menu bar item not seen.
- 2026-11-25: Road to C5 units 1 to 6 (permission window, image editor, video editor, C4 Captures, C4a text in images, C4b Float), one Fable batch review, fixes in. ClipboardKit 83, swift test 381, xcodebuild test 381. Verified by agent in the app on scratch data; Noel's look pending.
- 2026-11-25: Record shortcut now stops a live recording (it beeped before, despite the 17 Nov device-check entry). Fable: no defects; swift test 375, xcodebuild test 375. User-reported (Noel stopped a real recording).
- 2026-11-25: Onboarding guide in Quiet: compact panel, five pages, Next as the one accent, Return and Escape. Fable review fixed (record-shortcut stop claim removed; the shortcut itself does not stop a recording, inherited). swift test 374, xcodebuild test 374. Verified (snapshots, hook-driven keys) and user-reported ("Feels right").
- 2026-11-24: Compact Settings panel under the menu bar icon, growing in place to the four tabs. Fable review fixed; swift test 371, xcodebuild test 371. Verified (snapshots, traces) and user-reported ("Feels right").
- 2026-11-24: Compact clipboard panel: borderless rounded 420 pt panel, preview on Cmd+Y to 780 pt, remembered place, smooth resizing (frame-traced). Fable review fixed; swift test 367, xcodebuild test 367. Verified (snapshots, traces) and user-reported ("Feels right").
- 2026-11-24: Preview thumbnail restyled in Quiet (pilot step 3): floating panel, accent Copy with its key, keys under icons, Cmd+E for Edit, rise-in. Fable review fixed; swift test 358, xcodebuild test 358. Verified (snapshots) and user-reported ("Looks right").
- 2026-11-24: Settings restyled in Quiet (pilot step 3, first screen): toolbar tabs with eased resizing, grouped panels, switches, exact-count Clear, clipboard window keys and the open-history shortcut in Settings. Fable review fixed; swift test 355, xcodebuild test 355, ClipboardKit 76. Verified (agent snapshots and frame traces) and user-reported ("Looks right").
- 2026-11-24: Quiet restyle of the clipboard window (pilot step 1) committed as 9a1120d on feature/quiet-clipboard; Fable review fixed; swift test 352, xcodebuild test 353, ClipboardKit 76; Noel: "Looks good", clicks work. Verified (agent snapshots) and user-reported.
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
- Road to C5 units 1 to 6 built and committed, each on its own local branch, stacked: 66f854c permission window, 500161f image editor, a3018c8 video editor, cda3fda C4 Captures, 09efb97 C4a text in images, 7f71f8f C4b Float, then 71c3cec batch-review fixes (branch feature/c4b-float). Nothing pushed or merged. Noel said yes to the launch: his real history database is now schema 3 (13 items kept, captures table empty, Captures folder owner-only; verified 25 Nov). Clear while history is off built as 07ed1ac on feature/clear-while-off (stacked on feature/c4b-float). Current test build made from bb2307e, so it includes Clear while off (universal, macOS 14+, Apple Development-signed, not notarised, no debug hooks; DMG in dist/test-2026-11-25b, install steps in docs/INSTALL_TEST_BUILD.md) and sent to Noel; the earlier dist/test-2026-11-25 build lacks it. Waiting for Noel's look at all six and at Clear while off; it gets its Fable review with the next batch. Then the feature freeze (stability bar point 6), which starts C5; then the tester build. Do not merge or push without Noel's say.
- Due: none

## Human-only tail
- Approve any commit, push, deploy, publish or spend.
- Confirm whether the LinkedIn post is dropped.
- Delete STATUS.md.bak-2026-11-14 (the one-page STATUS.md was accepted on 2026-11-16).
