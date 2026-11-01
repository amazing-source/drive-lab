"""Checks that every image a car's import data uses passed Roblox moderation, before the Studio build.

    python -I tools/assets/check_moderation.py <import_data.json> --ids <ids.json> [--ids ...] [--states <states.json>]

A rejected image does not fail the import: its SurfaceAppearance silently renders untextured ("not
compliant"), which is how the Boss 302's paint came out plain grey. Every "rbxassetid://" image in the
data (set maps, emissive masks, the lamp mask and colour maps) and every "decal:" id is looked up with the
Open Cloud Assets API (GET /assets/v1/assets/<id>, moderationResult.moderationState); the key comes from
ROBLOX_OPEN_CLOUD_API_KEY, as tools/assets/upload_images.py reads it, and is never printed. "pending:"
maps are skipped (resolve them first). The --ids files name each image's map stem in the report.
Exit 1 when any image is not Approved (Rejected, still Reviewing, or unreadable), naming its stem.
--states <json> ({id: state}) replaces the API, for an offline run.
"""
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

args = sys.argv[1:]
data = json.loads(Path(args[0]).read_text())
ids_files = [Path(args[i + 1]) for i, a in enumerate(args) if a == "--ids"]
states_file = Path(args[args.index("--states") + 1]) if "--states" in args else None

stem_of = {}
for f in ids_files:
    j = json.loads(f.read_text())
    decals = {str(v): k for k, v in j.get("decals", {}).items()}
    for decal, image in j.get("images", {}).items():
        stem_of[str(image).replace("rbxassetid://", "")] = decals.get(str(decal), f"decal {decal}")
    stem_of.update(decals)
    for stem, entry in j.get("replace", {}).items():
        stem_of[entry["image"].replace("rbxassetid://", "")] = f"replacement for {stem}"

uris = set()
for s in data["sets"].values():
    for key, value in s.get("SurfaceAppearance", {}).items():
        if key.endswith("Map"):
            uris.add(value)
uris |= set(data.get("emissive", {}).values()) | set(data.get("lampColorMaps", {}).values()) | {data["mask"]}
ids = sorted({u.split("//")[1] if u.startswith("rbxassetid://") else u[6:] for u in uris
              if u.startswith(("rbxassetid://", "decal:"))})
skipped = sorted(u for u in uris if not u.startswith(("rbxassetid://", "decal:")))

if states_file:
    states = {str(k): v for k, v in json.loads(states_file.read_text()).items()}

    def state(asset_id):
        return states.get(asset_id, "unknown")
else:
    sys.path.insert(0, str(Path(__file__).parent))
    from upload_images import API, api_key

    key = api_key()

    def state(asset_id):
        request = urllib.request.Request(f"{API}/assets/{asset_id}?readMask=moderationResult", headers={"x-api-key": key})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response).get("moderationResult", {}).get("moderationState", "unknown")
        except urllib.error.HTTPError as error:
            return f"HTTP {error.code}"

bad = []
for asset_id in ids:
    s = state(asset_id)
    if "approved" not in str(s).lower():
        bad.append(f"{asset_id} ({stem_of.get(asset_id, 'no stem in the ids files')}): {s}")
print(f"MODERATION {len(ids)} images checked, {len(bad)} not approved, {len(skipped)} skipped (unresolved: {skipped[:4]})")
for line in bad:
    print("MODERATION NOT APPROVED", line)
sys.exit(1 if bad else 0)
