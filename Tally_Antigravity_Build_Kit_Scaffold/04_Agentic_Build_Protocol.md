# Agentic Build Protocol for Antigravity

## Mission
Build Tally end-to-end with minimal user intervention while reducing drift, unverified assumptions, and rework.

## Operating Rules
1. Read all files in this package before writing code.
2. Use the manifest as the source of truth.
3. Work in **small, reversible increments**.
4. Never mark work complete without verification.
5. Log each iteration.
6. Record blockers, assumptions, and decisions explicitly.
7. Update checkpoint and state files after every task.
8. Prefer native iOS best practices over clever shortcuts.
9. Protect privacy: never implement a backend that stores Canvas content.
10. If uncertain, create a TODO note and proceed only with safe, justified assumptions.

## Required Iteration Loop
### 1. Plan
- Load manifest task.
- Confirm inputs, outputs, dependencies, and acceptance criteria.
- Write a short plan to `build/logs/iteration_journal.md`.

### 2. Implement
- Change only the files required for the current task.
- Keep commits atomic.
- Avoid touching unrelated modules.

### 3. Verify
- Run lint.
- Run unit tests relevant to the change.
- Run build.
- If UI change: run preview or UI test if available.
- Document verification evidence.

### 4. Update State
- Update `build/state/current_status.json`
- Update `build/checkpoints/phase-<n>.md`
- Append any decisions to `build/decisions/`

### 5. Continue
- Select next unblocked task from manifest.
- Repeat until phase complete.

## Drift-Control Rules
- Do not redesign architecture mid-build without ADR.
- Do not invent hidden backend services.
- Do not persist Canvas data off-device.
- Do not skip tests to move faster.
- Do not close a task if any acceptance criterion is unmet.
- Do not delete logs/checkpoints.

## Logging Requirements
Each iteration must record:
- timestamp
- current task ID
- objective
- files changed
- validations run
- result
- next action
- blocker, if any

## Resume Protocol
If interrupted:
1. Read `build/state/current_status.json`
2. Read latest `build/logs/iteration_journal.md` entries
3. Read the active checkpoint file
4. Resume the first incomplete task in the manifest
