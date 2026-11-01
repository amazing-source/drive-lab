"""Studio import data for one car export: which piece becomes which part, each piece's look, and the uploads.

    python -I tools/assets/car_import_data.py <car settings.json> <export dir> <sa dir> <out.json>
        --ids <ids.json> [--ids <ids.json> ...] [--new <stem>,... | --new-all] [--binding <names.json>]
        [--old <old data.json>] [--stage <dir>] [--break <name>]

The pieces come from <export dir>/export.json (tools/blender/car_export.py), the looks from
<sa dir>/surface_appearances.json (tools/assets/car_surface_appearances.py) and <sa dir>/kept.json
(tools/assets/car_kept_maps.py), the per-car rules from the settings' "import" section.
- Each part keeps one MeshPart named exactly after it: its largest piece, or the piece whose material a
  "primary" rule names (a window's clear glass, a needle's pointer); its other pieces carry Part = the part.
- Ids: each --ids file holds {"decals": {map stem: Decal id}, "images": {Decal id: Image id}, "white": uri}
  from earlier uploads (the work folder's records, never the repository). Maps are matched by the content
  hash that starts their file name, so a map another car uploaded keeps its id. A map is written as
  "rbxassetid://<image>" when its image is known, "decal:<id>" when only its Decal is (the Studio runner
  resolves it), "pending:<stem>" when it is named by --new (or --new-all: every map without an id), and
  stops the build otherwise.
- Lamps: every piece named with the settings' lamp prefix gets the uniform white emissive mask at
  EmissiveStrength 0, and the ones matching `whiteColourMap` the same white image as their ColorMap
  (Roblox multiplies a glow by the colour map). Each lamp must have a SurfaceAppearance to carry it.
- Emissive: pieces matching kept.json's `emissive` patterns get that mask (a flat piece gets a
  SurfaceAppearance carrying the mask alone), at strength 0.
- Overrides: MeshPart properties for pieces matching a pattern, after their set.
- --binding: the part names the car's binding needs (games/drive-lab/tools/car_import_names.luau); a
  name with no piece stops the build.
- --old: against the previous import's data, `stable` (five unrotated Chassis pieces with identical rows,
  spread across the car: the Studio build places the new car by the offset they had in the old one) and
  `expect` new / gone / changed. Without --old, `stable` is five unrotated pieces spread across the car
  that place the upload against the export's own origins (a first import).
- --stage <dir>: copies what must be uploaded (the glb as <dir>/<car>/car.glb, so upload_images.py
  labels it with the car's name, and each pending map as <dir>/maps/<stem>.png) and writes
  <dir>/upload_list.json: path, published name, type, bytes, pixel size and sha256 per upload, and the
  maps reused from earlier uploads. Checks: at most 20 MB per file (the Open Cloud cap), no two uploads
  with the same bytes.
--break: binding (adds a name no piece has), lamp (drops the lamps' sets' maps), dup (stages one map
twice under two names), primary (a primary rule naming a material no piece of the part has).
"""
import collections
import hashlib
import json
import re
import shutil
import struct
import sys
from pathlib import Path

args = sys.argv[1:]
settings = json.loads(Path(args[0]).read_text())
S = settings["import"]
CAR = settings["car"]
export_dir, sa_dir, out = Path(args[1]), Path(args[2]), Path(args[3])


def opt(name):
    return args[args.index(name) + 1] if name in args else None


ids_files = [Path(args[i + 1]) for i, a in enumerate(args) if a == "--ids"]
NEW_ALL = "--new-all" in args
NEW = set(opt("--new").split(",")) if opt("--new") else set()
BINDING = Path(opt("--binding")) if opt("--binding") else None
OLD = Path(opt("--old")) if opt("--old") else None
STAGE = Path(opt("--stage")) if opt("--stage") else None
BREAK = opt("--break")
CAP = 20 * 1024 * 1024
problems = []

