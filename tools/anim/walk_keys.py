"""
The walk, built on the animator's four poses per step (contact, down, passing, up), with the
legs doing visible walking: the swinging leg lifts well out in front (48 degrees) before it
sets down at contact, and the back leg pushes off further behind before it swings through.

Arms are not a mirrored pendulum: the forward arm comes a little across the body and turns in,
the back arm opens slightly outward, and both peak just after contact, as arms lag the legs.
R6 has one block for pelvis and shoulders, so the torso turns with the ARMS (the right shoulder
comes forward with the right arm). Turned with the legs, as a pelvis would, the shoulders ran
against the arm swing and the owner saw the arms going the wrong way (2026-10-27).

The weight lands at contact: a short, sharp drop and a forward dip, then a slow rise through
passing. 12.5 studs/s with one full stride a second (owner, 2026-10-27). A kneeless 2-stud R6
leg cannot keep a foot planted at that speed, so the feet slide, as in Roblox's own R6 walk.
Same left-foot-first convention as the run, so the two blend.

  python walk_keys.py <out.keys.json>
"""
import sys

from cycle_keys import keys_file, write

FPS = 30
STEP = 15
FRONT = 40.0  # leading leg at contact
BACK = -34.0  # trailing leg at contact
REACH = 48.0  # swinging leg's highest point, just before it sets down
PUSH = -40.0  # trailing leg at toe-off
LEAN = -4.0
TURN = 7.0
DROP = 0.08

STEP_A = [
    {
        "frame": 0,  # contact: left heel strikes; the body has started to fall into the step
        "root": ((LEAN, TURN, 0), (0, -0.06, 0)),
        "neck": (0, 0, 0),
        "right_arm": (30, -8, -6),
        "left_arm": (-24, -6, -9),
        "left_leg": (FRONT, 0, 0),
        "right_leg": (BACK, 0, 1),
    },
    {
        "frame": 2,  # down: the weight lands; arms reach their peak a beat after the feet
        "root": ((LEAN - 3, TURN * 0.85, 0), (0, -0.06 - DROP, 0)),
        "right_arm": (36, -11, -8),
        "left_arm": (-30, -8, -11),
        "left_leg": (FRONT * 0.75, 0, 0),
    },
    {
        "frame": 3,  # toe-off: the right foot pushes away behind
        "right_leg": (PUSH, 0, 1),
    },
    {
        "frame": 4,
        "root": ((LEAN - 2, TURN * 0.6, 0), (0, -0.04 - DROP * 0.5, 0)),
        "left_leg": (FRONT * 0.5, 0, 0),
    },
    {"frame": 5, "right_leg": (-20, 0, 2)},
    {
        "frame": 7,  # passing: full height, the right leg swinging through under the body
        "root": ((LEAN, 0, 0), (0, 0, 0)),
        "right_arm": (6, -3, -3),
        "left_arm": (0, -2, -3),
        "left_leg": (2, 0, 0),
        "right_leg": (12, 0, 2),
    },
    {
        "frame": 10,  # up: the left foot drives back, the right leg rising out in front
        "root": ((LEAN + 1, -TURN * 0.5, 0), (0, 0.03, 0)),
        "left_leg": (-22, 0, 0),
        "right_leg": (40, 0, 1),
    },
    {
        "frame": 12,  # reach: the right leg at its highest, about to set down
        "right_arm": (-18, 6, 8),
        "left_arm": (24, 8, 5),
        "left_leg": (-28, 0, 0),
        "right_leg": (REACH, 0, 1),
    },
]

if __name__ == "__main__":
    write(
        sys.argv[1],
        keys_file(
            STEP_A,
            STEP,
            FPS,
            # The drop is sharp: a straight line into the down pose, eased out of it.
            linear={"root": [0]},
        ),
    )
