Evidence for #143: the dip in the engine loops at the end of a start-up played from the events
file's region (the SVJ's start-up, the DR458's fallback).

spec_before_fix.txt  tests/StartupHandOver.spec.luau run on 1123f39, the rule extracted with
                     main's order of checks (the bug kept): its two region-end cases fail.
mutations.txt        Each rule of Rules/StartupHandOver broken on purpose (mutate.py), the unit
                     tests run, the file restored from its saved bytes.
timeline.txt         tools/audio_timeline.luau on main, before the fix and after, compared field by
                     field (tldiff.py), with the idle loop traced at each start-up's end
                     (idle_trace.py).
playcheck.txt        Four muted Studio Play sessions through Controllers/CarAudio: main (the dip
                     reproduced, and what the removed Sound reads), then this branch on the SVJ, the
                     DR458's own sound and the DR458 fallback.

    python -I mutate.py <worktree> <out.txt>
    python -I tldiff.py <a.json> <b.json>
    python -I idle_trace.py <from s> <to s> <timeline.json>...
