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


def add_launch_deck(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats[:7][:7]
    concrete = mats[7]
    # A wider poured pad leaves a visible concrete lip around the raised steel skid.
    box("Launch pad | poured reinforced concrete plinth", (0.0, 0.035, 0.15), (6.35, 0.17, 8.35), concrete, 0.12)
    for x in (-2.75, 2.75):
        for z in (-3.45, 3.75):
            box("Launch pad | chamfered anchor block", (x, 0.10, z), (0.56, 0.22, 0.58), concrete, 0.075)
    # Layered steel foundation with bevels large enough to catch the range lights.
    box("Launch deck | structural foundation", (0.0, 0.12, 0.15), (5.2, 0.24, 7.2), dark, 0.15)
    box("Launch deck | armored top plate", (0.0, 0.255, 0.15), (4.82, 0.045, 6.84), enamel, 0.085)
    for side in (-1, 1):
        box("Launch deck | side armor skirt", (side * 2.48, 0.11, 0.15), (0.22, 0.28, 6.82), blue, 0.055)
        box("Launch deck | amber edge tracer", (side * 2.34, 0.283, 0.15), (0.060, 0.025, 6.35), amber, 0.014)
        box("Launch deck | cyan inset tracer", (side * 2.22, 0.281, 0.15), (0.035, 0.022, 6.12), screen, 0.008)
        # Recessed side ports and fastening strips.
        for z in (-2.72, -1.90, -1.08, -0.26, 0.56, 1.38, 2.20, 3.02):
            box("Launch deck | access panel", (side * 2.615, 0.10, z), (0.025, 0.15, 0.58), steel, 0.012)
            common.fastener("Launch deck | panel latch", (side * 2.635, 0.10, z), (side, 0.0, 0.0), 0.026, copper)
        for z in (-3.10, -2.20, -1.30, -0.40, 0.50, 1.40, 2.30, 3.20):
            for x in (-2.15, 2.15):
                common.fastener("Launch deck | countersunk top bolt", (x, 0.282, z), (0.0, 1.0, 0.0), 0.031, steel)
    # Beneath-deck beams and four mechanical feet make the platform feel planted.
    for z in (-2.70, -1.35, 0.15, 1.65, 3.0):
        box("Launch deck | underframe crossmember", (0.0, -0.06, z), (4.68, 0.16, 0.20), blue, 0.035)
    for side in (-1, 1):
        for fore in (-1, 1):
            x, z = side * 2.0, 0.15 + fore * 2.78
            box("Launch deck | outrigger pad", (x, -0.025, z), (0.50, 0.18, 0.58), dark, 0.075)
            rod("Launch deck | leveling jack", (x, 0.02, z), (x, 0.31, z), 0.095, steel)
            common.torus("Launch deck | jack locking collar", (x, 0.22, z), 0.104, 0.022, copper)
    # Modular anti-slip inserts add scale and give the cannon base an intentional seat.
    for index, z in enumerate((-2.70, -1.80, -0.90, 0.0, 0.90, 1.80, 2.70)):
        panel = box("Launch deck | anti-slip grate", (0.0, 0.282, z + 0.15), (3.88, 0.018, 0.67), dark, 0.022)
        for x in range(-8, 9):
            box("Launch deck | grate rib", (x * 0.22, 0.296, z + 0.15), (0.025, 0.012, 0.54), steel, 0.006)
        if index in (0, 6):
            for stripe in range(5):
                box("Launch deck | hazard dash", (-1.35 + stripe * 0.17, 0.298, z + 0.15), (0.10, 0.014, 0.48), amber, 0.008)


def add_access_stairs(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats[:7]
    # Five compact anti-slip steps bridge the concrete pad and the armored skid.
    stair_z = 0.22
    for index in range(5):
        x = 3.55 - index * 0.20
        y = 0.035 + index * 0.048
        box("Launch access | steel step", (x, y, stair_z), (0.27, 0.065, 1.12), dark, 0.025)
        box("Launch access | amber nosing", (x - 0.12, y + 0.037, stair_z), (0.035, 0.016, 1.02), amber, 0.008)
        for z_side in (-0.45, 0.45):
            common.fastener("Launch access | step bolt", (x, y + 0.039, stair_z + z_side), (0.0, 1.0, 0.0), 0.022, steel)
    # Box stringers and handrails give the steps a convincing load path.
    for side in (-1, 1):
        z = stair_z + side * 0.66
        rod("Launch access | stair stringer", (3.90, 0.015, z), (2.28, 0.26, z), 0.075, blue)
        rod("Launch access | handrail upright", (3.82, 0.10, z), (3.82, 0.74, z), 0.045, steel)
        rod("Launch access | handrail upright", (2.38, 0.24, z), (2.38, 0.74, z), 0.045, steel)
        rod("Launch access | amber handrail", (3.82, 0.74, z), (2.38, 0.74, z), 0.035, copper)


def add_warehouse_shells(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats[:7]
    for side in (-1, 1):
        x, z = side * 14.3, -51.5
        # Heavy service hangar with layered facade plates, buttresses, and roof plant.
        box("Range service hangar | main shell", (x, 2.8, z), (5.6, 5.6, 7.4), dark, 0.20)
        box("Range service hangar | roof cap", (x, 5.68, z), (6.08, 0.20, 7.78), blue, 0.11)
        box("Range service hangar | front facade", (x, 2.78, -47.74), (5.28, 5.34, 0.16), blue, 0.10)
        for panel_x in (-2.28, -1.52, -0.76, 0.0, 0.76, 1.52, 2.28):
            box("Hangar | vertical cladding rib", (x + panel_x, 2.82, -47.63), (0.055, 5.0, 0.065), steel, 0.018)
        # Large recessed vehicle doors make the structure read as a working facility.
        box("Hangar | cargo door gasket", (x, 2.15, -47.61), (2.36, 3.45, 0.11), dark, 0.07)
        box("Hangar | cargo door leaf", (x, 2.15, -47.535), (2.12, 3.20, 0.08), enamel, 0.055)
        for index in range(6):
            box("Hangar | cargo door rib", (x, 0.82 + index * 0.48, -47.47), (1.94, 0.055, 0.035), steel, 0.015)
        for side_offset in (-1.0, 1.0):
            box("Hangar | cyan window band", (x + side_offset * 1.82, 3.72, -47.55), (0.48, 0.42, 0.06), screen, 0.035)
            box("Hangar | warning stripe", (x + side_offset * 1.82, 1.0, -47.54), (0.52, 0.10, 0.07), amber, 0.025)
            # Side buttresses and accessible pipework.
            box("Hangar | outer buttress", (x + side_offset * 2.66, 2.82, z), (0.26, 5.5, 7.15), blue, 0.065)
            rod("Hangar | vertical process pipe", (x + side_offset * 2.85, 0.3, -54.3), (x + side_offset * 2.85, 4.8, -54.3), 0.075, copper)
            for y in (0.60, 4.45):
                common.torus("Hangar | process pipe clamp", (x + side_offset * 2.85, y, -54.3), 0.095, 0.022, steel)
        # Roof machinery and a short radio mast silhouette the horizon.
        for offset in (-1.70, 1.70):
            box("Hangar | rooftop HVAC plinth", (x + offset, 5.88, z), (1.18, 0.32, 1.52), dark, 0.08)
            for vent in range(5):
                box("Hangar | HVAC cooling fin", (x + offset, 6.12, z - 0.54 + vent * 0.27), (0.94, 0.045, 0.045), steel, 0.012)
        rod("Hangar | antenna mast", (x + side * 1.25, 5.78, z + 0.35), (x + side * 1.25, 8.55, z + 0.35), 0.045, steel, 16)
        for y in (6.45, 7.12, 7.78, 8.38):
            rod("Hangar | antenna crossarm", (x + side * 1.25 - 0.52, y, z + 0.35), (x + side * 1.25 + 0.52, y, z + 0.35), 0.024, copper, 12)
        face_light("Hangar | aviation beacon", (x + side * 1.25, 8.58, z + 0.35), 0.10, amber)


def add_console(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats[:7]
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
    dark, steel, blue, enamel, screen, amber, copper = mats[:7]
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
    dark, steel, blue, enamel, screen, amber, copper = mats[:7]
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


def add_equipment_crates(mats):
    dark, steel, blue, enamel, screen, amber, copper = mats[:7]
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
    concrete = common.material("Launch pad | weathered concrete", (0.19, 0.22, 0.23), 0.04, 0.86)
    mats = (dark, steel, blue, enamel, screen, amber, copper, concrete)
    add_launch_deck(mats)
    add_access_stairs(mats)
    add_console(mats)
    add_warehouse_shells(mats)
    add_flood_towers(mats)
    add_fencing(mats)
    add_equipment_crates(mats)

    # Apply bevels, then merge each material family to keep mobile draw calls low.
    for obj in list(bpy.data.objects):
        if obj.type == "MESH":
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.convert(target="MESH")
    for mat in mats:
        family = [
            obj for obj in bpy.data.objects
            if obj.type == "MESH" and mat in obj.data.materials[:]
        ]
        if len(family) > 1:
            bpy.ops.object.select_all(action="DESELECT")
            for obj in family:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = family[0]
            bpy.ops.object.join()
            family[0].name = "Range geometry | " + mat.name

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
