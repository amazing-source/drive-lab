"""
R6 forward kinematics outside Blender, the same joint chain as tools/blender/r6_rig.py: a part
sits at Part0 * T(C0 position) * anim * (C0 rotation * C1^-1), with anim = T(loc) * Rz * Ry * Rx
(Blender's XYZ Euler) in BODY axes. Used to aim rigid limbs at targets while authoring keys;
the checks read Blender's own bake, never this.

Scale 1 (Roblox's R6). Roblox frame: +X right, +Y up, -Z forward. The root part's centre is
ROOT_HEIGHT above the ground when standing.
"""
import math

import numpy as np
from scipy.optimize import least_squares

ROOT_HEIGHT = 3.0
ROOT_ROT = [-1, 0, 0, 0, 0, 1, 0, 1, 0]
RIGHT_ROT = [0, 0, 1, 0, 1, 0, -1, 0, 0]
LEFT_ROT = [0, 0, -1, 0, 1, 0, 1, 0, 0]
SIZES = {
    "Torso": (2, 2, 1),
    "Head": (2, 1, 1),
    "Right Arm": (1, 2, 1),
    "Left Arm": (1, 2, 1),
    "Right Leg": (1, 2, 1),
    "Left Leg": (1, 2, 1),
}


def cframe(x, y, z, r):
    m = np.identity(4)
    m[:3, :3] = np.array(r, dtype=float).reshape(3, 3)
    m[:3, 3] = (x, y, z)
    return m


JOINTS = {
    "RootJoint": ("HumanoidRootPart", "Torso", cframe(0, 0, 0, ROOT_ROT), cframe(0, 0, 0, ROOT_ROT)),
    "Neck": ("Torso", "Head", cframe(0, 1, 0, ROOT_ROT), cframe(0, -0.5, 0, ROOT_ROT)),
    "Right Shoulder": ("Torso", "Right Arm", cframe(1, 0.5, 0, RIGHT_ROT), cframe(-0.5, 0.5, 0, RIGHT_ROT)),
    "Left Shoulder": ("Torso", "Left Arm", cframe(-1, 0.5, 0, LEFT_ROT), cframe(0.5, 0.5, 0, LEFT_ROT)),
    "Right Hip": ("Torso", "Right Leg", cframe(1, -1, 0, RIGHT_ROT), cframe(0.5, 1, 0, RIGHT_ROT)),
    "Left Hip": ("Torso", "Left Leg", cframe(-1, -1, 0, LEFT_ROT), cframe(-0.5, 1, 0, LEFT_ROT)),
}
ORDER = ["RootJoint", "Neck", "Right Shoulder", "Left Shoulder", "Right Hip", "Left Hip"]
LIMB_JOINT = {"right_arm": "Right Shoulder", "left_arm": "Left Shoulder", "right_leg": "Right Hip", "left_leg": "Left Hip"}


def euler_xyz(x, y, z):
    """Blender's XYZ Euler, degrees: Rz @ Ry @ Rx."""
    x, y, z = (math.radians(a) for a in (x, y, z))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rz @ ry @ rx


def to_euler_xyz(r):
    """Inverse of euler_xyz (degrees), for r = Rz Ry Rx."""
    y = math.asin(max(-1.0, min(1.0, -r[2, 0])))
    x = math.atan2(r[2, 1], r[2, 2])
    z = math.atan2(r[1, 0], r[0, 0])
    return [math.degrees(x), math.degrees(y), math.degrees(z)]


def rotation(rot):
    """A joint rotation given as XYZ Euler degrees or as a 3x3 matrix."""
    if isinstance(rot, np.ndarray) and rot.shape == (3, 3):
        return rot
    return euler_xyz(*rot)


def body_turn(lean, yaw, roll):
    """The torso's turn from body-relative angles (degrees): yaw about the vertical, then lean
    forward/back (negative = forward, as RootJoint X) and roll (positive = lean left) about the
    turned body's own axes. Unlike Euler XYZ it has no lock at a 90-degree yaw."""
    return euler_xyz(0, yaw, 0) @ euler_xyz(lean, 0, 0) @ euler_xyz(0, 0, roll)


def anim_matrix(rot, loc=(0, 0, 0)):
    m = np.identity(4)
    m[:3, :3] = rotation(rot)
    m[:3, 3] = loc
    return m


