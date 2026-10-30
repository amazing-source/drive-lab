"""Write the Roblox-ready maps and the SurfaceAppearance contract for the material sets a car uses.

    python -I tools/assets/car_surface_appearances.py <map.json> <out dir> [<apply report.json> ...]
        [--sets a,b] [--break size]

Sets come from the apply reports' `materials_built` plus `--sets` (sets built by another step, such
as the livery bake), or every set the map names when no report is given. Per set, as the SVJ was done (docs/pipelines/HERO_CAR.md sections 5-6):
- tiled sets: ColorMap (opaque RGB, so the default Overlay mode cannot show the part's Color
  through), NormalMap (OpenGL), RoughnessMap and MetalnessMap; a map with one value everywhere is
  written as a 16 x 16 uniform map; identical files are written once (content hash in the name),
  so a map two sets share (carbon gloss and satin colour) uploads once;
- source-derived sets (a source texture on the mesh's own UVs): with alpha (the stitch strip) the
  ColorMap keeps it, AlphaMode Transparency, MeshPart Transparency >= 0.02; without, opaque Overlay;
- baked sets (a livery bake): ColorMap and RoughnessMap from the bake, metalness 0, no NormalMap;
- flat sets: no SurfaceAppearance, the MeshPart's Material, Color and Transparency only.
`surface_appearances.json` maps each set to its files and properties; the upload step swaps file
names for asset ids. Checks (exit 1): every map at most 1024 px and square power of two, colour
maps opaque unless the set is alpha-blended, scalar maps single-channel, normal maps pointing out
(mean blue above 200). `--break size` writes one map at 2048 to see the size check fail.
"""
import hashlib
import json
import re
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image

args = sys.argv[1:]
M = json.loads(Path(args[0]).read_text())
out = Path(args[1])
reports = [Path(a) for a in args[2:] if a.endswith(".json")]
BREAK = args[args.index("--break") + 1] if "--break" in args else None
LIB = Path(M["library"])
LIBJ = json.loads((LIB / "library.json").read_text())
SETS = {m["name"]: m for m in LIBJ["materials"]}
SETS.update(M.get("derived", {}))
maps_dir = out / "maps"
maps_dir.mkdir(parents=True, exist_ok=True)

extra = set(args[args.index("--sets") + 1].split(",")) if "--sets" in args else set()
if reports:
    used = sorted({n for r in reports for n in json.loads(r.read_text()).get("materials_built", {})} | extra)
else:
    used = sorted({r["set"] for r in M.get("objects", {}).values() if "set" in r}
                  | {v for r in M.get("objects", {}).values() if "split_by_normal" in r
                     for k, v in r["split_by_normal"].items() if k in ("up", "other")}
                  | {r["set"] for r in M.get("materials", {}).values()})


def lib_path(name, role):
    p = LIB / name / f"{name}_{role}.png"
    reuse = re.search(r"reuses (\w+)", str(LIBJ.get(name, "")))
    if not p.exists() and reuse:
        p = LIB / reuse.group(1) / f"{reuse.group(1)}_{role}.png"
    return p


fail, contract, written = [], {}, {}


def write(img: Image.Image, set_name, role):
    data = img.tobytes() + img.mode.encode() + str(img.size).encode()
    h = hashlib.sha1(data).hexdigest()[:10]
    if h in written:
        return written[h]
    path = maps_dir / f"{h}_{set_name}_{role}.png"
    img.save(path, optimize=True)
    written[h] = path.name
    return path.name


def check(img: Image.Image, where, role, alpha_ok=False):
    w, h = img.size
    if w > 1024 or h > 1024 or w != h or w & (w - 1):
        fail.append(f"{where} {role}: {w}x{h}, wants square, power of two, at most 1024")
    if role == "ColorMap" and not alpha_ok and img.mode == "RGBA" and np.asarray(img)[..., 3].min() < 255:
        fail.append(f"{where} ColorMap: has alpha but the set is opaque")
    if role in ("RoughnessMap", "MetalnessMap") and img.mode != "L":
        fail.append(f"{where} {role}: mode {img.mode}, wants single-channel")
    if role == "NormalMap" and np.asarray(img.convert("RGB"))[..., 2].mean() <= 200:
        fail.append(f"{where} NormalMap: mean blue {np.asarray(img.convert('RGB'))[..., 2].mean():.0f}, not a tangent map")


