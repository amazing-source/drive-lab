"""Keys a car's gear-lever hand (Config/DriverShift, Rules/ShiftHand) from measured inputs: the lever's
geometry, the right hand's grip on the knob, and the way between the steering grip and the knob.
Writes the car's Shift.luau and the paths.json that shift_check.py and the renders read.

  python tools/anim/shift_paths.py <inputs.json> <out dir> [--write <Shift.luau>]

inputs.json (seat frame, metres: x right, y up, z back, unless named):
  cabin, seat          the cockpit dump and the dump's point where the DriverSeat sits (as the
                       gesture tools read them)
  driver               shoulders (studs), upper, lower (studs), elbowBias: the arm controller's
  grip, wheel          hands.json, and the steering hub (pivot, axis, lift) it was posed on
  poses                hand_poses.py's poses.json: the Knob hand's ball places the knob grip (the open
                       hand's palm when the poses have no Knob)
  shiftConfig          games/drive-lab/tools/shift_config.luau's print: the model binding's shifter and
                       seat (car frame), the gearbox's gates; the lever is turned into the seat frame as
                       Rules/ShiftHand.leverFromBinding does
  seatCar              (forward, right, up) the DriverSeat's point the keys are made against, when the
                       binding's seat is still pending (all zero); otherwise it must equal the binding's
  knobRadius           the ball's radius
  shifter, gates       instead of shiftConfig (the synthetic prototype): pivot, knob, right, back,
                       knobRadius, columns [[column, degrees]...], forward, backward (degrees), push;
                       gates name -> [column, row]
  knobGrip             pitch (fingers forward and down, degrees), yaw (about the vertical, positive
                       turns the fingers toward the car's right), roll (about the fingers); palmGap (m)
                       only for the open-palm fallback
  reach                duration, offRim [out from the hub, up the wheel's face, toward the driver] (the
                       wheel's frame, m: the way's first pull, so the open fingers slide off the rim before
                       the hand comes back; the older lift [toward the driver, up] in the seat frame),
                       over (m above the knob grip at the way's middle), openAt, closeAt (seconds),
                       turnFrom (share of the eased way the hand keeps the grip's turn, so the
                       closed fingers leave the rim before the hand turns toward the knob)
  release, foot        seconds (the human pace); quick: {reach, release, foot}, the game-quick preset
  manifest             (optional) the 3D manifest: each gate's knob offset from neutral there
                       (knob_offset_m, worked out in Blender by the modeller) must match this lever's
                       to OFFSET_TOLERANCE, a check on the lever's turn that does not share its code

The lever turns as Rules/ShiftHand.lever turns it (sideways for the column, then fore and aft, about
the pivot). paths.json carries the knob's frame at every gate and at mid-path places for the Luau
parity spec.
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gesture_paths import STUDS, Frame, luau, matrix_quat, quat_matrix, rotation, sample, smooth, to_seat, unit, wheel_axes  # noqa: E402,F401

KEY_STEP = 1 / 60
# The manifest's knob offsets are rounded to 0.1 mm.
OFFSET_TOLERANCE = 0.0001
GATE_ORDER = ["R", "N", "1", "2", "3", "4", "5", "6"]


class Shifter:
    """Rules/ShiftHand's lever, as the manifest's gate motion turns it: sideways about the forward axis
    for the column (positive to the car's right), then fore and aft about the car's right for the row
    (positive forward), about the pivot."""

    def __init__(self, spec):
        self.pivot, self.knob = np.array(spec["pivot"], float), np.array(spec["knob"], float)
        self.right, self.back = unit(spec["right"]), unit(spec["back"])
        self.radius = spec["knobRadius"]
        self.columns = sorted((float(c), float(d)) for c, d in spec["columns"])
        self.forward, self.backward, self.push = spec["forward"], spec["backward"], spec["push"]

    @classmethod
    def from_binding(cls, config, seat_car, knob_radius):
        """Rules/ShiftHand.leverFromBinding: each column's angle is its gears' side angle, the rows'
        angles their gears' fore angles, the points moved into the seat frame at `seat_car`."""
        shifter = config["shifter"]
        by_column, forward, backward = {}, None, None
        for label, gate in config["gates"].items():
            angles = shifter["gates"][label]
            side = math.degrees(angles["side"])
            known = by_column.get(gate["column"])
            assert known is None or abs(known - side) < 1e-3, f"column {gate['column']}'s gears disagree"
            by_column[gate["column"]] = side
            fore = math.degrees(angles["fore"]) * gate["row"]
            if gate["row"] > 0:
                assert forward is None or abs(forward - fore) < 1e-3, "the forward gears disagree"
                forward = fore
            elif gate["row"] < 0:
                assert backward is None or abs(backward - fore) < 1e-3, "the back gears disagree"
                backward = fore
        seat = chassis(seat_car)
        return cls(
            {
                "pivot": (chassis(shifter["pivot"]) - seat).tolist(),
                "knob": (chassis(shifter["knob"]) - seat).tolist(),
                "right": (-chassis(shifter["axisFore"])).tolist(),
                "back": (-chassis(shifter["axisSide"])).tolist(),
                "knobRadius": knob_radius,
                "columns": sorted([c, d] for c, d in by_column.items()),
                "forward": forward,
                "backward": backward,
                "push": shifter["push"],
            }
        )

    def column_angle(self, column):
        cols = self.columns
        if column <= cols[0][0]:
            return cols[0][1]
        for (c0, d0), (c1, d1) in zip(cols, cols[1:]):
            if column <= c1:
                return d0 + (d1 - d0) * (column - c0) / (c1 - c0)
        return cols[-1][1]

    def lever(self, column, row, knob=0.0):
        """The knob's frame: its centre, and the seat's axes turned with the lever."""
        side = rotation(-self.back, math.radians(self.column_angle(column)))
        fore = rotation(-self.right, math.radians(self.forward * row if row >= 0 else self.backward * row))
        turn = fore @ side
        offset = turn @ (self.knob - self.pivot)
        pushed = self.push * min(1.0, max(0.0, knob)) / np.linalg.norm(offset)
        return Frame(turn, self.pivot + offset * (1 - pushed))

    def as_luau(self):
        return {
            "pivot": vec(self.pivot),
            "knob": vec(self.knob),
            "right": vec(self.right),
            "back": vec(self.back),
            "knobRadius": self.radius,
            "columns": [{"column": c, "degrees": d} for c, d in self.columns],
            "forward": self.forward,
            "backward": self.backward,
            "push": self.push,
        }


def chassis(point):
    """Rules/Hinge.chassis: a car-frame point (forward, right, up) in the chassis's axes (x right, y
    up, z back)."""
    if isinstance(point, dict):
        point = (point["forward"], point["right"], point["up"])
    return np.array([point[1], point[2], -point[0]], float)


def vec(v):
    return {"x": round(float(v[0]), 5), "y": round(float(v[1]), 5), "z": round(float(v[2]), 5)}


def path_states(gates, start, end, steps=24):
    """The lever's places along Vehicle/ShiftPlan's path from gate `start` to `end` (out of the gate to
    the rail, the knob down into reverse, across, into the gate), as (column, row, knob)."""
    c0, r0 = gates[start]
    c1, r1 = gates[end]
    into_reverse = end == "R" and start != "R"
    states = []
    for k in range(steps + 1):
        states.append((c0, r0 * (1 - k / steps), 0.0))
    if into_reverse:
        for k in range(1, steps + 1):
            states.append((c0, 0.0, k / steps))
    knob = 1.0 if into_reverse else 0.0
    for k in range(1, steps + 1):
        states.append((c0 + (c1 - c0) * k / steps, 0.0, knob))
    for k in range(1, steps + 1):
        states.append((c1, r1 * k / steps, knob if k < steps else 0.0))
    return states


def knob_grip(shifter, poses, spec):
    """The wrist frame gripping the knob, in the knob's frame: the fingers forward and down by
    `pitch`, turned about the vertical by `yaw` and about the fingers by `roll`; the Knob hand's ball
    (hand_poses.py, the ball it was closed round) on the knob's centre, or without a Knob hand the open
    hand's palm `palmGap` off the ball."""
    p, yaw, roll = (math.radians(spec[k]) for k in ("pitch", "yaw", "roll"))
    fingers = np.array([0.0, -math.sin(p), -math.cos(p)])
    back_of_hand = np.array([0.0, math.cos(p), -math.sin(p)])
    turn = rotation([0, 1, 0], -yaw)
    fingers, back_of_hand = turn @ fingers, turn @ back_of_hand
    spin = rotation(fingers, roll)
    back_of_hand = spin @ back_of_hand
    z = -fingers
    y = unit(back_of_hand - z * (back_of_hand @ z))
    rot = np.stack([np.cross(y, z), y, z], 1)
    knob = poses["shapes"].get("Knob", {}).get("R", {})
    if "ball" in knob:
        ball = np.array(knob["ball"], float) / poses["studsPerMetre"]
        radius = knob["ballRadius"] / poses["studsPerMetre"]
        assert abs(radius - shifter.radius) < 5e-4, f"the Knob hand was closed round a {radius:.4f} m ball, the knob is {shifter.radius:.4f}"
        return Frame(rot, -(rot @ ball))
    palm = np.array(poses["shapes"]["Rest"]["R"]["palm"], float) / poses["studsPerMetre"]
    target = y * (shifter.radius + spec["palmGap"])
    return Frame(rot, target - rot @ palm)


def compose(outer, inner):
    return Frame(outer.rot @ inner.rot, outer.apply(inner.pos))


def steering_grip(inputs):
    hands = json.load(open(inputs["grip"], encoding="utf-8"))["R"]
    axes, centre = wheel_axes({"steeringHub": inputs["wheel"], "steeringWheelLift": inputs["wheel"].get("lift", 0)})
    return to_seat(Frame.grip(hands["wrist"], hands["forearm"], hands["back"]), axes, centre)


def key_frame(key):
    return Frame(quat_matrix(key[4:8]), key[1:4])


def retarget(frame, frm, to, share):
    """Rules/StartupArms.retarget on frames."""
    turn = to.rot @ frm.rot.T
    angle = math.acos(max(-1.0, min(1.0, (np.trace(turn) - 1) / 2)))
    if angle < 1e-9:
        partial = np.eye(3)
    else:
        axis = np.array([turn[2, 1] - turn[1, 2], turn[0, 2] - turn[2, 0], turn[1, 0] - turn[0, 1]]) / (2 * math.sin(angle))
        k = np.array([[0, -axis[2], axis[1]], [axis[2], 0, -axis[0]], [-axis[1], axis[0], 0]])
        a = angle * share
        partial = np.eye(3) + math.sin(a) * k + (1 - math.cos(a)) * (k @ k)
    return Frame(partial @ frame.rot, frame.pos + (to.pos - frm.pos) * share)


def hand_on_way(keys, shapes, share, grip, knob_wrist):
    """Rules/ShiftHand.pose: the keyed way by share, its start carried onto the live grip and its end
    onto the live knob, and the shape shown at that share."""
    first, last = key_frame(keys[0]), key_frame(keys[-1])
    t = keys[0][0] + (keys[-1][0] - keys[0][0]) * share
    to_end = share * share * (3 - 2 * share)
    pos, q = sample(keys, t)
    frame = Frame(quat_matrix(q), pos)
    frame = retarget(frame, first, grip, 1 - to_end)
    shape = shapes[0]["shape"]
    for change in shapes:
        if t >= change["at"]:
            shape = change["shape"]
    return retarget(frame, last, knob_wrist, to_end), shape


def bezier(p0, p1, p2, p3, s):
    u = 1 - s
    return u**3 * p0 + 3 * u * u * s * p1 + 3 * u * s * s * p2 + s**3 * p3


def slerp_rot(a, b, s):
    qa, qb = matrix_quat(a), matrix_quat(b)
    if qa @ qb < 0:
        qb = -qb
    d = min(1.0, float(qa @ qb))
    if d > 0.9995:
        q = qa + (qb - qa) * s
    else:
        ang = math.acos(d)
        q = (qa * math.sin((1 - s) * ang) + qb * math.sin(s * ang)) / math.sin(ang)
    return quat_matrix(q / np.linalg.norm(q))


def reach_track(start, end, spec, wheel=None):
    """From the steering grip to the knob grip: off the rim (out along the wheel's face with "offRim",
    or toward the driver with "lift"), over the knob, down onto it, on an eased cubic; the hand turns
    on the same ease from turnFrom of the way."""
    duration = spec["duration"]
    if "offRim" in spec:
        p1 = start.pos + wheel @ np.array(spec["offRim"], float)
    else:
        p1 = start.pos + np.array([0.0, spec["lift"][1], spec["lift"][0]])
    p2 = end.pos + np.array([0.0, spec["over"], 0.0])
    hold = spec.get("turnFrom", 0.0)
    keys, t = [], 0.0
    while t < duration - 1e-9:
        s = smooth(t / duration)
        turn = smooth(max(0.0, (s - hold) / (1 - hold)))
        keys.append(Frame(slerp_rot(start.rot, end.rot, turn), bezier(start.pos, p1, p2, end.pos, s)).key(t))
        t = round(t + KEY_STEP, 6)
    keys.append(end.key(duration))
    shapes = [{"at": 0, "shape": "Grip"}, {"at": spec["openAt"], "shape": "Rest"}, {"at": spec["closeAt"], "shape": "Knob"}]
    return keys, shapes


def write_luau(path, data, about):
    body = luau(data, 0)
    text = (
        "--!strict\n--[[\n"
        + "".join(f"\t{line}\n" for line in about)
        + "]]\nlocal DriverShift = require(\"../../DriverShift\")\n\n"
        + f"local Shift: DriverShift.Shift = {body}\n\nreturn table.freeze(Shift)\n"
    )
    open(path, "w", encoding="utf-8", newline="\n").write(text)


# Places off the gates for the parity spec: (column, row, knob).
PARITY_PLACES = [(0.5, 0.0, 0.0), (-1.0, 0.0, 1.0), (-0.5, 0.0, 0.5), (1.0, 0.5, 0.0), (2.0, -0.3, 0.0), (0.0, -0.6, 0.0)]


def lever_inputs(inputs):
    """The Shifter, the gates (name -> (column, row)) and the seat point used (car frame, or None for
    the prototype's explicit lever)."""
    if "shiftConfig" not in inputs:
        return Shifter(inputs["shifter"]), {k: tuple(v) for k, v in inputs["gates"].items()}, None
    config = json.load(open(inputs["shiftConfig"], encoding="utf-8"))
    bound = config["seat"]
    bound = (bound["forward"], bound["right"], bound["up"])
    seat_car = tuple(inputs.get("seatCar", bound))
    if any(abs(c) > 1e-9 for c in bound):
        assert max(abs(a - b) for a, b in zip(seat_car, bound)) < 1e-4, f"keys made at seat {seat_car}, the binding's seat is {bound}"
    else:
        print(f"the binding's seat is pending (all zero): keys made at seatCar {seat_car}")
    shifter = Shifter.from_binding(config, seat_car, inputs["knobRadius"])
    gates = {k: (g["column"], g["row"]) for k, g in config["gates"].items()}
    return shifter, gates, seat_car


def offsets_against_manifest(shifter, gates, manifest_path, part="Shifter_Lever"):
    """Each gate's knob offset from neutral against the manifest's knob_offset_m (forward, right, up).
    Returns the worst difference, metres; raises when a gate is off by more than OFFSET_TOLERANCE."""
    parts = json.load(open(manifest_path, encoding="utf-8"))["parts"]
    offsets = next(p for p in parts if p["name"] == part)["knob_offset_m"]
    neutral = shifter.lever(*gates["N"]).pos
    worst = 0.0
    for label, gate in gates.items():
        o = offsets[label]
        theirs = np.array([o["right"], o["up"], -o["forward"]])
        mine = shifter.lever(*gate).pos - neutral
        off = float(np.abs(mine - theirs).max())
        assert off <= OFFSET_TOLERANCE, f"gate {label}: knob offset {np.round(mine, 4).tolist()} vs the manifest's {theirs.tolist()}"
        worst = max(worst, off)
    return worst


def parity(shifter, gates):
    rows = [{"at": g, "column": gates[g][0], "row": gates[g][1], "knob": 0.0} for g in GATE_ORDER if g in gates]
    rows += [{"at": "path", "column": c, "row": r, "knob": k} for c, r, k in PARITY_PLACES]
    for row in rows:
        frame = shifter.lever(row["column"], row["row"], row["knob"])
        row["position"] = [round(float(v), 6) for v in frame.pos]
        row["rotation"] = [round(float(v), 7) for v in matrix_quat(frame.rot)]
    return rows


def main(argv):
    inputs_path, out_dir = argv[0], argv[1]
    write = argv[argv.index("--write") + 1] if "--write" in argv else None
    inputs = json.load(open(inputs_path, encoding="utf-8"))
    os.makedirs(out_dir, exist_ok=True)
    shifter, gates, seat_car = lever_inputs(inputs)
    if "manifest" in inputs:
        print(f"knob offsets match the manifest's to {offsets_against_manifest(shifter, gates, inputs['manifest']) * 1000:.3f} mm")
    poses = json.load(open(inputs["poses"], encoding="utf-8"))
    grip_local = knob_grip(shifter, poses, inputs["knobGrip"])
    neutral = compose(shifter.lever(*gates["N"]), grip_local)
    start = steering_grip(inputs)
    wheel, _ = wheel_axes({"steeringHub": inputs["wheel"], "steeringWheelLift": inputs["wheel"].get("lift", 0)})
    keys, shapes = reach_track(start, neutral, inputs["reach"], wheel)
    grip_key = grip_local.key(0)
    data = {
        "knobRadius": shifter.radius,
        "grip": grip_key,
        "hand": {"keys": keys, "shapes": shapes},
        "reach": inputs["reach"]["duration"],
        "release": inputs["release"],
        "foot": inputs["foot"],
    }
    if "quick" in inputs:
        data["quick"] = {k: inputs["quick"][k] for k in ("reach", "release", "foot")}
    paths = {
        "inputs": os.path.abspath(inputs_path),
        "gates": gates,
        "gateOrder": [g for g in GATE_ORDER if g in gates],
        "shifter": shifter.as_luau(),
        "seatCar": seat_car,
        "parity": parity(shifter, gates),
        **data,
    }
    json.dump(paths, open(os.path.join(out_dir, "paths.json"), "w", encoding="utf-8"), indent=1)
    if write:
        write_luau(write, data, inputs.get("about", ["A car's gear lever and the right hand's way to it."]))
    print(f"knob grip (knob frame): wrist {grip_key[1:4]}, reach {len(keys)} keys over {data['reach']} s")
    print(f"steering grip wrist {np.round(start.pos, 4).tolist()}, knob grip in neutral {np.round(neutral.pos, 4).tolist()}")


if __name__ == "__main__":
    main(sys.argv[1:])
