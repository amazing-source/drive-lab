"""
The seated driver's resting hands: each hand lying palm down on its thigh, a little under half
way from the hip to the knee, in the driver's seat frame. Plain Python (no Blender): it mirrors
Rules/DriverLegs for the thighs and Controllers/DriverArms for the shoulders.

    python -I tools/blender/rest_pose.py <SEAT_WELD.json> <poses.json> <out REST_POSE.json>
    python -I tools/blender/rest_pose.py --car <car.json> <poses.json> <out REST_POSE.json>

Inputs: the seated R6 measured in Studio (SEAT_WELD.json: the torso's centre and the joints in
the DriverSeat part's frame at Driving.DRIVER_SCALE) and the posed hands of hand_poses.py
(poses.json: the Rest hand's palm and fingertips in its wrist frame). The footwell numbers below
are Config/DriverLegs' (rest: right foot on the throttle, unpressed; left on the footrest).

With --car, another car's driver: car.json gives its scale, each thigh's hip and knee (metres,
seat frame, as its legs are drawn), the arm controller's shoulders and the R6 shoulder joints
(studs), the arms' lengths at scale 1, and the "about" and "frame" lines to record.

Output: per side, the wrist frame (the frame the game moves the hand by: z up the forearm, y out
of the back of the hand) as a position and a quaternion, the palm's centre, the fingers' and the
palm's directions; and, for a blocky R6 arm ending on the hand, the point its end reaches along
its joint-to-hand line. Studs in the seat frame (x right, y up, -z forward).
"""

import json
import math
import sys

STUDS_PER_METRE = 1.5 / 0.28
DRIVER_SCALE = 1.5 / 1.75
# Config/DriverLegs.
THIGH, SHIN = 0.46, 0.45
# The SVJ's footwell (Config/Cars/SVJ/Driver): where each knee bends toward, the pedals, the footrest.
KNEE_TOWARD = {1: (0.17, 0.15, -0.4), -1: (-0.58, 0.62, 0.008)}
HIP = (0.5, -1.05, 0.05)
ANKLE_ALONG, ANKLE_UP = 0.075, 0.085
THROTTLE = {"heel": (0.1761, -0.2275, -0.8354), "ball": (0.2044, -0.0482, -0.924)}
FOOTREST = {"heel": (-0.1012, -0.2352, -0.8776), "ball": (-0.1012, -0.0519, -0.9575)}
BRAKE = {"hinge": (0.0304, 0.0956, -0.9992), "heel": (0.0308, -0.2334, -0.794), "ball": (0.0308, -0.0486, -0.8705)}
# tools/blender/driver_legs.py thigh_radius: the cloth's half-height along the thigh.
THIGH_TOP = (0.075, 0.06)
# Config/DriverArms at scale 1.
UPPER, LOWER, SHOULDER_INSET = 0.82, 0.77, 0.2
# Where on the thigh the palm lies, from the hip (0) to the knee (1), and the gap under it.
ALONG_THIGH = 0.45
GAP = 0.004


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def mul(a, k):
    return tuple(x * k for x in a)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    return mul(a, 1 / math.sqrt(dot(a, a)))


def apply(axes, v):
    """Hand-frame vector -> seat frame, axes = (x, y, z) columns."""
    return add(add(mul(axes[0], v[0]), mul(axes[1], v[1])), mul(axes[2], v[2]))


def turned(hinge, point, angle):
    """`point` turned with a pedal about its hinge's x axis (Rules/DriverLegs.turned)."""
    o = sub(point, hinge)
    c, s = math.cos(angle), math.sin(angle)
    return add(hinge, (o[0], o[1] * c - o[2] * s, o[1] * s + o[2] * c))


