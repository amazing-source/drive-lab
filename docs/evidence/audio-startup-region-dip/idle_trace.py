import json, sys
# Prints the idle loop's volume (layer 1) around a time window, for each timeline given.
lo, hi = float(sys.argv[1]), float(sys.argv[2])
for path in sys.argv[3:]:
    d = json.load(open(path))
    print("==", path.split("timeline")[-1])
    prev = None
    for f in d["frames"]:
        if lo <= f["t"] <= hi:
            v = f["volumes"][0]
            print(f"t={f['t']:.4f} rpm={f['rpm']:.1f} idle={v:.4f}")
