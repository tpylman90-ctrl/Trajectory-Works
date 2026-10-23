"""Generate the first Trajectory Works gas-cannon model as a GLB."""

from pathlib import Path
import math
import random
import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "generated" / "trajectory_cannon.glb"


def finish_texture(name, color, roughness):
    # Packed PBR maps keep the generated GLB self-contained for Android.
    size = 512
    seed = sum((index + 1) * ord(char) for index, char in enumerate(name))
    rng = random.Random(seed)
    color_image = bpy.data.images.new(name + " | enamel grain", width=size, height=size, alpha=False)
    rough_image = bpy.data.images.new(name + " | micro roughness", width=size, height=size, alpha=False)
    normal_image = bpy.data.images.new(name + " | micro normal", width=size, height=size, alpha=False)
    color_image.colorspace_settings.name = "sRGB"
    rough_image.colorspace_settings.name = "Non-Color"
    normal_image.colorspace_settings.name = "Non-Color"
    color_pixels = []
    rough_pixels = []
    normal_pixels = []
    for y in range(size):
        v = y / size
        for x in range(size):
            u = x / size
            phase_a = math.tau * (u * 19.0 + v * 7.0)
            phase_b = math.tau * (u * 43.0 - v * 31.0)
            phase_c = math.tau * (u * 71.0 + v * 53.0)
            grain = (math.sin(phase_a) + math.sin(phase_b) * 0.45 + math.sin(phase_c) * 0.22) / 1.67
            slope_u = (math.cos(phase_a) * math.tau * 19.0
                       + math.cos(phase_b) * math.tau * 43.0 * 0.45
                       + math.cos(phase_c) * math.tau * 71.0 * 0.22) / 1.67
            slope_v = (math.cos(phase_a) * math.tau * 7.0
                       - math.cos(phase_b) * math.tau * 31.0 * 0.45
                       + math.cos(phase_c) * math.tau * 53.0 * 0.22) / 1.67
            micrograin = rng.uniform(-1.0, 1.0)
            # Fine directional scuffs and broader roughness variation read as handling wear.
            scratch_wave = abs(math.sin(math.tau * (u * 137.0 + math.sin(v * math.tau * 9.0) * 0.008)))
            scratch = max(0.0, 1.0 - scratch_wave / 0.055)
            scratch *= 0.30 + 0.70 * (0.5 + 0.5 * math.sin(math.tau * (v * 2.0 + u * 0.13)))
            tint = 1.0 + grain * 0.035 + micrograin * 0.012 - scratch * 0.055
            color_pixels.extend(max(0.0, min(1.0, channel * tint)) for channel in color)
            color_pixels.append(1.0)
            r = max(0.04, min(0.96, roughness + grain * 0.05 + micrograin * 0.035 + scratch * 0.16))
            rough_pixels.extend((r, r, r, 1.0))
            normal_x = max(0.38, min(0.62, 0.5 - slope_u * 0.00036 + micrograin * 0.012))
            normal_y = max(0.38, min(0.62, 0.5 - slope_v * 0.00036 + micrograin * 0.012))
            normal_pixels.extend((normal_x, normal_y, 1.0, 1.0))
    color_image.pixels.foreach_set(color_pixels)
    rough_image.pixels.foreach_set(rough_pixels)
    normal_image.pixels.foreach_set(normal_pixels)
    color_image.pack()
    rough_image.pack()
    normal_image.pack()
    return color_image, rough_image, normal_image


def material(name, color, metallic=0.0, roughness=0.45, emission=None):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    links = mat.node_tree.links
    shader = nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness
    color_image, rough_image, normal_image = finish_texture(name, color, roughness)
    color_node = nodes.new("ShaderNodeTexImage")
    color_node.name = name + " | enamel grain"
    color_node.image = color_image
    rough_node = nodes.new("ShaderNodeTexImage")
    rough_node.name = name + " | micro roughness"
    rough_node.image = rough_image
    normal_node = nodes.new("ShaderNodeTexImage")
    normal_node.name = name + " | micro normal"
    normal_node.image = normal_image
    normal_map = nodes.new("ShaderNodeNormalMap")
    normal_map.inputs["Strength"].default_value = 0.42
    links.new(color_node.outputs["Color"], shader.inputs["Base Color"])
    links.new(rough_node.outputs["Color"], shader.inputs["Roughness"])
    links.new(normal_node.outputs["Color"], normal_map.inputs["Color"])
    links.new(normal_map.outputs["Normal"], shader.inputs["Normal"])
    if emission:
        shader.inputs["Emission Color"].default_value = (*emission, 1.0)
        shader.inputs["Emission Strength"].default_value = 0.65
    return mat