e = json.loads((export_dir / "export.json").read_text())
contract = json.loads((sa_dir / "surface_appearances.json").read_text())["sets"]
kept_file = sa_dir / "kept.json"
kept = json.loads(kept_file.read_text()) if kept_file.exists() else {"sets": {}, "emissive": []}
all_sets = dict(contract)
for name, s in kept["sets"].items():
    assert name not in all_sets, f"kept set {name} is also a library set"
    all_sets[name] = s

decal_by_hash, image_by_decal, white = {}, {}, None
for f in ids_files:
    j = json.loads(f.read_text())
    for stem, decal in j.get("decals", {}).items():
        decal_by_hash.setdefault(stem[:10], (stem, str(decal), f.name))
    image_by_decal.update({str(k): str(v) for k, v in j.get("images", {}).items()})
    white = white or j.get("white")
assert white, "no --ids file names the white image (\"white\")"


def setname(m):
    return re.sub(r"\.\d{3}$", "", m)


# Parts and their primary pieces -------------------------------------------------------------------------
primary_rules = list(S.get("primary", []))
if BREAK == "primary":
    primary_rules.insert(0, {"parts": ["Glass_Windscreen"], "materials": ["no_such_material"]})


def primary_materials(part):
    for rule in primary_rules:
        if part in rule.get("parts", []) or ("pattern" in rule and re.search(rule["pattern"], part)):
            return rule["materials"]
    return None


byp = collections.defaultdict(list)
for r in e["parts"]:
    byp[r["part"]].append(r)
names = {r["name"] for r in e["parts"]}
renames = {}
for part, rows in byp.items():
    want = primary_materials(part)
    if any(r["name"] == part for r in rows):
        if want and setname(next(r for r in rows if r["name"] == part)["material"]) not in want:
            problems.append(f"{part}: its single piece is {next(r for r in rows if r['name'] == part)['material']}, the primary rule wants {want}")
        continue
    if want:
        match = [r for r in rows if setname(r["material"]) in want]
        if not match:
            problems.append(f"{part}: no piece in {want} (pieces: {sorted(r['material'] for r in rows)})")
            match = rows
        primary = max(match, key=lambda r: r["triangles"])
    else:
        primary = max(rows, key=lambda r: r["triangles"])
    assert part not in names, part
    renames[primary["name"]] = part

pieces, final = {}, collections.Counter()
for r in e["parts"]:
    new = renames.get(r["name"], r["name"])
    final[new] += 1
    pieces[r["name"]] = {"name": new, "part": r["part"], "group": r["group"], "set": setname(r["material"]),
                         "size": r["size"], "origin": r["origin"]}
assert max(final.values()) == 1, [k for k, v in final.items() if v > 1]
by_final = {p["name"]: p for p in pieces.values()}

# Looks and ids -------------------------------------------------------------------------------------------
pending, reused, unresolved = {}, {}, []


def uri_of(file, where):
    stem = Path(file).stem
    h = stem[:10]
    if h in decal_by_hash:
        old_stem, decal, source = decal_by_hash[h]
        reused[stem] = {"from": old_stem, "decal": decal, "image": image_by_decal.get(decal), "record": source}
        return "rbxassetid://" + image_by_decal[decal] if decal in image_by_decal else "decal:" + decal
    if NEW_ALL or stem in NEW:
        pending[stem] = sa_dir / "maps" / file
        return "pending:" + stem
    unresolved.append(f"{where}: {file}")
    return "unresolved:" + stem


used = {p["set"] for p in pieces.values()}
fallback = S.get("fallback", {})
uncovered = sorted(used - set(all_sets) - set(fallback))
if uncovered:
    problems.append(f"materials on pieces with no set: {uncovered}")
sets = {}
for name in sorted(used & set(all_sets)):
    c = all_sets[name]
    entry = {"kind": c["kind"], "MeshPart": c.get("MeshPart", {})}
    if "SurfaceAppearance" in c and not (BREAK == "lamp" and any(p["name"].startswith(S["lamps"]["prefix"]) and p["set"] == name for p in pieces.values())):
        entry["SurfaceAppearance"] = {k: (uri_of(v, f"{name} {k}") if k.endswith("Map") else v) for k, v in c["SurfaceAppearance"].items()}
    sets[name] = entry

