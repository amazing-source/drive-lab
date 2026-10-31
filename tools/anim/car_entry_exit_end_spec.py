"""
Spec for car_entry_exit_end.py's --scale: a synthetic OutsideClose whose body stands at rest 1.2
studs out from the mark (body scale 1) for a few frames, then at the mark.

  python -I tools/anim/car_entry_exit_end_spec.py

At the SVJ's default scale that stance is 1.03 game studs out and is chosen; at 0.8 it is 0.96,
under the 1.0 minimum, so nothing is; at 1.15 it is chosen and `right` moves with the scale.
"""
import json
import os
import subprocess
import sys
import tempfile

TOOL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "car_entry_exit_end.py")
IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1]
REST = {"Torso": (0, 3, 0), "Head": (0, 4.5, 0), "Right Arm": (1.5, 3, 0), "Left Arm": (-1.5, 3, 0), "Right Leg": (0.5, 1, 0), "Left Leg": (-0.5, 1, 0)}


def frame(index, out):
    parts = {name: [x, y, z + out] + IDENTITY for name, (x, y, z) in REST.items()}
    return {"frame": index, "door": 0.0, "parts": parts}


def run(path, *extra):
    done = subprocess.run([sys.executable, "-I", TOOL, path, "--mark", "-0.9,0", *extra], capture_output=True, text=True)
    return done.returncode, done.stdout + done.stderr


def main():
    frames = [frame(i, 1.2 if 2 <= i <= 5 else 0.0) for i in range(10)]
    data = {"fps": 30, "frames": frames, "clips": [{"name": "OutsideClose", "start": 0, "end": 9}]}
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "exit.baked.json")
        json.dump(data, open(path, "w", encoding="utf-8"))
        checks = []
        code, text = run(path)
        checks.append(("default scale chooses the stance", code == 0 and "right = -1.0920" in text, text))
        code, text = run(path, "--scale", "0.8")
        checks.append(("0.8 puts it under the minimum", code != 0 and "no stance" in text, text))
        code, text = run(path, "--scale", "1.15")
        checks.append(("1.15 moves right with the scale", code == 0 and "right = -1.1576" in text, text))
    failed = [name for name, ok, _ in checks if not ok]
    for name, ok, text in checks:
        print(("ok   " if ok else "FAIL ") + name + ("" if ok else "\n" + text))
    print("all expectations hold" if not failed else f"{len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
