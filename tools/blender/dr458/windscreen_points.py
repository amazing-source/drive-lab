"""Write the windscreen's four corners as the driver sees them, as a manifest area file of points.

blender -b <master.blend> --factory-startup --python-exit-code 1 -P tools/blender/dr458/windscreen_points.py -- <out.json> [--pane <object>]

Measured as the SVJ's were: the vertices of the clear outer pane (the black frit band is its own
opaque object) within 3.5 cm of the pane's best-fit plane, and their four extremes in the plane:
across the car (the driver's left is Blender +X) and up the glass, each axis scaled by its half
extent so a wide screen does not pick its bottom corners from the width alone. Order and names as
the binding reads them: top left, top right, bottom right, bottom left. Frame: the manifest's
{forward = -y, right = -x, up = z} from the rear-axle midpoint on the ground.
"""
import json
import sys

import bpy
import numpy as np

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
PANE = args[args.index("--pane") + 1] if "--pane" in args else "fer_f142_10_cockpit_s_glassF_window_"
o = bpy.data.objects[PANE]
mw = np.array(o.matrix_world)
v = np.array([tuple(x.co) for x in o.data.vertices])
v = v @ mw[:3, :3].T + mw[:3, 3]
c = v.mean(0)
n = np.linalg.svd(v - c, full_matrices=False)[2][2]
near = v[np.abs((v - c) @ n) < 0.035]
left = np.array([1.0, 0, 0]) - n * n[0]
left /= np.linalg.norm(left)
upg = np.cross(n, left)
if upg[2] < 0:
    upg = -upg
a, b = (near - c) @ left, (near - c) @ upg
a, b = a / np.abs(a).max(), b / np.abs(b).max()
picks = {"Windshield_TopLeft": a + b, "Windshield_TopRight": -a + b, "Windshield_BottomRight": -a - b, "Windshield_BottomLeft": a - b}
corner = {name: near[int(np.argmax(score))] for name, score in picks.items()}
half_pane = float(np.abs(v[:, 0]).max())
half_quad = [float(abs(p[0])) for p in corner.values()]
points = {}
for name, p in corner.items():
    points[name] = {"forward": round(float(-p[1]), 4), "right": round(float(-p[0]), 4), "up": round(float(p[2]), 4),
                    "how": f"extreme of the clear windscreen pane ({PANE}) in its own plane: its vertices within 3.5 cm of the "
                           "best-fit plane, scored across the car and up the glass at equal half extents (the SVJ's method); "
                           f"the driver's left is the car's left. The pane wraps: the quad reaches {min(half_quad):.3f}-"
                           f"{max(half_quad):.3f} m either side of the centre line, the glass {half_pane:.3f} m"}
pts = np.array([[points[k]["forward"], points[k]["right"], points[k]["up"]] for k in picks])
top_w, base_w = abs(pts[0, 1] - pts[1, 1]), abs(pts[3, 1] - pts[2, 1])
height = float(np.linalg.norm((pts[0] + pts[1]) / 2 - (pts[2] + pts[3]) / 2))
problems = []
if not (pts[0, 2] > pts[3, 2] and pts[1, 2] > pts[2, 2]):
    problems.append("a top corner is not above its bottom corner")
if not (pts[0, 1] < pts[1, 1] and pts[3, 1] < pts[2, 1]):
    problems.append("a left corner is not left of its right corner (right = -x)")
if not (pts[0, 0] < pts[3, 0] and pts[1, 0] < pts[2, 0]):
    problems.append("a top corner is not behind its bottom corner (the screen rakes back)")
json.dump({"file": "work/assembly/" + bpy.path.basename(bpy.data.filepath), "frame": "manifest_schema.json frame",
           "parts": [], "points": points}, open(out, "w"), indent=1)
print(f"WINDSCREEN {len(near)}/{len(v)} vertices on the plane; top {top_w:.3f} m wide, base {base_w:.3f} m, {height:.3f} m roof to cowl; "
      f"glass {2 * half_pane:.3f} m wide")
for k, p in points.items():
    print(f"WINDSCREEN {k}: forward {p['forward']}, right {p['right']}, up {p['up']}")
print("WINDSCREEN", "PASS" if not problems else "FAIL", *problems, sep="\n  ")
sys.exit(1 if problems else 0)
