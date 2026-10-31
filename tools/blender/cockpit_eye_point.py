"""The driver's hip point (H-point) and eye point from a race seat's surface, for a car's cockpit camera
and its seated driver.

blender -b <car.blend> --factory-startup --python-exit-code 1 -P tools/blender/cockpit_eye_point.py -- <out.json>
        [--seat <object name prefix>] [--break]

Car frame as the hero car pipeline keeps it: metres, Z up, nose along -Y. Every mesh whose name starts
with the prefix (default `Seat_`) is the seat; its centre plane is the middle of its X extent.
- Rays straight down give the cushion, rays straight rearward the backrest, on that plane. The
  cushion line is fitted over the seat's depth from 18 to 46 % behind its front (under the thighs and
  buttocks, ahead of a crotch-strap slot), the backrest line over its height from 31 to 76 % above
  its bottom; a point more than 15 mm off a first fit is dropped (a slot or a seam).
- H-point (hip joint): 0.13 m off the backrest line and 0.095 m above the cushion line, both
  perpendicular (SAE J826 manikin proportions; a race cushion compresses little).
- Eye: a 50th-percentile male's. A 0.50 m torso along the backrest line to the base of the neck, the
  head upright to look at the road, the eye 0.08 m forward and 0.17 m up from there. At a 25 deg back
  angle that puts the eye 0.635 m above the H-point, the SAE J941 eyellipse centroid height.
- Helmet top: 0.16 m above the eye (0.125 m to the vertex, 0.035 m shell), 0.03 m behind it; the
  first surface straight up from it is reported as the roof (a cage tube there counts too).
Writes the points in the car frame and as {forward = -y, right = -x, up = z} (the manifest's frame).

Exit 1 unless the result is plausible: back angle 10 to 40 deg, cushion -5 to 30 deg, eye 0.56 to 0.66 m
above the H-point, helmet top under the roof. --break tilts the seat 35 deg back about its rear
bottom edge before measuring, so the check must fail.
"""
import json
import math
import sys

import bpy
import numpy as np
from mathutils import Matrix, Vector

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
prefix = args[args.index("--seat") + 1] if "--seat" in args else "Seat_"
BREAK = "--break" in args
OFF_BACK, OFF_CUSHION = 0.13, 0.095
TORSO, HEAD_FWD, HEAD_UP = 0.50, 0.08, 0.17
HELMET_UP, HELMET_BACK = 0.16, 0.03

sc = bpy.context.scene
seat = [o for o in sc.objects if o.type == "MESH" and o.name.startswith(prefix)]
if not seat:
    raise SystemExit(f"no mesh named {prefix}* in the scene")
bpy.context.view_layer.update()
pts = [o.matrix_world @ v.co for o in seat for v in o.data.vertices]
lo = Vector([min(p[i] for p in pts) for i in range(3)])
hi = Vector([max(p[i] for p in pts) for i in range(3)])
if BREAK:
    pivot = Vector(((lo.x + hi.x) / 2, hi.y, lo.z))
    tilt = Matrix.Translation(pivot) @ Matrix.Rotation(math.radians(-35), 4, "X") @ Matrix.Translation(-pivot)
    for o in seat:
        o.matrix_world = tilt @ o.matrix_world
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ v.co for o in seat for v in o.data.vertices]
    lo = Vector([min(p[i] for p in pts) for i in range(3)])
    hi = Vector([max(p[i] for p in pts) for i in range(3)])
dg = bpy.context.evaluated_depsgraph_get()
cx = (lo.x + hi.x) / 2
names = {o.name for o in seat}


def first_hit(origin, direction, only_seat=True, reach=3.0):
    o, d, went = Vector(origin), Vector(direction).normalized(), 0.0
    while went < reach:
        ok, loc, _n, _i, ob, _m = sc.ray_cast(dg, o, d, distance=reach - went)
        if not ok:
            return None
        if ob.hide_render or (only_seat and ob.name not in names):
            went += (loc - o).length + 1e-4
            o = loc + d * 1e-4
            continue
        return loc
    return None