LAMP = S.get("lamps", {})
lamps = sorted(p["name"] for p in pieces.values() if LAMP and p["name"].startswith(LAMP["prefix"]))
for lamp in lamps:
    if "SurfaceAppearance" not in sets.get(by_final[lamp]["set"], {}):
        problems.append(f"{lamp} has no SurfaceAppearance to carry a mask (set {by_final[lamp]['set']})")
colour_maps = {lamp: white for lamp in lamps if LAMP.get("whiteColourMap") and re.search(LAMP["whiteColourMap"], lamp)}

emissive = {}
for entry in kept.get("emissive", []):
    mask = uri_of(entry["EmissiveMask"], f"emissive {entry['pattern']}")
    hits = sorted(n for n in by_final if re.search(entry["pattern"], n))
    if not hits:
        problems.append(f"emissive pattern {entry['pattern']} matches no piece")
    for n in hits:
        emissive[n] = mask

overrides = {}
for rule in S.get("overrides", []):
    hits = sorted(n for n in by_final if re.search(rule["pattern"], n))
    if not hits:
        problems.append(f"override pattern {rule['pattern']} matches no piece")
    for n in hits:
        overrides[n] = rule["MeshPart"]

if unresolved:
    problems.append(f"{len(unresolved)} map uses have no id and are not named --new: {unresolved[:6]}")
if NEW - set(pending) - {s for s in reused}:
    problems.append(f"--new names maps the import does not use: {sorted(NEW - set(pending))}")
for stem in NEW & set(reused):
    problems.append(f"--new names {stem}, uploaded before as {reused[stem]['from']} (Decal {reused[stem]['decal']})")

binding_names = json.loads(BINDING.read_text()) if BINDING else []
if BREAK == "binding":
    binding_names = binding_names + ["Needle_Boost"]
missing = sorted(n for n in binding_names if n not in by_final)
if missing:
    problems.append(f"the binding names parts the car does not have: {missing}")

data = {"car": CAR, "pieces": pieces, "sets": sets, "fallback": fallback, "overrides": overrides, "lamps": lamps,
        "mask": white, "lampColorMaps": colour_maps, "emissive": emissive, "bindingNames": binding_names,
        "pendingMaps": sorted(pending)}


def has_sa(p):
    return "SurfaceAppearance" in sets.get(p["set"], {}) or p["name"] in emissive


glb = (export_dir / "car.glb").read_bytes()
gltf = json.loads(glb[20:20 + struct.unpack("<I", glb[12:16])[0]])
rotated = {n["name"] for n in gltf["nodes"]
           if any(abs(a - b) > 1e-6 for a, b in zip(n.get("rotation", [0, 0, 0, 1]), [0, 0, 0, 1]))}


def off_centre(node):
    # Roblox centres a MeshPart on its mesh's bounds: where the glTF writer dropped loose vertices, the
    # bounds (the POSITION accessors' min and max) are no longer centred on the node, so the piece
    # lands off its export origin and cannot place the car.
    lo, hi = [1e9] * 3, [-1e9] * 3
    for prim in gltf["meshes"][node["mesh"]]["primitives"]:
        acc = gltf["accessors"][prim["attributes"]["POSITION"]]
        lo = [min(a, b) for a, b in zip(lo, acc["min"])]
        hi = [max(a, b) for a, b in zip(hi, acc["max"])]
    return max(abs(a + b) / 2 for a, b in zip(lo, hi))


shifted = {renames.get(n["name"], n["name"]) for n in gltf["nodes"] if "mesh" in n and off_centre(n) > 1e-4}
fn = by_final
expect = {
    "parts": len(fn),
    "withSA": sum(1 for p in fn.values() if has_sa(p)),
    "flat": sum(1 for p in fn.values() if p["set"] in sets and not has_sa(p)),
    "fallback": sum(1 for p in fn.values() if p["set"] not in sets),
    "masks": len(lamps),
    "colourMaps": len(colour_maps),
    "emissive": len(emissive),
}


