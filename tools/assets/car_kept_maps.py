"""SurfaceAppearance sets for the source materials a car keeps (no library set), from their own textures.

    python -I tools/assets/car_kept_maps.py <car settings.json> <inventory.json> <export dir> <sa dir>
        --textures <dir> [--root <dir>] [--break size|cover|alpha]

The pieces in <export dir>/export.json whose material is neither a set of <sa dir>/surface_appearances.json
nor listed as flat in the settings get a set built from the material's Assetto Corsa values, as
tools/blender/kn5_import.py renders them (the inventory, tools/blender/car_inventory.py, carries them):
- ColorMap: txDiffuse x the mean colour of txDetail (when useDetail) x ksDiffuse / 0.5 (clamped to
  0.05..1), resized to a square power of two of at most 1024 px (UVs are relative, so a stretch keeps
  the mapping); its alpha is kept, with AlphaMode Transparency, on a blended or alpha-tested material;
- RoughnessMap: 1 - txMaps' green x min(1, ksSpecularEXP / 60), else one value from ksSpecular;
- MetalnessMap: 1 where fresnelC >= 0.7 and fresnelMaxLevel >= 0.9 (mirror-like), else 0;
- no NormalMap (the source's green-channel convention is not verified yet).
A map with one value everywhere is written at 16 px; maps are named by content hash exactly as
car_surface_appearances.py names them, so a map another car uploaded already keeps its id. A material
whose maps are all uniform and opaque becomes a flat set (Material and Color only).

Settings, section "import.kept" (per material name, after the ".001" suffix is dropped):
- {"flat": {Material, Color, Transparency?, Reflectance?}}: no SurfaceAppearance;
- {"image": <path under --root>, "roughness": r, "metalness": m}: a ColorMap from that image;
- {"roughness": r, "metalness": m}: override the derived values (uniform maps);
- section "import.detailColours" {texture file: [r, g, b]} replaces a detail texture's mean colour
  (a livery's paint), and "import.textures" {file: path under --root} replaces a source texture.
Writes <sa dir>/kept.json (sets in the surface_appearances.json form, kind "kept" or "flat") and the
maps into <sa dir>/maps. Checks (exit 1): every kept material on a piece is covered; every map square,
a power of two, at most 1024 px; a ColorMap has alpha only on a blended set; a derived ColorMap's mean
within 3 levels of the source's mean times its detail colour and ksDiffuse. --break size writes one
map at 2048, --break cover drops one material's settings entry and its source, --break alpha keeps the
alpha of an opaque material, --break resize resizes colour with its alpha (premultiplied: the mean check fails).
"""
import hashlib
import json
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

args = sys.argv[1:]
settings = json.loads(Path(args[0]).read_text())["import"]
inventory = json.loads(Path(args[1]).read_text())
export = json.loads((Path(args[2]) / "export.json").read_text())
sa_dir = Path(args[3])
TEX = Path(args[args.index("--textures") + 1])
ROOT = Path(args[args.index("--root") + 1]) if "--root" in args else TEX
BREAK = args[args.index("--break") + 1] if "--break" in args else None
contract = json.loads((sa_dir / "surface_appearances.json").read_text())["sets"]
maps_dir = sa_dir / "maps"
maps_dir.mkdir(parents=True, exist_ok=True)
KEPT = dict(settings.get("kept", {}))
DETAIL = settings.get("detailColours", {})
TEXTURES = settings.get("textures", {})
fail, out = [], {}
# Maps already in the folder (the library sets' contract) keep their names: one file per content hash.
written = {f.name[:10]: f.name for f in sorted(maps_dir.glob("*.png"))}


def setname(m):
    return re.sub(r"\.\d{3}$", "", m)


def write(img: Image.Image, set_name, role):
    data = img.tobytes() + img.mode.encode() + str(img.size).encode()
    h = hashlib.sha1(data).hexdigest()[:10]
    if h in written:
        return written[h]
    path = maps_dir / f"{h}_{set_name}_{role}.png"
    img.save(path, optimize=True)
    written[h] = path.name
    return path.name


def check(img, where, role, alpha_ok=False):
    w, h = img.size
    if w > 1024 or h > 1024 or w != h or w & (w - 1):
        fail.append(f"{where} {role}: {w}x{h}, wants square, power of two, at most 1024")
    if role == "ColorMap" and not alpha_ok and img.mode == "RGBA" and np.asarray(img)[..., 3].min() < 255:
        fail.append(f"{where} ColorMap: has alpha but the set is opaque")


