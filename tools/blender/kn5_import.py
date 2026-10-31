"""Import an Assetto Corsa .kn5 model into Blender: node tree, meshes, materials and embedded textures.

blender -b --factory-startup --python-exit-code 1 -P tools/blender/kn5_import.py -- <model.kn5> --out <out.blend>
        --textures <dir> [--report <report.json>] [--ksanim <file.ksanim> ...] [--frame last|first|<n>]
        [--knh <file.knh>] [--skin <skin dir>] [--shared-textures <dir>] [--break stride|winding|mirror]

Written from the public format (the gro-ove/actools KN5, KsAnim and KNH readers); no converter is run.
- KN5: "sc6969", version (int32), an extra int32 when version > 5; textures (active int32, name, uint32 length,
  the embedded DDS or PNG bytes); materials (name, shader, blend byte, alpha-tested byte, depth int32,
  properties: name + float + vec2 + vec3 + vec4, texture slots: name + int32 slot + texture name); then the node
  tree. Node: class int32 (1 transform, 2 mesh, 3 skinned), name, child count, active byte; a transform has a
  row-major 4x4 matrix (translation in the last row); a mesh has 3 flag bytes, 44-byte vertices (position,
  normal, uv, tangent), uint16 indices, material and layer (uint32), LOD in and out, bounding sphere, renderable;
  a skinned mesh has bones (name + matrix), 76-byte vertices (+ weights + bone indices) and 8 trailing bytes.
  Strings are an int32 length and ASCII bytes. Mesh vertices are in their parent node's space.
- Axes: the model's wheel nodes put the car facing +Z with +X on its LEFT and Y up (WHEEL_LF at +X, +Z), a
  right-handed frame. Blender here uses the team's car frame: Z up, nose toward -Y, +X the car's left, so
  (x, y, z) -> (x, -z, y), a rotation: windings are kept. UV v is flipped (DirectX top-left origin).
- Textures are written to --textures (never into the repo) and loaded from there; the report gives each one's
  container format, pixel format and size. --skin <dir> takes a skin folder's textures in place of the embedded
  ones of the same name. Materials approximate AC's shaders in a Principled BSDF (see the comment where they are
  built); every AC shader property and slot is kept as custom properties on the material.
- An LOD file embeds no textures (it uses the main file's): pass --shared-textures <dir> (the main file's
  extracted textures) and its slots resolve there; without it they fail the slot check.
- --ksanim applies an animation's keyframe (default the last) to the nodes it names, e.g. a door opened.
- --knh reads a node hierarchy (the driver's pose) and reports each node's position in the car frame.

Checks (exit 1): the parse ends exactly at the end of the file; every index is below its mesh's vertex count;
every material id and texture slot resolves; the triangles built in Blender equal the file's; each face's winding
agrees with its stored normals on >= 90 % of the area; with AC wheel nodes (WHEEL_LF ...), the front-left wheel
lands on the car's left and in front. `--break stride` reads 40-byte vertices, `--break winding` reverses every
face, `--break mirror` mirrors the car left to right (a reflection, faces reversed to match).
"""
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

args = sys.argv[sys.argv.index("--") + 1:]


def opt(name, default=None):
    return args[args.index(name) + 1] if name in args else default


def opts(name):
    return [args[i + 1] for i, a in enumerate(args) if a == name]


SRC = Path(args[0])
OUT, TEX, REPORT, KNH = opt("--out"), Path(opt("--textures")), opt("--report"), opt("--knh")
FRAME, BREAK = opt("--frame", "last"), opt("--break")
problems = []
report = {"file": SRC.name, "problems": problems}
C3 = Matrix(((-1, 0, 0), (0, 0, -1), (0, 1, 0))) if BREAK == "mirror" else Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))
C4 = C3.to_4x4()
C4I = C4.inverted()
CN = np.array(C3)
VSTRIDE = 10 if BREAK == "stride" else 11