def spread_pick(candidates):
    stable = []
    for axis, pick in ((0, min), (0, max), (2, min), (2, max), (1, max)):
        best = pick(candidates, key=lambda n: fn[n]["origin"][axis])
        if best not in stable:
            stable.append(best)
    return stable


if OLD:
    old = json.loads(OLD.read_text())
    fo = {p["name"]: p for p in old["pieces"].values()}

    def same(a, b):
        return all(a[k] == b[k] for k in ("set", "part", "group", "origin", "size"))

    both = sorted(set(fo) & set(fn))
    changed = [n for n in both if not same(fo[n], fn[n])]
    stable = spread_pick([n for n in both if n not in changed and n not in rotated and n not in shifted and fn[n]["group"] == "Chassis"])
    expect.update({"new": sorted(set(fn) - set(fo)), "gone": sorted(set(fo) - set(fn)), "changed": changed})
else:
    stable = spread_pick([n for n in fn if n not in rotated and n not in shifted and fn[n]["group"] == "Chassis"])
    expect.update({"new": sorted(fn), "gone": [], "changed": []})
if len(stable) != 5:
    problems.append(f"stable pieces: {stable}")
data["stable"] = stable
data["offCentre"] = sorted(shifted)
data["firstImport"] = OLD is None
data["expect"] = expect

# Uploads ---------------------------------------------------------------------------------------------------
if STAGE:
    if STAGE.exists():
        shutil.rmtree(STAGE)
    (STAGE / CAR.lower()).mkdir(parents=True)
    (STAGE / "maps").mkdir()
    entries = []
    shutil.copyfile(export_dir / "car.glb", STAGE / CAR.lower() / "car.glb")
    files = [(STAGE / CAR.lower() / "car.glb", CAR.lower(), "Model", None)]
    staged = dict(pending)
    if BREAK == "dup" and staged:
        first = sorted(staged)[0]
        staged["ffffffffff_dup_of_" + first] = staged[first]
    for stem, src in sorted(staged.items()):
        dst = STAGE / "maps" / f"{stem}.png"
        shutil.copyfile(src, dst)
        files.append((dst, stem, "Decal", src))
    from PIL import Image
    seen = {}
    for path, label, kind, src in files:
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        row = {"path": str(path).replace("\\", "/"), "published_name": label, "type": kind, "bytes": len(raw), "sha256": digest}
        if kind == "Decal":
            with Image.open(path) as im:
                row["pixels"] = list(im.size)
                row["mode"] = im.mode
        if len(raw) > CAP:
            problems.append(f"{label}: {len(raw)} bytes, over the 20 MB per-asset cap")
        if digest in seen:
            problems.append(f"{label} has the same bytes as {seen[digest]}: upload once")
        seen[digest] = label
        entries.append(row)
    upload = {"car": CAR, "uploads": entries, "upload_count": len(entries),
              "upload_bytes": sum(r["bytes"] for r in entries),
              "reused": [{"stem": k, **v} for k, v in sorted(reused.items())],
              "reused_count": len(reused)}
    (STAGE / "upload_list.json").write_text(json.dumps(upload, indent=1))

out.write_text(json.dumps(data))
print(f"{len(pieces)} pieces; {len(renames)} renamed to their part; {len(sets)} sets; {len(lamps)} lamps "
      f"({len(colour_maps)} with the white colour map); {len(emissive)} emissive; {len(overrides)} overrides; "
      f"{len(binding_names)} binding names checked")
print(f"maps: {len(reused)} reused, {len(pending)} pending upload; stable: {', '.join(stable)}; "
      f"{len(shifted)} pieces off their export origin in the glb: {sorted(shifted)[:8]}")
print("expect:", json.dumps({k: (v if not isinstance(v, list) else len(v)) for k, v in expect.items()}))
for p in problems:
    print("PROBLEM", p)
sys.exit(1 if problems else 0)
