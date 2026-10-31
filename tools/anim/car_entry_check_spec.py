"""
Spec for car_entry_check.py's per-group contact rule, on synthetic one-frame scenes.

A Right Leg box (half extents 0.5, 1, 0.5) has small flat patches cut into it at known depths, one
per surface group. The allow list lets the leg 0.25 into "seat" only. Each case states what the
deepest-only rule and the per-group rule must answer; exit code 1 when any answer differs.

  python -I tools/anim/car_entry_check_spec.py [--keep DIR]

--keep writes each case's baked.json, scene.npz and allow.json under DIR (to run another checker
on them).
"""
import contextlib
import io
import json
import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import car_entry_check as check  # noqa: E402

LEG = np.array([0.0, 3.0, 0.0])
IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1]
AWAY = {
    "Torso": (-5.0, 5.0, 0.0),
    "Head": (-5.0, 7.0, 0.0),
    "Right Arm": (-6.5, 5.0, 0.0),
    "Left Arm": (-3.5, 5.0, 0.0),
    "Left Leg": (-5.5, 3.0, 0.0),
}
SEAT_ONLY = [{"from": 0, "to": 0, "parts": ["Right Leg"], "groups": ["seat"], "depth": 0.25}]


def quad(corner, u, v):
    a = np.asarray(corner, dtype=float)
    return np.array([a, a + u, a + u + v, a + v]), np.array([[0, 1, 2], [0, 2, 3]], dtype=np.int32)


def floor_patch(leg, depth):
    """A 0.2 x 0.2 patch, depth above the leg's bottom face."""
    y = leg[1] - 1.0 + depth
    return quad((leg[0] - 0.1, y, leg[2] - 0.1), np.array([0.2, 0, 0]), np.array([0, 0, 0.2]))


def side_patch(leg, depth):
    """A 0.4 x 0.2 patch, depth inside the leg's +X face."""
    x = leg[0] + 0.5 - depth
    return quad((x, leg[1] - 0.2, leg[2] - 0.1), np.array([0, 0.4, 0]), np.array([0, 0, 0.2]))


def write_case(folder, leg, car, door=None, allow=SEAT_ONLY):
    os.makedirs(folder, exist_ok=True)
    parts = {name: list(c) + IDENTITY for name, c in AWAY.items()}
    parts["Right Leg"] = list(leg) + IDENTITY
    baked = {"fps": 30, "frames": [{"frame": 0, "door": 0.0, "parts": parts}]}
    scene = {"groups": np.array(list(car)), "hinge_pivot": np.zeros(3), "hinge_axis": np.array([0.0, 0, 1])}
    scene["open_angle"] = np.array(1.5)
    for group, (v, f) in car.items():
        scene[f"v_{group}"], scene[f"f_{group}"] = v.astype(np.float32), f
    if door is not None:
        scene["v_door"], scene["f_door"] = door[0].astype(np.float32), door[1]
    paths = {k: os.path.join(folder, n) for k, n in (("baked", "baked.json"), ("scene", "scene.npz"), ("allow", "allow.json"))}
    for key, data in (("baked", baked), ("allow", allow)):
        with open(paths[key], "w", encoding="utf-8") as handle:
            json.dump(data, handle)
    np.savez(paths["scene"], **scene)
    return paths


def run(paths, *flags):
    out = os.path.join(os.path.dirname(paths["baked"]), "check.json")
    argv = [paths["baked"], paths["scene"], "--allow", paths["allow"], "--json", out, *flags]
    with contextlib.redirect_stdout(io.StringIO()):
        code = check.main(argv)
    with open(out, encoding="utf-8") as handle:
        record = json.load(handle)
    failed = sorted((part, group, round(depth, 3)) for _, part, group, depth in record["failures"])
    return code, failed, record["per_group"]


def main(argv):
    keep = argv[argv.index("--keep") + 1] if "--keep" in argv else None
    root = keep or tempfile.mkdtemp(prefix="car_entry_check_spec_")
    seat = floor_patch(LEG, 0.22)
    low_leg = LEG - np.array([0.0, 2.1, 0.0])  # its bottom face 0.1 below the ground
    cases = {
        "masked_cage": write_case(f"{root}/masked_cage", LEG, {"seat": seat, "cage": side_patch(LEG, 0.20)}),
        "masked_door": write_case(f"{root}/masked_door", LEG, {"seat": seat}, door=side_patch(LEG, 0.20)),
        "masked_ground": write_case(f"{root}/masked_ground", low_leg, {"seat": floor_patch(low_leg, 0.22)}),
        "both_allowed": write_case(
            f"{root}/both_allowed",
            LEG,
            {"seat": seat, "cage": side_patch(LEG, 0.20)},
            allow=SEAT_ONLY + [{"from": 0, "to": 0, "parts": ["Right Leg"], "groups": ["cage"], "depth": 0.21}],
        ),
        "cage_under_tol": write_case(f"{root}/cage_under_tol", LEG, {"seat": seat, "cage": side_patch(LEG, 0.03)}),
        "deepest_over": write_case(f"{root}/deepest_over", LEG, {"seat": seat, "cage": side_patch(LEG, 0.20)}, allow=[]),
    }
    leg = "Right Leg"
    expect = [
        # The blind spot: the seat contact is allowed and deeper, so the cage contact is never tested.
        ("masked_cage", ("--no-per-group",), (0, [], False)),
        ("masked_cage", ("--per-group",), (1, [(leg, "cage", 0.2)], True)),
        ("masked_cage", (), (1, [(leg, "cage", 0.2)], True)),
        ("masked_door", ("--no-per-group",), (0, [], False)),
        ("masked_door", ("--per-group",), (1, [(leg, "door", 0.2)], True)),
        ("masked_ground", ("--no-per-group",), (0, [], False)),
        ("masked_ground", ("--per-group",), (1, [(leg, "ground", 0.1)], True)),
        # Controls: legitimate contacts still pass, and what the old rule failed still fails.
        ("both_allowed", ("--per-group",), (0, [], True)),
        ("cage_under_tol", ("--per-group",), (0, [], True)),
        ("deepest_over", ("--no-per-group",), (1, [(leg, "seat", 0.22)], False)),
        ("deepest_over", ("--per-group",), (1, [(leg, "cage", 0.2), (leg, "seat", 0.22)], True)),
    ]
    bad = 0
    for name, flags, want in expect:
        got = run(cases[name], *flags)
        ok = got == want
        bad += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:15s} {' '.join(flags) or '(default)':15s} exit {got[0]} failures {got[1]}")
        if not ok:
            print(f"     expected exit {want[0]} failures {want[1]} per_group {want[2]}; got per_group {got[2]}")

    # A scene listed in DEEPEST_ONLY_SCENES defaults to the deepest-only rule.
    listed = check.DEEPEST_ONLY_SCENES
    check.DEEPEST_ONLY_SCENES = frozenset({check.file_sha256(cases["masked_cage"]["scene"])})
    try:
        got = run(cases["masked_cage"])
    finally:
        check.DEEPEST_ONLY_SCENES = listed
    ok = got == (0, [], False)
    bad += not ok
    print(f"{'ok  ' if ok else 'FAIL'} {'masked_cage':15s} {'(listed scene)':15s} exit {got[0]} failures {got[1]} per_group {got[2]}")

    print(f"{bad} of {len(expect) + 1} expectations failed" if bad else f"all {len(expect) + 1} expectations hold")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