def scalar(path, role, set_name):
    a = np.asarray(Image.open(path).convert("L"))
    img = Image.fromarray(np.full((16, 16), int(a.flat[0]), np.uint8), "L") if a.min() == a.max() \
        else Image.fromarray(a, "L")
    check(img, set_name, role)
    return write(img, set_name, role.replace("Map", "").lower())


for name in used:
    spec = SETS[name]
    kind = spec.get("kind", "tiled")
    if kind == "flat":
        c = {"MeshPart": {"Material": spec.get("roblox_material", "SmoothPlastic"), "Color": spec["albedo_srgb"]},
             "kind": "flat"}
        if "transparency" in spec:
            c["MeshPart"]["Transparency"] = spec["transparency"]
        contract[name] = c
        continue
    if kind == "source_derived":
        blended = spec.get("alpha") == "color"
        col = Image.open(spec["color"]).convert("RGBA" if blended else "RGB")
        check(col, name, "ColorMap", alpha_ok=blended)
        sa = {"ColorMap": write(col, name, "color"), "AlphaMode": "Transparency" if blended else "Overlay"}
        rough = Image.fromarray(np.full((16, 16), round(spec["roughness"] * 255), np.uint8), "L")
        metal = Image.fromarray(np.full((16, 16), round(spec["metalness"] * 255), np.uint8), "L")
        sa["RoughnessMap"], sa["MetalnessMap"] = write(rough, name, "roughness"), write(metal, name, "metalness")
        part = {"Material": "SmoothPlastic", "Transparency": 0.02} if blended else {"Material": "SmoothPlastic"}
        contract[name] = {"kind": kind, "SurfaceAppearance": sa, "MeshPart": part,
                          "note": "UVs kept from the mesh (one stitch per UV unit along U)"}
        continue
    if kind == "baked":
        col = Image.open(spec["color"]).convert("RGB")
        check(col, name, "ColorMap")
        flat = Image.fromarray(np.zeros((16, 16), np.uint8), "L")
        sa = {"ColorMap": write(col, name, "color"), "RoughnessMap": scalar(spec["roughness"], "RoughnessMap", name),
              "MetalnessMap": write(flat, name, "metalness"), "AlphaMode": "Overlay"}
        contract[name] = {"kind": kind, "SurfaceAppearance": sa, "MeshPart": {"Material": "SmoothPlastic"},
                          "note": "UVs from the livery bake (one non-overlapping atlas per side), not tiled"}
        continue
    col = Image.open(lib_path(name, "color")).convert("RGB")
    if BREAK == "size" and not fail:
        col = col.resize((2048, 2048))
    nrm = Image.open(lib_path(name, "normal")).convert("RGB")
    check(col, name, "ColorMap")
    check(nrm, name, "NormalMap")
    sa = {"ColorMap": write(col, name, "color"), "NormalMap": write(nrm, name, "normal"),
          "RoughnessMap": scalar(lib_path(name, "roughness"), "RoughnessMap", name),
          "MetalnessMap": scalar(lib_path(name, "metalness"), "MetalnessMap", name),
          "AlphaMode": "Overlay"}
    contract[name] = {"kind": "tiled", "tile_m": spec["tile_m"], "SurfaceAppearance": sa,
                      "MeshPart": {"Material": "SmoothPlastic"}}

(out / "surface_appearances.json").write_text(json.dumps(
    {"about": "Per library set: the SurfaceAppearance maps (files in maps/) and MeshPart properties. "
              "UVs on the mesh are at metres / tile_m; maps tile.", "sets": contract}, indent=1))
sizes = sum((maps_dir / f).stat().st_size for f in written.values())
print(f"EXPORT {len(contract)} sets, {len(written)} unique maps ({sizes / 1e6:.1f} MB) -> {out}")
for f in fail:
    print("EXPORT FAIL", f)
sys.exit(1 if fail else 0)
