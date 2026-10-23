"""Generate the first Trajectory Works gas-cannon model as a GLB."""

from pathlib import Path
import math
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "generated" / "trajectory_cannon.glb"


def material(name, color, metallic=0.0, roughness=0.45, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    if emission:
        shader.inputs["Emission Color"].default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = 1.5
    return mat


def finish(obj, mat, bevel=0.0):
    obj.data.materials.append(mat)
    if bevel and obj.type == "MESH":
        mod = obj.modifiers.new("Machined edge highlights", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        normal = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        normal.keep_sharp = True
    return obj


def cube(name, location, dimensions, mat, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, bevel)


def cylinder_between(name, start, end, radius, mat, vertices=32):
    a, b = Vector(start), Vector(end)
    direction = b - a
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=vertices,
        radius=radius,
        depth=direction.length,
        location=(a + b) * 0.5,
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = direction.to_track_quat("Z", "Y")
    return finish(obj, mat, min(radius * 0.18, 0.025))


def torus(name, location, major, minor, mat):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=48,
        minor_segments=12,
        major_radius=major,
        minor_radius=minor,
        location=location,
        rotation=(math.pi * 0.5, 0.0, 0.0),
    )
    obj = bpy.context.object
    obj.name = name
    return finish(obj, mat)


def build():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    blue = material("Enamel | deep range blue", (0.045, 0.16, 0.29), 0.55, 0.3)
    blue_edge = material("Machined | blue steel", (0.12, 0.28, 0.39), 0.78, 0.26)
    dark = material("Frame | graphite steel", (0.045, 0.065, 0.075), 0.82, 0.34)
    barrel = material("Barrel | brushed titanium", (0.34, 0.42, 0.47), 0.86, 0.23)
    copper = material("Coils | warm copper", (0.66, 0.24, 0.10), 0.78, 0.26)
    tube = material("Pneumatic lines | pale alloy", (0.53, 0.67, 0.68), 0.76, 0.22)
    cyan = material("Field indicator | cyan", (0.12, 0.72, 0.90), 0.3, 0.2, (0.08, 0.65, 1.0))

    # The meshes are authored in Godot's Y-up / -Z-forward coordinates.
    # Pre-compensate the Blender glTF exporter's Z-up to Y-up axis rotation so
    # those coordinates arrive unchanged when Godot imports the GLB.
    cube("Foundation | chamfered skid", (0.0, 0.05, 0.0), (2.8, 0.32, 3.6), dark, 0.12)
    cube("Upper cradle", (0.0, 0.30, -0.12), (2.25, 0.32, 2.25), blue_edge, 0.08)
    for x in (-0.82, 0.82):
        cube("Recoil rail", (x, 0.53, -0.55), (0.16, 0.3, 1.75), dark, 0.035)
        cube("Rail highlight", (x, 0.70, -0.55), (0.075, 0.055, 1.45), copper, 0.015)

    cube("Armored pressure housing", (0.0, 0.93, 0.0), (2.05, 1.30, 1.75), blue, 0.18)
    cube("Front housing bezel", (0.0, 0.98, -0.91), (1.64, 0.98, 0.20), blue_edge, 0.06)
    cube("Service panel", (0.0, 1.55, 0.38), (1.2, 0.055, 0.62), dark, 0.04)
    cube("Status display", (0.0, 1.56, 0.36), (0.82, 0.025, 0.34), cyan, 0.025)

    # Barrel, muzzle collar, and multiple copper induction rings.
    cylinder_between("Main barrel", (0.0, 1.17, -0.82), (0.0, 1.17, -6.75), 0.31, barrel)
    for y, radius in ((1.17, 0.43), (1.17, 0.39)):
        torus("Muzzle restraint ring", (0.0, y, -6.52), radius, 0.075, dark)
    for index in range(10):
        y = 1.17
        z = -0.95 - index * 0.27
        torus("Copper induction coil %02d" % (index + 1), (0.0, y, z), 0.39, 0.055, copper)
    torus("Muzzle field indicator", (0.0, 1.17, -6.82), 0.36, 0.035, cyan)

    # Twin pressure accumulators and protective saddles.
    for side in (-1, 1):
        x = side * 1.04
        cylinder_between("Pressure accumulator", (x, 0.42, 0.18), (x, 1.30, 0.18), 0.27, blue_edge)
        for y in (0.48, 1.23):
            torus("Accumulator retaining band", (x, y, 0.18), 0.285, 0.035, copper)
        cube("Accumulator guard", (x, 0.86, 0.18), (0.12, 1.08, 0.16), dark, 0.025)
        cylinder_between("Feed manifold", (side * 0.75, 0.60, 0.75), (x, 0.55, 0.35), 0.075, tube)
        cylinder_between("Coil feed", (x, 0.55, 0.35), (side * 0.68, 1.05, -1.12), 0.06, copper)
        cube("Side armor lug", (side * 1.07, 0.92, -0.43), (0.20, 0.42, 0.65), blue_edge, 0.045)

    # Structural barrel cradles, support feet, bolts, and a small gauge.
    for z in (-2.0, -4.8):
        cube("Barrel cradle crossbeam", (0.0, 0.55, z), (1.35, 0.20, 0.26), dark, 0.045)
        for side in (-1, 1):
            cube("Angled support", (side * 0.48, 0.42, z + 0.18), (0.18, 0.54, 0.56), blue_edge, 0.035)
    cylinder_between("Gauge stem", (0.68, 1.30, 0.48), (0.80, 1.55, 0.48), 0.045, tube)
    cylinder_between("Pressure gauge body", (0.80, 1.55, 0.48), (0.80, 1.73, 0.48), 0.17, dark)
    cylinder_between("Gauge face", (0.80, 1.73, 0.48), (0.80, 1.76, 0.48), 0.12, tube)

    # Make the GLB convenient to place on a range deck in Godot.
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    precompensate_glb_axis_conversion = Matrix.Rotation(math.radians(90.0), 4, "X")
    for obj in bpy.context.selected_objects:
        obj.matrix_world = precompensate_glb_axis_conversion @ obj.matrix_world
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        export_apply=True,
        export_materials="EXPORT",
        export_yup=True,
    )
    print("Exported %s" % OUTPUT)


if __name__ == "__main__":
    build()
