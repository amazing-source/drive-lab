# Drive Lab

A realistic driving sandbox on Roblox, built around a detailed Lamborghini Aventador SVJ:
offline-calibrated vehicle physics, chase / cockpit / hood cameras, a working cockpit (animated
instrument cluster, steering wheel, hands on the rim), the car's own engine sound, lights,
weather with rain that wets the road, a driving HUD, and camera feel (vibration, motion blur).

It is also an experiment in **production-style agentic development**: the code, assets and docs
are built by AI agents working through issues and pull requests under one human owner. How that
works, and the evidence every change must carry, is in
[`docs/engineering/AGENTIC_WORKFLOW.md`](docs/engineering/AGENTIC_WORKFLOW.md).

## Layout

| Path | What |
|---|---|
| `games/drive-lab/` | The game: `src/` (client, server, shared), `tests/` (Lune specs), `tools/` (offline sims and previews). Systems map in its [README](games/drive-lab/README.md) |
| `kit/` | Shared Luau library (logging, isolation, cleanup) |
| `packages/` | Vendored third-party Luau packages, with their licences |
| `tools/` | Test runner, Studio sync, and the asset pipelines' scripts (Blender, audio, textures) |
| `docs/pipelines/` | How each kind of asset is made, so it can be made again to the same standard |
| `docs/engineering/` | The agentic workflow |
| `docs/history/` | Where the project came from |

## Working on it

Toolchain pinned in `aftman.toml` (`aftman install`). Gates, Studio sync and the rules for agents
are in [`CLAUDE.md`](CLAUDE.md). CI runs the same gates on every push and pull request.
