# Boss 302: a crack and a flame on every upshift, evidence (#263)

Systems agent, 2026-11-01. Offline, no Studio: everything here was run in Lune on DriveSim.

| File | What it is |
|---|---|
| `breaks.txt` | Four deliberate breaks, applied one at a time; each one fails a spec, and all pass once restored |
| `identical.txt` | SHA-256 of every SVJ and DR458 audio tool output, base (b11ff6a) against branch |

## Why the Boss never cracked on an upshift

The Boss used the SVJ's upshift floors: 4,000 rpm and 0.6 throttle, read on the frame the new gear engages. The readout's
throttle comes after the gearbox's cut, and on the Boss's H box (the automatic and the manual alike) it reads 0.00 to 0.10 on that
frame. Measured on DriveSim, from rest, in every mode. So no Boss upshift ever cracked, whatever its chance. Flames come one per pop,
so no upshift threw a flame either.

## Floors chosen

Both floors are 0. A floor on the throttle cannot pass, for the reason above. A floor on the revs silences upshifts made under power,
because the clutch-in sags the revs before the gear engages. My first try was 2,000 rpm. On the manual box at 0.6 throttle, a 2-to-3
asked at 3,500 rpm engaged at 1,987 rpm and stayed silent (break 2). So a light cruise upshift also cracks: on this box the readout cannot tell it from a power upshift.

## Upshifts against cracks and flames, measured

`Boss302.spec` "Boss 302's upshift cracks" pulls away from rest for 25 s with the throttle held. It draws 0.999 for every chance, the unluckiest draw that
still pops at a chance of 1, so any chance under 1 shows up.

| Mode | auto, throttle 1 | auto, 0.5 | manual, 1, shift at 6,800 | manual, 0.6, at 3,500 | manual, 0.4, at 2,500 |
|---|---|---|---|---|---|
| Normal | 4 / 4 / 4 | 4 / 4 / 4 | 5 / 5 / 5 | 5 / 5 / 5 | 4 / 4 / 4 |
| Sport | 4 / 4 / 4 | 3 / 3 / 3 | 5 / 5 / 5 | 5 / 5 / 5 | 4 / 4 / 4 |
| TracKey | 4 / 4 / 4 | 3 / 3 / 3 | 5 / 5 / 5 | 5 / 5 / 5 | 4 / 4 / 4 |

Each cell is upshifts engaged / Upshift pops / flames (`Rules/ExhaustFlames.share`). The automatic's shift points are the current
`Physics`. Another agent is retuning them, and the spec asks for at least three upshifts per run, with every one cracking.