def square(img):
    # Pillow premultiplies alpha when it resizes RGBA: colour under alpha 0 would come out black, so the
    # colour and the alpha are resized apart.
    side = 1
    while side < max(img.size):
        side *= 2
    side = min(side, 1024)
    if img.size == (side, side):
        return img
    if img.mode == "RGBA" and BREAK != "resize":
        rgb = img.convert("RGB").resize((side, side), Image.LANCZOS)
        return Image.merge("RGBA", (*rgb.split(), img.getchannel("A").resize((side, side), Image.LANCZOS)))
    return img.resize((side, side), Image.LANCZOS)


def uniform(a):
    return a.reshape(-1, a.shape[-1] if a.ndim == 3 else 1).min(0).tolist() == a.reshape(-1, a.shape[-1] if a.ndim == 3 else 1).max(0).tolist()


def scalar_map(value_or_array, set_name, role):
    if np.isscalar(value_or_array):
        img = Image.fromarray(np.full((16, 16), int(round(float(value_or_array) * 255)), np.uint8), "L")
    else:
        a = np.clip(np.round(value_or_array * 255), 0, 255).astype(np.uint8)
        img = Image.fromarray(np.full((16, 16), int(a.flat[0]), np.uint8) if a.min() == a.max() else a, "L")
    check(img, set_name, role)
    return write(img, set_name, role.replace("Map", "").lower()), img


def texture(file):
    return ROOT / TEXTURES[file] if file in TEXTURES else TEX / file


used = sorted({setname(r["material"]) for r in export["parts"]})
kept = [m for m in used if m not in contract]
mats = {setname(k): v for k, v in inventory["materials"].items()}
if BREAK == "cover":
    victim = next(m for m in kept if m not in KEPT or "flat" not in KEPT[m])
    KEPT.pop(victim, None)
    mats.pop(victim, None)
