# STATUS: DocShot

- ID: P05
- Tier: C
- Status: Active
- Last updated: 2026-11-16
- Definition of done: Local-only macOS menu bar tool for Noel: screenshots with annotation, recording with editing, bounded clipboard history in one on-demand window. Meets the six-point stability bar (plan §8). Windows parity only after that.

## Done so far
- 2026-11-14: Redefinition plan agreed: docs/DOCSHOT_REDEFINITION_PLAN.md. Verified.
- 2026-11-14: C0.5 shortcut rework built on feature/c0.5-shortcuts, uncommitted. Tests pass; partly checked in the app. Detail: docs/DEVICE_VERIFICATION.md, docs/PROGRESS_LOG.md.
- 2026-11-14: Settings window clipping fixed on the branch. Tests only, not yet seen in the app.
- macOS V1 done; origin/main 291a4a4, tag macos-v1.0.0. Inherited.

## Left
- C0.5: device checks, then commit.
- C0 spikes, then C1 to C5 clipboard milestones (plan §6).
- OCR and pin-to-screen, if Noel confirms.
- Merge the three windows/* branches into main; Windows work stays paused.
- Update PRODUCT_BRIEF.md, README.md and BACKLOG.md once the plan is signed off.

## Blocker
- None. Commits wait on Noel's approval.

## Next action
- Noel runs the C0.5 device checks, then approves the two commits on feature/c0.5-shortcuts. Do not merge to main.
- Due: none

## Human-only tail
- Approve any commit, push, deploy, publish or spend.
- Sign off plan §10: retention defaults, OCR and pin-to-screen, name, who builds what.
- Decide whether DocShot stays Tier C.
- Confirm whether the LinkedIn post is dropped.
- Delete STATUS.md.bak-2026-11-14 once this version is accepted.
