# The automatic's 1-2 hunt in Sport: Play check before and after (#35)

Solo Play in the owner's place, 2026-10-29 12:42-12:47, Studio lock held by the systems agent, no
network simulation. Keys from Studio's simulated keyboard: E at the door, R to start, M once
(Strada to Sport), then W held 6 s from a standstill, automatic. A client probe logged every gear
change with the signed speed along the car.

## After the fix (`agent/car-gearbox-hunt` on main cedf1d7; first sync 3 written, second 0)

    CHANGE t=6.31 g=2 v=71.2 km/h rpm=7583 thr=1.00 mode=Sport/auto
    CHANGE t=8.72 g=3 v=126.7 km/h rpm=8202 thr=1.00 mode=Sport/auto

One upshift per gear through 70-80 km/h. (A 3 to 4 followed at 144.8 km/h as W was released: the
part-throttle upshift point on the way down, unchanged by this fix.)

## Before the fix (main cedf1d7, synced from `.worktrees/car-launch-control`, whose game code is
## identical to main's; 3 written)

    CHANGE t=3.52 g=2 v=71.5 km/h rpm=7853 thr=1.00 mode=Sport/auto
    CHANGE t=3.72 g=1 v=74.7 km/h rpm=7129 thr=0.40 tc=true mode=Sport/auto
    CHANGE t=3.93 g=2 v=76.8 km/h rpm=7720 thr=1.00 mode=Sport/auto
    CHANGE t=5.99 g=3 v=127.1 km/h rpm=7887 thr=1.00 mode=Sport/auto

The hunt the owner saw: second, back to first 0.2 s later with traction control acting, second
again. The place was then synced back to the fix (3 written, then 0) and left there.

## The cause, from DriveSim (60 FPS, full throttle from a standstill)

    t=2.233 v=69.8 km/h gear=1 target=2 inputRpm=8115 rearSlip=0.107   <- upshift asked at 8,600
    t=2.383 v=72.7 km/h gear=2 inputRpm=6050 rearSlip=0.273 tc=true    <- the rears flare, TC cuts
    t=2.417 v=73.7 km/h gear=2 target=1 inputRpm=4879 rearSlip=0.048   <- back to road speed, under 5,000

With the downshift made impossible (a copy of Sport with no downshift point), second's input stayed
under 5,000 rpm for 0.15 s in all, the last time 0.34 s after the upshift, lowest 4,740 rpm; the same
within 0.04 s at 30, 60 and 240 FPS. Strada and Corsa shift 1, 2, 3 with or without the fix.
