# STATUS: DocShot

- ID: P05
- Tier: C
- Status: Active
- Last updated: 2026-11-17
- Definition of done: Local-only macOS menu bar tool for Noel: screenshots with annotation, recording with editing, bounded clipboard history in one on-demand window. Meets the six-point stability bar (plan §8). Windows parity only after that.

## Done so far
- 2026-11-17: Plan approved; all §10 decisions settled (plan §§2, 4.2, 4.5, 5, 6, 7, 10). Build lane: Opus 5.5 High builds, Fable reviews. Verified in session.
- 2026-11-17: Handoff files, plan and progress log committed as f3be4d4, local only. Verified.
- 2026-11-14: Redefinition plan agreed: docs/DOCSHOT_REDEFINITION_PLAN.md. Verified.
- 2026-11-17: C0.5 shortcut rework committed as e5288d4 on feature/c0.5-shortcuts, local only, not merged or pushed. Tests passed on the last run; device checks partly done (docs/DEVICE_VERIFICATION.md). Verified.
- 2026-11-14: Settings window clipping fixed on the branch. Tests only, not yet seen in the app.
- 2026-11-17: Noel looked at the fixed build: shortcuts look good, Settings liked. No row-by-row results. Inherited.
- 2026-11-17: Preview thumbnail added to the plan as C0.6 on Noel's say (plan §§2, 6, 7, 12). Plan only, nothing built. Verified.
- macOS V1 done; origin/main 291a4a4, tag macos-v1.0.0. Inherited.

## Left
- C0.5: remaining device checks (rows marked Not run).
- C0.6 preview thumbnail (plan §7), after the C0.5 commit.
- C0 spikes, then C1 to C4, C4a OCR, C4b Float, freeze, C5 (plan §6).
- Merge the three windows/* branches into main; Windows work stays paused.
- Update PRODUCT_BRIEF.md, README.md and BACKLOG.md (plan §11), after the C0.5 commit.

## Blocker
- None.

## Next action
- Write the short plan for C0.6 (preview thumbnail, plan §7) and show it to Noel before building. Do not merge feature/c0.5-shortcuts to main or push without Noel's say.
- Due: none

## Human-only tail
- Approve any commit, push, deploy, publish or spend.
- Confirm whether the LinkedIn post is dropped.
- Delete STATUS.md.bak-2026-11-14 (the one-page STATUS.md was accepted on 2026-11-16).
