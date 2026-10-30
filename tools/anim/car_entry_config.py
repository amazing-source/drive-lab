"""
Prints the clips, seatedPose and mark fields of a car's door
(games/drive-lab/src/shared/Config/Cars/<Car>/Door.luau) from an export (clips.json, car_entry_export.py) and the uploaded ids, formatted as stylua writes
them, to paste over the old fields (the file's other fields are not this tool's).

  python car_entry_config.py <clips.json> <ids.json> --mark -0.88,0
"""
import argparse
import json
import sys

ORDER = ["OutsideOpen", "GetIn", "InsideClose", "InsideOpen", "GetOut", "OutsideClose"]


def number(v):
    text = f"{v:.3f}".rstrip("0").rstrip(".")
    return text if text not in ("-0", "") else "0"


def main(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("clips")
    parser.add_argument("ids")
    parser.add_argument("--mark", required=True)
    args = parser.parse_args(argv)
    clips = json.load(open(args.clips, encoding="utf-8"))
    ids = json.load(open(args.ids, encoding="utf-8"))
    right, forward = (float(v) for v in args.mark.split(","))
    out = ["\tclips = table.freeze({"]
    for name in ORDER:
        clip, asset = clips[name], ids[name]
        out.append(f"\t\t{name} = table.freeze({{")
        out.append(f'\t\t\tseated = "{asset["seated"]}",')
        if "standing" in asset:
            out.append(f'\t\t\tstanding = "{asset["standing"]}",')
        out.append(f"\t\t\tduration = {number(clip['duration'])},")
        door = clip.get("door")
        if door:
            times = ", ".join(number(t) for t in door["times"])
            values = ", ".join(number(v) for v in door["values"])
            out.append("\t\t\tdoor = table.freeze({")
            out.append(f"\t\t\t\ttimes = {{ {times} }},")
            out.append(f"\t\t\t\tvalues = {{ {values} }},")
            out.append("\t\t\t}),")
        out.append("\t\t}),")
    out.append("\t}),")
    out.append(f'\tseatedPose = "{ids["SeatedPose"]["seated"]}",')
    out.append(f"\tmark = table.freeze({{ right = {number(right)}, forward = {number(forward)} }}),")
    print("\n".join(out))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
