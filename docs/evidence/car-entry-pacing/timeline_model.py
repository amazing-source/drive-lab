"""
Key press to first motion, and every wait after it, for getting in and getting out: a MODEL of
the client and server code before and after #40, not a measurement in Play (agents do not run
playtests; feel and live timing are the owner's).

What is measured, not modelled: the clips have no idle frame at either end (idle_frames_v4.json,
from the uploaded bakes), so consecutive clips meet with no gap; the exit's end stance
(exit_end_stance.txt). What is assumed: the walk at Movement.WALK_SPEED (12.5 studs/s, not
scaled), reached at once; a humanoid stopping where told; a round trip `rtt` split evenly
(0 in Studio, 0.1 s assumed live); a poll or a heartbeat costs half its period on average.

  python -I timeline_model.py
"""
import math

WALK = 12.5
FRAME = 1 / 60
CLIPS = {"OutsideOpen": 3.333, "GetIn": 4.267, "InsideOpen": 1.6, "GetOut": 4.0, "OutsideClose": 4.6}

BEFORE = {"arrived": 0.6, "poll": 0.05, "scale_wait": 0.8, "hold": 0.6, "exit_close": 4.6, "grow": 0.8}
AFTER = {
    "arrived": 0.2,
    "line_up": 1.2,
    "reach": 0.6,
    "line_up_angle": math.radians(30),
    "settle_speed": 12.5,
    "turn_speed": math.radians(600),
    "settle_cap": 0.2,
    "hold": 0.35,
    "exit_close": 3.433,
    "grow": 0.0,
}

# Where the player presses E: in the mark's frame (sideways, outward from the car), studs, and
# how far their facing is off the mark's when standing still.
STARTS = {
    "4 studs straight out": (0.0, 4.0, 0.0),
    "4 studs along the car, 1 out": (4.0, 1.0, 0.0),
    "on the mark, facing away": (0.0, 0.1, math.pi),
}


def entry_before(lateral, outward, _facing, rtt):
    p = BEFORE
    distance = math.hypot(lateral, outward)
    walk = max(0.0, distance - p["arrived"]) / WALK + p["poll"] / 2
    ready = rtt / 2 + p["scale_wait"]
    sent = max(walk, ready) + p["poll"] / 2
    first_clip = sent + rtt
    return {"walk ends": walk, "first clip frame": first_clip, "still at the mark": first_clip - walk}


def entry_after(lateral, outward, facing, rtt):
    p = AFTER
    walk, x, z, turn = 0.0, lateral, outward, facing
    if math.hypot(x, z) > p["arrived"]:
        if outward <= 0 or abs(lateral) > outward * math.tan(p["line_up_angle"]):
            to_line_up = math.hypot(x, z - p["line_up"])
            leg = max(0.0, to_line_up - p["reach"])
            walk += leg / WALK
            share = leg / to_line_up if to_line_up > 0 else 1
            x, z = x + (0 - x) * share, z + (p["line_up"] - z) * share
        distance = math.hypot(x, z)
        walk += max(0.0, distance - p["arrived"]) / WALK
        turn = math.atan2(abs(x), z) if z > 0 else math.pi
        residual = p["arrived"]
    else:
        residual = math.hypot(x, z)
    settle = min(max(residual / p["settle_speed"], abs(turn) / p["turn_speed"]), p["settle_cap"])
    settle_end = walk + settle
    received = walk + rtt / 2
    entry_at = max(settle_end, received)
    first_clip = entry_at + rtt / 2
    return {"walk ends": walk, "settle": settle, "first clip frame": first_clip, "still at the mark": first_clip - settle_end}


def exit_flow(p, rtt, door_open):
    first_motion = p["hold"] + FRAME / 2 + rtt
    clips = (0 if door_open else CLIPS["InsideOpen"]) + CLIPS["GetOut"] + p["exit_close"]
    hold_end = rtt / 2 + FRAME / 2
    free = first_motion + clips + hold_end + p["grow"]
    return {"first motion": first_motion, "sequence": clips, "held after": hold_end, "grow": p["grow"], "free at full size": free}


def main():
    for rtt in (0.0, 0.1):
        print(f"\n## round trip {rtt:.2f} s")
        for name, (lateral, outward, facing) in STARTS.items():
            before = entry_before(lateral, outward, facing, rtt)
            after = entry_after(lateral, outward, facing, rtt)
            print(f"entry, {name}:")
            for key in ("walk ends", "first clip frame", "still at the mark"):
                print(f"  {key:20s} before {before[key]:.3f}  after {after[key]:.3f}")
            print(f"  {'settle':20s} before  -     after {after['settle']:.3f}")
        for door_open in (False, True):
            before, after = exit_flow(BEFORE, rtt, door_open), exit_flow(AFTER, rtt, door_open)
            print(f"exit, door {'open' if door_open else 'shut'}:")
            for key in before:
                print(f"  {key:20s} before {before[key]:.3f}  after {after[key]:.3f}")
    print("\nentry sequence (door shut): OutsideOpen + GetIn = %.3f s, unchanged" % (CLIPS["OutsideOpen"] + CLIPS["GetIn"]))


if __name__ == "__main__":
    main()
