"""
Cuts a Drive Lab sound set for the Boss 302 out of an Assetto Corsa mod's FMOD bank (plain PCM, read
with tools/assets/fsb5_extract.py), the way the SVJ's and the DR458's mod banks were cut. Two banks:

  a3dr     the A3DR mod's own a3dr_boss302_laguna_seca.bank. Its samples are named after Corvettes
           (C7, C7 with a Borla exhaust, C6R, C5): the mod reuses another car's recordings.
  iracer5  iRacer5's HPE 650 replacement a3dr_boss302_laguna_seca_650.bank (2017): a numbered
           on-throttle set (ExhL exhaust takes, stereo; EngA and EngB engine takes, mono) whose name
           carries an rpm, off-throttle loops named after GM's LS9, and a Ford GT GT1 supercharger.
           Every numbered take's 4th-order line sits 44.1/48 below the rpm in its name, so that ratio
           times the name is where its line is looked for.

The banks' samples carry no loop points, so each engine loop is cut where the samples near its end
best match its first 50 ms (normalised cross-correlation) and crossfaded in. Its rpm is the 4th engine
order of a V8 (rpm / 15 Hz), read off the whole loop near a hint: the rpm at which the mod plays it at
its recorded pitch (the auto-pitch reference times 2^(-pitch / 12), tools/audio/fmod_autopitch.py),
unless the set gives one. Loops are matched to -18 LUFS, gear sounds to -14 LUFS and pops to -20 LUFS
on their loudest 400 ms, as the other cars' sets are; off-throttle loops keep their level against the
on-throttle ones at the same rpm. The limiter is the top on-throttle loop raised to the Boss 302's
7,500 rpm and gated. The one-shots go into one packed events file. Neither bank has a start-up.

    python -I tools/audio/cut_boss302.py <bank> <fmod_autopitch.txt> <out dir> [a3dr|iracer5]
"""

import json
import os
import re
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cut_dr458 as D  # noqa: E402
import cut_loops as C  # noqa: E402

RATE = D.RATE
LOOP_LUFS = -18.0
GEAR_LUFS = -14.0
POP_LUFS = -20.0
LIMITER_RPM = 7500
EVENT_GAP_SECONDS = 0.5

NAMED_RATE = 44100 / 48000

# Per set: Drive Lab layer name, bank sample, load, and optionally where to look for its line (rpm).
SETS = {
    # The exterior C7 set with the Borla exhaust above 6,000 rpm and the C5 on-throttle takes that fill
    # its 4,000 to 6,000 rpm gap, as the mod's exterior event does.
    "a3dr": {
        "loops": [
            ("idle", "C7_ex_idle", "Both"),
            ("on_verylow", "C7_ex_on_verylow2", "On"),
            ("on_low", "C7_ex_onlow2", "On"),
            ("on_lowmid", "C7_ex_onlow23", "On"),
            ("on_mid", "C5_onmid", "On"),
            ("on_midhigh", "C5_onhigh", "On"),
            ("on_high", "C7_Borla_ex_on_high", "On"),
            ("on_higher", "C7_Borla_ex_on_mid", "On"),
            ("on_top", "C7_Borla_ex_on_midhigh", "On"),
            ("off_verylow", "C7_ex_off_verylow", "Off"),
            ("off_low", "C7_ex_offlow", "Off"),
            ("off_mid", "C7_ex_off_mid_3", "Off"),
            ("off_high", "C7_ex_off_mid", "Off"),
            ("off_top", "C7_Borla_off_high", "Off"),
        ],
        # Smooth idles the bank also holds, measured for the TracKey question only.
        "idles": [("C7_ex_idle", None), ("C7_idle2", None)],
        "gears": ["gearup", "gearupEXT", "geardnEXT", "missgear"],
        "pops": ["C7_pop", "C7_pop23", "C7_back_1", "C7_back_2", "C7_back_3"],
        "backfires": [f"backfireEXT_{n}" for n in range(1, 10)],
    },
    # The exhaust takes, and the engine take at 2,451 that the mod's own curves cross with the exhaust
    # take at 3,279, where the exhaust set has nothing between 1,636 and 3,279.
    "iracer5": {
        "loops": [
            ("idle", "1 ExhL_00891", "Both", 891 * NAMED_RATE),
            ("on_1636", "4 ExhL_01636", "On", 1636 * NAMED_RATE),
            ("on_2451", "6 EngB_02451", "On", 2451 * NAMED_RATE),
            ("on_3279", "6 ExhL_03279", "On", 3279 * NAMED_RATE),
            ("on_3841", "7 ExhL_03841", "On", 3841 * NAMED_RATE),
            ("on_4418", "8 ExhL_04418", "On", 4418 * NAMED_RATE),
            ("on_5520", "10 ExhL_05520", "On", 5520 * NAMED_RATE),
            ("on_6623", "12 ExhL_06623", "On", 6623 * NAMED_RATE),
            ("on_7734", "14 ExhL_07734", "On", 7734 * NAMED_RATE),
            ("off_ls9_low", "ls9_offlow", "Off", 3250 * NAMED_RATE),
            ("off_ls9_mid", "ls9_offmid", "Off", 4250 * NAMED_RATE),
            ("off_ls9_high", "ls9_offhigh", "Off", 7000 * NAMED_RATE),
        ],
        # The LS9 loops are another engine's recordings, so their raw level says nothing about the
        # Boss's: the A3DR bank's off-to-on ratios (0.54 to 0.69, one recording session) set it.
        "off_volume": 0.6,
        "idles": [("1 ExhL_00891", 891 * NAMED_RATE), ("1 EngB_00891", 891 * NAMED_RATE)],
        "gears": ["shift", "gearupEXT", "missgear"],
        "pops": ["backfire", "1_ex"],
        "backfires": ["ext_backfire1", "ext_backfire3"],
        # Not a Boss 302 sound (its engine is not supercharged): cut for the HPE 650 question only.
        "whine": "fordgtgt1_supercharger",
    },
}


