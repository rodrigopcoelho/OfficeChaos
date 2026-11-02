"""Builds the OFFICE CHAOS mesh kit: soft, bevelled unit primitives with smooth normals.

Run headless (no MCP needed):
    /Applications/Blender.app/Contents/MacOS/Blender --background --python tools/blender/build_mesh_kit.py

Output: assets/meshes/kit.glb (one object per shape, each fitting a 1x1x1 box, centred).
The game scales these per part (see scripts/systems/mesh_factory.gd), so every JSON
part with "shape": "box" / "cyl" / "sphere" / ... gets the rounded toy look automatically.
Edit the bevel values below and re-run to change the style.
"""
import math
import os
import bmesh
import bpy

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "meshes", "kit.glb")

bpy.ops.wm.read_factory_settings(use_empty=True)


def finish(obj, name, bevel=0.0, segments=3, smooth=True, sharp_angle=0.0):
    obj.name = name
    obj.data.name = name
    if bevel > 0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "NONE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    if smooth and sharp_angle > 0:
        # Smooth, but keep creases (e.g. a flat sole) sharp; the glTF export splits them.
        bpy.ops.object.shade_smooth_by_angle(angle=math.radians(sharp_angle))
    elif smooth:
        bpy.ops.object.shade_smooth()
    else:
        bpy.ops.object.shade_flat()
    obj.select_set(False)
    return obj


def mesh_object(name, bm):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    return obj


def lathe(name, profile, segments=24):
    """Revolves a (radius, height) profile, listed top to bottom, around the vertical axis.
    Blender is Z-up; the glTF export turns Z into Godot's +Y."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0.0, 0.0, z))])
        else:
            rings.append([bm.verts.new((r * math.cos(math.tau * i / segments), r * math.sin(math.tau * i / segments), z)) for i in range(segments)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segments):
            j = (i + 1) % segments
            if len(a) == 1:
                bm.faces.new((a[0], b[i], b[j]))
            elif len(b) == 1:
                bm.faces.new((a[i], a[j], b[0]))
            else:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    return mesh_object(name, bm)


def superball(name, power=2.5, half=False, segments=32, rings=16):
    """Rounded 'squircle' ball |x|^p + |y|^p + |z|^p = r^p fitted to a unit box.
    half=True keeps the top half with a flat bottom, stretched back to a unit box
    (hair caps, shoes)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    if half:
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < -1e-4], context="VERTS")
        bm.edges.ensure_lookup_table()
        rim = [e for e in bm.edges if e.is_boundary]
        bmesh.ops.contextual_create(bm, geom=rim)
    for v in bm.verts:
        d = v.co.normalized() if v.co.length > 1e-6 else v.co
        s = (abs(d.x) ** power + abs(d.y) ** power + abs(d.z) ** power) ** (1.0 / power)
        p = d / s * 0.5 if s > 1e-6 else d
        if half:
            p.z = max(p.z, 0.0) * 2.0 - 0.5
        v.co = p
    return mesh_object(name, bm)


# Rounded box: the workhorse for bodies, desks, monitors, weapon blades...
bpy.ops.mesh.primitive_cube_add(size=1.0)
finish(bpy.context.active_object, "box", bevel=0.14, segments=3)

# Extra-soft box: pillows, heads, cute bodies.
bpy.ops.mesh.primitive_cube_add(size=1.0)
finish(bpy.context.active_object, "softbox", bevel=0.32, segments=4)

# Cylinder with rounded rims.
bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.5, depth=1.0)
finish(bpy.context.active_object, "cyl", bevel=0.1, segments=2)

# Cone (tip points up, +Y in Godot).
bpy.ops.mesh.primitive_cone_add(vertices=14, radius1=0.5, radius2=0.0, depth=1.0)
finish(bpy.context.active_object, "cone", bevel=0.04, segments=2)

# Smooth sphere.
bpy.ops.mesh.primitive_uv_sphere_add(segments=18, ring_count=10, radius=0.5)
finish(bpy.context.active_object, "sphere")

# Faceted gem (DATA fragments, terminal crystals).
bpy.ops.mesh.primitive_uv_sphere_add(segments=4, ring_count=2, radius=0.5)
finish(bpy.context.active_object, "gem", smooth=False)

# Ring.
bpy.ops.mesh.primitive_torus_add(major_radius=0.4, minor_radius=0.1, major_segments=24, minor_segments=8)
finish(bpy.context.active_object, "torus")

