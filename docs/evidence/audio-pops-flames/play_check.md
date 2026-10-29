# Play check: pops and flames by drive mode (#63)

Functional, not feel. Solo Play in the owner's place, 2026-10-29 12:04 to 12:09, branch head 01c058e
(main 7854a3b merged in), synced from the worktree; a second sync wrote 0. Studio lock held by the
audio agent; the place was synced back to main afterwards (second sync 0 written), not saved.

## How

- Into the car through the real path: the body stood 4 studs from the driver's door with the
  Enter prompt shown, then Studio's simulated keyboard: E tap (seated), R tap (engine on, audio
  session running).
- Checked the client runs this branch: `CarAudio.POP_TRIGGERS` read lift 0.35/1/1, upshift 0/0.6/1,
  downshift 0.25/1/1, floor 3000, lift rpm 4000, and `Rules.ExhaustPops` present.
- A client-side logger, installed in the Play session only, recorded each pop (a Sound from a pop
  region added under the car), each flame (an exhaust outlet's flash light switching on: two per
  pop, one per outlet), each gear change, and the throttle closing after it was open.
- Per mode, automatic gearbox: W held 4 s, released, 1.5 s coasting, S held 3.5 s. M to change mode.

The logger's `LIFT` is its own rough reading of the throttle: it also fires when traction control
or a shift cuts the engine's throttle (the `LIFT` at a standstill in each mode). The game's own
lift (`Rules/CarAudioEvents`) excludes those; no pop followed any of them.

## Results

| Mode | Upshifts at full throttle | Lift | Braking downshifts |
|---|---|---|---|
| Strada | 3, no crack (chance 0) | no train (chance 0.35; the automatic shifts up to seventh on the lift, at 2,846 rpm) | 6: two trains (4th at 3,430 rpm: 2 pops; 2nd at 3,447: 1 pop); 7-6 landed at 2,692, under the floor |
| Sport | 2 under load: 1 crack (chance 0.6); 2-3 at throttle 0.29: no crack (under-load rule) | one train, 3 pops | 2: both trains (3-2: 3 pops; 2-1: 5 pops) |
| Corsa | 2 under load: both cracked (chance 1); 3-4 at throttle 0.21: no crack | one train, 7 pops | 3: all trains (4-3: 2, 3-2: 4, 2-1: 4 pops) |

Every pop lit both outlets' flashes on the same frame. A 2-1 downshift at throttle 0.40 (Sport,
during the known 1-2-1 hunt, #35) did not pop: the throttle was open. No error in the session's
logs.

## Logs

Strada:

```
  8.95 LIFT      mode=Strada gear=1 rpm= 5999 thr=0.00 kmh=  3
 11.12 GEAR_UP   mode=Strada gear=2 rpm= 7216 thr=1.00 kmh= 78
 13.22 GEAR_UP   mode=Strada gear=3 rpm= 7644 thr=1.00 kmh=127
 14.40 GEAR_UP   mode=Strada gear=4 rpm= 5724 thr=0.00 kmh=144
 14.63 GEAR_UP   mode=Strada gear=5 rpm= 4583 thr=0.00 kmh=143
 14.86 GEAR_UP   mode=Strada gear=6 rpm= 3656 thr=0.00 kmh=142
 15.10 GEAR_UP   mode=Strada gear=7 rpm= 2846 thr=0.00 kmh=141
 15.18 LIFT      mode=Strada gear=7 rpm= 3207 thr=0.00 kmh=141
 18.83 GEAR_DOWN mode=Strada gear=6 rpm= 2692 thr=0.00 kmh=119
 19.11 GEAR_DOWN mode=Strada gear=5 rpm= 3139 thr=0.00 kmh=107
 19.35 GEAR_DOWN mode=Strada gear=4 rpm= 3430 thr=0.00 kmh= 98
 19.35 POP       mode=Strada gear=4 rpm= 3430 thr=0.00 kmh= 98
 19.35 FLAME     mode=Strada gear=4 rpm= 3430 thr=0.00 kmh= 98
 19.35 FLAME     mode=Strada gear=4 rpm= 3430 thr=0.00 kmh= 98
 19.49 POP       mode=Strada gear=4 rpm= 3462 thr=0.00 kmh= 93
 19.49 FLAME     mode=Strada gear=4 rpm= 3462 thr=0.00 kmh= 93
 19.49 FLAME     mode=Strada gear=4 rpm= 3462 thr=0.00 kmh= 93
 19.87 GEAR_DOWN mode=Strada gear=3 rpm= 3183 thr=0.00 kmh= 77
 20.29 GEAR_DOWN mode=Strada gear=2 rpm= 3447 thr=0.00 kmh= 60
 20.29 POP       mode=Strada gear=2 rpm= 3447 thr=0.00 kmh= 60
 20.29 FLAME     mode=Strada gear=2 rpm= 3447 thr=0.00 kmh= 60
 20.29 FLAME     mode=Strada gear=2 rpm= 3447 thr=0.00 kmh= 60
 20.74 GEAR_DOWN mode=Strada gear=1 rpm= 3904 thr=0.00 kmh= 42
```