def autopitch(path):
    """Sample name -> (pitch st, auto-pitch reference rpm, volume dB) of its first instrument on rpm."""
    out = {}
    for line in open(path, encoding="utf-8"):
        m = re.match(r"(\S.*?)\s+pitch\s+([+-][0-9.]+) st\s+volume\s+([+-][0-9.]+) dB.*auto-pitch on 'rpms': x1 at ([0-9.]+)", line)
        if m:
            out.setdefault(m.group(1), (float(m.group(2)), float(m.group(4)), float(m.group(3))))
    return out


def stereo(x):
    return x if x.shape[1] == 2 else np.repeat(x, 2, axis=1)


def lope(x, rpm):
    """How unevenly the idle fires: the spread of its 4th-order cycle-to-cycle amplitude (a lumpy cam
    idle varies a lot from one firing to the next), and its slow swell below 4 Hz."""
    m = C.mono(x)
    period = int(RATE * 15 / rpm)
    cycles = len(m) // period
    peaks = np.array([np.max(np.abs(m[i * period : (i + 1) * period])) for i in range(cycles)])
    env = np.sqrt(np.convolve(m**2, np.ones(int(0.02 * RATE)) / int(0.02 * RATE), mode="same"))
    spectrum = np.abs(np.fft.rfft(env - env.mean()))
    freqs = np.fft.rfftfreq(len(env), 1 / RATE)
    slow = spectrum[(freqs > 0.5) & (freqs < 4)].sum() / (spectrum[(freqs > 0.5) & (freqs < 40)].sum() + 1e-12)
    return {"firing_peak_cv": round(float(peaks.std() / peaks.mean()), 3), "slow_swell_share": round(float(slow), 3)}


def one_shot(bank, name, target):
    x = stereo(C.trim(bank[name][0]))
    y, lufs, peak = C.normalise(x, target, periodic=False)
    return y, {"source": name, "loudness_lufs_400ms_max": round(lufs, 2), "peak_dbfs": round(peak, 2)}


