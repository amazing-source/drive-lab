"""
Foot contact check for a baked R6 cycle: per frame, each leg's lowest corner (ground is y=0)
and how fast that corner moves against the ground at the travel speed. A planted foot should
sit at y ~ 0 and move backwards at exactly the travel speed; anything else is a float, a dig
or a slide.

  python -I contact_report.py <baked.json> <speed studs/s>
"""
import json
import sys

LEG_HALF = (0.5, 1.0, 0.5)
CONTACT = 0.08


def corners(values):
    px, py, pz = values[0:3]
    r = values[3:12]
    out = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                lx, ly, lz = sx * LEG_HALF[0], sy * LEG_HALF[1], sz * LEG_HALF[2]
                out.append(
                    (
                        px + r[0] * lx + r[1] * ly + r[2] * lz,
                        py + r[3] * lx + r[4] * ly + r[5] * lz,
                        pz + r[6] * lx + r[7] * ly + r[8] * lz,
                    )
                )
    return out


def lowest(values):
    return min(corners(values), key=lambda c: c[1])


def main(path, speed):
    data = json.load(open(path))
    frames = data["frames"]
    dt = 1 / data["fps"]
    print(f"{'f':>5} | {'Right Leg y':>11} {'slip':>7} | {'Left Leg y':>10} {'slip':>7} | root y")
    for i, frame in enumerate(frames):
        row = [f"{frame['frame']:>5.2f}"]
        for leg in ("Right Leg", "Left Leg"):
            now = lowest(frame["parts"][leg])
            nxt = frames[(i + 1) % len(frames)]["parts"][leg]
            # Velocity of the same body point, not of whichever corner is lowest next frame.
            index = corners(frame["parts"][leg]).index(now)
            ahead = corners(nxt)[index]
            vz = (ahead[2] - now[2]) / dt
            slip = vz - speed
            mark = "*" if now[1] < CONTACT else " "
            row.append(f"{now[1]:>10.2f}{mark} {slip if now[1] < CONTACT else float('nan'):>7.1f}")
        row.append(f"{frame['parts']['Torso'][1]:.2f}")
        print(" | ".join(row))


if __name__ == "__main__":
    main(sys.argv[1], float(sys.argv[2]))