Sport:

```
 46.80 LIFT      mode=Sport  gear=1 rpm= 6230 thr=0.00 kmh=  2
 48.15 LIFT      mode=Sport  gear=1 rpm= 5459 thr=0.00 kmh= 42
 49.21 GEAR_UP   mode=Sport  gear=2 rpm= 7740 thr=1.00 kmh= 73
 49.30 LIFT      mode=Sport  gear=2 rpm= 6239 thr=0.00 kmh= 75
 49.41 GEAR_DOWN mode=Sport  gear=1 rpm= 7261 thr=0.40 kmh= 76
 49.59 GEAR_UP   mode=Sport  gear=2 rpm= 7688 thr=1.00 kmh= 77
 49.59 POP       mode=Sport  gear=2 rpm= 7688 thr=1.00 kmh= 77
 49.59 FLAME     mode=Sport  gear=2 rpm= 7688 thr=1.00 kmh= 77
 49.59 FLAME     mode=Sport  gear=2 rpm= 7688 thr=1.00 kmh= 77
 51.20 GEAR_UP   mode=Sport  gear=3 rpm= 7004 thr=0.29 kmh=115
 51.23 LIFT      mode=Sport  gear=3 rpm= 5620 thr=0.00 kmh=115
 51.23 POP       mode=Sport  gear=3 rpm= 5620 thr=0.00 kmh=115
 51.23 FLAME     mode=Sport  gear=3 rpm= 5620 thr=0.00 kmh=115
 51.23 FLAME     mode=Sport  gear=3 rpm= 5620 thr=0.00 kmh=115
 51.45 POP       mode=Sport  gear=3 rpm= 5538 thr=0.00 kmh=114
 51.45 FLAME     mode=Sport  gear=3 rpm= 5538 thr=0.00 kmh=114
 51.45 FLAME     mode=Sport  gear=3 rpm= 5538 thr=0.00 kmh=114
 51.56 POP       mode=Sport  gear=3 rpm= 5499 thr=0.00 kmh=113
 51.56 FLAME     mode=Sport  gear=3 rpm= 5499 thr=0.00 kmh=113
 51.56 FLAME     mode=Sport  gear=3 rpm= 5499 thr=0.00 kmh=113
 53.29 GEAR_DOWN mode=Sport  gear=2 rpm= 5291 thr=0.00 kmh= 87
 53.29 POP       mode=Sport  gear=2 rpm= 5291 thr=0.00 kmh= 87
 53.29 FLAME     mode=Sport  gear=2 rpm= 5291 thr=0.00 kmh= 87
 53.29 FLAME     mode=Sport  gear=2 rpm= 5291 thr=0.00 kmh= 87
 53.52 POP       mode=Sport  gear=2 rpm= 4369 thr=0.00 kmh= 77
 53.52 FLAME     mode=Sport  gear=2 rpm= 4369 thr=0.00 kmh= 77
 53.52 FLAME     mode=Sport  gear=2 rpm= 4369 thr=0.00 kmh= 77
 53.64 POP       mode=Sport  gear=2 rpm= 4573 thr=0.00 kmh= 74
 53.64 FLAME     mode=Sport  gear=2 rpm= 4573 thr=0.00 kmh= 74
 53.64 FLAME     mode=Sport  gear=2 rpm= 4573 thr=0.00 kmh= 74
 53.81 GEAR_DOWN mode=Sport  gear=1 rpm= 5764 thr=0.00 kmh= 66
 53.81 POP       mode=Sport  gear=1 rpm= 5764 thr=0.00 kmh= 66
 53.81 FLAME     mode=Sport  gear=1 rpm= 5764 thr=0.00 kmh= 66
 53.81 FLAME     mode=Sport  gear=1 rpm= 5764 thr=0.00 kmh= 66
 53.93 POP       mode=Sport  gear=1 rpm= 5988 thr=0.00 kmh= 61
 53.93 FLAME     mode=Sport  gear=1 rpm= 5988 thr=0.00 kmh= 61
 53.93 FLAME     mode=Sport  gear=1 rpm= 5988 thr=0.00 kmh= 61
 54.15 POP       mode=Sport  gear=1 rpm= 5073 thr=0.00 kmh= 51
 54.15 FLAME     mode=Sport  gear=1 rpm= 5073 thr=0.00 kmh= 51
 54.15 FLAME     mode=Sport  gear=1 rpm= 5073 thr=0.00 kmh= 51
 54.25 POP       mode=Sport  gear=1 rpm= 4395 thr=0.00 kmh= 48
 54.25 FLAME     mode=Sport  gear=1 rpm= 4395 thr=0.00 kmh= 48
 54.25 FLAME     mode=Sport  gear=1 rpm= 4395 thr=0.00 kmh= 48
 54.39 POP       mode=Sport  gear=1 rpm= 4125 thr=0.00 kmh= 41
 54.39 FLAME     mode=Sport  gear=1 rpm= 4125 thr=0.00 kmh= 41
 54.39 FLAME     mode=Sport  gear=1 rpm= 4125 thr=0.00 kmh= 41
```

