"""
The run cycle's key poses, authored for one step and mirrored for the other, written as the
keys file r6_rig.py builds from. Angles are degrees in body axes (see r6_rig.py for signs);
a limb's world angle is its joint angle minus the torso lean, so a leg straight down under a
torso leaned 40 degrees forward is a hip angle of +40.

Timing comes from the reference clip: a full cycle of 16 frames at 30 fps (0.53 s), each step
8 frames: flight, contact, compression, then a fast scissor into the mirrored pose.

  python -I run_keys.py <out.keys.json>
"""
import sys

from cycle_keys import keys_file, write

FPS = 30
STEP = 8

LEAN = -45.0

# One step, from flight with the right arm and left leg forward to the same pose mirrored.
# "near" is the right side in step A. Each key: frame -> joint -> (x, y, z) [, root loc].
# Arms and the trailing leg HOLD through flight and stance and swap in about two frames, as
# in the reference; only the planted leg and the body move during the hold.
STEP_A = [
    {
        "frame": 0,  # flight: hold the throw
        "root": ((LEAN, 10, 0), (0, 0.20, 0)),
        "neck": (32, -8, 0),
        "right_arm": (112, 0, 18),
        "left_arm": (-84, 0, -6),
        "right_leg": (-45, 0, 4),
        "left_leg": (75, 0, -3),
    },
    {
        "frame": 1,
        "root": ((LEAN - 1, 10, 0), (0, 0.15, 0)),
        "neck": (32, -8, 0),
        "right_arm": (114, 0, 18),
        "left_arm": (-85, 0, -6),
        "right_leg": (-46, 0, 4),
        "left_leg": (76, 0, -3),
    },
    {
        "frame": 2,  # end of flight: the front leg reaches for the ground
        "root": ((LEAN - 2, 10, 0), (0, 0.0, 0)),
        "neck": (33, -8, 0),
        "right_arm": (114, 0, 18),
        "left_arm": (-85, 0, -6),
        "right_leg": (-47, 0, 4),
        "left_leg": (76, 0, -3),
    },
    {
        "frame": 3,  # contact, well ahead of the body
        "root": ((LEAN - 3, 9, 0), (0, -0.28, 0)),
        "neck": (34, -8, 0),
        "right_arm": (113, 0, 18),
        "left_arm": (-84, 0, -6),
        "right_leg": (-47, 0, 4),
        "left_leg": (74, 0, -3),
    },
    {
        "frame": 4,  # mid-stance: a rigid leg vaults the body; the give is in the lean
        "root": ((LEAN - 6, 8, 0), (0, -0.33, 0)),
        "neck": (36, -7, 0),
        "right_arm": (112, 0, 18),
        "left_arm": (-83, 0, -6),
        "right_leg": (-46, 0, 4),
        "left_leg": (52, 0, -3),
    },
    {
        "frame": 5,  # late stance: the leg drives back under and behind
        "root": ((LEAN - 5, 6, 0), (0, -0.31, 0)),
        "neck": (36, -6, 0),
        "right_arm": (108, 0, 17),
        "left_arm": (-79, 0, -6),
        "right_leg": (-42, 0, 4),
        "left_leg": (25, 0, -2),
    },
    {
        "frame": 6,  # toe-off; the swap begins
        "root": ((LEAN - 3, 2, 0), (0, -0.08, 0)),
        "neck": (35, -2, 0),
        "right_arm": (70, 0, 14),
        "left_arm": (-30, 0, -10),
        "right_leg": (-10, 0, 3),
        "left_leg": (6, 0, -2),
    },
    {
        "frame": 7,  # the swap, nearly done in one frame
        "root": ((LEAN - 1, -7, 0), (0, 0.15, 0)),
        "neck": (33, 6, 0),
        "right_arm": (-50, 0, 13),
        "left_arm": (95, 0, -16),
        "right_leg": (60, 0, 3),
        "left_leg": (-35, 0, -3),
    },
]

if __name__ == "__main__":
    write(
        sys.argv[1],
        keys_file(
            STEP_A,
            STEP,
            FPS,
            # The planted leg sweeps at an even rate from contact to toe-off, so the foot keeps
            # pace with the ground; eased keys there slow it at each key and make it slide.
            linear={"left_leg": range(3, 6)},
            # The swap: arms and legs scissor here, and the wind-wrap effect covers it.
            markers=[("Swap", 6)],
        ),
    )
