"""Generate detailed industrial test-range dressing as a textured GLB."""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / "assets" / "generated" / "trajectory_range.glb"
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_cannon as common


def box(name, location, dimensions, mat, bevel=0.04):
    return common.cube(name, location, dimensions, mat, bevel)


def rod(name, start, end, radius, mat, vertices=24):
    return common.cylinder_between(name, start, end, radius, mat, vertices=vertices)


def face_light(name, location, radius, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=radius, location=location)
    obj = bpy.context.object
    obj.name = name
    common.smooth_surface(obj)
    return common.finish(obj, mat)


def cable_run(name, points, radius, mat):
    for index in range(len(points) - 1):
        rod("%s | section %02d" % (name, index + 1), points[index], points[index + 1], radius, mat, 16)


def add_console(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats
    # Grounded operator plinth and angled instrument deck.
    box("Console | weighted plinth", (-4.15, 0.18, 0.42), (2.24, 0.36, 1.62), dark, 0.10)
    box("Console | armored pedestal", (-4.15, 0.70, 0.40), (1.92, 0.78, 1.28), blue, 0.16)
    box("Console | upper shoulder", (-4.15, 1.08, 0.27), (1.78, 0.22, 1.14), steel, 0.07)
    # Beveled slab tilted toward the operator (+Z).
    deck = box("Console | sloped control surface", (-4.15, 1.29, 0.02), (1.78, 0.12, 1.12), dark, 0.07)
    deck.rotation_euler[0] = math.radians(23.0)
    monitor = box("Console | recessed display bezel", (-4.15, 1.38, 0.11), (1.36, 0.055, 0.60), steel, 0.045)
    monitor.rotation_euler[0] = math.radians(23.0)
    panel = box("Console | cyan glass display", (-4.15, 1.414, 0.14), (1.20, 0.022, 0.45), screen, 0.025)
    panel.rotation_euler[0] = math.radians(23.0)
    # Framed secondary readouts, pressure dials, and a guarded firing control.
    for side in (-1, 1):
        box("Console | side instrument bezel", (-4.15 + side * 0.70, 1.32, 0.18), (0.26, 0.045, 0.30), blue, 0.035)
        face_light("Console | status lamp", (-4.15 + side * 0.70, 1.365, 0.19), 0.055, amber if side < 0 else screen)
        for index in range(3):
            box("Console | tactile key", (-4.15 + side * (0.36 + index * 0.10), 1.27, 0.59), (0.07, 0.065, 0.12), amber if index == 0 and side < 0 else steel, 0.018)
    # Cooling intake, louver strips, screws, and cable glands give the shell real assembly depth.
    for side in (-1, 1):
        for index in range(5):
            box("Console | cooling louver", (-4.15 + side * 0.84, 0.65 + index * 0.055, -0.13), (0.045, 0.024, 0.52), dark, 0.009)
    for x in (-5.0, -3.3):
        for z in (-0.22, 1.00):
            common.fastener("Console | captive corner bolt", (x, 0.82, z), (0.0, 1.0, 0.0), 0.043, copper)
    for side in (-1, 1):
        rod("Console | cable gland", (-4.15 + side * 0.67, 0.31, -0.43), (-4.15 + side * 0.67, 0.31, -0.68), 0.11, steel)
    cable_run("Console | bundled umbilicals", [
        (-3.20, 0.24, -0.42), (-2.90, 0.18, -0.18), (-2.56, 0.16, 0.06),
        (-2.15, 0.17, 0.02), (-1.74, 0.21, -0.23)
    ], 0.045, copper)
    cable_run("Console | sensor conduit", [
        (-3.12, 0.21, -0.55), (-2.86, 0.20, -0.54), (-2.55, 0.20, -0.45),
        (-2.22, 0.23, -0.45)
    ], 0.034, screen)


def add_flood_towers(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats
    for side in (-1, 1):
        for index, z in enumerate((-5.0, -22.0, -40.0)):
            x = side * 10.0
            # Four-footed lattice mast with cross braces, access ladder, and maintenance platform.
            box("Flood mast | anchor shoe", (x, 0.12, z), (0.76, 0.24, 0.76), dark, 0.08)
            rod("Flood mast | spine", (x, 0.28, z), (x, 4.52, z), 0.10, steel)
            for offset in (-0.43, 0.43):
                rod("Flood mast | splayed leg", (x + offset, 0.18, z + 0.28), (x, 1.18, z + 0.28), 0.055, dark)
                rod("Flood mast | lattice brace", (x + offset, 0.20, z - 0.28), (x, 1.18, z - 0.28), 0.045, blue)
            for y in (1.2, 2.4, 3.6):
                rod("Flood mast | cross tie", (x - 0.38, y, z), (x + 0.38, y, z), 0.035, steel)
            box("Flood mast | service platform", (x, 4.37, z), (1.0, 0.13, 0.82), dark, 0.035)
            for offset in (-0.39, 0.39):
                rod("Flood mast | guard rail", (x + offset, 4.42, z - 0.33), (x + offset, 4.80, z - 0.33), 0.025, steel, 16)
            # Deep housing with individual lensed emitters.
            housing = box("Flood mast | armored luminaire", (x - side * 0.18, 4.87, z + 0.02), (1.02, 0.48, 0.66), blue, 0.12)
            housing.rotation_euler[1] = math.radians(-side * 7.0)
            box("Flood mast | face bezel", (x - side * 0.18, 4.84, z + 0.37), (0.83, 0.32, 0.055), dark, 0.045)
            for emitter in range(4):
                face_light("Flood mast | lens %02d" % emitter, (x - side * 0.47 + emitter * 0.19, 4.85, z + 0.408), 0.060, screen if emitter > 0 else amber)
            for step in range(9):
                y = 0.48 + step * 0.40
                box("Flood mast | ladder rung", (x + 0.19, y, z + 0.16), (0.31, 0.035, 0.055), copper, 0.012)
            cable_run("Flood mast | power lead", [
                (x + side * 0.34, 4.35, z), (x + side * 0.40, 3.55, z + 0.10),
                (x + side * 0.43, 2.25, z + 0.10), (x + side * 0.46, 0.28, z + 0.10)
            ], 0.032, dark)


def add_fencing(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats
    for side in (-1, 1):
        x = side * 12.25
        for index in range(8):
            z0 = -7.0 - index * 5.6
            z1 = z0 - 5.6
            zmid = (z0 + z1) * 0.5
            for z in (z0, z1):
                box("Range fence | post foot", (x, 0.12, z), (0.38, 0.18, 0.38), dark, 0.045)
                rod("Range fence | post", (x, 0.18, z), (x, 2.36, z), 0.062, steel)
                box("Range fence | amber cap", (x, 2.34, z), (0.17, 0.10, 0.17), amber, 0.025)
            for y in (0.45, 1.96, 2.24):
                rod("Range fence | rail", (x, y, z0), (x, y, z1), 0.036 if y != 1.96 else 0.048, dark if y != 1.96 else blue)
            # Fine vertical mesh bars keep the fence light and legible at gameplay distance.
            for span in range(1, 9):
                z = z0 + (z1 - z0) * span / 9.0
                rod("Range fence | mesh upright", (x, 0.50, z), (x, 1.90, z), 0.012, steel, 12)
            rod("Range fence | safety tracer", (x - side * 0.045, 0.55, zmid), (x - side * 0.045, 0.55, z1), 0.014, amber, 12)
            # Three horizontal strands across each bay read as tensioned mesh cables.
            for y in (0.82, 1.18, 1.54):
                rod("Range fence | tension wire", (x - side * 0.045, y, z0), (x - side * 0.045, y, z1), 0.010, steel, 12)


def add_target_service_frames(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats
    for target_z, radius in ((-32.0, 2.5), (-46.0, 1.7)):
        frame_z = target_z - 0.62
        width = radius * 2.55
        height = radius * 2.70
        # Feet, shoulders, and high crossbeam support the rotating target carriage.
        for side in (-1, 1):
            x = side * width * 0.5
            box("Target carriage | outrigger foot", (x, 0.17, frame_z), (1.05, 0.30, 1.45), dark, 0.10)
            rod("Target carriage | outer strut", (x, 0.22, frame_z), (x, height, frame_z), 0.10, steel)
            rod("Target carriage | diagonal brace", (x, 0.28, frame_z + 0.38), (side * width * 0.22, height * 0.72, frame_z + 0.38), 0.064, blue)
            rod("Target carriage | diagonal brace", (x, 0.28, frame_z - 0.38), (side * width * 0.22, height * 0.72, frame_z - 0.38), 0.064, blue)
            box("Target carriage | pivot armor", (x, radius * 1.06, frame_z + 0.12), (0.46, 0.68, 0.42), blue, 0.08)
            # Two visible hydraulic rams explain how the plate is raised and locked.
            rod("Target carriage | ram sleeve", (side * radius * 0.72, 0.35, frame_z + 0.02), (side * radius * 0.72, radius * 1.15, frame_z + 0.02), 0.13, dark)
            rod("Target carriage | ram piston", (side * radius * 0.72, radius * 0.56, frame_z + 0.02), (side * radius * 0.72, radius * 1.28, frame_z + 0.02), 0.065, copper)
            for y in (0.40, radius * 1.08):
                common.torus("Target carriage | actuator collar", (side * radius * 0.72, y, frame_z + 0.02), 0.14, 0.025, steel)
        box("Target carriage | crown beam", (0.0, height, frame_z), (width + 0.70, 0.36, 0.72), dark, 0.11)
        box("Target carriage | cyan status bar", (0.0, height - 0.02, frame_z + 0.38), (width * 0.58, 0.055, 0.028), screen, 0.012)
        for side in (-1, 1):
            box("Target carriage | amber warning lamp", (side * width * 0.43, height, frame_z + 0.39), (0.16, 0.22, 0.07), amber, 0.025)


def add_equipment_crates(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats
    crates = ((3.8, 0.0, 1.5, 1.35), (5.3, 0.0, -1.4, 1.05), (-6.2, 0.0, 2.5, 1.15))
    for x, _, z, scale in crates:
        box("Field crate | armored body", (x, scale * 0.48, z), (scale * 1.52, scale * 0.92, scale), blue, 0.09)
        box("Field crate | lid gasket", (x, scale * 0.96, z), (scale * 1.54, scale * 0.08, scale * 1.02), dark, 0.04)
        box("Field crate | lid plate", (x, scale * 1.02, z), (scale * 1.38, scale * 0.08, scale * 0.86), enamel, 0.035)
        for side in (-1, 1):
            box("Field crate | reinforced corner", (x + side * scale * 0.64, scale * 0.50, z), (0.12, scale * 0.78, scale * 0.90), steel, 0.025)
            box("Field crate | amber latch", (x + side * scale * 0.36, scale * 0.62, z + scale * 0.52), (0.18, 0.18, 0.08), amber, 0.025)
        for side in (-1, 1):
            for fore in (-1, 1):
                common.fastener("Field crate | lid fastener", (x + side * scale * 0.55, scale * 1.08, z + fore * scale * 0.32), (0.0, 1.0, 0.0), 0.035, copper)


def build():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    dark = common.material("Range | blackened structural steel", (0.025, 0.045, 0.057), 0.78, 0.48)
    steel = common.material("Range | brushed steel", (0.20, 0.29, 0.33), 0.82, 0.30)
    blue = common.material("Range | deep enamel", (0.035, 0.115, 0.17), 0.53, 0.31)
    enamel = common.material("Range | satin panel enamel", (0.09, 0.23, 0.29), 0.48, 0.33)
    screen = common.material("Range | cyan phosphor", (0.12, 0.76, 0.95), 0.22, 0.21, (0.10, 0.72, 1.0))
    amber = common.material("Range | amber hazard light", (1.0, 0.29, 0.045), 0.26, 0.24, (0.95, 0.16, 0.015))
    copper = common.material("Range | exposed copper alloy", (0.65, 0.22, 0.095), 0.74, 0.30)
    mats = (dark, steel, blue, enamel, screen, amber, copper)
    add_console(mats)
    add_flood_towers(mats)
    add_fencing(mats)
    add_target_service_frames(mats)
    add_equipment_crates(mats)

    # Correct the Blender Z-up authoring transform for Godot's Y-up / -Z-forward world.
    bpy.ops.object.select_all(action="SELECT")
    bpy.context.view_layer.objects.active = bpy.context.selected_objects[0]
    compensate = Matrix.Rotation(math.radians(90.0), 4, "X")
    for obj in bpy.context.selected_objects:
        obj.matrix_world = compensate @ obj.matrix_world
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