Corsa:

```
 70.91 LIFT      mode=Corsa  gear=1 rpm= 5672 thr=0.00 kmh=  3
 72.95 GEAR_UP   mode=Corsa  gear=2 rpm= 8119 thr=1.00 kmh= 77
 72.95 POP       mode=Corsa  gear=2 rpm= 8119 thr=1.00 kmh= 77
 72.95 FLAME     mode=Corsa  gear=2 rpm= 8119 thr=1.00 kmh= 77
 72.95 FLAME     mode=Corsa  gear=2 rpm= 8119 thr=1.00 kmh= 77
 75.01 GEAR_UP   mode=Corsa  gear=3 rpm= 8398 thr=1.00 kmh=128
 75.01 POP       mode=Corsa  gear=3 rpm= 8398 thr=1.00 kmh=128
 75.01 FLAME     mode=Corsa  gear=3 rpm= 8398 thr=1.00 kmh=128
 75.01 FLAME     mode=Corsa  gear=3 rpm= 8398 thr=1.00 kmh=128
 75.26 GEAR_UP   mode=Corsa  gear=4 rpm= 6104 thr=0.21 kmh=133
 75.27 LIFT      mode=Corsa  gear=4 rpm= 5295 thr=0.04 kmh=132
 75.28 POP       mode=Corsa  gear=4 rpm= 5295 thr=0.04 kmh=132
 75.28 FLAME     mode=Corsa  gear=4 rpm= 5295 thr=0.04 kmh=132
 75.28 FLAME     mode=Corsa  gear=4 rpm= 5295 thr=0.04 kmh=132
 75.42 POP       mode=Corsa  gear=4 rpm= 5140 thr=0.00 kmh=132
 75.42 FLAME     mode=Corsa  gear=4 rpm= 5140 thr=0.00 kmh=132
 75.42 FLAME     mode=Corsa  gear=4 rpm= 5140 thr=0.00 kmh=132
 75.63 POP       mode=Corsa  gear=4 rpm= 5117 thr=0.00 kmh=130
 75.63 FLAME     mode=Corsa  gear=4 rpm= 5117 thr=0.00 kmh=130
 75.63 FLAME     mode=Corsa  gear=4 rpm= 5117 thr=0.00 kmh=130
 75.71 POP       mode=Corsa  gear=4 rpm= 5094 thr=0.00 kmh=130
 75.71 FLAME     mode=Corsa  gear=4 rpm= 5094 thr=0.00 kmh=130
 75.71 FLAME     mode=Corsa  gear=4 rpm= 5094 thr=0.00 kmh=130
 75.83 POP       mode=Corsa  gear=4 rpm= 5059 thr=0.00 kmh=129
 75.83 FLAME     mode=Corsa  gear=4 rpm= 5059 thr=0.00 kmh=129
 75.83 FLAME     mode=Corsa  gear=4 rpm= 5059 thr=0.00 kmh=129
 75.94 POP       mode=Corsa  gear=4 rpm= 5029 thr=0.00 kmh=128
 75.94 FLAME     mode=Corsa  gear=4 rpm= 5029 thr=0.00 kmh=128
 75.94 FLAME     mode=Corsa  gear=4 rpm= 5029 thr=0.00 kmh=128
 76.12 POP       mode=Corsa  gear=4 rpm= 4984 thr=0.00 kmh=127
 76.12 FLAME     mode=Corsa  gear=4 rpm= 4984 thr=0.00 kmh=127
 76.12 FLAME     mode=Corsa  gear=4 rpm= 4984 thr=0.00 kmh=127
 76.99 GEAR_DOWN mode=Corsa  gear=3 rpm= 4708 thr=0.00 kmh=118
 76.99 POP       mode=Corsa  gear=3 rpm= 4708 thr=0.00 kmh=118
 76.99 FLAME     mode=Corsa  gear=3 rpm= 4708 thr=0.00 kmh=118
 76.99 FLAME     mode=Corsa  gear=3 rpm= 4708 thr=0.00 kmh=118
 77.15 POP       mode=Corsa  gear=3 rpm= 5145 thr=0.00 kmh=111
 77.15 FLAME     mode=Corsa  gear=3 rpm= 5145 thr=0.00 kmh=111
 77.15 FLAME     mode=Corsa  gear=3 rpm= 5145 thr=0.00 kmh=111
 77.38 GEAR_DOWN mode=Corsa  gear=2 rpm= 5583 thr=0.00 kmh=108
 77.38 POP       mode=Corsa  gear=2 rpm= 5583 thr=0.00 kmh=108
 77.38 FLAME     mode=Corsa  gear=2 rpm= 5583 thr=0.00 kmh=108
 77.38 FLAME     mode=Corsa  gear=2 rpm= 5583 thr=0.00 kmh=108
 77.52 POP       mode=Corsa  gear=2 rpm= 6243 thr=0.00 kmh=102
 77.52 FLAME     mode=Corsa  gear=2 rpm= 6243 thr=0.00 kmh=102
 77.52 FLAME     mode=Corsa  gear=2 rpm= 6243 thr=0.00 kmh=102
 77.71 POP       mode=Corsa  gear=2 rpm= 5433 thr=0.00 kmh= 95
 77.71 FLAME     mode=Corsa  gear=2 rpm= 5433 thr=0.00 kmh= 95
 77.71 FLAME     mode=Corsa  gear=2 rpm= 5433 thr=0.00 kmh= 95
 77.84 POP       mode=Corsa  gear=2 rpm= 5414 thr=0.00 kmh= 89
 77.84 FLAME     mode=Corsa  gear=2 rpm= 5414 thr=0.00 kmh= 89
 77.84 FLAME     mode=Corsa  gear=2 rpm= 5414 thr=0.00 kmh= 89
 78.13 GEAR_DOWN mode=Corsa  gear=1 rpm= 5579 thr=0.00 kmh= 76
 78.14 POP       mode=Corsa  gear=1 rpm= 5579 thr=0.00 kmh= 76
 78.14 FLAME     mode=Corsa  gear=1 rpm= 5579 thr=0.00 kmh= 76
 78.14 FLAME     mode=Corsa  gear=1 rpm= 5579 thr=0.00 kmh= 76
 78.28 POP       mode=Corsa  gear=1 rpm= 6528 thr=0.00 kmh= 70
 78.28 FLAME     mode=Corsa  gear=1 rpm= 6528 thr=0.00 kmh= 70
 78.28 FLAME     mode=Corsa  gear=1 rpm= 6528 thr=0.00 kmh= 70
 78.48 POP       mode=Corsa  gear=1 rpm= 5479 thr=0.00 kmh= 62
 78.48 FLAME     mode=Corsa  gear=1 rpm= 5479 thr=0.00 kmh= 62
 78.48 FLAME     mode=Corsa  gear=1 rpm= 5479 thr=0.00 kmh= 62
 78.70 POP       mode=Corsa  gear=1 rpm= 4665 thr=0.00 kmh= 54
 78.70 FLAME     mode=Corsa  gear=1 rpm= 4665 thr=0.00 kmh= 54
 78.70 FLAME     mode=Corsa  gear=1 rpm= 4665 thr=0.00 kmh= 54
```
