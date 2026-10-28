"""
Uploads files to Roblox through the Open Cloud Assets API and prints a JSON map of label to
asset id: PNGs as Decals, .glb/.gltf/.fbx/.obj files as Models, which Roblox imports into
MeshParts, .rbxm KeyframeSequences as Animations, and .ogg/.wav/.mp3 files as Audio (private
to the creator: it plays only in that creator's experiences). A file named car.* is labelled by its folder. The key comes from
ROBLOX_OPEN_CLOUD_API_KEY, in the process environment or the Windows user environment, and
is never printed. A decal id is not an image id: resolve the image ids afterwards
(InsertService:LoadAsset on the decal).

    python -I tools/assets/upload_images.py <user id> <file> [<file> ...]
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://apis.roblox.com/assets/v1"
POLL_SECONDS = 2
POLL_LIMIT = 90

KINDS = {
    ".png": ("Decal", "image/png"),
    ".glb": ("Model", "model/gltf-binary"),
    ".gltf": ("Model", "model/gltf+json"),
    ".fbx": ("Model", "model/fbx"),
    ".obj": ("Model", "model/obj"),
    # A KeyframeSequence saved as a model file (tools/anim/build_keyframes.luau).
    ".rbxm": ("Animation", "model/x-rbxm"),
    # Audio: under 20 MB and 7 minutes; 100 uploads a month for an ID-verified creator, 10 if not.
    ".ogg": ("Audio", "audio/ogg"),
    ".wav": ("Audio", "audio/wav"),
    ".mp3": ("Audio", "audio/mpeg"),
}


def api_key() -> str:
    key = os.environ.get("ROBLOX_OPEN_CLOUD_API_KEY")
    if not key and sys.platform == "win32":
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as environment:
            key, _ = winreg.QueryValueEx(environment, "ROBLOX_OPEN_CLOUD_API_KEY")
    if not key:
        raise SystemExit("ROBLOX_OPEN_CLOUD_API_KEY is not set")
    return key


def label_of(path: Path) -> str:
    return path.parent.name if path.stem == "car" else path.stem


def multipart(fields: dict, file_name: str, data: bytes, file_type: str) -> tuple:
    boundary = uuid.uuid4().hex
    parts = []
    for name, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    header = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="fileContent"; filename="{file_name}"\r\n'
        f"Content-Type: {file_type}\r\n\r\n"
    )
    parts.append(header.encode() + data + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def call(request: urllib.request.Request) -> dict:
    with urllib.request.urlopen(request, timeout=120) as response:
        return json.load(response)


def upload(key: str, user_id: str, path: Path) -> str:
    asset_type, file_type = KINDS[path.suffix.lower()]
    request_body = json.dumps(
        {
            "assetType": asset_type,
            "displayName": label_of(path),
            "description": "Steal Cars asset",
            "creationContext": {"creator": {"userId": user_id}},
        }
    )
    body, content_type = multipart({"request": request_body}, path.name, path.read_bytes(), file_type)
    started = call(
        urllib.request.Request(
            f"{API}/assets", data=body, method="POST", headers={"x-api-key": key, "Content-Type": content_type}
        )
    )
    operation = started.get("operationId") or started["path"].split("/")[-1]
    for _ in range(POLL_LIMIT):
        time.sleep(POLL_SECONDS)
        status = call(urllib.request.Request(f"{API}/operations/{operation}", headers={"x-api-key": key}))
        if status.get("done"):
            response = status.get("response")
            if response is None:
                raise RuntimeError(json.dumps(status.get("error", status))[:400])
            return response["assetId"]
    raise RuntimeError(f"{path.name}: upload did not finish")


def main():
    key = api_key()
    user_id = sys.argv[1]
    result = {}
    for name in sys.argv[2:]:
        path = Path(name)
        label = label_of(path)
        try:
            result[label] = upload(key, user_id, path)
        except urllib.error.HTTPError as error:
            result[label] = f"failed: {error.code} {error.read().decode(errors='replace')[:300]}"
        except (RuntimeError, KeyError) as error:
            result[label] = f"failed: {error}"
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
