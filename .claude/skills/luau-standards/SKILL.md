---
name: luau-standards
description: The coding standard for every Roblox Luau file in this kit, the bar a senior engineer reviewing the code expects. Use before writing or editing any .luau file, when reviewing Luau, or when asked to clean up code. Covers naming, file layout, strict types, comment discipline, lifecycle and cleanup, networking security, error handling, performance, and the AI-slop tells to eliminate, plus the gate to run before handing code over.
---

# Luau standards

Sources: the Roblox Lua Style Guide, luau.org (performance, types), and the Roblox docs
(security, network ownership, deferred events, native codegen), read 2026-10-15. Full notes
with citations: `research_notes/Roblox build standards/code_quality.md`.

The reader is a senior engineer. Every line must earn its place. Code that is short,
typed and obvious beats code that is clever or commented.

## Layout and naming

- `--!strict` on every file. Order: services → requires (alphabetical) → constants →
  types → locals and functions → the returned table → `return`.
- Spell words out. `PascalCase` for modules, classes, types and enum-like tables;
  `camelCase` for locals, fields and functions; `LOUD_SNAKE_CASE` for constants; `_camelCase`
  for private members. Acronyms as words: `userId`, `HttpClient`.
- The file name is the module name. One term per concept across the whole project: if it is
  `car` in config, it is not `vehicle` in one service and `ride` in another.
- One responsibility per module, about 300 lines at most. One job per function, about 40
  lines and three levels of nesting at most. Guard clauses instead of pyramids.
- No `Utils`, `Helpers`, `Manager` or `Misc` modules. Name the concept, or the code
  belongs somewhere else.

## Types

- Annotate every parameter and return. Annotate empty tables (`local cache: { [Player]: Session } = {}`).
- `export type` in the module that owns the concept. Prefer `unknown` plus refinement to
  `any`; every `any` or `:: any` needs a reason a reviewer would accept.
- String unions for states (`type Phase = "Idle" | "Chasing" | "Asleep"`), never free strings.
- Class pattern: `Class.__index = Class`,
  `export type Class = typeof(setmetatable({} :: Fields, Class))`, a `new` constructor, and
  methods declared `function Class.method(self: Class, ...)`.

## Comments

Default to none. A comment states **why**, an invariant the types cannot express, or an
engine quirk. Never what the code does.

Delete on sight:
- narration (`-- loop over players`)
- restated names
- banners (`--// Services`, `-- ===== X =====`)
- step numbers
- changelog notes
- commented-out code
- TODOs with no condition
- emoji anywhere: code, logs or UI strings

A top-of-file block is allowed only for why the module exists, and only when that is not
obvious. Doc blocks only on public APIs others will call. Target below 5% comment lines; zero
is fine.

## Architecture

- Pure logic (economy maths, rolls, curves, validation) lives in plain modules with no
  Roblox APIs, so Lune can test it. Engine glue is thin and calls the pure modules.
- Each service exports `init(deps)` and `start()`. Nothing runs at require time: no
  connections, loops or spawns. One bootstrap script per side requires the services, calls
  every `init`, then every `start`.
- Dependencies arrive as parameters or explicit requires, never through `_G`, `shared` or
  hidden singletons. State is module-private behind a narrow API.
- All tunables live in `Config` modules with exported types. Logic modules contain no magic
  numbers or display strings.
- Server-only code and data stay in ServerScriptService or ServerStorage. ReplicatedStorage
  holds only what the client needs.
- No abstraction before its second real use. Functions and tables over inheritance.

## Lifecycle and memory

- `task.spawn/defer/delay/wait/cancel` only. `os.clock()` for durations,
  `workspace:GetServerTimeNow()` or `os.time()` for shared time. Never `wait`, `spawn`,
  `delay` or `tick`.
- Every connection has an owner. Per-player resources go in a `Trove` created on join and
  cleaned on `PlayerRemoving`. Use `Once` for one-shots.
- After any yield (DataStore, `InvokeServer`, `WaitForChild`, `task.wait`), re-check that
  the player and session still exist before touching them.
- Set every property first and `Parent` last. Never use `Instance.new(class, parent)`.
- Code must not depend on immediate signal order (`SignalBehavior` is Deferred).

## Networking and security

- The server is authoritative. Clients send intent ("steal the car on pad 3"), never
  outcomes ("I now own car X").
- Every remote is declared once in `Net` with a validator and a rate limit. Validators
  check `typeof`, NaN and infinity, ranges, string length, membership in config sets, and
  that Instances are descendants of the expected container.
- Re-check distance and state on the server for `Touched`, ProximityPrompt and remotes:
  all of them can be fired from anywhere.
- Client-owned vehicles: compare movement against the player's allowed speed with a
  tolerance envelope and a leaky bucket. Reject non-finite values. Rubber-band, don't kick,
  on the first violation.
- Never let a client-reported value set money, speed, ownership or prices.

## Errors and logging

- `pcall` only at boundaries: DataStore, MemoryStore, Marketplace, HTTP, and the top of
  remote handlers. Never swallow a result silently.
- `assert` for programmer errors. Failable operations return `(ok, result)` or `T?`.
  Bounded exponential backoff for retries.
- Log through `Log` with levels. No `print` in committed code.

## Performance

- Build tables in one literal with every field (stable shapes). Use `table.create` when the
  size is known. Use generic `for` without `pairs`/`ipairs`.
- Event-driven over polling. One Heartbeat loop over a registry, not a loop per entity.
  Cache instance lookups at init.
- Batch network traffic. Send state once per tick, not per change. Use
  `UnreliableRemoteEvent` for cosmetic high-frequency data.
- `@native` only on hot numeric functions, and only after measuring. No ritual
  micro-optimisation (localising `math`, caching `Vector3.new`).

## Gate before handing over

Run from the repo root. All of these must be clean:

```
stylua --check games kit tools
selene games kit tools
rojo sourcemap games/<game>/default.project.json -o sourcemap.json
luau-lsp analyze --sourcemap=sourcemap.json --definitions=roblox.d.luau games kit
lune run tests
```

Then grep for `wait(`, `spawn(`, `delay(`, `tick(`, `:: any`, `print(`, `_G`, `--//`,
`-- ==`, and emoji. Any hit gets fixed or justified.