class Reader:
    def __init__(self, data):
        self.d, self.p = data, 0

    def take(self, n):
        if self.p + n > len(self.d):
            raise ValueError(f"read past the end at byte {self.p} (+{n})")
        b = self.d[self.p:self.p + n]
        self.p += n
        return b

    def i32(self):
        return struct.unpack("<i", self.take(4))[0]

    def u32(self):
        return struct.unpack("<I", self.take(4))[0]

    def f32(self, n=1):
        v = struct.unpack(f"<{n}f", self.take(4 * n))
        return v[0] if n == 1 else v

    def u8(self):
        return self.take(1)[0]

    def s(self):
        n = self.i32()
        if n < 0 or n > 4096:
            raise ValueError(f"string length {n} at byte {self.p - 4}")
        return self.take(n).decode("ascii", "replace")

    def mat(self):
        m = struct.unpack("<16f", self.take(64))
        return Matrix([m[0:4], m[4:8], m[8:12], m[12:16]])

    def arr(self, dtype, count):
        nbytes = np.dtype(dtype).itemsize * count
        a = np.frombuffer(self.d, dtype=dtype, count=count, offset=self.p).copy()
        self.take(nbytes)
        return a


def ac_to_blender(m_row):
    """An AC row-major matrix (row vectors) as a Blender column-major matrix in the team's car frame."""
    return C4 @ m_row.transposed() @ C4I


def dds_info(b):
    if b[:4] != b"DDS ":
        if b[:8] == b"\x89PNG\r\n\x1a\n":
            w, h = struct.unpack(">II", b[16:24])
            return {"container": "png", "width": w, "height": h}
        return {"container": "unknown"}
    h, w = struct.unpack("<II", b[12:20])
    mips = struct.unpack("<I", b[28:32])[0]
    four = b[84:88]
    fmt = four.decode("ascii", "replace").strip("\x00") if four != b"\x00\x00\x00\x00" else "uncompressed"
    if four == b"DX10":
        fmt = f"DXGI {struct.unpack('<I', b[128:132])[0]}"
    return {"container": "dds", "width": w, "height": h, "mips": mips, "format": fmt}


# ------------------------------------------------------------------------------------------------- parse
data = SRC.read_bytes()
r = Reader(data)
textures, materials, nodes = [], [], []
try:
    if r.take(6) != b"sc6969":
        raise ValueError("not a KN5 file (magic)")
    version = r.i32()
    extra = r.i32() if version > 5 else 0
    report["version"], report["extra"] = version, extra
    for _ in range(r.i32()):
        active = r.i32()
        name = r.s()
        blob = r.take(r.u32())
        textures.append({"name": name, "active": active == 1, "bytes": len(blob), "blob": blob, **dds_info(blob)})
    for _ in range(r.i32()):
        m = {"name": r.s(), "shader": r.s(), "blend": r.u8(), "alpha_tested": bool(r.u8()), "depth": r.i32()}
        m["properties"] = {}
        for _ in range(r.i32()):
            pn = r.s()
            a = r.f32()
            b2, c3, d4 = r.f32(2), r.f32(3), r.f32(4)
            m["properties"][pn] = {"a": a, "b": list(b2), "c": list(c3), "d": list(d4)}
        m["slots"] = {}
        for _ in range(r.i32()):
            sn = r.s()
            slot = r.i32()
            m["slots"][sn] = {"slot": slot, "texture": r.s()}
        materials.append(m)

    def read_node(parent):
        cls = r.i32()
        name = r.s()
        nchild = r.i32()
        active = bool(r.u8())
        n = {"cls": cls, "name": name, "parent": parent, "active": active, "index": len(nodes)}
        nodes.append(n)
        if cls == 1:
            n["matrix"] = r.mat()
        elif cls in (2, 3):
            n["cast_shadows"], n["visible"], n["transparent"] = bool(r.u8()), bool(r.u8()), bool(r.u8())
            if cls == 3:
                n["bones"] = [(r.s(), r.mat()) for _ in range(r.i32())]
            nv = r.u32()
            stride = VSTRIDE if cls == 2 else 19
            v = r.arr("<f4", nv * stride).reshape(nv, stride)
            n["pos"], n["nrm"], n["uv"] = v[:, 0:3], v[:, 3:6], v[:, 6:8]
            ni = r.u32()
            n["idx"] = r.arr("<u2", ni).astype(np.int64)
            n["material"] = r.u32()
            n["layer"] = r.u32()
            if cls == 2:
                n["lod_in"], n["lod_out"] = r.f32(), r.f32()
                n["sphere"] = (r.f32(3), r.f32())
                n["renderable"] = bool(r.u8())
            else:
                r.take(8)
        else:
            raise ValueError(f"unknown node class {cls} at node {name!r}")
        n["children"] = [read_node(n["index"]) for _ in range(nchild)]
        return n["index"]

    read_node(None)
    if r.p != len(data):
        problems.append(f"parse ended at byte {r.p} of {len(data)}")