for name in kept:
    spec = KEPT.get(name, {})
    if "flat" in spec:
        out[name] = {"kind": "flat", "MeshPart": spec["flat"]}
        continue
    if "image" in spec:
        col = square(Image.open(ROOT / spec["image"]).convert("RGB"))
        if BREAK == "size" and not fail:
            col = col.resize((2048, 2048))
        check(col, name, "ColorMap")
        sa = {"ColorMap": write(col, name, "color"), "AlphaMode": "Overlay"}
        sa["RoughnessMap"] = scalar_map(spec.get("roughness", 0.5), name, "RoughnessMap")[0]
        sa["MetalnessMap"] = scalar_map(spec.get("metalness", 0.0), name, "MetalnessMap")[0]
        out[name] = {"kind": "kept", "SurfaceAppearance": sa, "MeshPart": {"Material": spec.get("material", "SmoothPlastic")},
                     "note": f"ColorMap from {spec['image']}"}
        continue
    m = mats.get(name)
    props = m and m["props"].get("kn5_properties")
    if not props:
        fail.append(f"{name}: kept on {sum(1 for r in export['parts'] if setname(r['material']) == name)} pieces, "
                    "no Assetto Corsa values and no settings entry")
        continue
    p = json.loads(props)
    slots = {k: v["texture"] for k, v in json.loads(m["props"]["kn5_slots"]).items()}

    def prop(key, default=0.0):
        return p[key]["a"] if key in p else default

    kd = min(1.0, max(0.05, prop("ksDiffuse", 0.5) / 0.5))
    blended = m["props"].get("kn5_blend", 0) != 0 or bool(m["props"].get("kn5_alpha_tested")) or prop("ksAlphaRef") > 0
    if BREAK == "alpha" and not blended and "txDiffuse" in slots:
        blended, forced = True, True
    else:
        forced = False
    src = Image.open(texture(slots["txDiffuse"])).convert("RGBA") if "txDiffuse" in slots else None
    a = np.asarray(square(src), np.float64) if src else np.full((16, 16, 4), 255.0 * kd * 0.5)
    rgb = a[..., :3]
    detail_note, factor = "", np.ones(3)
    if src is not None and "txDetail" in slots and prop("useDetail") > 0:
        file = slots["txDetail"]
        colour = DETAIL.get(file)
        if colour is None:
            colour = np.asarray(Image.open(texture(file)).convert("RGB"), np.float64).reshape(-1, 3).mean(0).tolist()
        factor = np.asarray(colour) / 255.0
        rgb = rgb * factor
        detail_note = f" x {file} {[round(c) for c in colour]}"
    if src is not None:
        rgb = rgb * kd
        # The map's mean against the same product at the source's own size: a resize that loses the colour fails.
        want = np.asarray(src, np.float64)[..., :3].reshape(-1, 3).mean(0) * factor * kd
        if np.abs(rgb.reshape(-1, 3).mean(0) - want).max() > 3:
            fail.append(f"{name} ColorMap: mean {rgb.reshape(-1, 3).mean(0).round(1).tolist()}, the source gives {want.round(1).tolist()}")
    rgb = np.clip(np.round(rgb), 0, 255).astype(np.uint8)
    if blended:
        alpha = np.clip(np.round(a[..., 3]), 0, 255).astype(np.uint8)
        if forced:
            alpha[0, 0] = 0
        col = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
    else:
        col = Image.fromarray(rgb, "RGB")
    if uniform(np.asarray(col)):
        col = col.resize((16, 16), Image.NEAREST)
    check(col, name, "ColorMap", alpha_ok=blended and not forced)
    exp_ = min(1.0, prop("ksSpecularEXP", 10.0) / 60.0)
    if "roughness" in spec:
        rough = float(spec["roughness"])
    elif "txMaps" in slots:
        g = np.asarray(square(Image.open(texture(slots["txMaps"])).convert("RGB")), np.float64)[..., 1] / 255.0
        rough = np.clip(1.0 - g * exp_, 0.0, 1.0)
    else:
        rough = max(0.05, min(0.95, 1.0 - exp_ * min(1.0, prop("ksSpecular", 0.3))))
    metal = float(spec["metalness"]) if "metalness" in spec else (
        1.0 if prop("fresnelC") >= 0.7 and prop("fresnelMaxLevel") >= 0.9 else 0.0)
    rname, rimg = scalar_map(rough, name, "RoughnessMap")
    mname, _ = scalar_map(metal, name, "MetalnessMap")
    material = "Metal" if metal >= 0.5 else "SmoothPlastic"
    if col.size == (16, 16) and not blended and rimg.size == (16, 16):
        c = np.asarray(col.convert("RGB"))[0, 0].tolist()
        out[name] = {"kind": "flat", "MeshPart": {"Material": material, "Color": c},
                     "note": f"every derived map uniform: {slots.get('txDiffuse')}{detail_note} x {kd:.2f}"}
        continue
    sa = {"ColorMap": write(col, name, "color"), "RoughnessMap": rname, "MetalnessMap": mname,
          "AlphaMode": "Transparency" if blended else "Overlay"}
    part = {"Material": material, "Transparency": 0.02} if blended else {"Material": material}
    out[name] = {"kind": "kept", "SurfaceAppearance": sa, "MeshPart": part,
                 "note": f"{slots.get('txDiffuse')}{detail_note} x ksDiffuse {kd:.2f}; roughness "
                         + ("txMaps green" if not np.isscalar(rough) else f"{float(rough):.3f}") + f"; metalness {metal:.0f}"}

emissive = []
for entry in settings.get("emissive", []):
    img = Image.open(ROOT / entry["image"]).convert("L")
    check(img, entry["pattern"], "EmissiveMask")
    emissive.append({"pattern": entry["pattern"], "EmissiveMask": write(img, re.sub(r"\W", "", entry["pattern"]), "emissive")})
(sa_dir / "kept.json").write_text(json.dumps(
    {"about": "Kept source materials: SurfaceAppearance sets from their own textures on their own UVs "
              "(tools/assets/car_kept_maps.py); no NormalMap. `emissive`: masks for pieces matching a pattern.",
     "sets": out, "emissive": emissive}, indent=1))
refs = {v for s in out.values() for k, v in s.get("SurfaceAppearance", {}).items() if k.endswith("Map")} | {
    e["EmissiveMask"] for e in emissive}
sizes = sum((maps_dir / f).stat().st_size for f in refs)
print(f"KEPT {len(kept)} kept materials on the pieces: {sum(1 for v in out.values() if v['kind'] == 'kept')} with maps, "
      f"{sum(1 for v in out.values() if v['kind'] == 'flat')} flat; {len(refs)} maps ({sizes / 1e6:.2f} MB)")
for name, v in sorted(out.items()):
    print(f"KEPT   {name:28s} {v['kind']:5s} {v.get('note', '')}")
for f in fail:
    print("KEPT FAIL", f)
sys.exit(1 if fail else 0)