def pose_parts(pose, root=None):
    """pose: {joint: (rot degrees, loc)} -> {part: 4x4 in Roblox space}. Missing joints rest."""
    parts = {"HumanoidRootPart": root if root is not None else cframe(0, ROOT_HEIGHT, 0, [1, 0, 0, 0, 1, 0, 0, 0, 1])}
    for name in ORDER:
        part0, part1, c0, c1 = JOINTS[name]
        rot, loc = pose.get(name, ((0, 0, 0), (0, 0, 0)))
        pivot = np.identity(4)
        pivot[:3, 3] = c0[:3, 3]
        c0_rot = np.identity(4)
        c0_rot[:3, :3] = c0[:3, :3]
        parts[part1] = parts[part0] @ pivot @ anim_matrix(rot, loc) @ c0_rot @ np.linalg.inv(c1)
    return parts


def point(part_matrix, local):
    return part_matrix[:3, :3] @ np.asarray(local, dtype=float) + part_matrix[:3, 3]


# Points on parts, in each part's own frame (Roblox axes of the part: +Y up its length).
HAND = (0, -0.85, -0.05)  # palm centre, just above the arm's bottom face
FOOT = (0, -1.0, 0)  # bottom centre of a leg
PELVIS = (0, -1.0, 0)  # bottom centre of the torso, between the hip joints


def torso_root_offset(rot, pelvis):
    """RootJoint loc (in the root part's frame) that puts the torso's pelvis point at `pelvis`
    (root frame) with the torso turned `rot` (body axes): the torso turns about its centre, so the
    centre goes where the pelvis plus the turned half-height puts it."""
    r = rotation(rot)
    # The torso's frame is anim * (C0rot * C1^-1) = anim here (ROOT_ROT twice is identity).
    return np.asarray(pelvis, dtype=float) - r @ np.asarray(PELVIS, dtype=float)


def lowest_corner(part_matrix, half=(0.5, 1.0, 0.5)):
    return min(point(part_matrix, (sx * half[0], sy * half[1], sz * half[2]))[1] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1))


def ground_foot(pose, limb, spread=0.0, ground=0.0, backward=False):
    """The leg swung straight forward (or back) from this pose until its lowest corner meets the
    ground: (swing degrees, sole centre). None if the hip is too high for the leg to reach."""
    joint = LIMB_JOINT[limb]
    part = JOINTS[joint][1]
    sign = -1.0 if backward else 1.0

    def low(theta):
        trial = dict(pose)
        trial[joint] = ((sign * theta, 0.0, spread), (0, 0, 0))
        leg = pose_parts(trial)[part]
        return lowest_corner(leg) - ground, point(leg, FOOT)

    lo, hi = 0.0, 85.0
    if low(lo)[0] > 0:
        return None
    for _ in range(40):
        mid = (lo + hi) / 2
        if low(mid)[0] < 0:
            lo = mid
        else:
            hi = mid
    return sign * hi, low(hi)[1]


# Swing X and spread Z bounds (degrees) for aimed limbs.
LIMITS = {"leg": ((-130.0, -85.0), (165.0, 85.0)), "arm": ((-200.0, -130.0), (230.0, 130.0))}


def limb_frame(parent, joint, rot):
    """Part1 of `joint` under a parent part frame, the joint turned `rot`."""
    _, _, c0, c1 = JOINTS[joint]
    pivot = np.identity(4)
    pivot[:3, 3] = c0[:3, 3]
    c0_rot = np.identity(4)
    c0_rot[:3, :3] = c0[:3, :3]
    return parent @ pivot @ anim_matrix(rot) @ c0_rot @ np.linalg.inv(c1)


def aim(pose, limb, target, part_point, root=None, twist=0.0, guess=(0.0, 0.0), weights=None):
    """Swing X and spread Z of `limb` so its `part_point` lands on `target` (Roblox space).
    Returns (x, y, z) degrees and the miss distance; a rigid limb cannot always reach."""
    joint = LIMB_JOINT[limb]
    torso = pose_parts({"RootJoint": pose["RootJoint"]}, root)["Torso"]
    local = np.asarray(part_point, dtype=float)

    def miss(angles):
        m = limb_frame(torso, joint, (angles[0], twist, angles[1]))
        return m[:3, :3] @ local + m[:3, 3] - target

    # One branch of the Euler angles only: (X, Z) and (X + 180, Z + 180) pose a box the same way,
    # and keys that hop between them make Blender swing the limb the long way round.
    lo, hi = LIMITS["leg" if limb.endswith("leg") else "arm"]
    start = np.clip(np.asarray(guess, dtype=float), np.array(lo) + 1e-6, np.array(hi) - 1e-6)
    best = least_squares(miss, x0=start, method="trf", bounds=(lo, hi))
    x, z = best.x
    return (float(x), float(twist), float(z)), float(np.linalg.norm(miss(best.x)))