except (ValueError, struct.error, IndexError) as e:
    problems.append(f"parse failed: {e} (byte {r.p} of {len(data)})")

def finish():
    if REPORT:
        Path(REPORT).write_text(json.dumps(report, indent=1, default=str))
    print("KN5", SRC.name, "PASS" if not problems else "FAIL", *problems[:20], sep="\n  ")
    sys.exit(1 if problems else 0)


if any(p.startswith("parse") for p in problems):
    finish()


SHARED = Path(opt("--shared-textures")) if opt("--shared-textures") else None
shared_names = {f.name for f in SHARED.iterdir()} if SHARED and SHARED.is_dir() else set()
tex_names = {t["name"] for t in textures} | shared_names
for n in nodes:
    if n["cls"] in (2, 3):
        if len(n["idx"]) and n["idx"].max() >= len(n["pos"]):
            problems.append(f"{n['name']}: index {n['idx'].max()} >= {len(n['pos'])} vertices")
        if len(n["idx"]) % 3:
            problems.append(f"{n['name']}: {len(n['idx'])} indices, not whole triangles")
        if n["material"] >= len(materials):
            problems.append(f"{n['name']}: material {n['material']} of {len(materials)}")
for m in materials:
    for sn, s in m["slots"].items():
        if s["texture"] not in tex_names:
            problems.append(f"material {m['name']}: slot {sn} names missing texture {s['texture']}")
