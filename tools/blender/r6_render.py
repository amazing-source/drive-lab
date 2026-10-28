"""
Review renders for an R6 animation built by r6_rig.py: a baseplate-style floor that scrolls
backwards at the travel speed (so a planted foot that slides is visible), a sky like the
reference clip, and three cameras: side, game (Roblox's default third-person framing) and ref
(low front three-quarter, matching the reference clip).

  blender -b <anim.blend> -P r6_render.py -- <out_dir> --speed 22 --loops 3 --stretch 1 --cams side,game,ref --res 540

--stretch 4 renders the same motion four times slower with in-between frames, for a smooth
quarter-speed review.
"""
import argparse
import math
import os
import sys

import bpy
from mathutils import Vector


def parse(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("out_dir")
    parser.add_argument("--speed", type=float, default=0.0, help="travel speed, studs per second")
    parser.add_argument("--loops", type=int, default=3, help="animation cycles to render")
    parser.add_argument("--stretch", type=int, default=1)
    parser.add_argument("--cams", default="side,game,ref")
    parser.add_argument("--res", type=int, default=540)
    return parser.parse_args(argv)


def flat_material(name, colour):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = colour
    return mat


def add_floor(speed, total_frames, fps):
    """A dark floor with light stripes every 2 studs across the run and every 4 along it.
    Real geometry rather than a shader, so the fast Workbench renderer shows it."""
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 0, 0))
    floor = bpy.context.active_object
    floor.name = "Floor"
    floor.data.materials.append(flat_material("Floor", (0.20, 0.23, 0.30, 1)))
    stripe = flat_material("Stripe", (0.36, 0.40, 0.50, 1))
    for i in range(-150, 151):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, i * 2.0, 0.005))
        line = bpy.context.active_object
        line.scale = (60, 0.08, 0.01)
        line.data.materials.append(stripe)
        line.parent = floor
    for i in range(-8, 9):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(i * 4.0, 0, 0.005))
        line = bpy.context.active_object
        line.scale = (0.08, 600, 0.01)
        line.data.materials.append(stripe)
        line.parent = floor
    # The character faces Blender +Y; the ground runs past it toward -Y.
    floor.location.y = 0
    floor.keyframe_insert("location", index=1, frame=0)
    floor.location.y = -speed * total_frames / fps
    floor.keyframe_insert("location", index=1, frame=total_frames)
    for curve in floor.animation_data.action.layers[0].strips[0].channelbags[0].fcurves:
        for point in curve.keyframe_points:
            point.interpolation = "LINEAR"
        curve.extrapolation = "LINEAR"


def add_world():
    world = bpy.data.worlds.new("Sky")
    world.color = (0.45, 0.70, 0.92)
    bpy.context.scene.world = world
    bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(-35)))
    sun = bpy.context.active_object
    sun.data.energy = 3.2
    sun.data.angle = math.radians(3)


def add_camera(name, location, target, lens=50):
    data = bpy.data.cameras.new(name)
    data.lens = lens
    camera = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(camera)
    camera.location = location
    direction = Vector(target) - Vector(location)
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return camera


CAMERAS = {
    "side": ((13.0, 0.0, 4.2), (0.0, 0.0, 2.2), 50),
    "game": ((0.0, -12.5, 6.5), (0.0, 0.0, 3.2), 45),
    "ref": ((-8.6, 3.2, 2.9), (0.0, 0.2, 2.2), 45),
}


def main(argv):
    args = parse(argv)
    scene = bpy.context.scene
    fps = scene.render.fps
    cycle_frames = scene.frame_end - scene.frame_start
    total = cycle_frames * args.loops
    add_world()
    add_floor(args.speed, total, fps)

    # Workbench: Eevee renders nothing in background mode on this machine, and shading
    # detail does not matter for judging motion.
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "MATERIAL"
    shading.show_shadows = True
    shading.shadow_intensity = 0.45
    shading.show_cavity = True
    shading.background_type = "WORLD"
    scene.display.light_direction = (0.45, -0.35, 0.82)
    scene.display.render_aa = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.exposure = 0.9
    for mat in bpy.data.materials:
        if mat.name.startswith("R6 "):
            # The reference character: white skin, a mid-grey shirt.
            mat.diffuse_color = (0.42, 0.44, 0.48, 1) if mat.name == "R6 Torso" else (1, 1, 1, 1)
    scene.render.resolution_x = args.res
    scene.render.resolution_y = args.res
    scene.render.image_settings.file_format = "PNG"
    scene.render.frame_map_old = 1
    scene.render.frame_map_new = args.stretch
    scene.frame_start = 0
    scene.frame_end = total * args.stretch - 1

    for name in args.cams.split(","):
        location, target, lens = CAMERAS[name]
        scene.camera = add_camera(name, location, target, lens)
        scene.render.filepath = os.path.join(args.out_dir, name, "f_")
        bpy.ops.render.render(animation=True)


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1 :])