# --- Character kit (scripts/actors/character_visual.gd) -------------------------------

# Big round villager head: a soft squircle ball. The face is painted on its front
# by shaders/character.gdshader, so it needs even, dense vertices more than detail.
finish(superball("head", power=2.5), "head")

# Top half of the same ball with a flat bottom: hair caps that hug the head, shoes.
finish(superball("dome", power=2.5, half=True), "dome", sharp_angle=60.0)

# Capsule with half-height caps: when scaled 1:2 (arms, legs) the caps are round.
cap = [(0.5 * math.sin(math.radians(a)), 0.25 + 0.25 * math.cos(math.radians(a))) for a in range(0, 91, 15)]
finish(lathe("capsule", cap + [(r, -z) for r, z in reversed(cap)]), "capsule")

# A-line blazer body: rounded shoulders, flared hem (shirt/tie/lapels are painted on).
blazer = [(0.0, 0.5), (0.3, 0.5), (0.36, 0.49), (0.395, 0.465), (0.413, 0.43), (0.42, 0.36), (0.43, 0.2),
          (0.45, 0.0), (0.475, -0.2), (0.495, -0.36), (0.5, -0.43), (0.494, -0.475), (0.47, -0.5), (0.0, -0.5)]
finish(lathe("blazer", blazer), "blazer")

# --- Office dressing kit (scripts/world/game_world.gd) -------------------------------

# Tapered planter with a rolled rim and a sunken soil top.
pot = [(0.0, 0.36), (0.4, 0.36), (0.43, 0.42), (0.5, 0.46), (0.5, 0.5), (0.46, 0.5), (0.44, 0.38),
       (0.41, 0.1), (0.36, -0.3), (0.32, -0.46), (0.3, -0.5), (0.0, -0.5)]
finish(lathe("pot", pot), "pot", sharp_angle=50.0)

# Mug: a straight cup with a lip, plus a loop handle on +X (Blender) = +X (Godot).
mug = lathe("mug", [(0.0, 0.3), (0.3, 0.3), (0.33, 0.5), (0.4, 0.5), (0.4, -0.45), (0.36, -0.5), (0.0, -0.5)])
bpy.ops.mesh.primitive_torus_add(major_radius=0.2, minor_radius=0.065, major_segments=16, minor_segments=8,
                                 location=(0.4, 0.0, 0.0), rotation=(math.radians(90), 0.0, 0.0))
handle = bpy.context.active_object
bpy.ops.object.select_all(action="DESELECT")
handle.select_set(True)
mug.select_set(True)
bpy.context.view_layer.objects.active = mug
bpy.ops.object.join()
finish(mug, "mug", sharp_angle=40.0)

# Water-cooler jug: a ribbed bottle, neck down (it sits upside down on the cooler).
jug = [(0.0, 0.5), (0.36, 0.5), (0.46, 0.44), (0.5, 0.32), (0.47, 0.22), (0.5, 0.1), (0.47, -0.02),
       (0.5, -0.14), (0.46, -0.28), (0.3, -0.38), (0.16, -0.42), (0.15, -0.5), (0.0, -0.5)]
finish(lathe("jug", jug), "jug")

# Leaf: a pointed, cupped blade lying along +Y (Blender), bent upward toward the tip.
# Fitted to the unit box like everything else: width x 1, length y 1, depth z 1.
bm = bmesh.new()
rows, cols = 10, 6
grid = []
for i in range(rows + 1):
    t = i / rows
    half_w = 0.5 * math.sin(math.pi * t) ** 0.8
    row = []
    for j in range(cols + 1):
        s = j / cols * 2.0 - 1.0
        x = s * half_w
        z = -0.5 + 0.7 * t * t + 0.25 * (1.0 - s * s) * math.sin(math.pi * t)  # arch + cup
        row.append(bm.verts.new((x, t - 0.5, z)))
    grid.append(row)
for i in range(rows):
    for j in range(cols):
        bm.faces.new((grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j]))
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
leaf = mesh_object("leaf", bm)
mod = leaf.modifiers.new("solid", "SOLIDIFY")
mod.thickness = 0.06
mod.offset = 0.0
finish(leaf, "leaf")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_apply=True, export_materials="NONE", export_yup=True)
print("[kit] wrote", OUT)