def finish(obj, mat, bevel=0.0):
    obj.data.materials.append(mat)
    if bevel and obj.type == "MESH":
        mod = obj.modifiers.new("Soft machined radii", "BEVEL")
        mod.width = bevel
        mod.segments = 3
        mod.harden_normals = True
        normal = obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
        normal.keep_sharp = True
    return obj


def smooth_surface(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    return obj


def fastener(name, position, outward, radius, mat):
    axis = Vector(outward).normalized()
    return cylinder_between(name, position, Vector(position) + axis * 0.035, radius, mat, vertices=24)


def cube(name, location, dimensions, mat, bevel=0.04):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, mat, bevel)


def cylinder_between(name, start, end, radius, mat, vertices=64):
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
    smooth_surface(obj)
    return finish(obj, mat, min(radius * 0.12, 0.018))


def torus(name, location, major, minor, mat, rotation=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_torus_add(
        major_segments=64,
        minor_segments=16,
        major_radius=major,
        minor_radius=minor,
        location=location,
        rotation=rotation,
    )
    obj = bpy.context.object
    obj.name = name
    smooth_surface(obj)
    return finish(obj, mat)


def build():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)

    blue = material("Enamel | deep range blue", (0.045, 0.16, 0.29), 0.55, 0.3)
    blue_edge = material("Machined | blue steel", (0.12, 0.28, 0.39), 0.78, 0.26)
    ceramic = material("Armor | satin cobalt ceramic", (0.075, 0.235, 0.39), 0.36, 0.31)
    graphite = material("Gaskets | charcoal elastomer", (0.018, 0.027, 0.034), 0.12, 0.58)
    fastener_metal = material("Fasteners | brushed nickel", (0.48, 0.59, 0.62), 0.82, 0.27)
    amber = material("Safety marks | signal amber", (0.95, 0.31, 0.055), 0.42, 0.3, (0.16, 0.035, 0.005))
    dark = material("Frame | graphite steel", (0.045, 0.065, 0.075), 0.82, 0.34)
    barrel = material("Barrel | brushed titanium", (0.34, 0.42, 0.47), 0.86, 0.23)
    copper = material("Coils | warm copper", (0.66, 0.24, 0.10), 0.78, 0.26)
    tube = material("Pneumatic lines | pale alloy", (0.53, 0.67, 0.68), 0.76, 0.22)
    cyan = material("Field indicator | cyan", (0.09, 0.48, 0.62), 0.3, 0.24, (0.035, 0.31, 0.48))

    # The meshes are authored in Godot's Y-up / -Z-forward coordinates.
    # Pre-compensate the Blender glTF exporter's Z-up to Y-up axis rotation so
    # those coordinates arrive unchanged when Godot imports the GLB.
    cube("Foundation | chamfered skid", (0.0, 0.05, 0.0), (2.8, 0.32, 3.6), dark, 0.12)
    # Azimuth bearing and rotating table replace the plain square cradle.
    cylinder_between("Azimuth bearing | lower race", (0.0, 0.20, 0.0), (0.0, 0.34, 0.0), 1.15, dark)
    torus("Azimuth bearing | machined race", (0.0, 0.34, 0.0), 1.02, 0.035, fastener_metal, rotation=(math.pi * 0.5, 0.0, 0.0))
    cylinder_between("Rotating gun table", (0.0, 0.34, 0.0), (0.0, 0.48, 0.0), 0.94, blue_edge)
    torus("Rotating table | copper seal", (0.0, 0.475, 0.0), 0.81, 0.032, copper, rotation=(math.pi * 0.5, 0.0, 0.0))
    for index in range(12):
        angle = math.tau * index / 12.0
        fastener("Azimuth table lock bolt", (math.cos(angle) * 0.88, 0.48, math.sin(angle) * 0.88), (0.0, 1.0, 0.0), 0.035, fastener_metal)
    for x in (-0.82, 0.82):
        cube("Recoil rail", (x, 0.53, -0.55), (0.16, 0.3, 1.75), dark, 0.035)
        cube("Rail highlight", (x, 0.70, -0.55), (0.075, 0.055, 1.45), copper, 0.015)

    cube("Armored pressure housing", (0.0, 0.93, 0.0), (2.05, 1.30, 1.75), blue, 0.20)
    # Exposed elevation trunnions and paired yoke struts make the mount read as operable machinery.
    for side in (-1, 1):
        cylinder_between("Elevation yoke strut", (side * 1.08, 0.44, 0.34), (side * 1.08, 0.93, 0.34), 0.14, dark)
        cylinder_between("Trunnion drum", (side * 0.94, 0.94, 0.30), (side * 1.19, 0.94, 0.30), 0.39, blue_edge)
        torus("Trunnion bronze race", (side * 1.18, 0.94, 0.30), 0.31, 0.035, copper, rotation=(0.0, math.pi * 0.5, 0.0))
        cylinder_between("Trunnion locking hub", (side * 1.19, 0.94, 0.30), (side * 1.24, 0.94, 0.30), 0.19, dark)
        cylinder_between("Trunnion center cap", (side * 1.24, 0.94, 0.30), (side * 1.27, 0.94, 0.30), 0.105, fastener_metal)
    # Sculpted shoulder armor softens the silhouette and breaks up the large blue mass.
    for side in (-1, 1):
        shoulder = cube("Floating shoulder armor", (side * 0.73, 1.40, -0.05), (0.62, 0.34, 1.42), ceramic, 0.14)
        shoulder.rotation_euler[1] = side * math.radians(-7.0)
        cube("Shoulder inset gasket", (side * 0.72, 1.575, -0.05), (0.38, 0.045, 0.91), graphite, 0.055)
        cube("Shoulder service insert", (side * 0.72, 1.603, -0.05), (0.25, 0.018, 0.70), blue_edge, 0.025)
    cube("Crown pressure cover", (0.0, 1.59, 0.18), (1.23, 0.22, 0.76), ceramic, 0.11)
    cube("Top access hatch gasket", (0.0, 1.715, 0.20), (0.78, 0.035, 0.43), graphite, 0.04)
    cube("Top access hatch", (0.0, 1.741, 0.20), (0.64, 0.025, 0.31), blue_edge, 0.035)
    # Small amber index marks are restrained visual accents, not large graphic stripes.
    for side in (-1, 1):
        cube("Pressure limit index", (side * 0.91, 1.18, 0.57), (0.035, 0.10, 0.23), amber, 0.012)
    cube("Front housing bezel", (0.0, 0.98, -0.91), (1.64, 0.98, 0.20), blue_edge, 0.06)
    cube("Service panel", (0.0, 1.55, 0.38), (1.2, 0.055, 0.62), dark, 0.04)
    cube("Status display", (0.0, 1.56, 0.36), (0.82, 0.025, 0.34), cyan, 0.025)

    # Finished breech assembly: pressure cap, lock ring, cooling vents, and service plate.
    cube("Breech rear service plate", (0.0, 1.02, 0.93), (1.42, 0.98, 0.12), blue_edge, 0.10)
    for side in (-1, 1):
        for index in range(4):
            cube(
                "Breech cooling vent",
                (side * (0.42 + index * 0.045), 0.88, 1.005),
                (0.045, 0.42, 0.035), graphite, 0.016
            )
        cube("Breech rear shoulder", (side * 0.75, 1.37, 0.98), (0.30, 0.24, 0.18), ceramic, 0.06)
    cylinder_between("Breech pressure cap", (0.0, 1.16, 0.94), (0.0, 1.16, 1.13), 0.39, dark)
    torus("Breech locking ring", (0.0, 1.16, 1.13), 0.34, 0.045, copper)
    cylinder_between("Breech inspection plate", (0.0, 1.16, 1.13), (0.0, 1.16, 1.16), 0.26, blue_edge)
    torus("Breech indicator bezel", (0.0, 1.16, 1.16), 0.17, 0.025, fastener_metal)
    cylinder_between("Breech status lens", (0.0, 1.16, 1.16), (0.0, 1.16, 1.18), 0.105, cyan, vertices=48)
    cube("Breech ID plaque", (0.0, 1.58, 0.99), (0.78, 0.12, 0.045), dark, 0.025)
    for side in (-1, 1):
        fastener("Breech plate screw", (side * 0.59, 1.40, 1.01), (0.0, 0.0, 1.0), 0.035, fastener_metal)

    # Fasteners and recessed seams give the armor readable scale and assembly logic.
    for side in (-1, 1):
        for y in (0.57, 1.28):
            for z in (-0.60, 0.58):
                fastener("Armor captive bolt", (side * 1.035, y, z), (side, 0, 0), 0.052, fastener_metal)
        for z in (-0.61, 0.61):
            cylinder_between("Shoulder armor pin", (side * 0.91, 1.41, z), (side * 0.94, 1.41, z), 0.045, fastener_metal, vertices=24)

    # Exposed emitter assembly: segmented titanium jackets, visible induction coils, and a clean bore.
    cylinder_between("Main barrel | dark titanium liner", (0.0, 1.17, -0.82), (0.0, 1.17, -6.75), 0.30, dark)
    for index in range(9):
        z = -1.02 - index * 0.125
        torus("Exposed copper induction winding %02d" % (index + 1), (0.0, 1.17, z), 0.365, 0.052, copper)
    # Four separate jacket modules leave dark expansion gaps so the emitter reads
    # as engineered machinery instead of one oversized sleeve.
    for index, z in enumerate((-2.52, -3.56, -4.60, -5.64)):
        jacket_material = barrel if index % 2 == 0 else blue_edge
        cylinder_between(
            "Segmented emitter jacket %02d" % (index + 1),
            (0.0, 1.17, z - 0.37),
            (0.0, 1.17, z + 0.37),
            0.405 if index < 3 else 0.39,
            jacket_material,
        )
        for edge in (-1, 1):
            collar_z = z + edge * 0.37
            torus("Emitter jacket locking collar", (0.0, 1.17, collar_z), 0.414 if index < 3 else 0.40, 0.028, dark)
            torus("Collar index | amber", (0.0, 1.17, collar_z + edge * 0.045), 0.416 if index < 3 else 0.402, 0.012, amber)
    # Longitudinal bus rails bridge the modules and expose the cannon's power path.
    for index in range(6):
        angle = math.tau * index / 6.0
        x = math.cos(angle) * 0.398
        y = 1.17 + math.sin(angle) * 0.398
        cylinder_between("Emitter bus rail", (x, y, -2.02), (x, y, -6.05), 0.027, fastener_metal, vertices=24)
        for z in (-2.16, -3.20, -4.24, -5.28, -6.02):
            fastener("Bus rail clamp", (x, y, z), (math.cos(angle), math.sin(angle), 0.0), 0.022, copper)
