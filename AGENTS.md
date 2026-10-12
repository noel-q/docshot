# Project instructions

Personal style and tone come from the global AGENTS file. This file holds only what is specific to this project.

## Project
DocShot repository.

## Read first (maximum two files)
1. STATUS.md (current state: definition of done, next action, blocker, human-only tail)
2. HANDOFF.md if it exists

Everything else is reference. Open other files only when the current action needs them.

## Source of truth
Current instructions from Noel outrank older documents.

## Rules
- Label claims verified, inherited, assumed, proposed or unknown. A passing local build is not delivery evidence.
- Do not commit, push, deploy, publish, spend, send messages to people or run live migrations without explicit authority from Noel.
- Keep secrets, real personal data and large generated files out of the repo and out of docs.
- One writer at a time. Do not edit files another agent is changing.
- When starting or first touching a project folder with no STATUS.md, run `node ~/Documents/ai-skills/skills/handoff/scripts/bootstrap-project.mjs <folder>` before other work.

## Handoff
Follow the handoff skill at the start and end of each unit of work. Update the next action in STATUS.md, run `node tools/handoff.mjs --from <tool> --to <tool>`, and move to a fresh session when the skill says so, whether the cause is a nearing usage limit or degraded context.