file_tris = sum(len(n["idx"]) // 3 for n in nodes if n["cls"] in (2, 3))
report.update({"textures_n": len(textures), "materials_n": len(materials), "nodes_n": len(nodes),
               "meshes_n": sum(1 for n in nodes if n["cls"] in (2, 3)), "file_triangles": file_tris})


# ------------------------------------------------------------------------------------------------- build
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
TEX.mkdir(parents=True, exist_ok=True)
images = {}
SKIN = Path(opt("--skin")) if opt("--skin") else None
for t in textures:
    path = TEX / Path(t["name"]).name
    skin_file = SKIN / Path(t["name"]).name if SKIN else None
    if skin_file is not None and skin_file.exists():
        t["skin"] = SKIN.name
        t.update({k: v for k, v in dds_info(skin_file.read_bytes()).items()})
        path = TEX / f"{SKIN.name}__{skin_file.name}"
        path.write_bytes(skin_file.read_bytes())
    else:
        path.write_bytes(t["blob"])
    img = None
    try:
        img = bpy.data.images.load(str(path), check_existing=True)
        t["loaded"] = bool(img.size[0])
    except RuntimeError as e:
        t["loaded"] = False
        t["load_error"] = str(e)
    images[t["name"]] = img
    t["file"] = path.name
    del t["blob"]
for nm in sorted(shared_names - {t["name"] for t in textures}):
    try:
        images[nm] = bpy.data.images.load(str(SHARED / nm), check_existing=True)
    except RuntimeError:
        images[nm] = None
report["textures"] = textures
report["shared_textures_used"] = sorted(shared_names & {s["texture"] for m in materials for s in m["slots"].values()})
report["textures_not_loaded"] = [t["name"] for t in textures if not t.get("loaded")]

def prop(m, name, default=0.0):
    p = m["properties"].get(name)
    return p["a"] if p else default


def tex_node(nt, name, colour=True):
    img = images.get(name)
    if img is None:
        return None
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = img
    if not colour:
        img.colorspace_settings.name = "Non-Color"
    return n


bmats = []
for m in materials:
    # An approximation of AC's shaders in a Principled BSDF (the original values stay in custom properties):
    # base = txDiffuse x txDetail (tiled by detailUVMultiplier when useDetail) x ksDiffuse / 0.5 (at most 1);
    # roughness from txMaps' green (gloss) and ksSpecularEXP, or ksSpecular x ksSpecularEXP without maps;
    # metallic where fresnelC and fresnelMaxLevel are both high (mirror-like); a clear coat on car paint;
    # txNormal as a tangent-space normal map, except on damage shaders.
    bm = bpy.data.materials.new(m["name"])
    bm.use_nodes = True
    nt = bm.node_tree
    bsdf = next(x for x in nt.nodes if x.type == "BSDF_PRINCIPLED")
    bm["kn5_shader"], bm["kn5_blend"], bm["kn5_alpha_tested"] = m["shader"], m["blend"], m["alpha_tested"]
    bm["kn5_properties"] = json.dumps(m["properties"])
    bm["kn5_slots"] = json.dumps(m["slots"])
    sl = {k: v["texture"] for k, v in m["slots"].items()}
    kd = min(1.0, max(0.05, prop(m, "ksDiffuse", 0.5) / 0.5))
    dif = tex_node(nt, sl["txDiffuse"]) if "txDiffuse" in sl else None
    colour = dif.outputs["Color"] if dif else None
    if dif and "txDetail" in sl and prop(m, "useDetail") > 0:
        det = tex_node(nt, sl["txDetail"])
        mult = prop(m, "detailUVMultiplier", 1.0) or 1.0
        if det:
            uvn = nt.nodes.new("ShaderNodeTexCoord")
            mp = nt.nodes.new("ShaderNodeMapping")
            mp.inputs["Scale"].default_value = (mult, mult, 1.0)
            nt.links.new(uvn.outputs["UV"], mp.inputs["Vector"])
            nt.links.new(mp.outputs["Vector"], det.inputs["Vector"])
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type, mix.blend_type = "RGBA", "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(colour, mix.inputs["A"])
            nt.links.new(det.outputs["Color"], mix.inputs["B"])
            colour = mix.outputs["Result"]
    if colour is not None:
        gain = nt.nodes.new("ShaderNodeMix")
        gain.data_type, gain.blend_type = "RGBA", "MULTIPLY"
        gain.inputs["Factor"].default_value = 1.0
        gain.inputs["B"].default_value = (kd, kd, kd, 1.0)
        nt.links.new(colour, gain.inputs["A"])
        nt.links.new(gain.outputs["Result"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = (kd * 0.5, kd * 0.5, kd * 0.5, 1)
    if dif and (m["blend"] != 0 or m["alpha_tested"] or prop(m, "ksAlphaRef") > 0):
        nt.links.new(dif.outputs["Alpha"], bsdf.inputs["Alpha"])
    exp_ = min(1.0, prop(m, "ksSpecularEXP", 10.0) / 60.0)
    maps = tex_node(nt, sl["txMaps"], colour=False) if "txMaps" in sl else None
    if maps:
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(maps.outputs["Color"], sep.inputs["Color"])
        rough = nt.nodes.new("ShaderNodeMath")
        rough.operation, rough.use_clamp = "MULTIPLY_ADD", True
        rough.inputs[1].default_value = -exp_
        rough.inputs[2].default_value = 1.0
        nt.links.new(sep.outputs["Green"], rough.inputs[0])
        nt.links.new(rough.outputs["Value"], bsdf.inputs["Roughness"])
    else:
        bsdf.inputs["Roughness"].default_value = max(0.05, min(0.95, 1.0 - exp_ * min(1.0, prop(m, "ksSpecular", 0.3))))
    if prop(m, "fresnelC") >= 0.7 and prop(m, "fresnelMaxLevel") >= 0.9:
        bsdf.inputs["Metallic"].default_value = 1.0
    if "paint" in m["name"].lower() or "damage" in m["shader"].lower():
        bsdf.inputs["Coat Weight"].default_value = 1.0
        bsdf.inputs["Coat Roughness"].default_value = 0.03
    # AC's damage shaders keep the dent map in txNormal and blend it in by damage: at rest it is not there.
    use_nrm = "txNormal" in sl and prop(m, "nmObjectSpace") == 0 and "damage" not in m["shader"].lower()
    nrm = tex_node(nt, sl["txNormal"], colour=False) if use_nrm else None
    if nrm:
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nt.links.new(nrm.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    bmats.append(bm)

col = bpy.data.collections.new(SRC.stem)
bpy.context.scene.collection.children.link(col)
objs = {}
agree_area = total_area = 0.0
built_tris = 0
for n in nodes:
    parent = objs.get(n["parent"])
    if n["cls"] == 1:
        o = bpy.data.objects.new(n["name"][:63], None)
        o.empty_display_size = 0.05
        col.objects.link(o)
        o.parent = parent
        o.matrix_parent_inverse = Matrix.Identity(4)
        o.matrix_basis = ac_to_blender(n["matrix"])
    else:
        P = n["pos"] @ CN.T
        N = n["nrm"] @ CN.T
        tri = n["idx"].reshape(-1, 3)
        if BREAK in ("winding", "mirror"):  # a reflection (or a deliberate break) reverses each face
            tri = tri[:, [0, 2, 1]]
        me = bpy.data.meshes.new(n["name"][:63])
        me.vertices.add(len(P))
        me.vertices.foreach_set("co", P.astype(np.float32).ravel())
        me.loops.add(tri.size)
        me.loops.foreach_set("vertex_index", tri.ravel().astype(np.int32))
        me.polygons.add(len(tri))
        me.polygons.foreach_set("loop_start", np.arange(0, tri.size, 3, dtype=np.int32))
        uv = me.uv_layers.new(name="UVMap")
        U = n["uv"].copy()
        U[:, 1] = 1.0 - U[:, 1]
        uv.data.foreach_set("uv", U[tri.ravel()].astype(np.float32).ravel())
        me.update()
        me.polygons.foreach_set("use_smooth", np.ones(len(tri), dtype=bool))
        me.normals_split_custom_set_from_vertices([tuple(x) for x in N])
        me.materials.append(bmats[n["material"]] if n["material"] < len(bmats) else None)
        o = bpy.data.objects.new(n["name"][:63], me)
        col.objects.link(o)
        o.parent = parent
        o.matrix_parent_inverse = Matrix.Identity(4)
        o["kn5_layer"], o["kn5_material"] = n["layer"], materials[n["material"]]["name"]
        o.hide_render = o.hide_viewport = not (n["active"] and n.get("visible", True))
        built_tris += len(me.polygons)
        if len(tri):
            a, b, c = P[tri[:, 0]], P[tri[:, 1]], P[tri[:, 2]]
            fn = np.cross(b - a, c - a)
            area = np.linalg.norm(fn, axis=1)
            vn = N[tri[:, 0]] + N[tri[:, 1]] + N[tri[:, 2]]
            agree_area += float(area[(fn * vn).sum(1) > 0].sum())
            total_area += float(area.sum())
    o["kn5_name"], o["kn5_class"] = n["name"], n["cls"]
    if not n["active"]:
        o.hide_render = o.hide_viewport = True
    objs[n["index"]] = o
bpy.context.view_layer.update()

if built_tris != file_tris:
    problems.append(f"built {built_tris} triangles, the file holds {file_tris}")
agree = agree_area / total_area if total_area else 1.0
report["winding_agreement"] = agree
if agree < 0.9:
    problems.append(f"winding agrees with the stored normals on {100 * agree:.1f} % of the area (wants >= 90 %)")


def find(name):
    return next((o for o in objs.values() if o["kn5_name"] == name), None)


wheels = {k: find(f"WHEEL_{k}") for k in ("LF", "RF", "LR", "RR")}
if all(wheels.values()):
    wp = {k: list(o.matrix_world.translation) for k, o in wheels.items()}
    report["wheels"] = wp
    report["wheelbase_m"] = (abs(wp["LF"][1] - wp["LR"][1]) + abs(wp["RF"][1] - wp["RR"][1])) / 2
    report["track_front_m"] = abs(wp["LF"][0] - wp["RF"][0])
    report["track_rear_m"] = abs(wp["LR"][0] - wp["RR"][0])
    if not (wp["LF"][0] > 0 and wp["LF"][1] < wp["LR"][1]):
        problems.append(f"WHEEL_LF at {[round(x, 3) for x in wp['LF']]}: not front-left (x > 0, ahead of WHEEL_LR)")
else:
    report["wheels"] = "no AC wheel nodes: orientation check skipped"

# ksanim: pose the named nodes at a keyframe
for path in opts("--ksanim"):
    rr = Reader(Path(path).read_bytes())
    ver = rr.i32()
    posed = {}
    for _ in range(rr.i32()):
        nn = rr.s()
        frames = []
        for _ in range(rr.i32()):
            if ver == 2:
                q = rr.f32(4)
                tr, sc = rr.f32(3), rr.f32(3)
                m_col = (Matrix.Translation(Vector(tr)) @ Quaternion((q[3], q[0], q[1], q[2])).to_matrix().to_4x4()
                         @ Matrix.Diagonal((*sc, 1.0)))
                frames.append(m_col)
            else:
                frames.append(rr.mat().transposed())
        if not frames:
            continue
        k = {"last": len(frames) - 1, "first": 0}.get(FRAME)
        k = int(FRAME) if k is None else min(int(k), len(frames) - 1)
        o = find(nn)
        if o is not None:
            o.matrix_basis = C4 @ frames[k] @ C4I
            posed[nn] = {"frame": k, "frames": len(frames)}
    report.setdefault("ksanim", {})[Path(path).name] = {"version": ver, "posed": posed}
bpy.context.view_layer.update()

# knh: the driver's node positions in the car frame
if KNH:
    kr = Reader(Path(KNH).read_bytes())
    out = {}

    def walk(parent_col):
        name = kr.s()
        m_col = parent_col @ kr.mat().transposed()
        p = C4 @ m_col @ C4I
        out[name] = [round(x, 4) for x in p.translation]
        for _ in range(kr.i32()):
            walk(m_col)

    walk(Matrix.Identity(4))
    report["knh"] = out

# report: nodes and bounds
pts, rows = [], []
for o in objs.values():
    row = {"name": o["kn5_name"], "class": o["kn5_class"], "parent": o.parent["kn5_name"] if o.parent else None,
           "shown": not o.hide_render}
    if o.type == "MESH":
        row["tris"] = len(o.data.polygons)
        row["material"] = o["kn5_material"]
        if not o.hide_render and len(o.data.vertices):
            co = np.empty(len(o.data.vertices) * 3, dtype=np.float32)
            o.data.vertices.foreach_get("co", co)
            mw = np.array(o.matrix_world)
            vw = co.reshape(-1, 3) @ mw[:3, :3].T + mw[:3, 3]
            row["bounds"] = [vw.min(0).round(4).tolist(), vw.max(0).round(4).tolist()]
            pts += row["bounds"]
    rows.append(row)
if pts:
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    report["bounds_shown"] = {"min": lo, "max": hi, "size_m": [hi[i] - lo[i] for i in range(3)]}
report["nodes"] = rows
report["materials"] = [{k: v for k, v in m.items() if k != "properties"} | {"properties": list(m["properties"])} for m in materials]
report["built_triangles"] = built_tris
if OUT:
    bpy.ops.wm.save_as_mainfile(filepath=OUT, compress=True)
print("KN5 version", report.get("version"), "textures", len(textures), "materials", len(materials), "nodes", len(nodes),
      "meshes", report["meshes_n"], "triangles", file_tris, "winding agreement %.3f" % agree)
if isinstance(report["wheels"], dict):
    print("KN5 wheelbase %.3f m, track %.3f / %.3f m" % (report["wheelbase_m"], report["track_front_m"], report["track_rear_m"]))
if "bounds_shown" in report:
    print("KN5 size (x, y, z) m", [round(x, 3) for x in report["bounds_shown"]["size_m"]])
finish()
