# CLAUDE.md: Drive Lab

A realistic driving sandbox on Roblox around a detailed Lamborghini Aventador SVJ: physics,
cameras, cockpit, sound, weather, lights. Private portfolio project. Built by agents under one
owner; **read `docs/engineering/AGENTIC_WORKFLOW.md` before your first change.**

## The rules that matter most

- **Own your mistakes.** Mistakes are expected. When a check fails, a measurement contradicts
  the plan, or you need to deviate from a recorded decision, say so at once (to your lead or the
  coordinator, and in the PR's provenance), explain why, then fix it. Never work around a failing
  check, loosen a test or change a decided behaviour silently to get the gates green: a green gate
  over a hidden problem is the worst thing we can ship. Nobody is blamed for an honest report.
- Plan first. Anything new is planned and approved by the owner before code.
- Every change: an issue, a branch `agent/<area>-<slug>` in its own worktree under `.worktrees/`,
  a PR with the template filled, your own self-review comment, CI green. The coordinator merges.
- Restate the owner's requests as requirements (goal, scope, constraints, acceptance); never paste
  their chat words.
- Keep diffs readable: a code comment only says what the code cannot (a non-obvious why, a unit,
  a trap). History, dates, the owner's remarks, "was X" and measurements go in the commit message,
  the PR and the README decisions table, never in the code (owner, 2026-10-30).
- Evidence: gates green; every new rule's spec shown failing on a deliberate break; edit-mode
  Studio captures for anything visual; performance numbers for anything per-frame; an honest
  not-verified list. Feel is judged by the owner in Play, not measured by agents.
- A change to a runtime flow (input, round trips, state, timing) is run end to end in a short Play
  session before its PR (functional, not feel); a PR whose not-verified list names its own runtime
  path is not merged.
- Never: publish to Roblox, write DataStores, print or commit a key, force-push, rewrite history,
  start or stop the owner's playtest.

## Gates (from the repo root)

    stylua --check games kit tools
    selene games/drive-lab/src kit/src tools
    cd games/drive-lab && rojo sourcemap default.project.json -o sourcemap.json && luau-lsp analyze --sourcemap=sourcemap.json --definitions=../../roblox.d.luau --base-luaurc=../../.luaurc --ignore="**/packages/**" src
    lune run tools/test/run
    lune run tools/test/tools        # runs every games/<game>/tools/*.luau once (about 20 s)
    rojo build games/drive-lab/default.project.json -o drive-lab.rbxl

`roblox.d.luau` is downloaded, not committed (see the CI workflow). The toolchain is pinned in
`aftman.toml`. Read `.claude/skills/luau-standards/SKILL.md` before writing Luau.

## Studio

- Sync code into the place with the MCP `execute_luau` tool, while a local server serves the repo
  root on 8765 (`python -I -m http.server 8765 --bind 127.0.0.1`):

      local m = Instance.new("ModuleScript")
      m.Source = game:GetService("HttpService"):GetAsync("http://localhost:8765/tools/studio/dev.luau")
      return require(m).sync("games/drive-lab")

  A worktree syncs with its own path, e.g. `sync(".worktrees/<slug>/games/drive-lab")`.
- Before every Studio action, `get_studio_mode` AND `get_connected_instances`: act only when there
  are no server or client peers. `get_studio_mode` alone has answered "stop" during the owner's
  playtest (2026-10-28). Edit mode only; the `.studio-lock` (with an owner file)
  for captures, camera moves and temporary objects; restore everything.
- List every change stored in the place in your PR: only the owner saves the place.

## Units and contracts

- `Shared.Units`: 1 stud = 0.28 / 1.5 m. Configs are in metres; code converts.
- The driven car publishes its readouts as attributes on its model (SpeedKmh, Rpm, Gear,
  Throttle, Brake, Steer, LongitudinalG, LateralG, DrivingMode, GearboxMode, ...); the camera
  publishes `DriveLabView` (OnFoot/Chase/Hood/Cockpit); the atmosphere publishes Workspace
  `RainIntensity` and `Wetness`.

## Git identity and attribution

Every agent authors its own commits under its role name, at a reserved non-routable address:

    git commit --author "Roadside agent <roadside@agents.drive-lab.invalid>" -m "..."

The committer stays the repository's configured identity (the owner's), so the history shows
who wrote a change and who let it in. No Co-Authored-By trailers. Never rewrite history to change
a past author. The PR's provenance section and the issue carry the rest of the story.
