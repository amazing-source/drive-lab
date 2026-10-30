"""
Downloads Sketchfab models by uid into their own folders and records who made them, so the
game can credit every author. The token comes from SKETCHFAB_API_TOKEN, in the process
environment or the Windows user environment, and is never printed. GLB is preferred; the
glTF zip is the fallback and is extracted into the same folder.

    python -I tools/assets/sketchfab_download.py <out dir> <label>=<uid> [<label>=<uid> ...]

Each folder gets the model and a credit.json; the run prints one line per model.
"""

import json
import os
import sys
import urllib.request
import zipfile
from pathlib import Path

API = "https://api.sketchfab.com/v3/models"


def token() -> str:
    value = os.environ.get("SKETCHFAB_API_TOKEN")
    if not value and sys.platform == "win32":
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as environment:
            value, _ = winreg.QueryValueEx(environment, "SKETCHFAB_API_TOKEN")
    if not value:
        raise SystemExit("SKETCHFAB_API_TOKEN is not set")
    return value


def get_json(url: str, headers: dict) -> dict:
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0", **headers})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def fetch(url: str, path: Path):
    request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(request, timeout=300) as response, open(path, "wb") as file:
        while chunk := response.read(1 << 20):
            file.write(chunk)


def download(out: Path, label: str, uid: str, auth: dict) -> str:
    folder = out / label
    folder.mkdir(parents=True, exist_ok=True)
    info = get_json(f"{API}/{uid}", {})
    links = get_json(f"{API}/{uid}/download", auth)
    if "glb" in links:
        fetch(links["glb"]["url"], folder / "model.glb")
        model = "model.glb"
    else:
        archive = folder / "model.zip"
        fetch(links["gltf"]["url"], archive)
        with zipfile.ZipFile(archive) as bundle:
            bundle.extractall(folder / "gltf")
        archive.unlink()
        model = str(next((folder / "gltf").rglob("*.gltf")).relative_to(folder))
    credit = {
        "name": info["name"],
        "author": info["user"]["displayName"] or info["user"]["username"],
        "username": info["user"]["username"],
        "license": info["license"]["label"] if info.get("license") else "unknown",
        "url": info["viewerUrl"],
        "model": model,
    }
    (folder / "credit.json").write_text(json.dumps(credit, indent=1))
    return f"{label}: {credit['name']} by {credit['author']} ({credit['license']}) -> {model}"


def main():
    # A redirected stdout on Windows is cp1252; an author's name in another script would crash the
    # print after the model is already written.
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    out = Path(sys.argv[1])
    auth = {"Authorization": f"Token {token()}"}
    for pair in sys.argv[2:]:
        label, uid = pair.split("=", 1)
        try:
            print(download(out, label, uid, auth))
        except Exception as error:
            print(f"{label}: failed: {error}")


if __name__ == "__main__":
    main()