def leg(hip, heel, ball, toward):
    """The knee and the ankle reached (Rules/DriverLegs' leg)."""
    forward = unit(sub(ball, heel))
    up = unit(cross((1, 0, 0), forward))
    ankle = add(heel, add(mul(forward, ANKLE_ALONG), mul(up, ANKLE_UP)))
    d = sub(ankle, hip)
    dist = math.sqrt(dot(d, d))
    reach = min(max(dist, abs(THIGH - SHIN) + 1e-6), THIGH + SHIN - 1e-6)
    bend = math.acos(max(-1, min(1, (THIGH * THIGH + reach * reach - SHIN * SHIN) / (2 * THIGH * reach))))
    along = unit(d)
    pole = sub(toward, hip)
    perp = unit(sub(pole, mul(along, dot(pole, along))))
    knee = add(hip, add(mul(along, THIGH * math.cos(bend)), mul(perp, THIGH * math.sin(bend))))
    return knee, add(hip, mul(along, reach))


def quaternion(axes):
    """Rotation matrix with columns x, y, z -> (w, x, y, z)."""
    (m00, m10, m20), (m01, m11, m21), (m02, m12, m22) = axes
    trace = m00 + m11 + m22
    if trace > 0:
        s = math.sqrt(trace + 1) * 2
        return (0.25 * s, (m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s)
    if m00 > m11 and m00 > m22:
        s = math.sqrt(1 + m00 - m11 - m22) * 2
        return ((m21 - m12) / s, 0.25 * s, (m01 + m10) / s, (m02 + m20) / s)
    if m11 > m22:
        s = math.sqrt(1 + m11 - m00 - m22) * 2
        return ((m02 - m20) / s, (m01 + m10) / s, 0.25 * s, (m12 + m21) / s)
    s = math.sqrt(1 + m22 - m00 - m11) * 2
    return ((m10 - m01) / s, (m02 + m20) / s, (m12 + m21) / s, 0.25 * s)


def svj_side(seat_weld, sign):
    """The SVJ's thigh and shoulders, from the measured sit and the constants above."""
    torso = seat_weld["robloxSit"]["pointsInSeat"]["torsoCentre"]
    hip_studs = add(torso, mul((sign * HIP[0], HIP[1], HIP[2]), DRIVER_SCALE))
    hip = mul(hip_studs, 1 / STUDS_PER_METRE)
    feet = THROTTLE if sign > 0 else FOOTREST
    knee, _ = leg(hip, feet["heel"], feet["ball"], KNEE_TOWARD[sign])
    return {
        "hip": hip,
        "knee": knee,
        "shoulder": (sign * (1 - SHOULDER_INSET) * DRIVER_SCALE, seat_weld["robloxSit"]["pointsInSeat"]["rightShoulder"][1], 0),
        "reach": (UPPER + LOWER) * DRIVER_SCALE,
        "joint": seat_weld["robloxSit"]["pointsInSeat"]["rightShoulder" if sign > 0 else "leftShoulder"],
        "blocky": 1.5 * DRIVER_SCALE,
    }


def car_side(car, sign):
    """Another car's thigh (hip and knee, metres) and shoulders (studs) from its car file."""
    side = "right" if sign > 0 else "left"
    return {
        "hip": tuple(car["thighs"][side]["hip"]),
        "knee": tuple(car["thighs"][side]["knee"]),
        "shoulder": tuple(car["shoulders"][side]),
        "reach": (car["arms"][0] + car["arms"][1]) * car["scale"],
        "joint": car["joints"][side],
        "blocky": 1.5 * car["scale"],
    }


def rest_side(body, shape, sign):
    hip, knee = body["hip"], body["knee"]
    thigh_dir = unit(sub(knee, hip))
    centre = add(hip, mul(sub(knee, hip), ALONG_THIGH))
    up = unit(sub((0, 1, 0), mul(thigh_dir, dot((0, 1, 0), thigh_dir))))
    radius = THIGH_TOP[0] + (THIGH_TOP[1] - THIGH_TOP[0]) * ALONG_THIGH
    surface = add(centre, mul(up, radius + GAP))
    # The hand frame: fingers along the thigh (-z), back of the hand up (y), then pitched so the
    # palm and the fingertips both lie on the thigh's top.
    palm = mul(shape["palm"], 1 / STUDS_PER_METRE)
    tip = mul(shape["fingertip"], 1 / STUDS_PER_METRE)
    v = sub(tip, palm)
    pitch = math.atan(-v[1] / v[2])
    z0 = mul(thigh_dir, -1)
    y0 = up
    x0 = cross(y0, z0)
    c, s = math.cos(pitch), math.sin(pitch)
    # Rotate about the hand's x so its palm-to-fingertip line runs along the thigh.
    y1 = add(mul(y0, c), mul(z0, -s))
    z1 = add(mul(y0, s), mul(z0, c))
    axes = (x0, y1, z1)
    palm_seat = apply(axes, palm)
    wrist = sub(surface, palm_seat)
    shoulder_studs = body["shoulder"]
    reach = body["reach"]
    wrist_studs = mul(wrist, STUDS_PER_METRE)
    distance = math.sqrt(dot(sub(wrist_studs, shoulder_studs), sub(wrist_studs, shoulder_studs)))
    tip_seat = add(wrist, apply(axes, tip))
    tip_height = dot(sub(tip_seat, centre), up) - radius
    joint = body["joint"]
    hand_studs = mul(surface, STUDS_PER_METRE)
    blocky_length = body["blocky"]
    blocky_end = add(joint, mul(unit(sub(hand_studs, joint)), blocky_length))
    w, qx, qy, qz = quaternion(axes)
    return {
        "wrist": [round(c, 4) for c in wrist_studs],
        "rotation": [round(c, 5) for c in (w, qx, qy, qz)],
        "palmCentre": [round(c, 4) for c in hand_studs],
        "handAxis": [round(c, 4) for c in mul(z1, -1)],
        "palmFacing": [round(c, 4) for c in mul(y1, -1)],
        "blockyArmEnd": [round(c, 4) for c in blocky_end],
        "check": {
            "wristFromShoulderStuds": round(distance, 4),
            "armReachStuds": round(reach, 4),
            "fingertipAboveThighMetres": round(tip_height, 4),
            "kneeMetres": [round(c, 4) for c in knee],
            "hipMetres": [round(c, 4) for c in hip],
        },
    }


def main(args):
    if args[0] == "--car":
        car = json.load(open(args[1]))
        poses = json.load(open(args[2]))
        result = {
            "about": car["about"],
            "frame": car["frame"],
            "wristFrame": "wrist + rotation (w, x, y, z) is the frame the game places the hand by: z from the wrist up the forearm, y out of the back of the hand.",
            "forBlockyArms": "palmCentre is the middle of the palm on the thigh; blockyArmEnd is where an R6 arm's end lands aimed from its shoulder joint at palmCentre (its 1.5-stud reach at scale 1, times the driver's scale).",
            "right": rest_side(car_side(car, 1), poses["shapes"]["Rest"]["R"], 1),
            "left": rest_side(car_side(car, -1), poses["shapes"]["Rest"]["L"], -1),
        }
        json.dump(result, open(args[3], "w"), indent=1)
        print(json.dumps(result, indent=1))
        return
    seat_weld = json.load(open(args[0]))
    poses = json.load(open(args[1]))
    result = {
        "about": "The seated driver's resting hands (tools/blender/rest_pose.py). Hands palm down on the thighs, the palm 45 percent of the way from hip to knee, the right foot on the throttle and the left on the footrest.",
        "frame": "The DriverSeat part's frame (x right, y up, -z forward), studs of the 1.5x world, for a driver at Driving.DRIVER_SCALE seated by Roblox's SeatWeld with the upright sit torso.",
        "wristFrame": "wrist + rotation (w, x, y, z) is the frame the game places the hand by: z from the wrist up the forearm, y out of the back of the hand.",
        "forBlockyArms": "palmCentre is the middle of the palm on the thigh; blockyArmEnd is where an R6 arm's end lands aimed from its shoulder joint at palmCentre (its 1.5-stud reach at scale 1).",
        "right": rest_side(svj_side(seat_weld, 1), poses["shapes"]["Rest"]["R"], 1),
        "left": rest_side(svj_side(seat_weld, -1), poses["shapes"]["Rest"]["L"], -1),
    }
    json.dump(result, open(args[2], "w"), indent=1)
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main(sys.argv[1:])
