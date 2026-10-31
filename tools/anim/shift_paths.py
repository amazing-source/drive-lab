"""Keys a car's gear-lever hand (Config/DriverShift, Rules/ShiftHand) from measured inputs: the lever's
geometry, the right hand's grip on the knob, and the way between the steering grip and the knob.
Writes the car's Shift.luau and the paths.json that shift_check.py and the renders read.

  python tools/anim/shift_paths.py <inputs.json> <out dir> [--write <Shift.luau>]

inputs.json (seat frame, metres: x right, y up, z back, unless named):
  cabin, seat          the cockpit dump and the dump's point where the DriverSeat sits (as the
                       gesture tools read them)
  driver               shoulders (studs), upper, lower (studs), elbowBias: the arm controller's
  grip, wheel          hands.json, and the steering hub (pivot, axis, lift) it was posed on
  poses                hand_poses.py's poses.json (the open hand's palm places the knob grip)
  shifter              pivot, knob (centre in neutral), right, back, knobRadius, columns
                       [[column, degrees]...],
                       forward, backward (degrees), push (metres)
  gates                name -> [column, row] (as Vehicle/ShiftPlan's gates; N included)
  knobGrip             palmGap (m), pitch (fingers forward and down, degrees), yaw (about the lever,
                       positive turns the fingers toward the car's right), roll (about the fingers)
  reach                duration, lift [toward the driver, up] off the rim, over (m above the knob grip
                       at the way's middle), openAt, closeAt (seconds)
  release, foot        seconds

The lever turns as Rules/ShiftHand.lever turns it (sideways for the column, then fore and aft about
the leaned lever's cross axis); lever() here is that rule, and a spec-level parity check against the
Luau is a follow-up.
"""
import json
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gesture_paths import STUDS, Frame, luau, matrix_quat, quat_matrix, rotation, sample, smooth, to_seat, unit, wheel_axes  # noqa: E402

KEY_STEP = 1 / 60
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
    """The wrist frame gripping the knob, in the knob's frame: the open hand's palm over the ball, the
    fingers forward and down by `pitch`, turned about the lever by `yaw` and about the fingers by
    `roll`, the palm `palmGap` off the ball."""
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
    palm = np.array(poses["shapes"]["Rest"]["R"]["palm"], float) / poses["studsPerMetre"]
    target = y * (shifter.radius + spec["palmGap"])
    return Frame(rot, target - rot @ palm)


def compose(outer, inner):
    return Frame(outer.rot @ inner.rot, outer.apply(inner.pos))


def steering_grip(inputs):
    hands = json.load(open(inputs["grip"], encoding="utf-8"))["R"]
    axes, centre = wheel_axes({"steeringHub": inputs["wheel"], "steeringWheelLift": inputs["wheel"].get("lift", 0)})
    return to_seat(Frame.grip(hands["wrist"], hands["forearm"], hands["back"]), axes, centre)


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


def reach_track(start, end, spec):
    """From the steering grip to the knob grip: off the rim toward the driver, over the knob, down onto
    it, on an eased cubic; the hand turns evenly on the same ease."""
    duration = spec["duration"]
    lift = np.array([0.0, spec["lift"][1], spec["lift"][0]])
    p1 = start.pos + lift
    p2 = end.pos + np.array([0.0, spec["over"], 0.0])
    keys, t = [], 0.0
    while t < duration - 1e-9:
        s = smooth(t / duration)
        keys.append(Frame(slerp_rot(start.rot, end.rot, s), bezier(start.pos, p1, p2, end.pos, s)).key(t))
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


def main(argv):
    inputs_path, out_dir = argv[0], argv[1]
    write = argv[argv.index("--write") + 1] if "--write" in argv else None
    inputs = json.load(open(inputs_path, encoding="utf-8"))
    os.makedirs(out_dir, exist_ok=True)
    shifter = Shifter(inputs["shifter"])
    poses = json.load(open(inputs["poses"], encoding="utf-8"))
    grip_local = knob_grip(shifter, poses, inputs["knobGrip"])
    gates = {k: tuple(v) for k, v in inputs["gates"].items()}
    neutral = compose(shifter.lever(*gates["N"]), grip_local)
    start = steering_grip(inputs)
    keys, shapes = reach_track(start, neutral, inputs["reach"])
    grip_key = grip_local.key(0)
    data = {
        "shifter": shifter.as_luau(),
        "grip": grip_key,
        "hand": {"keys": keys, "shapes": shapes},
        "reach": inputs["reach"]["duration"],
        "release": inputs["release"],
        "foot": inputs["foot"],
    }
    paths = {"inputs": os.path.abspath(inputs_path), "gates": gates, "gateOrder": [g for g in GATE_ORDER if g in gates], **data}
    json.dump(paths, open(os.path.join(out_dir, "paths.json"), "w", encoding="utf-8"), indent=1)
    if write:
        write_luau(write, data, inputs.get("about", ["A car's gear lever and the right hand's way to it."]))
    print(f"knob grip (knob frame): wrist {grip_key[1:4]}, reach {len(keys)} keys over {data['reach']} s")
    print(f"steering grip wrist {np.round(start.pos, 4).tolist()}, knob grip in neutral {np.round(neutral.pos, 4).tolist()}")


if __name__ == "__main__":
    main(sys.argv[1:])