def main(bank_path, autopitch_path, out, set_name="a3dr"):
    chosen = SETS[set_name]
    os.makedirs(os.path.join(out, "wav"), exist_ok=True)
    bank = D.read_bank(bank_path)
    mapping = autopitch(autopitch_path)
    files, raw_levels = [], {}
    for name, sample, load, *hint in chosen["loops"]:
        x = stereo(bank[sample][0])
        pitch, reference, _ = mapping[sample]
        played_at = reference * 2 ** (-pitch / 12)
        loop, cut = D.seamless(x, len(x))
        rpm = D.line_rpm(loop, hint[0] if hint else played_at, orders=(4.0,), band=0.15)
        raw = C.loudness(loop, periodic=True)
        raw_levels[name] = raw
        y, lufs, peak = C.normalise(loop, LOOP_LUFS, periodic=True)
        entry = {"name": name, "kind": "engine_loop", "load": load, "rpm": round(rpm), "loop": True, "source": sample,
                 "mod_pitch_st": pitch, "mod_reference_rpm": reference, "mod_played_at_rpm": round(played_at),
                 "cut": cut, "raw_lufs": round(raw, 2), "loudness_lufs": round(lufs, 2), "peak_dbfs": round(peak, 2),
                 "tilt": D.tilt(y)}
        if name == "idle":
            entry["lope"] = lope(y, rpm)
        files.append(D.save(out, name, y, entry))
    on = sorted((e["rpm"], raw_levels[e["name"]]) for e in files if e["load"] == "On")
    for e in files:
        if e["load"] == "Off":
            near = min(on, key=lambda p: abs(p[0] - e["rpm"]))
            e["volume_vs_on"] = chosen.get("off_volume") or round(float(min(1.0, 10 ** ((raw_levels[e["name"]] - near[1]) / 20))), 3)
    top = max((e for e in files if e["load"] == "On"), key=lambda e: e["rpm"])
    top_audio = C.read(os.path.join(out, "wav", top["name"] + ".wav"))
    D.LIMITER_RPM = LIMITER_RPM
    limiter, how = D.limiter_loop(top_audio, top["rpm"])
    files.append(D.save(out, "limiter", limiter, {"name": "limiter", "kind": "limiter", "rpm": LIMITER_RPM, "loop": True, "source": how}))

    if "whine" in chosen:
        sample = chosen["whine"]
        pitch, reference, volume = mapping[sample]
        loop, cut = D.seamless(stereo(bank[sample][0]), len(bank[sample][0]))
        raw = C.loudness(loop, periodic=True)
        y, lufs, peak = C.normalise(loop, LOOP_LUFS, periodic=True)
        # Its level against the engine is not readable from the bank (its raw level plus the
        # instrument's volume puts it 15 dB over the on loops), so none is given.
        files.append(D.save(out, "whine", y, {
            "name": "whine", "kind": "whine", "loop": True, "source": sample, "rpm": round(reference * 2 ** (-pitch / 12)),
            "mod_pitch_st": pitch, "mod_reference_rpm": reference, "mod_volume_db": volume, "cut": cut, "raw_lufs": round(raw, 2),
            "loudness_lufs": round(lufs, 2), "peak_dbfs": round(peak, 2)}))

    idles = {}
    for sample, hint in chosen["idles"]:
        x = stereo(bank[sample][0])
        pitch, reference, _ = mapping[sample]
        rpm = D.line_rpm(x, hint or reference * 2 ** (-pitch / 12), orders=(4.0,), band=0.15)
        idles[sample] = dict(lope(x, rpm), line_rpm=round(rpm))

    gap = np.zeros((int(EVENT_GAP_SECONDS * RATE), 2))
    parts, regions, cursor = [], {}, 0
    for group, names, target in (("gear", chosen["gears"], GEAR_LUFS), ("pop", chosen["pops"], POP_LUFS), ("backfire", chosen["backfires"], POP_LUFS)):
        for name in names:
            y, info = one_shot(bank, name, target)
            regions[name] = dict(info, group=group, region={"from": round(cursor / RATE, 4), "to": round((cursor + len(y)) / RATE, 4)})
            parts += [y, gap]
            cursor += len(y) + len(gap)
    events = np.concatenate(parts)
    files.append(D.save(out, "events", events, {"name": "events", "kind": "events", "loop": False, "regions": regions}))
    manifest = {"source": os.path.basename(bank_path), "files": files, "idles": idles,
                "missing": ["start-up", "clutch", "shift lever foley", "stall"]}
    json.dump(manifest, open(os.path.join(out, "manifest.json"), "w"), indent=1)
    for e in files:
        if e["kind"] == "engine_loop":
            print("%-11s %-24s %-4s rpm %5d (mod plays at %5d) raw %6.1f LUFS seam ncc %.2f seam-after-ogg jump %.2f  roll-off: >2k %.2f%%%s" % (
                e["name"], e["source"], e["load"], e["rpm"], e["mod_played_at_rpm"], e["raw_lufs"], e["cut"]["seam_ncc"],
                e["seam_after_ogg"]["jump_vs_p999"], e["tilt"]["above_2k_pct"], ("  off volume %.3f" % e["volume_vs_on"]) if "volume_vs_on" in e else ""))
    print("idles:", json.dumps(idles))
    print("events:", len(regions), "one-shots,", round(len(events) / RATE, 2), "s")


if __name__ == "__main__":
    main(*sys.argv[1:5])
