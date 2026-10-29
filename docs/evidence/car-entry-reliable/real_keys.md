# Real key presses in Play

Studio's simulated keyboard (the MCP `simulate_keyboard_input`), not a physical keyboard, in solo
Play. The harness sets the scenario up, then waits; the key comes from outside.

## No network simulation (ping 0.002 s), branch head e874f92

Re-run on the final head, 1624e96: see the end of this file.

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

## Poor profile (ping 0.36 s), branch head 1624e96

| Test | Key | Result | Numbers |
|---|---|---|---|
| Get in from 4 studs out, door shut | E tap 0.1 s at the shown prompt | PASS | seated, one Enter request; 0.40 s on the mark, hand-over 0.04 |
| Shut the open door from outside, 4 studs out | F tap 0.1 s | PASS | door shut, body free, one Door request; largest move 0.22 |
| Get out, door open | E held 0.6 s, seated | PASS | stood up on the exit spot, drift 0.00, car after 0.00 |
| Walk away during the walk (from 4.8 sideways, 1 out, facing along the car) | W held 0.6 s, the go and the key sent together | PASS | walk given up, reservation 0, not seated, full size, AutoRotate on, head back in the characters' group |
| A movement key after the request was sent | W held 0.5 s, arrived after the walk had reached the mark and asked | entry completed | the body stayed on the mark and was seated cleanly (hand-over 0.03, largest move 0.25). The harness expected a walk given up and marked it FAIL: the key came after the commitment point. On 6aefdb0 the same key walked the body off the mark and the server seated it from there, a 4.79-stud jump; 1624e96 fixes that |
| Walk keys during the entry sequence | W held 0.6 s, 0.30 s into the entry clip | PASS | seated, one Enter request, car moved 0.02; hand-over 0.01 |


## No network simulation (ping 0.001 s), final head 1624e96

| Test | Key | Result | Numbers |
|---|---|---|---|
| Get in with the door open, 4 studs out | E tap 0.1 s at the shown prompt | PASS | seated, one Enter request; 0.24 s on the mark, hand-over 0.01 |
| Walk away during the walk (from 2.2 sideways, 4.4 out, facing away) | W held 0.5 s, sent once the walk had started | PASS | Cancel reached the server, reservation 0, not seated, full size, AutoRotate on, head back in the characters' group |
| A movement key after the request was sent (from 4.8 sideways, 1 out) | W held 0.6 s, arrived after the walk had asked | entry completed | the body stayed on the mark and was seated cleanly (largest move 0.35); the harness's walk-away expectation does not apply once asked |
| Walk keys during the entry sequence | W held 0.6 s, 0.30 s into the entry clip | PASS | seated, one Enter request, car moved 0.02; hand-over 0.05 |
