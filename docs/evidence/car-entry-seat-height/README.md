# Seat height for the seated driver (decided 2026-10-28)

**Decision (coordinator, delegated by the owner): keep today's seat height (T).** Recorded on #8.

The question: with Roblox's upright sit at the seat point the owner tuned for the cockpit eye, the
seated R6 floats above the SVJ's cushion. Should the body be lowered onto it?

Measured by the hands-and-legs agent in Studio edit mode (a rigged copy of the car, an R6 at the
seated scale, the custom arms and legs running; everything restored). Numbers in
`measurements.json`.

| | T: today | B: on the cushion, eye kept | B': B with a 20-degree recline |
|---|---|---|---|
| Body drop | none | 0.87 studs (0.16 m) | as B, torso reclined |
| Arm reach used, straight ahead | 94% | 128% (forearms short of the cuffs) | 156% |
| First-person view from the owner's eye | reference | identical | identical |
| Thighs | 4 to 18 cm above the cushion | resting on it | resting on it |
| Head top under the roof | 6.7 cm | 22.9 cm | 12.1 cm |

Why T:
1. The first-person view is the same in all three, so the tuned view gives no reason to move.
2. From outside, which every other player sees, B puts the head low in the window and the avatar
   reads as sunk in the seat. T shows head and shoulders above the beltline, like a real driver.
   Compare `T_outside_side_door_shut.jpg` with `B_outside_side_door_shut.jpg`.
3. B needs arms 33% longer, re-bakes of the entry clips and the hands, and moves the door prompts,
   to fix flaws mostly hidden while the door is shut. B' cannot reach the wheel.

Follow-ups inside T: the seated thighs meet the cushion with no visible gap, and the knee stays at
least 1 cm clear of the dash under full braking (#11); the entry and exit clips stay as authored
(#10). The existing over-stretch of the hand crossing the top at the 110-degree follow limit (142 to
144% reach) has its own issue, #25.
