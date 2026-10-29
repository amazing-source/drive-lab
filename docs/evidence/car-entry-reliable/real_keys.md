# Real key presses in Play

Studio's simulated keyboard (the MCP `simulate_keyboard_input`), not a physical keyboard, on branch
head e874f92 in solo Play. The harness sets the scenario up, then waits; the key comes from outside.

## No network simulation (ping 0.002 s)

| Test | Key | Result | Numbers |
|---|---|---|---|
| Get in from 4 studs out, door shut | E tap 0.1 s at the shown Enter prompt | PASS | seated, one Enter request, server saw the body 3.88 from the mark when it arrived; hand-over 0.02, torso 0.23 |
| Open the door from outside, 4 studs out | F tap 0.1 s at the shown Door prompt | PASS | door fully open, body free, one Door request; torso 0.22 |
| Get out, door shut | E held 0.6 s, seated | PASS | stood up 0.00 from where getting out ends, drift 0.00, car after 0.00; torso 0.07 |
| A tap is not an exit | E tap 0.1 s, seated | still seated 1.5 s later | entry state stayed "Enter" |
| Walk away during the walk | W held 0.5 s, sent once the walk had started (from 2.2 sideways, 4.4 out, facing away) | PASS | Cancel reached the server, reservation 0, not seated, full size, AutoRotate on, head back in the characters' collision group; torso 0.31 |
| Walk keys during the entry sequence | W held 0.6 s, sent 0.31 s into the entry clip | PASS | seated, one Enter request, the car moved 0.00 (engine off); hand-over 0.05 |

A start 5.98 studs from the prompt, inside its 6-stud reach by the harness's measure, never had the
prompt shown: the reach is measured from a point the harness does not use. A player there cannot
press it either; the walk-away test was moved nearer.

POOR_SECTION
