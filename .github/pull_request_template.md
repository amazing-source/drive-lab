## What and why

<!-- The problem, then the change, in two or three sentences. -->

Closes #<!-- issue -->

## Agentic provenance

- **Built by:** <!-- agent role, e.g. "tyre smoke agent"; lead and sub-agents if split -->
- **Brief:** <!-- the requirement as restated in the issue, in one line; never the owner's raw words -->
- **Decisions taken on the way:** <!-- each choice, who made it (owner / coordinator / agent), and why -->

## Evidence

- [ ] Gates green locally: format, lint, types, unit tests, build
- [ ] Every new or changed rule has a spec, shown **failing** on a deliberate break (say what was broken and which line failed)
- [ ] Studio, edit mode: what was captured or measured (paths), or why it could not be
- [ ] Performance, for anything per-frame: method and numbers (script time p50/p95, frame time vs baseline)
- [ ] No key printed or committed; nothing published; no DataStore written

## Changes stored in the place

<!-- ApplyMesh, new assets under ReplicatedStorage.DriveLabAssets, uploaded asset ids. The owner must save the place for these. Write "none" if none. -->

## Not verified

<!-- Everything the evidence does not cover, plainly. Feel is judged by the owner in Play. -->

## Self-review

<!-- The author agent's own pass after the PR is open: re-read the diff, list anything it would flag in someone else's PR. Post it as the first comment. -->

## How to revert

<!-- The exact undo: revert this merge; and for place changes, what to restore. -->