def fit(samples, x_of, y_of):
    """Least squares y = a x + b, refitted without points more than 15 mm off the first line."""
    s = np.array([(x_of(p), y_of(p)) for p in samples])
    a, b = np.polyfit(s[:, 0], s[:, 1], 1)
    keep = np.abs(s[:, 1] - (a * s[:, 0] + b)) < 0.015
    if keep.sum() >= 4:
        a, b = np.polyfit(s[keep, 0], s[keep, 1], 1)
    return a, b


depth, height = hi.y - lo.y, hi.z - lo.z
cushion = [h for h in (first_hit((cx, lo.y + depth * t, hi.z + 0.2), (0, 0, -1)) for t in np.linspace(0.18, 0.46, 30)) if h]
back = [h for h in (first_hit((cx, lo.y - 0.5, lo.z + height * t), (0, 1, 0)) for t in np.linspace(0.31, 0.76, 46)) if h]
if len(cushion) < 6 or len(back) < 6:
    raise SystemExit(f"too few seat hits on the centre plane x {cx:.4f}: cushion {len(cushion)}, back {len(back)}")
cz = fit(cushion, lambda p: p.y, lambda p: p.z)          # z = c y + d
by = fit(back, lambda p: p.z, lambda p: p.y)             # y = a z + b
ub = np.array([by[0], 1.0]) / math.hypot(by[0], 1.0)     # up the backrest, (y, z)
nb = np.array([-ub[1], ub[0]])                           # off the backrest, toward the nose
uc = np.array([-1.0, -cz[0]]) / math.hypot(1.0, cz[0])   # forward along the cushion
nc = np.array([uc[1], -uc[0]])
if nc[1] < 0:
    nc = -nc                                              # up, off the cushion
z_mid = lo.z + height * 0.5
y_mid = lo.y + depth * 0.4
pb = np.array([by[0] * z_mid + by[1], z_mid]) + OFF_BACK * nb
pc = np.array([y_mid, cz[0] * y_mid + cz[1]]) + OFF_CUSHION * nc
s_, _t = np.linalg.solve(np.column_stack([ub, -uc]), pc - pb)
H = pb + s_ * ub
neck = H + TORSO * ub
eye = neck + np.array([-HEAD_FWD, HEAD_UP])
helmet = eye + np.array([HELMET_BACK, HELMET_UP])
roof = first_hit((cx, helmet[0], helmet[1] - 0.05), (0, 0, 1), only_seat=False)
back_deg = math.degrees(math.atan(by[0]))
cushion_deg = math.degrees(math.atan(-cz[0]))


def pt(yz):
    return [round(cx, 4), round(float(yz[0]), 4), round(float(yz[1]), 4)]


def manifest(p):
    return {"forward": round(-p[1], 4), "right": round(-p[0], 4), "up": round(p[2], 4)}


res = {"seat": sorted(names), "centre_plane_x": round(cx, 4), "back_angle_deg": round(back_deg, 1),
       "cushion_angle_deg": round(cushion_deg, 1), "h_point": pt(H), "neck_base": pt(neck), "eye": pt(eye),
       "helmet_top": pt(helmet), "roof_above_helmet_z": round(roof.z, 4) if roof else None,
       "eye_above_h_point_m": round(float(eye[1] - H[1]), 4), "samples": {"cushion": len(cushion), "back": len(back)},
       "break": BREAK}
res["manifest"] = {"Driver_HPoint": manifest(res["h_point"]), "Driver_Eye": manifest(res["eye"])}
problems = []
if not 10 <= back_deg <= 40:
    problems.append(f"back angle {back_deg:.1f} deg outside 10-40")
if not -5 <= cushion_deg <= 30:
    problems.append(f"cushion angle {cushion_deg:.1f} deg outside -5-30")
if not 0.56 <= res["eye_above_h_point_m"] <= 0.66:
    problems.append(f"eye {res['eye_above_h_point_m']:.3f} m above the H-point, outside 0.56-0.66")
if roof is None or roof.z <= helmet[1]:
    problems.append("helmet top not under the roof")
res["verdict"] = "FAIL" if problems else "PASS"
res["problems"] = problems
json.dump(res, open(out, "w"), indent=1)
print("EYE", res["verdict"], json.dumps({k: res[k] for k in ("h_point", "eye", "back_angle_deg", "eye_above_h_point_m", "problems")}))
sys.exit(1 if problems else 0)
