"""
Builds and uploads the car-entry clips of one or more exported timelines, and REFUSES to unless
the contact check passed on that exact timeline.

  python -I tools/anim/car_entry_upload.py <creator id> <export_dir>=<check.json> [...]
      --ids <ids.json> [--override "<the owner's decision, with a link>"] [--dry-run]

For every timeline it requires, before anything is built or uploaded:
  - a check record (car_entry_check.py --json) that passed, over every frame, unmutated;
  - the check's baked timeline and scene to be the ones this export was cut from (SHA-256 in the
    export's source.json, written by car_entry_export.py);
  - every file of the export to be unchanged since the export.
Any miss refuses the whole run with the reasons, and nothing is uploaded. The only way past is
--override naming the owner's decision; it is appended to <export_dir>/upload_overrides.log and
printed, with the reasons it overrode.

Then each clip is built with tools/anim/build_keyframes (seated variants at Action priority, the
standing ones with the neck left to HeadLook, SeatedPose looped) and uploaded through
tools/assets/upload_images.py, which reads the Open Cloud key from the Windows user environment
(the inherited process variable is dropped, as the pipeline doc says) and never prints it. The
ids are merged into --ids, with the hash of the timeline each came from.
"""
import argparse
import datetime
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from car_entry_check import file_sha256  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PREFIX = "DriveLabEntry"


def refusals(export_dir, check_path):
    """Why this timeline may not be uploaded (empty when it may)."""
    reasons = []
    source_path = os.path.join(export_dir, "source.json")
    if not os.path.exists(source_path):
        return [f"{export_dir}: no source.json (export it with car_entry_export.py)"]
    if not os.path.exists(check_path):
        return [f"{check_path}: no contact check record (run car_entry_check.py --json)"]
    source = json.load(open(source_path, encoding="utf-8"))
    check = json.load(open(check_path, encoding="utf-8"))
    if "baked_sha256" not in check:
        return [f"{check_path}: the record does not say what it checked (an older check?)"]
    if not check.get("passed") or check.get("failures"):
        reasons.append(f"the contact check FAILED: {len(check.get('failures', []))} failures")
    if check.get("range") is not None:
        reasons.append(f"the check covered only frames {check['range']}, not the whole timeline")
    if check.get("mutate"):
        reasons.append(f"the check ran on a deliberately broken copy ({check['mutate']})")
    if check["baked_sha256"] != source["baked_sha256"]:
        reasons.append("the check ran on a different bake from the one this export was cut from")
    if check.get("scene_sha256") != source["scene_sha256"]:
        reasons.append("the check ran against a different scene from the export's")
    for name, digest in source["files"].items():
        path = os.path.join(export_dir, name)
        if not os.path.exists(path):
            reasons.append(f"{name} is missing from the export")
        elif file_sha256(path) != digest:
            reasons.append(f"{name} changed after the export")
    return reasons


def build(export_dir, clip, standing, out_dir):
    """Builds the clip's .rbxm files; returns [(variant, path)]."""
    built = []
    variants = [("seated", f"{clip}.seated.json", f"{PREFIX}{clip}")]
    if standing:
        variants.append(("standing", f"{clip}.standing.json", f"{PREFIX}{clip}Standing"))
    for variant, source, name in variants:
        out = os.path.join(out_dir, f"{name}.rbxm")
        command = ["lune", "run", "tools/anim/build_keyframes", os.path.join(export_dir, source), out, name]
        command += ["--priority", "Action"]
        if variant == "standing":
            command += ["--rest", "Neck"]
        if clip == "SeatedPose":
            command += ["--loop"]
        subprocess.run(command, cwd=REPO, check=True, capture_output=True, text=True)
        built.append((variant, out))
    return built


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("creator")
    parser.add_argument("timelines", nargs="+", help="<export_dir>=<check.json>")
    parser.add_argument("--ids", required=True)
    parser.add_argument("--override", help="the owner's decision that allows uploading over a refusal")
    parser.add_argument("--dry-run", action="store_true", help="check and build, upload nothing")
    args = parser.parse_args(argv)

    pairs = [tuple(t.split("=", 1)) for t in args.timelines]
    refused = {export_dir: refusals(export_dir, check) for export_dir, check in pairs}
    blocked = {k: v for k, v in refused.items() if v}
    for export_dir, reasons in blocked.items():
        print(f"REFUSED {export_dir}:")
        for reason in reasons:
            print(f"  - {reason}")
    if blocked and not args.override:
        print("Nothing uploaded. Fix the timeline and re-run the check, or pass --override with the owner's decision.")
        return 2
    if blocked:
        stamp = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        for export_dir, reasons in blocked.items():
            line = json.dumps({"at": stamp, "override": args.override, "reasons": reasons})
            with open(os.path.join(export_dir, "upload_overrides.log"), "a", encoding="utf-8", newline="\n") as h:
                h.write(line + "\n")
            print(f"OVERRIDDEN {export_dir}: {args.override}")

    ids = json.load(open(args.ids, encoding="utf-8")) if os.path.exists(args.ids) else {}
    for export_dir, _ in pairs:
        source = json.load(open(os.path.join(export_dir, "source.json"), encoding="utf-8"))
        out_dir = os.path.join(export_dir, "rbxm")
        os.makedirs(out_dir, exist_ok=True)
        files = []
        for clip in source["clips"]:
            for variant, path in build(export_dir, clip, clip in source["standing"], out_dir):
                files.append((clip, variant, path))
        print(f"built {len(files)} clips from {export_dir} (bake {source['baked_sha256'][:12]})")
        if args.dry_run:
            continue
        env = {k: v for k, v in os.environ.items() if k != "ROBLOX_OPEN_CLOUD_API_KEY"}
        uploader = os.path.join(REPO, "tools", "assets", "upload_images.py")
        done = subprocess.run(
            [sys.executable, "-I", uploader, args.creator] + [p for _, _, p in files],
            env=env, check=True, capture_output=True, text=True,
        )
        result = json.loads(done.stdout)
        for clip, variant, path in files:
            label = os.path.splitext(os.path.basename(path))[0]
            asset = result.get(label, "missing")
            if not str(asset).isdigit():
                raise SystemExit(f"{label}: upload {asset}")
            ids.setdefault(clip, {})[variant] = f"rbxassetid://{asset}"
            ids.setdefault("_source", {})[clip] = source["baked_sha256"]
            print(f"  {clip} {variant}: rbxassetid://{asset}")
        with open(args.ids, "w", encoding="utf-8", newline="\n") as h:
            json.dump(ids, h, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
