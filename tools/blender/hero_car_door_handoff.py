"""
Writes the door's geometry hand-off for the animation and code side, from the door pipeline's
outputs (plain Python, no Blender):

    python -I tools/blender/hero_car_door_handoff.py <door dir> <rig blend> <out HANDOFF.json>

<door dir> holds hinge.json and door_selection.json (hero_car_door_hinge.py, hero_car_door.py).
Every point is given in Blender metres (the .blend: nose along -Y, Z up, driver on +X) and in
the model binding's car frame (Config/Cars/SVJModel: metres from the centre of mass, forward,
right, up, before the rig's body raise, as `seat` is). The centre of mass is where
Car/CarRig.rigFrame puts it: frontWeightShare (0.43) of the wheelbase ahead of the rear axle,
cgHeight (0.444 m) above the mean of the wheels' lowest points, measured on the .blend's wheels.
"""

import json
import sys
from pathlib import Path

# Blender metres, measured on svj_interior_v2_wheel.blend's wheel objects (2026-10-28): wheel
# centres y -1.2600 (front) and 1.4400 (rear), lowest points z -0.0129 and -0.0123.
CENTRE_OF_MASS = (0.0, 1.44 + (-1.26 - 1.44) * 0.43, (-0.0129 * 2 + -0.0123 * 2) / 4 + 0.444)

door_dir, rig_blend, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
hinge = json.loads((door_dir / "hinge.json").read_text())
selection = json.loads((door_dir / "door_selection.json").read_text())


def car_point(p):
    x, y, z = p
    cx, cy, cz = CENTRE_OF_MASS
    return {"forward": round(-(y - cy), 4), "right": round(-(x - cx), 4), "up": round(z - cz, 4)}


def car_direction(d):
    x, y, z = d
    return {"forward": round(-y, 5), "right": round(-x, 5), "up": round(z, 5)}


slices = selection["sill"]["slices"]
handoff = {
    "note": "Blender metres of the rig blend (nose -Y, Z up, driver +X); car frame = Config/Cars/SVJModel's: "
    "metres from the centre of mass, forward/right/up, before CarRig's bodyRaise (add bodyRaise to `up` in game). "
    "A positive right-hand turn about an axis opens; in game the weld C0 = RestC0 * CFrame.Angles(angle, 0, 0), "
    "angle = openness x open angle.",
    "blend": str(rig_blend),
    "centreOfMassBlender": [round(c, 4) for c in CENTRE_OF_MASS],
    "door": {
        "parts": "Door_* objects, children of the Empty DoorHinge (its local X is the axis)",
        "pivotBlender": hinge["pivot"],
        "axisBlender": hinge["axis"],
        "pivotCar": car_point(hinge["pivot"]),
        "axisCar": car_direction(hinge["axis"]),
        "openDegrees": hinge["openDegrees"],
        "leanWhenOpen": hinge["leanWhenOpen"],
        "placeParts": ["DoorPaint", "DoorCarbon", "DoorTrim", "DoorInterior", "DoorGlass", "DoorGlassInside", "DoorBase"],
    },
    "flap": {
        "object": "StartFlap, child of the Empty FlapHinge",
        "pivotBlender": selection["flapHinge"]["pivot"],
        "axisBlender": selection["flapHinge"]["axis"],
        "pivotCar": car_point(selection["flapHinge"]["pivot"]),
        "axisCar": car_direction(selection["flapHinge"]["axis"]),
        "openDegrees": "Config/CarEntry STARTUP.flapAngle (70 deg)",
        "freeEdge": "the rear edge, with the finger notch",
        "buttonTopBlender": selection["buttonTop"],
        "buttonTopCar": car_point(selection["buttonTop"]),
        "placePart": "StartFlap",
    },
    "sill": {
        "columns": "y, top z, lip x (outer edge), lip z, inner x (inner edge), inner z; Blender metres",
        "slicesBlender": slices,
        "topFrontBlender": slices[1][1] if len(slices) > 1 else slices[0][1],
        "topRearBlender": slices[-2][1] if len(slices) > 1 else slices[-1][1],
        "innerEdgeBlender": round(sum(s[4] for s in slices) / len(slices), 4),
        "outerEdgeBlender": round(sum(s[2] for s in slices) / len(slices), 4),
        "placePart": "DoorSill",
    },
}
handoff["sill"]["topFrontCarUp"] = round(handoff["sill"]["topFrontBlender"] - CENTRE_OF_MASS[2], 4)
handoff["sill"]["topRearCarUp"] = round(handoff["sill"]["topRearBlender"] - CENTRE_OF_MASS[2], 4)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(handoff, indent=1))
print(json.dumps({k: v for k, v in handoff.items() if k != "sill"}, indent=1))