# Twin pressure accumulators and protective saddles.
    for side in (-1, 1):
        x = side * 1.04
        cylinder_between("Pressure accumulator", (x, 0.42, 0.18), (x, 1.30, 0.18), 0.27, blue_edge)
        for y in (0.48, 1.23):
            torus("Accumulator retaining band", (x, y, 0.18), 0.285, 0.035, copper, rotation=(math.pi * 0.5, 0.0, 0.0))
        cube("Accumulator guard", (x, 0.86, 0.18), (0.12, 1.08, 0.16), dark, 0.025)
        cylinder_between("Feed manifold", (side * 0.75, 0.60, 0.75), (x, 0.55, 0.35), 0.075, tube)
        cylinder_between("Coil feed", (x, 0.55, 0.35), (side * 0.68, 1.05, -1.12), 0.06, copper)
        cube("Side armor lug", (side * 1.07, 0.92, -0.43), (0.20, 0.42, 0.65), blue_edge, 0.045)

    # A stepped muzzle jacket, inset bore, and concentric field emitter finish the barrel.
    cylinder_between("Muzzle shroud", (0.0, 1.17, -6.18), (0.0, 1.17, -6.82), 0.425, blue_edge)
    cylinder_between("Bore shadow insert", (0.0, 1.17, -6.835), (0.0, 1.17, -6.85), 0.285, graphite, vertices=64)
    torus("Muzzle seal | graphite", (0.0, 1.17, -6.20), 0.432, 0.035, graphite)
    torus("Muzzle crown | titanium", (0.0, 1.17, -6.83), 0.455, 0.055, fastener_metal)
    for index in range(8):
        angle = index * math.tau / 8.0
        fastener(
            "Muzzle crown bolt",
            (0.0 + math.cos(angle) * 0.38, 1.17 + math.sin(angle) * 0.38, -6.94),
            (0, 0, -1), 0.028, fastener_metal
        )

    # The segmented emitter jackets are supported by the continuous titanium liner.
    # Detached mid-barrel posts were removed so the underside silhouette stays intentional.
    cylinder_between("Gauge stem", (0.68, 1.30, 0.48), (0.80, 1.55, 0.48), 0.045, tube)
    cylinder_between("Pressure gauge body", (0.80, 1.55, 0.48), (0.80, 1.73, 0.48), 0.17, dark)
    cylinder_between("Gauge face", (0.80, 1.73, 0.48), (0.80, 1.76, 0.48), 0.12, tube)

    # A visible regulator cluster connects the accumulators to the firing chamber.
    for side in (-1, 1):
        x = side * 0.57
        cylinder_between("Regulator body", (x, 0.50, 0.57), (x, 0.95, 0.57), 0.14, dark)
        torus("Regulator brass seat", (x, 0.92, 0.57), 0.145, 0.025, copper, rotation=(math.pi * 0.5, 0.0, 0.0))
        cylinder_between("Regulator cap", (x, 0.95, 0.57), (x, 1.06, 0.57), 0.09, fastener_metal)
        cylinder_between("Regulator indicator", (x, 1.06, 0.57), (x, 1.075, 0.57), 0.045, cyan, vertices=32)

    # Pivot around the actual trunnion center, not the barrel throat. This keeps
    # the breech seated in the yoke as elevation changes in Godot.
    pivot = bpy.data.objects.new("ElevationPivot", None)
    bpy.context.collection.objects.link(pivot)
    pivot.location = (0.0, 0.94, 0.30)
    pivot.empty_display_type = "CIRCLE"
    pivot.empty_display_size = 0.24
    pivot_parts = (
        "Main barrel | dark titanium liner",
        "Exposed copper induction winding",
        "Segmented emitter jacket",
        "Emitter jacket locking collar",
        "Collar index | amber",
        "Emitter bus rail",
        "Bus rail clamp",
        "Muzzle shroud",
        "Bore shadow insert",
        "Muzzle seal | graphite",
        "Muzzle crown | titanium",
        "Muzzle crown bolt",
    )
    for obj in list(bpy.context.scene.objects):
        if obj is pivot or not obj.name.startswith(pivot_parts):
            continue
        world_matrix = obj.matrix_world.copy()
        obj.parent = pivot
        obj.matrix_world = world_matrix

    # Keep the fixed base in its own transform group. Godot needs the barrel
    # axis correction for the emitter, while the skid and pressure housing stay upright.
    base_assembly = bpy.data.objects.new("CannonBaseAssembly", None)
    bpy.context.collection.objects.link(base_assembly)
    base_assembly.location = (0.0, 0.0, 0.0)
    for obj in list(bpy.context.scene.objects):
        if obj is base_assembly or obj is pivot or obj.parent is not None:
            continue
        world_matrix = obj.matrix_world.copy()
        obj.parent = base_assembly
        obj.matrix_world = world_matrix

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
