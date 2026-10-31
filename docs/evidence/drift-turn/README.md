# Arcade drift: evidence (#195)

Systems agent, 2026-10-31. Offline on `tools/DriveSim`, driven on the keys (`tools/DriftTurn`); no
Studio.

| File | What it is |
|---|---|
| `before_60fps.txt` | `tools/drift_turn.luau` from this branch, run on main 2f81def: the angle-holding drift before this change |
| `after_30fps.txt`, `after_60fps.txt`, `after_120fps.txt` | The same tool on this branch |
| `tools_identical.txt` | Every game tool run on main and on this branch without the drift button: all identical except calibrate's wall-clock timing line |
| `breaks.txt` | Nine deliberate breaks against `tests/Drift.spec.luau`. Eight failed. The one that did not (the handbrake held off during the exit) led to that rule's removal |
