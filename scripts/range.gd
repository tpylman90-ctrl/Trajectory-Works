extends Node3D

const RANGE_LENGTH := 2000.0
const AIR_DENSITY := 1.225
const SEA_LEVEL_SOUND_SPEED := 343.0
const AIR_GAS_CONSTANT := 287.05
const AIR_GAMMA := 1.4
const AIR_GRAVITY := 9.80665
const EARTH_RADIUS := 6371000.0
const MAX_SHOT_FLIGHT_TIME := 900.0
const MAX_SHOT_TRAVEL := 2500000.0
const PROJECTILE_TYPES := [
	{"name": "Dense slug", "mass": 42.0, "diameter": 0.18, "cd": 0.24, "shape": "slug", "length": 0.54, "color": Color(0.67, 0.78, 0.83)},
	{"name": "Training sphere", "mass": 24.0, "diameter": 0.20, "cd": 0.47, "shape": "sphere", "length": 0.20, "color": Color(0.86, 0.90, 0.88)},
	{"name": "Drag shuttle", "mass": 12.0, "diameter": 0.15, "cd": 0.92, "shape": "shuttle", "length": 0.375, "color": Color(1.0, 0.54, 0.18)},
]

var camera: Camera3D
var camera_focus := Vector3(0.0, 1.8, -16.0)
var camera_yaw := 0.20
var camera_pitch := 0.24
var camera_distance := 34.0
var status_label: Label
var analysis_label: Label
var projectile_picker: OptionButton
var current_projectile: Dictionary = {}
var custom_round_active := false
var round_editor_screen: Control
var round_preview_spin: Node3D
var round_preview_model: MeshInstance3D
var round_preview_view: SubViewport
var round_nose_picker: OptionButton
var round_material_picker: OptionButton
var round_diameter_slider: HSlider
var round_length_slider: HSlider
var round_dimensions_label: Label
var round_mass_label: Label
var round_volume_label: Label
var round_material_label: Label
var round_preview_container: SubViewportContainer
var round_station_slider: HSlider
var round_station_label: Label
var round_sculpt_hint: Label
var round_surface_picker: OptionButton
var round_rib_count_slider: HSlider
var round_rib_depth_slider: HSlider
var round_spiral_turns_slider: HSlider
var round_surface_info: Label
var round_mode_buttons: Array[Button] = []
var round_mode := "pull"
var round_drag_active := false
var round_last_pointer := Vector2.ZERO
var speed_slider: HSlider
var elevation_slider: HSlider
var wind_slider: HSlider
var target_distance_picker: OptionButton
var target_distance_label: Label
var active_target: Node3D
var target_distance_m := 2000
var projectile_camera_button: Button
var projectile_camera_enabled := false
var followed_projectile: RigidBody3D
var last_projectile: RigidBody3D
var projectile_flow_material: StandardMaterial3D
var speed_value_label: Label
var elevation_value_label: Label
var wind_value_label: Label
var shot_count := 0
var camera_dragging := false
var active_shots: Dictionary = {}
var barrel_pivot: Node3D
var barrel_pivot_base_rotation := Vector3.ZERO
var ground_visual: MeshInstance3D
var ground_mesh: PlaneMesh
var ground_render_size := 100000.0
var ground_home := Vector3(0.0, -0.12, 0.0)

const ROUND_NOSES := ["Ogive", "Conical", "Round", "Flat"]
const ROUND_MATERIALS := [
	{"name": "Aluminum alloy", "density": 2700.0, "color": Color(0.58, 0.69, 0.73)},
	{"name": "Steel", "density": 7850.0, "color": Color(0.40, 0.51, 0.58)},
	{"name": "Copper alloy", "density": 8960.0, "color": Color(0.72, 0.32, 0.15)},
	{"name": "Tungsten alloy", "density": 18000.0, "color": Color(0.25, 0.31, 0.37)},
]


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	_build_world()
	_build_cannon()
	_add_ambient_steam()
	_build_range()
	_build_range_details()
	_build_range_assets()
	current_projectile = PROJECTILE_TYPES[0].duplicate(true)
	_load_saved_round()
	_build_hud()
	set_physics_process(true)


func _build_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_shader := Shader.new()
	sky_shader.code = """shader_type sky;
uniform vec3 sky_top : source_color = vec3(0.012, 0.022, 0.052);
uniform vec3 sky_horizon : source_color = vec3(0.12, 0.16, 0.23);
uniform vec3 cloud_color : source_color = vec3(0.19, 0.22, 0.29);
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
void sky() {
	vec3 direction = normalize(EYEDIR);
	float elevation = clamp(direction.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 base = mix(sky_horizon, sky_top, smoothstep(0.12, 0.94, elevation));
	vec2 cloud_uv = direction.xz * 18.0 / max(direction.y + 0.32, 0.18);
	float cloud_shape = noise2d(cloud_uv * 0.22) * 0.68
		+ noise2d(cloud_uv * 0.72 + vec2(8.3, 2.7)) * 0.32;
	float cloud_cover = smoothstep(0.37, 0.68, cloud_shape);
	float cloud_band = smoothstep(-0.04, 0.24, direction.y) * (1.0 - smoothstep(0.58, 0.88, direction.y));
	float lower_atmosphere = 1.0 - smoothstep(-0.10, 0.10, direction.y);
	base = mix(vec3(0.055, 0.085, 0.11), base, 1.0 - lower_atmosphere);
	base = mix(base, cloud_color, cloud_cover * cloud_band * 0.82);
	float dusk_glow = pow(1.0 - clamp(abs(direction.y), 0.0, 1.0), 7.0) * (1.0 - cloud_cover * 0.72);
	base += vec3(0.085, 0.032, 0.012) * dusk_glow;
	COLOR = base;
}
"""
	var sky_material := ShaderMaterial.new()
	sky_material.shader = sky_shader
	environment.sky.sky_material = sky_material
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.24, 0.31, 0.43)
	environment.ambient_light_energy = 0.46
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.095, 0.13, 0.19)
	# Keep the 2 km instrumentation visible while preserving a soft distance haze.
	environment.fog_density = 0.00072
	environment.fog_sun_scatter = 0.035
	# Mobile rendering does not support volumetric fog; Forward+ desktops get the real volume.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		environment.volumetric_fog_enabled = true
		environment.volumetric_fog_density = 0.015
		environment.volumetric_fog_length = 110.0
		environment.volumetric_fog_detail_spread = 2.2
		environment.volumetric_fog_albedo = Color(0.36, 0.43, 0.53)
		environment.volumetric_fog_emission = Color(0.012, 0.02, 0.04)
		environment.volumetric_fog_emission_energy = 0.35
	environment.glow_enabled = true
	for level in range(7):
		environment.set_glow_level(level, 0.0)
	environment.set_glow_level(0, 0.34)
	environment.set_glow_level(1, 0.19)
	environment.set_glow_level(2, 0.07)
	environment.glow_intensity = 0.86
	environment.glow_strength = 0.92
	environment.glow_bloom = 0.045
	environment.glow_hdr_threshold = 1.25
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.55, 0.34)
	sun.light_energy = 0.62
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 43.0
	camera.far = 110000.0
	add_child(camera)
	_update_camera()
	camera.make_current()

	ground_visual = MeshInstance3D.new()
	ground_visual.name = "Projectile-following render ground"
	ground_mesh = PlaneMesh.new()
	# One large shader-driven tile follows the projectile so the horizon never exposes a board edge.
	ground_mesh.size = Vector2(100000.0, 100000.0)
	ground_visual.mesh = ground_mesh
	ground_visual.position = ground_home
	ground_visual.material_override = _ground_material()
	add_child(ground_visual)
	var ground_body := StaticBody3D.new()
	ground_body.name = "Continuous long-range collision floor"
	ground_body.position = Vector3(0.0, -0.12, 0.0)
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(5000000.0, 0.2, 5000000.0)
	ground_collision.shape = ground_shape
	ground_body.add_child(ground_collision)
	add_child(ground_body)


func _build_cannon() -> void:
	# Only use the Blender model when Godot imports it in the expected orientation
	# and at the expected scale. A bad transform otherwise leaves the firing deck empty.
	var glb_path := "res://assets/generated/trajectory_cannon.glb"
	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed != null:
			var imported := packed.instantiate() as Node3D
			# The Blender GLB arrives with its long axis on local Y; rotate it onto Godot's -Z firing axis.
			imported.rotation.x = -PI * 0.5
			# Preserve the Blender model's full dimensions; the imported base was being compressed.
			imported.position.y = 0.385
			add_child(imported)
			# Keep the base's authored orientation under the shared import correction:
			# its underside then points down while the emitter remains aligned with the lane.
			var base_assembly := imported.find_child("CannonBaseAssembly", true, false) as Node3D
			if not is_instance_valid(base_assembly):
				push_warning("Cannon base transform group is missing from the imported model.")
			barrel_pivot = imported.find_child("ElevationPivot", true, false) as Node3D
			if is_instance_valid(barrel_pivot):
				barrel_pivot_base_rotation = barrel_pivot.rotation
				barrel_pivot.set_meta("muzzle_offset", -7.24)
			var mesh_points: Array[Vector3] = []
			_collect_mesh_points(imported, Transform3D.IDENTITY, mesh_points)
			if not mesh_points.is_empty():
				var bounds := AABB(mesh_points[0], Vector3.ZERO)
				for point in mesh_points:
					bounds = bounds.expand(point)
				# Rest the generated skid on the launch deck after its axis correction.
				var ground_lift := 0.385 - bounds.position.y
				imported.position.y += ground_lift
				bounds.position += Vector3(0.0, ground_lift, 0.0)
				var looks_like_cannon := bounds.size.x > 1.5 and bounds.size.x < 4.0 and bounds.size.y > 0.9 and bounds.size.y < 3.2 and bounds.size.z > 6.0 and bounds.size.z < 10.0 and bounds.position.z < -5.5
				if looks_like_cannon:
					print("Using Blender cannon; imported bounds: ", bounds)
					return
			push_warning("Blender cannon orientation/scale is invalid; using the built-in cannon model. Imported bounds: %s" % str(_bounds_from_points(mesh_points)))
			imported.queue_free()

	var cannon := Node3D.new()
	cannon.name = "CannonPreview"
	cannon.position.y = 0.385
	add_child(cannon)
	_add_box(cannon, Vector3(0.0, 0.30, 0.5), Vector3(2.8, 0.42, 3.4), Color(0.07, 0.13, 0.19), 0.35, 0.72)
	_add_box(cannon, Vector3(0.0, 0.82, 0.0), Vector3(2.15, 1.65, 1.85), Color(0.10, 0.29, 0.47), 0.28, 0.58)
	_add_box(cannon, Vector3(0.0, 0.92, -1.12), Vector3(1.55, 1.10, 0.55), Color(0.14, 0.37, 0.56), 0.20, 0.55)

	# Barrel elevation pivots about the trunnion; the bore and shot direction share it.
	barrel_pivot = Node3D.new()
	barrel_pivot.name = "ElevationPivot"
	barrel_pivot.position = Vector3(0.0, 1.47, 0.18)
	barrel_pivot.set_meta("muzzle_offset", -7.16)
	barrel_pivot_base_rotation = Vector3.ZERO
	cannon.add_child(barrel_pivot)
	_add_cylinder(barrel_pivot, Vector3(0.0, 0.0, -4.13), 0.36, 5.8, Color(0.42, 0.49, 0.54), 0.22, 0.72, true)
	_add_cylinder(barrel_pivot, Vector3(0.0, 0.0, -7.0), 0.48, 0.38, Color(0.10, 0.16, 0.20), 0.32, 0.48, true)
	_add_cylinder(barrel_pivot, Vector3(0.0, 0.0, -7.16), 0.34, 0.07, Color(0.15, 0.87, 1.0), 0.2, 0.24, true)

	# Exposed copper coil stack and luminous containment bands.
	for i in range(8):
		var z := -0.95 - float(i) * 0.28
		_add_torus(barrel_pivot, Vector3(0.0, 0.0, z - 0.18), 0.48, 0.075, Color(0.77, 0.34, 0.14), 0.26)
	for side in [-1.0, 1.0]:
		_add_cylinder(cannon, Vector3(side * 1.18, 0.55, -0.35), 0.25, 1.3, Color(0.14, 0.43, 0.58), 0.28, 0.5)
		_add_cylinder(cannon, Vector3(side * 1.18, 1.15, -0.35), 0.32, 0.12, Color(0.78, 0.40, 0.18), 0.27, 0.52)
		_add_pipe(cannon, Vector3(side * 0.86, 0.32, 0.65), Vector3(side * 1.12, 0.45, -0.15), 0.075, Color(0.58, 0.68, 0.70))
		_add_pipe(cannon, Vector3(side * 1.12, 0.45, -0.15), Vector3(side * 0.92, 0.78, -1.35), 0.075, Color(0.78, 0.39, 0.17))
	_add_box(cannon, Vector3(0.0, 1.70, 0.12), Vector3(0.90, 0.16, 0.62), Color(0.12, 0.82, 0.95), 0.08, 0.24)
	_add_box(cannon, Vector3(0.0, 0.30, -2.1), Vector3(1.15, 0.42, 1.0), Color(0.16, 0.21, 0.24), 0.14, 0.68)


func _collect_mesh_points(node: Node3D, parent_transform: Transform3D, points: Array[Vector3]) -> void:
	var node_transform := parent_transform * node.transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_bounds: AABB = (node as MeshInstance3D).get_aabb()
		for x in [mesh_bounds.position.x, mesh_bounds.end.x]:
			for y in [mesh_bounds.position.y, mesh_bounds.end.y]:
				for z in [mesh_bounds.position.z, mesh_bounds.end.z]:
					points.append(node_transform * Vector3(x, y, z))
	for child in node.get_children():
		if child is Node3D:
			_collect_mesh_points(child as Node3D, node_transform, points)


func _bounds_from_points(points: Array[Vector3]) -> AABB:
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds


func _build_range() -> void:
	for distance in [12.0, 24.0, 38.0]:
		_add_box(self, Vector3(0.0, 0.015, -distance), Vector3(0.22, 0.03, 1.0), Color(0.78, 0.83, 0.80), 0.0, 0.9)
		_add_box(self, Vector3(0.0, 0.12, -distance), Vector3(4.2, 0.24, 0.14), Color(0.12, 0.18, 0.22), 0.03, 0.7)
		_add_box(self, Vector3(-1.95, 0.22, -distance), Vector3(0.12, 0.42, 0.18), Color(0.92, 0.55, 0.12), 0.02, 0.58)
		_add_box(self, Vector3(1.95, 0.22, -distance), Vector3(0.12, 0.42, 0.18), Color(0.92, 0.55, 0.12), 0.02, 0.58)
	_add_box(self, Vector3(-8.0, 0.025, -24.0), Vector3(0.12, 0.05, 48.0), Color(0.96, 0.48, 0.10), 0.0, 0.7)
	_add_box(self, Vector3(8.0, 0.025, -24.0), Vector3(0.12, 0.05, 48.0), Color(0.96, 0.48, 0.10), 0.0, 0.7)
	# Extend the launch lane into a measured 2 km ballistic course.
	for side in [-1.0, 1.0]:
		for segment in range(10):
			var center_z := -100.0 - float(segment) * 200.0
			_add_box(self, Vector3(side * 9.2, 0.36, center_z), Vector3(0.22, 0.72, 199.0), Color(0.09, 0.17, 0.22), 0.42, 0.46)
			_add_box(self, Vector3(side * 9.2, 0.74, center_z), Vector3(0.25, 0.045, 199.0), Color(1.0, 0.42, 0.10), 0.1, 0.36)
	for distance in range(250, 2001, 250):
		_add_box(self, Vector3(0.0, 0.02, -float(distance)), Vector3(0.28, 0.035, 2.2), Color(0.84, 0.89, 0.88), 0.05, 0.62)
		_add_box(self, Vector3(0.0, 0.13, -float(distance)), Vector3(4.4, 0.26, 0.16), Color(0.09, 0.16, 0.20), 0.25, 0.58)
		var readout := Label3D.new()
		readout.text = "%d M" % distance
		readout.position = Vector3(-9.45, 1.3, -float(distance))
		readout.font_size = 64
		readout.pixel_size = 0.008
		readout.modulate = Color(0.55, 0.85, 0.92)
		readout.outline_size = 8
		add_child(readout)
	# Tall, illuminated sensor portals and staggered target stations provide distance cues.
	for distance in [300.0, 700.0, 1100.0, 1500.0, 1900.0]:
		for side in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 8.0, 5.0, -distance), Vector3(0.18, 10.0, 0.22), Color(0.10, 0.18, 0.23), 0.34, 0.5)
			_add_box(self, Vector3(side * 8.0, 9.98, -distance), Vector3(0.24, 0.06, 0.26), Color(1.0, 0.36, 0.12), 0.08, 0.36)
		_add_box(self, Vector3(0.0, 10.02, -distance), Vector3(16.0, 0.16, 0.22), Color(0.12, 0.20, 0.24), 0.36, 0.5)
		_add_box(self, Vector3(0.0, 10.12, -distance), Vector3(3.2, 0.035, 0.25), Color(0.12, 0.84, 0.98), 0.04, 0.28)
	# Keep one selectable target on the lane so the player can place it beyond a long shot.
	active_target = _add_target(Vector3(0.0, 3.2, -float(target_distance_m)), 2.5)


func _add_ambient_steam() -> void:
	for side in [-1.0, 1.0]:
		_create_steam_emitter(self, Vector3(side * 1.25, 0.46, 0.42), 22)
	if is_instance_valid(barrel_pivot):
		_create_steam_emitter(barrel_pivot, Vector3(0.43, -0.18, -1.55), 18)
		_create_steam_emitter(barrel_pivot, Vector3(-0.43, -0.18, -1.55), 18)


func _create_steam_emitter(parent: Node3D, at: Vector3, particle_count: int) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "Slow ambient pressure steam"
	particles.position = at
	particles.amount = particle_count
	particles.lifetime = 3.8
	particles.preprocess = 1.4
	particles.explosiveness = 0.0
	particles.randomness = 0.18
	particles.visibility_aabb = AABB(Vector3(-2.5, -0.5, -2.5), Vector3(5.0, 5.0, 5.0))
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 1.0, 0.0)
	process.spread = 24.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.24
	process.gravity = Vector3(0.0, 0.035, 0.0)
	process.scale_min = 0.10
	process.scale_max = 0.27
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process.emission_sphere_radius = 0.045
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.12, 0.72, 1.0])
	fade.colors = PackedColorArray([
		Color(0.75, 0.84, 0.90, 0.0),
		Color(0.75, 0.84, 0.90, 0.16),
		Color(0.70, 0.80, 0.87, 0.08),
		Color(0.65, 0.76, 0.84, 0.0)
	])
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = fade
	process.color_ramp = color_ramp
	particles.process_material = process
	var puff := SphereMesh.new()
	puff.radius = 0.15
	puff.height = 0.30
	puff.radial_segments = 8
	puff.rings = 4
	var puff_material := StandardMaterial3D.new()
	puff_material.albedo_color = Color(0.72, 0.82, 0.88, 0.20)
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_material.roughness = 1.0
	puff.material = puff_material
	particles.draw_pass_1 = puff
	parent.add_child(particles)


func _add_light_shaft(origin: Vector3, target: Vector3, color: Color) -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "Mobile compatible floodlight shaft"
	var cone := CylinderMesh.new()
	cone.top_radius = 0.025
	cone.bottom_radius = 2.8
	cone.height = 27.0
	cone.radial_segments = 24
	shaft.mesh = cone
	var direction := (target - origin).normalized()
	shaft.position = origin + direction * (cone.height * 0.5)
	shaft.quaternion = Quaternion(Vector3.UP, -direction)
	var shaft_shader := Shader.new()
	shaft_shader.code = """shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform vec4 shaft_color : source_color = vec4(1.0, 0.58, 0.34, 0.035);
void fragment() {
	float fade_ends = smoothstep(0.02, 0.20, UV.y) * (1.0 - smoothstep(0.78, 1.0, UV.y));
	float soft_pulse = 0.82 + 0.18 * sin(UV.x * TAU);
	ALBEDO = shaft_color.rgb;
	ALPHA = shaft_color.a * fade_ends * soft_pulse;
}
"""
	var shaft_material := ShaderMaterial.new()
	shaft_material.shader = shaft_shader
	shaft_material.set_shader_parameter("shaft_color", Color(color.r, color.g, color.b, 0.038))
	shaft.material_override = shaft_material
	add_child(shaft)


func _add_hud_corner_marks(layer: CanvasLayer, panel: Control) -> void:
	var marks := Control.new()
	marks.name = "Tactical HUD corner marks"
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks.z_index = 8
	layer.add_child(marks)
	for index in 8:
		var bar := ColorRect.new()
		bar.color = Color(0.38, 0.91, 1.0, 0.94)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marks.add_child(bar)
	panel.resized.connect(_sync_hud_corner_marks.bind(panel, marks))
	_sync_hud_corner_marks(panel, marks)


func _sync_hud_corner_marks(panel: Control, marks: Control) -> void:
	marks.position = panel.position
	marks.size = panel.size
	var arm := 16.0
	var inset := 7.0
	for corner in 4:
		var right := corner % 2 == 1
		var bottom := corner >= 2
		var x := marks.size.x - inset - arm if right else inset
		var y := marks.size.y - inset - arm if bottom else inset
		var horizontal := marks.get_child(corner * 2) as ColorRect
		horizontal.position = Vector2(x, y)
		horizontal.size = Vector2(arm, 2.0)
		var vertical := marks.get_child(corner * 2 + 1) as ColorRect
		vertical.position = Vector2(x, y)
		vertical.size = Vector2(2.0, arm)


func _build_range_details() -> void:
	for distance in [-5.0, -10.0, -15.0, -20.0, -25.0, -30.0, -35.0, -40.0, -45.0]:
		_add_box(self, Vector3(0.0, -0.105, distance), Vector3(36.0, 0.012, 0.018), Color(0.075, 0.105, 0.12), 0.22, 0.7)
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 18.0, -0.105, -25.0), Vector3(0.018, 0.012, 50.0), Color(0.075, 0.105, 0.12), 0.22, 0.7)
	# A pair of recessed service trenches and segmented steel covers lead the eye downrange.
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 6.6, 0.018, -27.0), Vector3(0.62, 0.035, 46.0), Color(0.055, 0.078, 0.09), 0.55, 0.64)
		_add_box(self, Vector3(side * 6.6, 0.04, -27.0), Vector3(0.12, 0.025, 46.0), Color(0.90, 0.33, 0.08), 0.28, 0.48)
		for distance in [-8.0, -13.0, -18.0, -23.0, -28.0, -33.0, -38.0, -43.0]:
			_add_box(self, Vector3(side * 6.6, 0.047, distance), Vector3(0.54, 0.022, 0.045), Color(0.25, 0.34, 0.38), 0.68, 0.46)
	# Repeating launch gates and tower-like supports create scale and a vanishing point.
	for distance in [-14.0, -30.0, -46.0]:
		for side in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 9.6, 3.15, distance), Vector3(0.24, 6.3, 0.28), Color(0.075, 0.12, 0.16), 0.62, 0.46)
			_add_box(self, Vector3(side * 9.6, 3.12, distance + 0.16), Vector3(0.055, 5.5, 0.025), Color(0.94, 0.34, 0.08), 0.25, 0.4)
		_add_box(self, Vector3(0.0, 6.15, distance), Vector3(19.2, 0.24, 0.28), Color(0.075, 0.12, 0.16), 0.62, 0.46)
		_add_box(self, Vector3(0.0, 6.0, distance + 0.16), Vector3(18.2, 0.045, 0.035), Color(0.10, 0.66, 0.82), 0.2, 0.35)
	# Side-mounted range lights frame the lane without spanning across the shot path.
	for distance in [-5.0, -22.0, -40.0]:
		for side in [-1.0, 1.0]:
			if distance != -40.0:
				var flood := OmniLight3D.new()
				flood.position = Vector3(side * 9.65, 4.58, distance)
				flood.light_color = Color(1.0, 0.54, 0.30)
				flood.light_energy = 1.15
				flood.omni_range = 10.0
				flood.shadow_enabled = false
				add_child(flood)
				var beam := SpotLight3D.new()
				beam.name = "FloodPoleSpotlight"
				beam.position = Vector3(side * 9.65, 4.55, distance)
				beam.light_color = Color(1.0, 0.59, 0.36)
				beam.light_energy = 4.2
				beam.spot_range = 32.0
				beam.spot_angle = 42.0
				beam.shadow_enabled = false
				if RenderingServer.get_current_rendering_method() == "forward_plus":
					beam.light_volumetric_fog_energy = 2.2
				add_child(beam)
				var beam_target := Vector3(0.0, 0.0, distance - 12.0)
				beam.look_at(beam_target, Vector3.UP)
				_add_light_shaft(beam.global_position, beam_target, beam.light_color)


func _build_range_assets() -> void:
	var path := "res://assets/generated/trajectory_range.glb"
	if not ResourceLoader.exists(path):
		push_warning("Detailed Blender range package is missing.")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		push_warning("Detailed Blender range package could not be loaded.")
		return
	var imported := packed.instantiate() as Node3D
	imported.name = "BlenderRangeSetDressing"
	add_child(imported)
	print("Using detailed Blender range set dressing.")


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(26.0, 22.0)
	panel.custom_minimum_size = Vector2(390.0, 142.0)
	var glass := StyleBoxFlat.new()
	glass.bg_color = Color(0.012, 0.025, 0.039, 0.48)
	glass.border_color = Color(0.22, 0.82, 0.94, 0.78)
	glass.set_border_width_all(1)
	glass.set_corner_radius_all(3)
	glass.shadow_color = Color(0.0, 0.0, 0.0, 0.36)
	glass.shadow_size = 8
	panel.add_theme_stylebox_override("panel", glass)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var title := Label.new()
	title.text = "TRAJECTORY WORKS  /  RANGE 01"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.83, 0.94, 0.98))
	stack.add_child(title)
	status_label = Label.new()
	status_label.text = "HYPERVELOCITY RANGE  •  CROSSWIND: 0.0 M/S"
	status_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.95))
	stack.add_child(status_label)
	var hint := Label.new()
	hint.text = "2 KM COURSE  •  Tune the shot; tap PROJECTILE CAM to ride it"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.75, 0.86, 0.90))
	stack.add_child(hint)
	var selector_style := StyleBoxFlat.new()
	selector_style.bg_color = Color(0.018, 0.052, 0.068, 0.48)
	selector_style.border_color = Color(0.20, 0.72, 0.84, 0.70)
	selector_style.set_border_width_all(1)
	selector_style.set_corner_radius_all(2)
	projectile_picker = OptionButton.new()
	projectile_picker.add_theme_stylebox_override("normal", selector_style)
	projectile_picker.add_theme_stylebox_override("hover", selector_style)
	projectile_picker.add_theme_stylebox_override("pressed", selector_style)
	projectile_picker.add_theme_color_override("font_color", Color(0.83, 0.92, 0.95))
	for projectile_data in PROJECTILE_TYPES:
		projectile_picker.add_item(str(projectile_data.name))
	projectile_picker.add_item("Custom round")
	if custom_round_active:
		projectile_picker.select(PROJECTILE_TYPES.size())
	projectile_picker.item_selected.connect(_on_projectile_preset_selected)
	stack.add_child(projectile_picker)
	target_distance_label = Label.new()
	stack.add_child(target_distance_label)
	target_distance_picker = OptionButton.new()
	target_distance_picker.add_theme_stylebox_override("normal", selector_style)
	target_distance_picker.add_theme_stylebox_override("hover", selector_style)
	target_distance_picker.add_theme_stylebox_override("pressed", selector_style)
	target_distance_picker.add_theme_color_override("font_color", Color(0.83, 0.92, 0.95))
	for distance in range(250, 2001, 250):
		target_distance_picker.add_item("%d M" % distance)
	target_distance_picker.selected = target_distance_picker.item_count - 1
	target_distance_picker.item_selected.connect(_on_target_distance_selected)
	stack.add_child(target_distance_picker)
	_on_target_distance_selected(target_distance_picker.selected)
	speed_value_label = Label.new()
	stack.add_child(speed_value_label)
	speed_slider = HSlider.new()
	speed_slider.min_value = 250.0
	speed_slider.max_value = 3000.0
	speed_slider.step = 25.0
	speed_slider.value = 1800.0
	speed_slider.value_changed.connect(_on_speed_changed)
	stack.add_child(speed_slider)
	elevation_value_label = Label.new()
	stack.add_child(elevation_value_label)
	elevation_slider = HSlider.new()
	elevation_slider.min_value = -1.0
	elevation_slider.max_value = 15.0
	elevation_slider.step = 0.1
	elevation_slider.value = 0.2
	elevation_slider.value_changed.connect(_on_elevation_changed)
	stack.add_child(elevation_slider)
	wind_value_label = Label.new()
	stack.add_child(wind_value_label)
	wind_slider = HSlider.new()
	wind_slider.min_value = -15.0
	wind_slider.max_value = 15.0
	wind_slider.step = 0.5
	wind_slider.value = 0.0
	wind_slider.value_changed.connect(_on_wind_changed)
	stack.add_child(wind_slider)
	analysis_label = Label.new()
	analysis_label.text = "SHOT DATA  •  Awaiting launch"
	analysis_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(analysis_label)
	var fire := Button.new()
	fire.text = "FIRE TEST SHOT"
	fire.custom_minimum_size = Vector2(220.0, 72.0)
	fire.anchor_left = 1.0
	fire.anchor_top = 1.0
	fire.anchor_right = 1.0
	fire.anchor_bottom = 1.0
	fire.offset_left = -246.0
	fire.offset_top = -98.0
	fire.offset_right = -26.0
	fire.offset_bottom = -26.0
	fire.add_theme_font_size_override("font_size", 22)
	var button_normal := StyleBoxFlat.new()
	button_normal.bg_color = Color(0.015, 0.075, 0.095, 0.58)
	button_normal.border_color = Color(0.12, 0.76, 0.91, 0.88)
	button_normal.set_border_width_all(1)
	button_normal.set_corner_radius_all(4)
	var button_hover := StyleBoxFlat.new()
	button_hover.bg_color = Color(0.04, 0.23, 0.29, 0.76)
	button_hover.border_color = Color(0.35, 0.91, 1.0)
	button_hover.set_border_width_all(1)
	button_hover.set_corner_radius_all(4)
	fire.add_theme_stylebox_override("normal", button_normal)
	fire.add_theme_stylebox_override("hover", button_hover)
	fire.add_theme_color_override("font_color", Color(0.55, 0.94, 1.0))
	fire.pressed.connect(_fire_test_shot)
	layer.add_child(fire)
	projectile_camera_button = Button.new()
	projectile_camera_button.text = "PROJECTILE CAM  •  OFF"
	projectile_camera_button.custom_minimum_size = Vector2(220.0, 54.0)
	projectile_camera_button.anchor_left = 1.0
	projectile_camera_button.anchor_top = 1.0
	projectile_camera_button.anchor_right = 1.0
	projectile_camera_button.anchor_bottom = 1.0
	projectile_camera_button.offset_left = -246.0
	projectile_camera_button.offset_top = -162.0
	projectile_camera_button.offset_right = -26.0
	projectile_camera_button.offset_bottom = -108.0
	projectile_camera_button.add_theme_font_size_override("font_size", 18)
	projectile_camera_button.add_theme_stylebox_override("normal", button_normal)
	projectile_camera_button.add_theme_stylebox_override("hover", button_hover)
	projectile_camera_button.add_theme_color_override("font_color", Color(0.55, 0.94, 1.0))
	projectile_camera_button.pressed.connect(_toggle_projectile_camera)
	layer.add_child(projectile_camera_button)
	var edit_round_button := Button.new()
	edit_round_button.text = "EDIT ROUND"
	edit_round_button.custom_minimum_size = Vector2(220.0, 44.0)
	edit_round_button.anchor_left = 1.0
	edit_round_button.anchor_top = 1.0
	edit_round_button.anchor_right = 1.0
	edit_round_button.anchor_bottom = 1.0
	edit_round_button.offset_left = -246.0
	edit_round_button.offset_top = -216.0
	edit_round_button.offset_right = -26.0
	edit_round_button.offset_bottom = -170.0
	edit_round_button.add_theme_font_size_override("font_size", 18)
	edit_round_button.add_theme_stylebox_override("normal", button_normal)
	edit_round_button.add_theme_stylebox_override("hover", button_hover)
	edit_round_button.add_theme_color_override("font_color", Color(0.55, 0.94, 1.0))
	edit_round_button.pressed.connect(_open_round_editor)
	layer.add_child(edit_round_button)
	_on_speed_changed(speed_slider.value)
	_on_elevation_changed(elevation_slider.value)
	_on_wind_changed(wind_slider.value)
	_add_hud_corner_marks(layer, panel)


func _on_projectile_preset_selected(index: int) -> void:
	if index >= PROJECTILE_TYPES.size():
		custom_round_active = true
		return
	custom_round_active = false
	current_projectile = PROJECTILE_TYPES[index].duplicate(true)


func _open_round_editor() -> void:
	if is_instance_valid(round_editor_screen):
		return
	if custom_round_active and not current_projectile.is_empty():
		current_projectile = current_projectile.duplicate(true)
	else:
		current_projectile = PROJECTILE_TYPES[projectile_picker.selected].duplicate(true)
	current_projectile["shape"] = "custom"
	current_projectile["name"] = "Custom round"
	if not current_projectile.has("nose"):
		current_projectile["nose"] = "Ogive"
	if not current_projectile.has("material"):
		current_projectile["material"] = "Steel"
	if not current_projectile.has("density"):
		current_projectile["density"] = 7850.0
	if not current_projectile.has("tip_length"):
		current_projectile["tip_length"] = 0.0
	_ensure_round_stations()
	_build_round_editor()


func _start_fresh_round() -> void:
	var steel: Dictionary = ROUND_MATERIALS[1]
	current_projectile = {
		"name": "Custom round",
		"shape": "custom",
		"diameter": 0.18,
		"length": 0.54,
		"nose": "Ogive",
		"material": str(steel.name),
		"density": float(steel.density),
		"color": steel.color,
		"tip_length": 0.243,
		"cd": _round_drag_coefficient("Ogive"),
		"surface_pattern": "smooth",
		"rib_count": 6,
		"rib_depth": 0.0,
		"spiral_turns": 0.0,
	}
	_ensure_round_stations()
	custom_round_active = true
	round_mode = "pull"
	for mode_button in round_mode_buttons:
		mode_button.button_pressed = mode_button.text == "PULL"
	if is_instance_valid(round_station_slider):
		round_station_slider.set_value_no_signal(4.0)
		_on_round_station_changed(4.0)
	if is_instance_valid(round_preview_spin):
		round_preview_spin.rotation = Vector3.ZERO
	if is_instance_valid(round_surface_picker):
		round_surface_picker.select(0)
	if is_instance_valid(round_rib_count_slider):
		round_rib_count_slider.set_value_no_signal(6.0)
	if is_instance_valid(round_rib_depth_slider):
		round_rib_depth_slider.set_value_no_signal(0.0)
	if is_instance_valid(round_spiral_turns_slider):
		round_spiral_turns_slider.set_value_no_signal(0.0)
	_set_round_sculpt_mode("pull")
	if is_instance_valid(round_nose_picker):
		round_nose_picker.select(0)
	if is_instance_valid(round_material_picker):
		round_material_picker.select(1)
	if is_instance_valid(round_diameter_slider):
		round_diameter_slider.set_value_no_signal(180.0)
	if is_instance_valid(round_length_slider):
		round_length_slider.set_value_no_signal(540.0)
	_on_round_design_changed(0.0)


func _build_round_editor() -> void:
	var layer := get_node_or_null("RoundEditorLayer") as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "RoundEditorLayer"
		layer.layer = 10
		add_child(layer)
	round_editor_screen = Control.new()
	round_editor_screen.name = "RoundEditingPage"
	round_editor_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	round_editor_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(round_editor_screen)

	var background := ColorRect.new()
	background.color = Color(0.012, 0.022, 0.034, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	round_editor_screen.add_child(background)

	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margins.add_theme_constant_override("margin_left", 26)
	margins.add_theme_constant_override("margin_right", 26)
	margins.add_theme_constant_override("margin_top", 18)
	margins.add_theme_constant_override("margin_bottom", 18)
	round_editor_screen.add_child(margins)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 14)
	margins.add_child(page)

	var header := HBoxContainer.new()
	page.add_child(header)
	var title := Label.new()
	title.text = "PROJECTILE LAB  /  ROUND DESIGN"
	title.add_theme_font_size_override("font_size", 25)
	title.add_theme_color_override("font_color", Color(0.78, 0.94, 0.98))
	header.add_child(title)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_spacer)
	var return_button := Button.new()
	return_button.text = "SAVE & RETURN TO RANGE"
	return_button.custom_minimum_size = Vector2(260.0, 48.0)
	return_button.add_theme_font_size_override("font_size", 17)
	return_button.pressed.connect(_close_round_editor)
	header.add_child(return_button)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	page.add_child(body)

	var editor_card := PanelContainer.new()
	editor_card.custom_minimum_size = Vector2(390.0, 0.0)
	editor_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(editor_card)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.018, 0.044, 0.061, 0.92)
	card_style.border_color = Color(0.12, 0.68, 0.82, 0.78)
	card_style.set_border_width_all(1)
	card_style.set_corner_radius_all(5)
	editor_card.add_theme_stylebox_override("panel", card_style)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor_card.add_child(scroll)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 7)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)

	var instructions := Label.new()
	instructions.text = "Shape the round. Geometry and material set mass; nose profile sets drag."
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_color_override("font_color", Color(0.70, 0.84, 0.89))
	form.add_child(instructions)
	var fresh_round_button := Button.new()
	fresh_round_button.text = "START FRESH ROUND"
	fresh_round_button.custom_minimum_size.y = 42.0
	fresh_round_button.add_theme_color_override("font_color", Color(0.55, 0.94, 1.0))
	fresh_round_button.pressed.connect(_start_fresh_round)
	form.add_child(fresh_round_button)

	var nose_label := Label.new()
	nose_label.text = "NOSE PROFILE"
	form.add_child(nose_label)
	round_nose_picker = OptionButton.new()
	for nose_name in ROUND_NOSES:
		round_nose_picker.add_item(nose_name)
	round_nose_picker.selected = max(ROUND_NOSES.find(str(current_projectile.get("nose", "Ogive"))), 0)
	form.add_child(round_nose_picker)

	var material_label := Label.new()
	material_label.text = "BODY MATERIAL"
	form.add_child(material_label)
	round_material_picker = OptionButton.new()
	for material_data in ROUND_MATERIALS:
		round_material_picker.add_item(str(material_data.name))
	var initial_material := 1
	for material_index in ROUND_MATERIALS.size():
		if ROUND_MATERIALS[material_index].name == str(current_projectile.get("material", "Steel")):
			initial_material = material_index
	round_material_picker.selected = initial_material
	form.add_child(round_material_picker)

	var sculpt_title := Label.new()
	sculpt_title.text = "FREEFORM SHAPING"
	sculpt_title.add_theme_color_override("font_color", Color(0.45, 0.86, 0.95))
	form.add_child(sculpt_title)
	var sculpt_modes := HBoxContainer.new()
	sculpt_modes.add_theme_constant_override("separation", 4)
	form.add_child(sculpt_modes)
	var sculpt_mode_group := ButtonGroup.new()
	round_mode_buttons.clear()
	for mode_name in ["PULL", "BEND", "TWIST", "ORBIT"]:
		var mode_button := Button.new()
		mode_button.text = mode_name
		mode_button.toggle_mode = true
		mode_button.button_group = sculpt_mode_group
		mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mode_button.button_pressed = mode_name == "PULL"
		mode_button.pressed.connect(_set_round_sculpt_mode.bind(mode_name.to_lower()))
		round_mode_buttons.append(mode_button)
		sculpt_modes.add_child(mode_button)
	round_station_label = Label.new()
	form.add_child(round_station_label)
	round_station_slider = HSlider.new()
	round_station_slider.min_value = 0
	round_station_slider.max_value = 8
	round_station_slider.step = 1
	round_station_slider.value = 4
	round_station_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	round_station_slider.value_changed.connect(_on_round_station_changed)
	form.add_child(round_station_slider)
	round_sculpt_hint = Label.new()
	round_sculpt_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	round_sculpt_hint.add_theme_color_override("font_color", Color(0.70, 0.84, 0.89))
	form.add_child(round_sculpt_hint)
	var surface_title := Label.new()
	surface_title.text = "RIBS, GROOVES & SPIRAL"
	surface_title.add_theme_color_override("font_color", Color(0.45, 0.86, 0.95))
	form.add_child(surface_title)
	round_surface_picker = OptionButton.new()
	round_surface_picker.add_item("Smooth jacket")
	round_surface_picker.add_item("Raised helical ribs")
	round_surface_picker.add_item("Cut helical grooves")
	form.add_child(round_surface_picker)
	round_rib_count_slider = _add_round_editor_slider(form, "RIB / GROOVE COUNT", 3.0, 12.0, 1.0, float(current_projectile.get("rib_count", 6)))
	round_rib_depth_slider = _add_round_editor_slider(form, "RIDGE / GROOVE DEPTH (MM)", 0.0, 8.0, 0.25, float(current_projectile.get("rib_depth", 0.002)) * 1000.0)
	round_spiral_turns_slider = _add_round_editor_slider(form, "HELIX TURNS OVER BODY", -3.0, 3.0, 0.25, float(current_projectile.get("spiral_turns", 0.0)))
	round_surface_info = Label.new()
	round_surface_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	round_surface_info.add_theme_color_override("font_color", Color(0.70, 0.84, 0.89))
	form.add_child(round_surface_info)
	round_diameter_slider = _add_round_editor_slider(form, "BODY DIAMETER", 80.0, 320.0, 5.0, float(current_projectile.get("diameter", 0.18)) * 1000.0)
	round_length_slider = _add_round_editor_slider(form, "OVERALL LENGTH", 250.0, 1250.0, 25.0, maxf(float(current_projectile.get("length", 0.54)), 0.25) * 1000.0)
	round_dimensions_label = Label.new()
	round_dimensions_label.add_theme_color_override("font_color", Color(0.45, 0.86, 0.95))
	form.add_child(round_dimensions_label)
	round_mass_label = Label.new()
	round_mass_label.add_theme_font_size_override("font_size", 23)
	round_mass_label.add_theme_color_override("font_color", Color(0.96, 0.67, 0.29))
	form.add_child(round_mass_label)
	round_volume_label = Label.new()
	form.add_child(round_volume_label)
	round_material_label = Label.new()
	form.add_child(round_material_label)

	var preview_column := VBoxContainer.new()
	preview_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(preview_column)
	var preview_title := Label.new()
	preview_title.text = "LIVE 3D ROUND  •  TOUCH DRAG TO SCULPT"
	preview_title.add_theme_color_override("font_color", Color(0.47, 0.83, 0.92))
	preview_column.add_child(preview_title)
	var preview_frame := PanelContainer.new()
	preview_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_column.add_child(preview_frame)
	var preview_frame_style := StyleBoxFlat.new()
	preview_frame_style.bg_color = Color(0.023, 0.038, 0.055, 1.0)
	preview_frame_style.border_color = Color(0.10, 0.54, 0.67, 0.62)
	preview_frame_style.set_border_width_all(1)
	preview_frame_style.set_corner_radius_all(4)
	preview_frame.add_theme_stylebox_override("panel", preview_frame_style)
	round_preview_container = SubViewportContainer.new()
	var viewport_container := round_preview_container
	viewport_container.mouse_filter = Control.MOUSE_FILTER_STOP
	viewport_container.gui_input.connect(_on_round_preview_input)
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.stretch = true
	preview_frame.add_child(viewport_container)
	round_preview_view = SubViewport.new()
	round_preview_view.size = Vector2i(720, 480)
	round_preview_view.own_world_3d = true
	round_preview_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(round_preview_view)
	_build_round_preview_scene()
	_refresh_round_design()

	var footer := Label.new()
	footer.text = "SELECT A STATION, THEN DRAG THE ROUND: PULL CHANGES WIDTH  •  BEND MOVES THE CENTERLINE  •  TWIST ADDS SPIRAL FLUTES"
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_color_override("font_color", Color(0.52, 0.71, 0.78))
	preview_column.add_child(footer)

	round_nose_picker.item_selected.connect(_on_round_design_changed)
	round_material_picker.item_selected.connect(_on_round_material_changed)
	round_diameter_slider.value_changed.connect(_on_round_design_changed)
	round_length_slider.value_changed.connect(_on_round_design_changed)
	round_surface_picker.item_selected.connect(_on_round_surface_changed)
	round_rib_count_slider.value_changed.connect(_on_round_surface_changed)
	round_rib_depth_slider.value_changed.connect(_on_round_surface_changed)
	round_spiral_turns_slider.value_changed.connect(_on_round_surface_changed)
	round_surface_picker.select(clampi(1 if str(current_projectile.get("surface_pattern", "smooth")) == "ridges" else (2 if str(current_projectile.get("surface_pattern", "smooth")) == "grooves" else 0), 0, 2))
	_on_round_surface_changed(0.0)
	_on_round_station_changed(round_station_slider.value)
	_on_round_design_changed(0.0)


func _add_round_editor_slider(parent: VBoxContainer, caption: String, minimum: float, maximum: float, step: float, initial: float) -> HSlider:
	var label := Label.new()
	label.text = caption
	label.add_theme_color_override("font_color", Color(0.79, 0.87, 0.90))
	parent.add_child(label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = clampf(initial, minimum, maximum)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 30.0
	parent.add_child(slider)
	return slider


func _build_round_preview_scene() -> void:
	var preview_world := Node3D.new()
	preview_world.name = "RoundPreviewWorld"
	round_preview_view.add_child(preview_world)
	var preview_environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.023, 0.038, 0.055)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.48, 0.57, 0.68)
	env.ambient_light_energy = 0.72
	preview_environment.environment = env
	preview_world.add_child(preview_environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -28.0, 0.0)
	key.light_color = Color(0.67, 0.84, 1.0)
	key.light_energy = 1.25
	preview_world.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.0, 1.2, -1.4)
	rim.light_color = Color(0.12, 0.72, 0.92)
	rim.light_energy = 2.0
	rim.omni_range = 5.0
	rim.shadow_enabled = false
	preview_world.add_child(rim)
	var pedestal := MeshInstance3D.new()
	var pedestal_mesh := CylinderMesh.new()
	pedestal_mesh.top_radius = 0.34
	pedestal_mesh.bottom_radius = 0.37
	pedestal_mesh.height = 0.035
	pedestal_mesh.radial_segments = 48
	pedestal.mesh = pedestal_mesh
	pedestal.position = Vector3(0.0, -0.42, 0.0)
	pedestal.material_override = _material(Color(0.08, 0.16, 0.20), 0.78, 0.34)
	preview_world.add_child(pedestal)
	var accent := MeshInstance3D.new()
	var accent_mesh := TorusMesh.new()
	accent_mesh.inner_radius = 0.33
	accent_mesh.outer_radius = 0.345
	accent_mesh.rings = 48
	accent_mesh.ring_segments = 12
	accent.mesh = accent_mesh
	accent.position = Vector3(0.0, -0.395, 0.0)
	accent.rotation.x = PI * 0.5
	accent.material_override = _material(Color(0.10, 0.63, 0.78), 0.62, 0.3)
	preview_world.add_child(accent)
	round_preview_spin = Node3D.new()
	preview_world.add_child(round_preview_spin)
	var preview_camera := Camera3D.new()
	preview_camera.position = Vector3(1.05, 0.78, 1.60)
	preview_camera.fov = 32.0
	preview_camera.current = true
	preview_world.add_child(preview_camera)
	preview_camera.look_at(Vector3.ZERO, Vector3.UP)




func _on_round_design_changed(_value: float) -> void:
	if not is_instance_valid(round_diameter_slider) or not is_instance_valid(round_length_slider):
		return
	var nose_index := round_nose_picker.selected if is_instance_valid(round_nose_picker) else 0
	var material_index := round_material_picker.selected if is_instance_valid(round_material_picker) else 1
	var material_data: Dictionary = ROUND_MATERIALS[clampi(material_index, 0, ROUND_MATERIALS.size() - 1)]
	current_projectile["shape"] = "custom"
	current_projectile["name"] = "Custom round"
	current_projectile["diameter"] = round_diameter_slider.value / 1000.0
	current_projectile["length"] = round_length_slider.value / 1000.0
	current_projectile["nose"] = ROUND_NOSES[clampi(nose_index, 0, ROUND_NOSES.size() - 1)]
	current_projectile["material"] = material_data.name
	current_projectile["density"] = material_data.density
	current_projectile["color"] = material_data.color
	var radius := float(current_projectile.diameter) * 0.5
	var nose_length := minf(float(current_projectile.diameter) * 1.35, float(current_projectile.length) * 0.45)
	current_projectile["tip_length"] = nose_length
	current_projectile["mass"] = _round_volume(current_projectile) * float(current_projectile.density)
	current_projectile["cd"] = _round_drag_coefficient(str(current_projectile.nose))
	custom_round_active = true
	if is_instance_valid(projectile_picker):
		projectile_picker.select(PROJECTILE_TYPES.size())
	_refresh_round_design()


func _on_round_material_changed(_index: int) -> void:
	_on_round_design_changed(0.0)



func _on_round_surface_changed(_value: float = 0.0) -> void:
	if current_projectile.is_empty() or not is_instance_valid(round_surface_picker):
		return
	var pattern := "smooth"
	if round_surface_picker.selected == 1:
		pattern = "ridges"
	elif round_surface_picker.selected == 2:
		pattern = "grooves"
	current_projectile["surface_pattern"] = pattern
	current_projectile["rib_count"] = int(round_rib_count_slider.value) if is_instance_valid(round_rib_count_slider) else 6
	current_projectile["rib_depth"] = round_rib_depth_slider.value / 1000.0 if is_instance_valid(round_rib_depth_slider) else 0.0
	current_projectile["spiral_turns"] = round_spiral_turns_slider.value if is_instance_valid(round_spiral_turns_slider) else 0.0
	current_projectile["mass"] = _round_volume(current_projectile) * float(current_projectile.get("density", 7850.0))
	if is_instance_valid(round_surface_info):
		var description := "Smooth jacket: choose ridges or grooves to add a patterned surface."
		if pattern != "smooth":
			var chirality := "right hand" if float(current_projectile.spiral_turns) > 0.0 else ("left hand" if float(current_projectile.spiral_turns) < 0.0 else "straight ribs")
			var spin_note := "Air drag adds spin when helix turns are nonzero." if absf(float(current_projectile.spiral_turns)) > 0.001 else "Set helix turns to create spin from air drag."
			description = "%s %d × %0.1f mm  •  %0.2f turns over body (%s). %s" % ["Raised ribs" if pattern == "ridges" else "Cut grooves", int(current_projectile.rib_count), float(current_projectile.rib_depth) * 1000.0, absf(float(current_projectile.spiral_turns)), chirality, spin_note]
		round_surface_info.text = description
	_refresh_round_design()


func _ensure_round_stations() -> void:
	var stations: Array = current_projectile.get("stations", [])
	if stations.size() != 9:
		stations.clear()
		for _i in range(9):
			stations.append({"pull": 1.0, "bend_x": 0.0, "bend_y": 0.0, "twist": 0.0})
		current_projectile["stations"] = stations


func _set_round_sculpt_mode(mode: String) -> void:
	round_mode = mode
	if is_instance_valid(round_sculpt_hint):
		match mode:
			"pull":
				round_sculpt_hint.text = "DRAG UP/DOWN to thicken or taper the selected profile station."
			"bend":
				round_sculpt_hint.text = "DRAG to move the selected station sideways or vertically; neighbors blend smoothly."
			"twist":
				round_sculpt_hint.text = "DRAG HORIZONTALLY to twist the round's deep helical grooves."
			_:
				round_sculpt_hint.text = "DRAG to orbit the model. Choose PULL, BEND or TWIST to sculpt."
	if is_instance_valid(round_preview_container):
		round_preview_container.mouse_default_cursor_shape = Control.CURSOR_MOVE


func _on_round_station_changed(value: float) -> void:
	if not is_instance_valid(round_station_label):
		return
	var station := int(round(value))
	var location := "TIP" if station == 0 else ("TAIL" if station == 8 else "BODY %02d%%" % int(round(float(station) / 8.0 * 100.0)))
	var stations: Array = current_projectile.get("stations", [])
	var values: Dictionary = stations[station] if stations.size() == 9 else {}
	round_station_label.text = "STATION %d / 9  •  %s  •  WIDTH %0.2f×  •  TWIST %0.0f°" % [station + 1, location, float(values.get("pull", 1.0)), rad_to_deg(float(values.get("twist", 0.0)))]


func _on_round_preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		round_drag_active = event.pressed
		round_last_pointer = event.position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and round_drag_active:
		_apply_round_drag(event.position - round_last_pointer)
		round_last_pointer = event.position
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		round_drag_active = event.pressed
		round_last_pointer = event.position
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and round_drag_active:
		_apply_round_drag(event.relative)
		get_viewport().set_input_as_handled()


func _apply_round_drag(relative: Vector2) -> void:
	if round_mode == "orbit":
		if is_instance_valid(round_preview_spin):
			round_preview_spin.rotation.y += relative.x * 0.008
			round_preview_spin.rotation.x = clampf(round_preview_spin.rotation.x - relative.y * 0.008, -0.8, 0.8)
		return
	_ensure_round_stations()
	var stations: Array = current_projectile["stations"]
	var index := clampi(int(round(round_station_slider.value)), 0, 8)
	var station: Dictionary = stations[index].duplicate(true)
	match round_mode:
		"pull":
			station["pull"] = clampf(float(station.get("pull", 1.0)) - relative.y * 0.009, 0.35, 2.0)
		"bend":
			station["bend_x"] = clampf(float(station.get("bend_x", 0.0)) + relative.x * 0.0012, -0.24, 0.24)
			station["bend_y"] = clampf(float(station.get("bend_y", 0.0)) - relative.y * 0.0012, -0.24, 0.24)
		"twist":
			station["twist"] = clampf(float(station.get("twist", 0.0)) + relative.x * 0.018, -PI, PI)
	stations[index] = station
	current_projectile["stations"] = stations
	_on_round_station_changed(float(index))
	current_projectile["mass"] = _round_volume(current_projectile) * float(current_projectile.get("density", 7850.0))
	_refresh_round_design()


func _round_station_at(z: float, design: Dictionary) -> Dictionary:
	var stations: Array = design.get("stations", [])
	if stations.size() != 9:
		return {"pull": 1.0, "bend_x": 0.0, "bend_y": 0.0, "twist": 0.0}
	var u := clampf(inverse_lerp(-float(design.length) * 0.5, float(design.length) * 0.5, z), 0.0, 1.0)
	var station_position := u * 8.0
	var lower := clampi(int(floor(station_position)), 0, 8)
	var upper := mini(lower + 1, 8)
	var blend := station_position - float(lower)
	blend = blend * blend * (3.0 - 2.0 * blend)
	var first: Dictionary = stations[lower]
	var second: Dictionary = stations[upper]
	var result := {}
	for key in ["pull", "bend_x", "bend_y", "twist"]:
		var fallback := 1.0 if key == "pull" else 0.0
		result[key] = lerpf(float(first.get(key, fallback)), float(second.get(key, fallback)), blend)
	return result


func _round_ring_point(radius: float, z: float, angle: float, design: Dictionary) -> Vector3:
	var station := _round_station_at(z, design)
	var body_radius := float(design.diameter) * 0.5
	var normalized_z := clampf((z + float(design.length) * 0.5) / maxf(float(design.length), 0.001), 0.0, 1.0)
	var twist := float(station.get("twist", 0.0)) + normalized_z * float(design.get("spiral_turns", 0.0)) * TAU
	var nose_start := -float(design.length) * 0.5 + float(design.get("tip_length", 0.0))
	var body_fade := smoothstep(nose_start, nose_start + body_radius * 0.9, z) * (1.0 - smoothstep(float(design.length) * 0.5 - body_radius * 0.6, float(design.length) * 0.5, z))
	var rib_count := maxi(int(design.get("rib_count", 6)), 3)
	var amplitude := minf(float(design.get("rib_depth", 0.0)), body_radius * 0.18)
	var pattern := str(design.get("surface_pattern", "smooth"))
	var ridge_sign := 1.0 if pattern == "ridges" else -1.0
	var rib_offset := 0.0
	if pattern != "smooth" and amplitude > 0.00001:
		rib_offset = ridge_sign * amplitude * body_fade * cos(float(rib_count) * (angle - twist))
	var scaled_radius := maxf(radius * float(station.get("pull", 1.0)) + rib_offset, radius * 0.25)
	return Vector3(
		float(station.get("bend_x", 0.0)) + scaled_radius * cos(angle),
		float(station.get("bend_y", 0.0)) + scaled_radius * sin(angle),
		z
	)


func _round_volume(design: Dictionary) -> float:
	var radius := float(design.diameter) * 0.5
	var length := float(design.length)
	var nose_length := minf(float(design.get("tip_length", radius * 2.7)), length * 0.45)
	var area := PI * radius * radius
	var body_volume := area * maxf(length - nose_length, 0.0)
	var nose_shape := str(design.get("nose", "Ogive"))
	var nose_factor := 0.55
	match nose_shape:
		"Conical":
			nose_factor = 1.0 / 3.0
		"Flat":
			nose_factor = 1.0
		"Round":
			nose_factor = 0.58
	var base_volume := body_volume + area * nose_length * nose_factor
	var surface_pattern := str(design.get("surface_pattern", "smooth"))
	if surface_pattern != "smooth":
		var depth_ratio := minf(float(design.get("rib_depth", 0.0)) / maxf(radius, 0.001), 0.18)
		base_volume *= 1.0 + 0.5 * depth_ratio * depth_ratio
	var stations: Array = design.get("stations", [])
	if stations.size() < 2:
		return base_volume
	var pull_area_factor := 0.0
	for station in stations:
		pull_area_factor += pow(clampf(float(station.get("pull", 1.0)), 0.35, 2.0), 2.0)
	pull_area_factor /= float(stations.size())
	return base_volume * pull_area_factor


func _round_max_pull(design: Dictionary) -> float:
	var stations: Array = design.get("stations", [])
	var maximum := 0.0 if design.shape == "custom" and not stations.is_empty() else 1.0
	for station in stations:
		maximum = maxf(maximum, clampf(float(station.get("pull", 1.0)), 0.35, 2.0))
	return maximum


func _round_drag_coefficient(nose_shape: String) -> float:
	match nose_shape:
		"Conical":
			return 0.31
		"Flat":
			return 0.42
		"Round":
			return 0.34
		_:
			return 0.24


func _round_profile(design: Dictionary) -> Array[Vector2]:
	var radius := float(design.diameter) * 0.5
	var length := float(design.length)
	var nose_length := minf(float(design.get("tip_length", radius * 2.7)), length * 0.45)
	var body_end_z := -length * 0.5 + nose_length
	var profile: Array[Vector2] = []
	for segment in range(65):
		var along := float(segment) / 64.0
		var z := lerpf(length * 0.5, -length * 0.5, along)
		var ring_radius := radius
		if z < body_end_z and nose_length > 0.001:
			var t := clampf(inverse_lerp(body_end_z, -length * 0.5, z), 0.0, 1.0)
			match str(design.get("nose", "Ogive")):
				"Conical":
					ring_radius = radius * (1.0 - t)
				"Round":
					var smooth := t * t * (3.0 - 2.0 * t)
					ring_radius = radius * (1.0 - smooth)
				"Flat":
					ring_radius = radius
				_:
					ring_radius = radius * sqrt(maxf(0.0, 1.0 - t * t))
		profile.append(Vector2(ring_radius, z))
	return profile


func _round_collision_points(design: Dictionary) -> PackedVector3Array:
	var points := PackedVector3Array()
	for ring in _round_profile(design):
		for slice in range(48):
			var angle := TAU * float(slice) / 48.0
			points.append(_round_ring_point(ring.x, ring.y, angle, design))
	return points


func _build_round_mesh(design: Dictionary) -> ArrayMesh:
	var profile := _round_profile(design)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var slices := 96
	for segment in range(profile.size() - 1):
		var first: Vector2 = profile[segment]
		var second: Vector2 = profile[segment + 1]
		for slice in range(slices):
			var a0 := TAU * float(slice) / slices
			var a1 := TAU * float(slice + 1) / slices
			var p00 := _round_ring_point(first.x, first.y, a0, design)
			var p01 := _round_ring_point(first.x, first.y, a1, design)
			var p10 := _round_ring_point(second.x, second.y, a0, design)
			var p11 := _round_ring_point(second.x, second.y, a1, design)
			tool.add_vertex(p00)
			tool.add_vertex(p10)
			tool.add_vertex(p01)
			tool.add_vertex(p01)
			tool.add_vertex(p10)
			tool.add_vertex(p11)
	var radius := float(design.diameter) * 0.5
	var back_z := float(design.length) * 0.5
	var back_station := _round_station_at(back_z, design)
	for slice in range(slices):
		var a0 := TAU * float(slice) / slices
		var a1 := TAU * float(slice + 1) / slices
		var center := Vector3(float(back_station.get("bend_x", 0.0)), float(back_station.get("bend_y", 0.0)), back_z)
		tool.add_vertex(center)
		tool.add_vertex(_round_ring_point(radius, back_z, a1, design))
		tool.add_vertex(_round_ring_point(radius, back_z, a0, design))
	if str(design.get("nose", "")) == "Flat":
		var front_z := -float(design.length) * 0.5
		var front_station := _round_station_at(front_z, design)
		for slice in range(slices):
			var a0 := TAU * float(slice) / slices
			var a1 := TAU * float(slice + 1) / slices
			var center := Vector3(float(front_station.get("bend_x", 0.0)), float(front_station.get("bend_y", 0.0)), front_z)
			tool.add_vertex(center)
			tool.add_vertex(_round_ring_point(radius, front_z, a0, design))
			tool.add_vertex(_round_ring_point(radius, front_z, a1, design))
	tool.index()
	tool.generate_normals()
	return tool.commit()


func _refresh_round_design() -> void:
	if not is_instance_valid(round_editor_screen):
		return
	var diameter_mm := float(current_projectile.get("diameter", 0.18)) * 1000.0
	var length_mm := float(current_projectile.get("length", 0.54)) * 1000.0
	var tip_mm := float(current_projectile.get("tip_length", 0.0)) * 1000.0
	if is_instance_valid(round_dimensions_label):
		round_dimensions_label.text = "%s  •  Ø %0.0f MM  ×  %0.0f MM\nNOSE: %0.0f MM" % [str(current_projectile.nose).to_upper(), diameter_mm, length_mm, tip_mm]
	if is_instance_valid(round_mass_label):
		round_mass_label.text = "ESTIMATED MASS  •  %0.2f KG" % float(current_projectile.mass)
	if is_instance_valid(round_volume_label):
		round_volume_label.text = "SOLID VOLUME  •  %0.1f L" % (_round_volume(current_projectile) * 1000.0)
	if is_instance_valid(round_material_label):
		round_material_label.text = "%s  •  %0.0f KG/M³" % [str(current_projectile.material).to_upper(), float(current_projectile.density)]
	if is_instance_valid(round_preview_model):
		round_preview_model.queue_free()
		round_preview_model = null
	if is_instance_valid(round_preview_spin):
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Live machined round preview"
		mesh_instance.mesh = _build_round_mesh(current_projectile)
		mesh_instance.material_override = _material(current_projectile.color, 0.76, 0.27)
		round_preview_spin.add_child(mesh_instance)
		round_preview_model = mesh_instance
		var preview_camera := round_preview_view.get_camera_3d()
		if is_instance_valid(preview_camera):
			var length := float(current_projectile.length)
			var diameter := float(current_projectile.diameter)
			var camera_distance := maxf(length * 1.55, diameter * 4.0)
			preview_camera.position = Vector3(camera_distance * 0.58, diameter * 2.4, camera_distance * 0.89)
			preview_camera.look_at(Vector3.ZERO, Vector3.UP)


func _save_custom_round() -> void:
	var save_data := {
		"name": str(current_projectile.get("name", "Custom round")),
		"diameter": float(current_projectile.get("diameter", 0.18)),
		"length": float(current_projectile.get("length", 0.54)),
		"nose": str(current_projectile.get("nose", "Ogive")),
		"material": str(current_projectile.get("material", "Steel")),
		"density": float(current_projectile.get("density", 7850.0)),
		"tip_length": float(current_projectile.get("tip_length", 0.24)),
		"stations": current_projectile.get("stations", []),
		"surface_pattern": str(current_projectile.get("surface_pattern", "smooth")),
		"rib_count": int(current_projectile.get("rib_count", 6)),
		"rib_depth": float(current_projectile.get("rib_depth", 0.0)),
		"spiral_turns": float(current_projectile.get("spiral_turns", 0.0)),
	}
	var file := FileAccess.open("user://trajectory_round.json", FileAccess.WRITE)
	if file == null:
		push_warning("Could not save the custom round to user storage.")
		return
	file.store_string(JSON.stringify(save_data))


func _load_saved_round() -> void:
	if not FileAccess.file_exists("user://trajectory_round.json"):
		return
	var file := FileAccess.open("user://trajectory_round.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var saved: Dictionary = parsed
	var nose := str(saved.get("nose", "Ogive"))
	var material_name := str(saved.get("material", "Steel"))
	var material_data: Dictionary = ROUND_MATERIALS[1]
	for candidate in ROUND_MATERIALS:
		if str(candidate.name) == material_name:
			material_data = candidate
			break
	var diameter := clampf(float(saved.get("diameter", 0.18)), 0.08, 0.32)
	var length := clampf(float(saved.get("length", 0.54)), 0.25, 1.25)
	current_projectile = {
		"name": "Custom round",
		"shape": "custom",
		"diameter": diameter,
		"length": length,
		"nose": nose if ROUND_NOSES.has(nose) else "Ogive",
		"material": str(material_data.name),
		"density": float(material_data.density),
		"color": material_data.color,
		"tip_length": clampf(float(saved.get("tip_length", diameter * 1.35)), 0.01, length * 0.45),
		"stations": saved.get("stations", []),
		"surface_pattern": str(saved.get("surface_pattern", "grooves")),
		"rib_count": clampi(int(saved.get("rib_count", 6)), 3, 12),
		"rib_depth": clampf(float(saved.get("rib_depth", 0.008)), 0.0, 0.008),
		"spiral_turns": clampf(float(saved.get("spiral_turns", 0.0)), -3.0, 3.0),
		"cd": _round_drag_coefficient(nose),
	}
	current_projectile["mass"] = _round_volume(current_projectile) * float(current_projectile.density)
	custom_round_active = true


func _close_round_editor() -> void:
	_save_custom_round()
	if is_instance_valid(round_editor_screen):
		round_editor_screen.queue_free()
		round_editor_screen = null
	if is_instance_valid(status_label):
		status_label.text = "CUSTOM ROUND READY  •  %0.2f KG  •  %s" % [float(current_projectile.mass), str(current_projectile.nose).to_upper()]


func _toggle_projectile_camera() -> void:
	projectile_camera_enabled = not projectile_camera_enabled
	if projectile_camera_enabled:
		followed_projectile = last_projectile if is_instance_valid(last_projectile) else null
		if is_instance_valid(followed_projectile):
			_update_projectile_camera(followed_projectile)
	else:
		followed_projectile = null
		if is_instance_valid(ground_visual):
			ground_visual.position = ground_home
		_update_camera()
	if is_instance_valid(projectile_camera_button):
		projectile_camera_button.text = "PROJECTILE CAM  •  ON" if projectile_camera_enabled else "PROJECTILE CAM  •  OFF"


func _update_projectile_camera(projectile: RigidBody3D) -> void:
	if not is_instance_valid(projectile):
		return
	var velocity := projectile.linear_velocity
	var forward := velocity.normalized() if velocity.length_squared() > 1.0 else -projectile.global_transform.basis.z.normalized()
	# Keep the chase view attached to the shot without pitching straight into empty sky.
	# A slight downward bias preserves the course and horizon while the projectile remains in frame.
	var view_forward := Vector3(forward.x, clampf(forward.y * 0.34 - 0.08, -0.35, 0.18), forward.z).normalized()
	var altitude := maxf(projectile.global_position.y, 0.0)
	camera.far = clampf(110000.0 + altitude * 24.0, 110000.0, 15000000.0)
	camera.fov = 72.0
	camera.global_position = projectile.global_position - forward * 1.8 + Vector3.UP * 0.58
	camera.look_at(projectile.global_position + view_forward * 35.0, Vector3.UP)


func _on_target_distance_selected(index: int) -> void:
	if not is_instance_valid(target_distance_picker):
		return
	target_distance_m = int(target_distance_picker.get_item_text(index).trim_suffix(" M"))
	if is_instance_valid(target_distance_label):
		target_distance_label.text = "TARGET DISTANCE  •  %d M" % target_distance_m
	if is_instance_valid(active_target):
		active_target.position = Vector3(0.0, 3.2, -float(target_distance_m))


func _on_speed_changed(value: float) -> void:
	if is_instance_valid(speed_value_label):
		speed_value_label.text = "MUZZLE VELOCITY  •  %0.0f M/S  (MACH %0.1f)" % [value, value / SEA_LEVEL_SOUND_SPEED]


func _on_elevation_changed(value: float) -> void:
	if is_instance_valid(elevation_value_label):
		elevation_value_label.text = "BARREL ELEVATION  •  %+0.1f°" % value
	if is_instance_valid(barrel_pivot):
		var pivot_rotation := barrel_pivot_base_rotation
		pivot_rotation.x += deg_to_rad(value)
		barrel_pivot.rotation = pivot_rotation


func _on_wind_changed(value: float) -> void:
	if is_instance_valid(wind_value_label):
		wind_value_label.text = "CROSSWIND  •  %+0.1f M/S" % value
	if is_instance_valid(status_label):
		status_label.text = "HYPERVELOCITY RANGE  •  CROSSWIND: %+0.1f M/S" % value


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			camera_dragging = event.position.x < get_viewport().get_visible_rect().size.x - 250.0 and event.position.y > 145.0
		else:
			camera_dragging = false
	elif event is InputEventScreenDrag and camera_dragging:
		_orbit_camera(event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		camera_dragging = event.pressed and event.position.y > 145.0
	elif event is InputEventMouseMotion and camera_dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_orbit_camera(event.relative)


func _orbit_camera(relative: Vector2) -> void:
	camera_yaw -= relative.x * 0.004
	camera_pitch = clampf(camera_pitch + relative.y * 0.003, 0.06, 0.72)
	_update_camera()


func _update_camera() -> void:
	camera.fov = 43.0
	var horizontal := camera_distance * cos(camera_pitch)
	camera.position = camera_focus + Vector3(sin(camera_yaw) * horizontal, sin(camera_pitch) * camera_distance, cos(camera_yaw) * horizontal)
	camera.look_at(camera_focus, Vector3.UP)


func _fire_test_shot() -> void:
	shot_count += 1
	var design: Dictionary = current_projectile.duplicate(true) if custom_round_active else PROJECTILE_TYPES[projectile_picker.selected].duplicate(true)
	status_label.text = "SHOT %02d  •  %s" % [shot_count, str(design.name).to_upper()]
	var projectile := RigidBody3D.new()
	projectile.name = "TestProjectile_%02d" % shot_count
	projectile.mass = float(design.mass)
	projectile.linear_damp = 0.0
	projectile.gravity_scale = 0.0
	projectile.angular_damp = 0.03 if design.shape == "custom" and str(design.get("surface_pattern", "smooth")) != "smooth" else 0.35
	projectile.continuous_cd = true
	projectile.contact_monitor = true
	projectile.max_contacts_reported = 4
	projectile.body_entered.connect(_on_projectile_body_entered.bind(projectile))
	var mesh_instance := MeshInstance3D.new()
	var radius := float(design.diameter) * 0.5
	var mesh: Mesh
	if design.shape == "custom":
		mesh = _build_round_mesh(design)
	elif design.shape == "sphere":
		var sphere := SphereMesh.new()
		sphere.radius = radius
		sphere.height = radius * 2.0
		mesh = sphere
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = radius
		capsule.height = float(design.length)
		mesh = capsule
	mesh_instance.mesh = mesh
	if design.shape != "custom":
		mesh_instance.rotation.x = PI * 0.5
	var projectile_material := _material(design.color, 0.36, 0.68)
	projectile_material.emission_enabled = true
	projectile_material.emission = Color(0.025, 0.13, 0.17) if design.shape != "shuttle" else Color(0.17, 0.055, 0.015)
	projectile_material.emission_energy_multiplier = 0.42
	mesh_instance.material_override = projectile_material
	projectile.add_child(mesh_instance)
	if design.shape == "shuttle":
		for fin_index in 4:
			var fin := MeshInstance3D.new()
			var fin_mesh := BoxMesh.new()
			fin_mesh.size = Vector3(0.015, 0.12, 0.18)
			fin.mesh = fin_mesh
			fin.position = Vector3(0.0, 0.0, radius * 1.25)
			fin.rotation.z = TAU * float(fin_index) / 4.0
			fin.material_override = projectile_material
			mesh_instance.add_child(fin)
	var projectile_light := OmniLight3D.new()
	projectile_light.light_color = Color(0.12, 0.58, 0.78)
	projectile_light.light_energy = 0.28
	projectile_light.omni_range = 1.15
	projectile_light.shadow_enabled = false
	projectile.add_child(projectile_light)
	var flow_visual := MeshInstance3D.new()
	flow_visual.name = "Subtle aerodynamic flow lines"
	var flow_mesh := ImmediateMesh.new()
	flow_visual.mesh = flow_mesh
	flow_visual.material_override = _get_projectile_flow_material()
	flow_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	projectile.add_child(flow_visual)
	projectile.set_meta("flow_mesh", flow_mesh)
	projectile.set_meta("flow_update_accumulator", 0.0)
	var collision := CollisionShape3D.new()
	var collision_shape: Shape3D
	if design.shape == "custom":
		var round_shape := ConvexPolygonShape3D.new()
		round_shape.points = _round_collision_points(design)
		collision_shape = round_shape
	elif design.shape == "sphere":
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = radius
		collision_shape = sphere_shape
	else:
		var capsule_shape := CapsuleShape3D.new()
		capsule_shape.radius = radius
		capsule_shape.height = float(design.length)
		collision_shape = capsule_shape
		collision.rotation.x = PI * 0.5
	collision.shape = collision_shape
	projectile.add_child(collision)
	add_child(projectile)
	var muzzle_forward := Vector3(0.0, sin(deg_to_rad(elevation_slider.value)), -cos(deg_to_rad(elevation_slider.value)))
	if is_instance_valid(barrel_pivot):
		var muzzle_offset := float(barrel_pivot.get_meta("muzzle_offset", -6.12))
		projectile.global_position = barrel_pivot.to_global(Vector3(0.0, 0.0, muzzle_offset))
		muzzle_forward = -barrel_pivot.global_transform.basis.z.normalized()
	var stable_up := Vector3.UP if absf(muzzle_forward.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	projectile.look_at(projectile.global_position + muzzle_forward.normalized(), stable_up)
	projectile.linear_velocity = muzzle_forward.normalized() * speed_slider.value
	last_projectile = projectile
	if projectile_camera_enabled:
		followed_projectile = projectile
	projectile.set_meta("design", design)
	projectile.set_meta("wind_x", wind_slider.value)
	active_shots[projectile.get_instance_id()] = {"body": projectile, "number": shot_count, "time": 0.0, "max_height": projectile.global_position.y, "origin": projectile.global_position, "design": design}
	analysis_label.text = "IN FLIGHT  •  %0.1f KG / %0.0f MM / Cd %0.2f" % [design.mass, design.diameter * 1000.0, design.cd]
	# Shots remain active until impact; the long failsafe only cleans up runaway bodies.


func _get_projectile_flow_material() -> StandardMaterial3D:
	if is_instance_valid(projectile_flow_material):
		return projectile_flow_material
	projectile_flow_material = StandardMaterial3D.new()
	projectile_flow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	projectile_flow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	projectile_flow_material.vertex_color_use_as_albedo = true
	projectile_flow_material.albedo_color = Color.WHITE
	projectile_flow_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	projectile_flow_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	projectile_flow_material.emission_enabled = false
	projectile_flow_material.render_priority = 1
	return projectile_flow_material


func _flow_vertex(mesh: ImmediateMesh, point: Vector3, tint: Color) -> void:
	mesh.surface_set_color(tint)
	mesh.surface_add_vertex(point)


func _update_projectile_flow_vfx(projectile: RigidBody3D, design: Dictionary, relative_air_velocity: Vector3, speed: float, density: float, mach: float, flight_time: float) -> void:
	var flow_mesh := projectile.get_meta("flow_mesh", null) as ImmediateMesh
	if not is_instance_valid(flow_mesh):
		return
	flow_mesh.clear_surfaces()
	flow_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var diameter := float(design.get("diameter", 0.12))
	var radius := diameter * 0.5
	var length := float(design.get("length", diameter * 3.0))
	var tip_length := clampf(float(design.get("tip_length", radius * 1.4)), length * 0.04, length * 0.46)
	var body_start := -length * 0.5 + tip_length
	var body_length := maxf(length - tip_length, length * 0.35)
	var wake_length := clampf(0.30 + speed * 0.00045, 0.30, 1.35)
	var density_factor := clampf(sqrt(maxf(density, 0.0) / AIR_DENSITY), 0.0, 1.0)
	var local_flow := projectile.global_transform.basis.inverse() * -relative_air_velocity.normalized()
	var crossflow := Vector3(local_flow.x, local_flow.y, 0.0).limit_length(0.8)
	var mach_factor := clampf(mach / 5.0, 0.35, 1.0)
	var segment_count := 14
	for line_index in range(4):
		var angle := TAU * float(line_index) / 4.0
		var radial := Vector3(cos(angle), sin(angle), 0.0)
		var width_axis := Vector3(-sin(angle), cos(angle), 0.0)
		var previous_left := Vector3.ZERO
		var previous_right := Vector3.ZERO
		var previous_alpha := 0.0
		for point_index in range(segment_count + 1):
			var u := float(point_index) / float(segment_count)
			var z := body_start
			var radial_scale := 1.0
			var wake_t := 0.0
			if u <= 0.70:
				var body_t := u / 0.70
				z = body_start + body_length * body_t
				radial_scale = lerpf(0.10, 1.045, smoothstep(0.0, 0.085, body_t))
			else:
				wake_t = (u - 0.70) / 0.30
				z = length * 0.5 + wake_length * wake_t
				radial_scale = 1.045 + wake_t * 0.18
			var flutter := sin(flight_time * 8.0 + u * 20.0 + float(line_index) * 1.9) * radius * 0.045 * mach_factor * wake_t
			var wind_offset := crossflow * wake_length * wake_t * 0.28
			var station := _round_station_at(z, design) if design.shape == "custom" else {"bend_x": 0.0, "bend_y": 0.0, "pull": 1.0}
			var local_radius := radius * radial_scale * float(station.get("pull", 1.0)) + flutter
			var center := Vector3(float(station.get("bend_x", 0.0)), float(station.get("bend_y", 0.0)), z) + radial * local_radius + wind_offset
			var width := maxf(diameter * 0.018 * (1.0 - wake_t * 0.58), 0.0008)
			var left := center + width_axis * width
			var right := center - width_axis * width
			var alpha := density_factor * (0.38 if u <= 0.70 else 0.38 * (1.0 - wake_t) * (1.0 - wake_t))
			alpha *= 0.92 + 0.08 * sin(flight_time * 6.0 + float(line_index))
			var tint := Color(0.18, 0.68, 0.83, alpha)
			if point_index > 0:
				_flow_vertex(flow_mesh, previous_left, Color(tint.r, tint.g, tint.b, previous_alpha))
				_flow_vertex(flow_mesh, previous_right, Color(tint.r, tint.g, tint.b, previous_alpha))
				_flow_vertex(flow_mesh, left, tint)
				_flow_vertex(flow_mesh, previous_right, Color(tint.r, tint.g, tint.b, previous_alpha))
				_flow_vertex(flow_mesh, right, tint)
				_flow_vertex(flow_mesh, left, tint)
			previous_left = left
			previous_right = right
			previous_alpha = alpha
	flow_mesh.surface_end()


func _atmosphere_state(altitude: float) -> Dictionary:
	var h := maxf(altitude, 0.0)
	var temperature := 288.15
	var density := AIR_DENSITY
	if h <= 11000.0:
		temperature = 288.15 - 0.0065 * h
		density = AIR_DENSITY * pow(temperature / 288.15, 4.25588)
	elif h <= 20000.0:
		temperature = 216.65
		density = 0.36391 * exp(-(h - 11000.0) / 6341.6)
	elif h <= 32000.0:
		temperature = 216.65 + 0.001 * (h - 20000.0)
		var density_at_20km := 0.36391 * exp(-9000.0 / 6341.6)
		density = density_at_20km * pow(temperature / 216.65, -(AIR_GRAVITY / (AIR_GAS_CONSTANT * 0.001)) - 1.0)
	else:
		temperature = 228.65
		var density_at_32km := 0.36391 * exp(-9000.0 / 6341.6) * pow(228.65 / 216.65, -(AIR_GRAVITY / (AIR_GAS_CONSTANT * 0.001)) - 1.0)
		density = density_at_32km * exp(-(h - 32000.0) / 7000.0)
	return {
		"density": maxf(density, 0.0),
		"sound_speed": sqrt(AIR_GAMMA * AIR_GAS_CONSTANT * temperature),
	}


func _mach_drag_multiplier(mach: float) -> float:
	var transonic_peak := 0.28 * exp(-pow((mach - 1.0) / 0.32, 2.0))
	var high_mach_reduction := 0.08 * clampf((mach - 3.0) / 2.0, 0.0, 1.0)
	return 1.0 + transonic_peak - high_mach_reduction


func _physics_process(_delta: float) -> void:
	for shot_id in active_shots.keys():
		var shot: Dictionary = active_shots[shot_id]
		var projectile: RigidBody3D = shot.body
		if not is_instance_valid(projectile):
			active_shots.erase(shot_id)
			continue
		var altitude := maxf(projectile.global_position.y, 0.0)
		var local_gravity := AIR_GRAVITY * pow(EARTH_RADIUS / (EARTH_RADIUS + altitude), 2.0)
		projectile.apply_central_force(Vector3.DOWN * projectile.mass * local_gravity)
		var velocity := projectile.linear_velocity
		var relative_air_velocity := velocity - Vector3(float(projectile.get_meta("wind_x")), 0.0, 0.0)
		var speed := relative_air_velocity.length()
		if speed > 0.01:
			var design: Dictionary = shot.design
			var shape_width_scale := _round_max_pull(design) if design.shape == "custom" else 1.0
			var radius := float(design.diameter) * 0.5 * shape_width_scale
			var projected_area := PI * radius * radius
			var effective_cd := float(design.cd)
			if design.shape == "custom" and str(design.get("surface_pattern", "smooth")) != "smooth":
				var depth_ratio := clampf(float(design.get("rib_depth", 0.0)) / maxf(float(design.diameter) * 0.5, 0.001), 0.0, 0.18)
				effective_cd *= 1.0 + depth_ratio * 0.22 + float(design.get("rib_count", 6)) * depth_ratio * 0.008
			var axis := -projectile.global_transform.basis.z.normalized()
			if design.shape != "sphere":
				var air_direction := relative_air_velocity.normalized()
				var axial_alignment := clampf(absf(axis.dot(air_direction)), 0.0, 1.0)
				var side_on := sqrt(1.0 - axial_alignment * axial_alignment)
				var side_area := float(design.length) * float(design.diameter) * shape_width_scale * side_on
				projected_area = projected_area * axial_alignment + side_area
				effective_cd *= (axial_alignment + 1.6 * side_on) / maxf(axial_alignment + side_on, 0.001)
			var atmosphere := _atmosphere_state(projectile.global_position.y)
			var density := float(atmosphere.density)
			var mach := speed / maxf(float(atmosphere.sound_speed), 1.0)
			var drag := 0.5 * density * effective_cd * _mach_drag_multiplier(mach) * projected_area * speed * speed
			projectile.apply_central_force(-relative_air_velocity.normalized() * drag)
			if design.shape != "sphere" and speed > 1.0:
				var dynamic_pressure := 0.5 * density * speed * speed
				var alignment_error := axis.cross(relative_air_velocity.normalized())
				var spin_rate := projectile.angular_velocity.dot(axis)
				var spin_stability := 1.0 / (1.0 + absf(spin_rate) * 0.018)
				var stability_torque := alignment_error * minf(dynamic_pressure * projected_area * float(design.length) * 0.00004, 30.0) * spin_stability
				var rotational_damping := projectile.angular_velocity * minf(dynamic_pressure * projected_area * float(design.length) * 0.000003, 5.0)
				var aero_torque := Vector3.ZERO
				if design.shape == "custom" and str(design.get("surface_pattern", "smooth")) != "smooth":
					var stations: Array = design.get("stations", [])
					var station_turns := 0.0
					if stations.size() >= 2:
						station_turns = (float(stations[8].get("twist", 0.0)) - float(stations[0].get("twist", 0.0))) / TAU
					var total_turns := float(design.get("spiral_turns", 0.0)) + station_turns
					if absf(total_turns) > 0.001:
						var helical_slope := sin(atan(float(design.diameter) * 0.5 * TAU * total_turns / maxf(float(design.length), 0.001)))
						var rib_ratio := clampf(float(design.get("rib_depth", 0.0)) / maxf(float(design.diameter) * 0.5, 0.001), 0.0, 0.18)
						var spin_torque := drag * float(design.diameter) * 0.5 * rib_ratio * helical_slope * 0.22
						aero_torque = axis * spin_torque
				projectile.apply_torque(stability_torque - rotational_damping + aero_torque)
			var flow_timer := float(projectile.get_meta("flow_update_accumulator", 0.0)) + _delta
			if flow_timer >= 0.05:
				projectile.set_meta("flow_update_accumulator", fmod(flow_timer, 0.05))
				_update_projectile_flow_vfx(projectile, design, relative_air_velocity, speed, density, mach, float(shot.time))
			else:
				projectile.set_meta("flow_update_accumulator", flow_timer)
		if projectile == followed_projectile:
			if is_instance_valid(ground_visual):
				ground_visual.global_position = Vector3(projectile.global_position.x, ground_home.y, projectile.global_position.z)
				var desired_ground_size := clampf(maxf(100000.0, projectile.global_position.y * 24.0), 100000.0, 12000000.0)
				if absf(desired_ground_size - ground_render_size) > ground_render_size * 0.08:
					ground_render_size = desired_ground_size
					ground_mesh.size = Vector2(ground_render_size, ground_render_size)
			_update_projectile_camera(projectile)
		shot.time = float(shot.time) + _delta
		shot.max_height = maxf(float(shot.max_height), projectile.global_position.y)
		if shot.time >= MAX_SHOT_FLIGHT_TIME or projectile.global_position.distance_squared_to(shot.origin) >= MAX_SHOT_TRAVEL * MAX_SHOT_TRAVEL:
			_remove_projectile(projectile)
			continue
		active_shots[shot_id] = shot


func _make_fx_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = Color(color.r, color.g, color.b, 1.0)
	material.emission_energy_multiplier = energy
	return material


func _spawn_impact_splash(position: Vector3, normal: Vector3, design: Dictionary, impact_speed: float) -> void:
	var effect := Node3D.new()
	effect.name = "RoundImpactSplash"
	add_child(effect)
	effect.global_position = position
	var surface_normal := normal.normalized() if normal.length_squared() > 0.001 else Vector3.UP
	var impact_energy_mj := 0.5 * float(design.get("mass", 1.0)) * impact_speed * impact_speed / 1000000.0
	var burst_scale := clampf(sqrt(maxf(impact_energy_mj, 0.1) / 25.0), 0.75, 2.2)

	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.22
	flash_mesh.height = 0.44
	flash_mesh.radial_segments = 20
	flash_mesh.rings = 10
	flash.mesh = flash_mesh
	var flash_material := _make_fx_material(Color(0.30, 0.86, 1.0, 0.92), 5.0)
	flash.material_override = flash_material
	flash.scale = Vector3.ONE * 0.18
	effect.add_child(flash)
	var flash_tween := effect.create_tween().set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector3.ONE * 4.8 * burst_scale, 0.34).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	flash_tween.tween_property(flash_material, "albedo_color", Color(0.30, 0.86, 1.0, 0.0), 0.34)

	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.18
	ring_mesh.outer_radius = 0.24
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 10
	ring.mesh = ring_mesh
	ring.material_override = _make_fx_material(Color(1.0, 0.38, 0.10, 0.95), 4.0)
	ring.scale = Vector3.ONE * 0.22
	var ring_right := surface_normal.cross(Vector3.UP)
	if ring_right.length_squared() < 0.001:
		ring_right = surface_normal.cross(Vector3.RIGHT)
	ring_right = ring_right.normalized()
	var ring_up := surface_normal.cross(ring_right).normalized()
	ring.basis = Basis(ring_right, ring_up, surface_normal).orthonormalized()
	effect.add_child(ring)
	var ring_tween := effect.create_tween().set_parallel(true)
	ring_tween.tween_property(ring, "scale", Vector3.ONE * 18.0 * burst_scale, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ring_tween.tween_property(ring.material_override, "albedo_color", Color(1.0, 0.38, 0.10, 0.0), 0.62)

	var burst_light := OmniLight3D.new()
	burst_light.light_color = Color(0.28, 0.78, 1.0)
	burst_light.light_energy = 7.0 * burst_scale
	burst_light.omni_range = 12.0 * burst_scale
	burst_light.shadow_enabled = false
	effect.add_child(burst_light)
	effect.create_tween().tween_property(burst_light, "light_energy", 0.0, 0.46)

	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.035
	spark_mesh.height = 0.07
	spark_mesh.radial_segments = 8
	spark_mesh.rings = 4
	for spark_index in range(26):
		var spark := MeshInstance3D.new()
		spark.mesh = spark_mesh
		var spark_color := Color(0.22, 0.88, 1.0, 1.0) if spark_index % 2 == 0 else Color(1.0, 0.42, 0.12, 1.0)
		var spark_material := _make_fx_material(spark_color, 5.5)
		spark.material_override = spark_material
		spark.scale = Vector3.ONE * randf_range(0.65, 1.35)
		effect.add_child(spark)
		var spread := Vector3(randf_range(-1.0, 1.0), randf_range(-0.4, 1.2), randf_range(-1.0, 1.0))
		var direction := (surface_normal + spread).normalized()
		var travel := direction * randf_range(2.0, 8.0) * burst_scale
		travel.y += randf_range(0.2, 1.5)
		var lifetime := randf_range(0.42, 1.05)
		var spark_tween := effect.create_tween().set_parallel(true)
		spark_tween.tween_property(spark, "position", travel, lifetime).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		spark_tween.tween_property(spark, "scale", Vector3.ZERO, lifetime)
		spark_tween.tween_property(spark_material, "albedo_color", Color(spark_color.r, spark_color.g, spark_color.b, 0.0), lifetime)
	var cleanup_tween := effect.create_tween()
	cleanup_tween.tween_interval(1.25)
	cleanup_tween.tween_callback(effect.queue_free)


func _hold_projectile_camera_at_impact(position: Vector3, incoming: Vector3) -> void:
	if not projectile_camera_enabled:
		return
	followed_projectile = null
	var forward := incoming.normalized() if incoming.length_squared() > 0.001 else Vector3.FORWARD
	var stable_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	camera.global_position = position - forward * 16.0 + Vector3.UP * 8.0
	camera.look_at(position + forward * 4.0, stable_up)
	camera.fov = 72.0
	if is_instance_valid(ground_visual):
		ground_visual.global_position = Vector3(position.x, ground_home.y, position.z)


func _on_projectile_body_entered(body: Node, projectile: RigidBody3D) -> void:
	var shot_id := projectile.get_instance_id()
	if not active_shots.has(shot_id):
		return
	var shot: Dictionary = active_shots[shot_id]
	var displacement: Vector3 = projectile.global_position - shot.origin
	var result := "IMPACT • %0.1f M • X %+0.1f M" % [-displacement.z, displacement.x]
	if body.is_in_group("range_targets"):
		result = "TARGET HIT • %0.1f M • X %+0.1f M" % [-displacement.z, displacement.x]
	status_label.text = "SHOT %02d  •  %s" % [shot.number, result]
	var incoming := projectile.linear_velocity.normalized()
	var impact_normal := Vector3.UP
	if body.is_in_group("range_targets"):
		impact_normal = -incoming
	var impact_radius := float(shot.design.get("diameter", 0.18)) * 0.5
	var impact_speed := projectile.linear_velocity.length()
	var impact_position := projectile.global_position - impact_normal * impact_radius
	_spawn_impact_splash(impact_position, impact_normal, shot.design, impact_speed)
	var impact_atmosphere := _atmosphere_state(projectile.global_position.y)
	var impact_mach := impact_speed / maxf(float(impact_atmosphere.sound_speed), 1.0)
	analysis_label.text = "%s\nTIME %0.2f S  •  APEX %0.1f M\nIMPACT %0.0f M/S (MACH %0.2f)\nMASS %0.1f KG  •  Cd %0.2f" % [result, shot.time, shot.max_height, impact_speed, impact_mach, shot.design.mass, shot.design.cd]
	active_shots.erase(shot_id)
	if projectile == followed_projectile:
		_hold_projectile_camera_at_impact(impact_position, incoming)
	if projectile == last_projectile:
		last_projectile = null


func _remove_projectile(projectile: RigidBody3D) -> void:
	if is_instance_valid(projectile):
		if projectile == followed_projectile:
			_toggle_projectile_camera()
		if projectile == last_projectile:
			last_projectile = null
		active_shots.erase(projectile.get_instance_id())
		projectile.queue_free()


func _add_target(at: Vector3, radius: float) -> Node3D:
	var target := Node3D.new()
	target.add_to_group("range_targets")
	add_child(target)
	var backing := _add_cylinder(target, Vector3.ZERO, radius, 0.16, Color(0.11, 0.16, 0.19), 0.24, 0.65, true)
	backing.rotation.x = PI * 0.5
	var outer := _add_cylinder(target, Vector3(0.0, 0.0, 0.10), radius * 0.76, 0.05, Color(0.96, 0.42, 0.11), 0.18, 0.5, true)
	outer.rotation.x = PI * 0.5
	var inner := _add_cylinder(target, Vector3(0.0, 0.0, 0.16), radius * 0.40, 0.05, Color(0.92, 0.94, 0.87), 0.12, 0.45, true)
	inner.rotation.x = PI * 0.5
	var center := _add_cylinder(target, Vector3(0.0, 0.0, 0.22), radius * 0.15, 0.06, Color(0.10, 0.78, 0.96), 0.12, 0.28, true)
	center.rotation.x = PI * 0.5
	var target_body := StaticBody3D.new()
	target_body.add_to_group("range_targets")
	var hit_area := CollisionShape3D.new()
	var hit_disc := CylinderShape3D.new()
	hit_disc.radius = radius
	hit_disc.height = 0.25
	hit_area.shape = hit_disc
	hit_area.rotation.x = PI * 0.5
	target_body.add_child(hit_area)
	target.add_child(target_body)
	target.position = at
	# Tall instrument stations stand on cross-braced towers, leaving the firing
	# centerline open for low-angle shots to travel the full two-kilometre lane.
	# Armored carriage sits on the lane deck; bogies, rails, and actuator struts tie the plate to it.
	var chassis_y := -radius - 0.35
	_add_box(target, Vector3(0.0, chassis_y, -0.35), Vector3(radius * 3.2, 0.70, radius * 2.15), Color(0.055, 0.075, 0.085), 0.78, 0.48)
	_add_box(target, Vector3(0.0, chassis_y + 0.37, -0.35), Vector3(radius * 2.85, 0.08, radius * 1.9), Color(0.12, 0.19, 0.22), 0.64, 0.38)
	for side in [-1.0, 1.0]:
		_add_box(target, Vector3(side * radius * 1.48, chassis_y - 0.13, -0.35), Vector3(0.38, 0.42, radius * 1.8), Color(0.10, 0.16, 0.18), 0.72, 0.36)
		for bogie_z in [-1.55, 0.85]:
			var wheel := _add_cylinder(target, Vector3(side * radius * 1.45, chassis_y - 0.26, bogie_z), 0.32, 0.20, Color(0.30, 0.39, 0.41), 0.78, 0.32)
			wheel.rotation.z = PI * 0.5
			var wheel_hub := _add_cylinder(target, Vector3(side * radius * 1.55, chassis_y - 0.26, bogie_z), 0.13, 0.055, Color(0.78, 0.34, 0.12), 0.72, 0.32)
			wheel_hub.rotation.z = PI * 0.5
		_add_box(target, Vector3(side * radius * 1.28, chassis_y + 0.74, -0.20), Vector3(0.72, 0.62, 1.05), Color(0.08, 0.17, 0.22), 0.68, 0.34)
		_add_pipe(target, Vector3(side * radius * 1.34, chassis_y + 0.92, -0.20), Vector3(side * radius * 0.74, -0.62, -0.02), 0.15, Color(0.44, 0.51, 0.52))
		_add_pipe(target, Vector3(side * radius * 0.74, -0.62, -0.02), Vector3(side * radius * 0.74, -radius, -0.02), 0.11, Color(0.72, 0.31, 0.13))
		for bolt_z in [-1.8, 1.0]:
			var bolt := _add_cylinder(target, Vector3(side * radius * 1.47, chassis_y + 0.41, bolt_z), 0.075, 0.035, Color(0.68, 0.76, 0.75), 0.84, 0.24)
			bolt.rotation.z = PI * 0.5
	var target_glow := OmniLight3D.new()
	target_glow.position = Vector3(0.0, 0.0, 0.9)
	target_glow.light_color = Color(0.16, 0.66, 0.88)
	target_glow.light_energy = 1.4
	target_glow.omni_range = radius * 2.2
	target_glow.shadow_enabled = false
	target.add_child(target_glow)
	return target


func _add_box(parent: Node3D, at: Vector3, size: Vector3, color: Color, metallic: float, roughness: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = at
	node.material_override = _material(color, metallic, roughness)
	parent.add_child(node)
	return node


func _add_cylinder(parent: Node3D, at: Vector3, radius: float, length: float, color: Color, metallic: float, roughness: float, horizontal := false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 32
	node.mesh = mesh
	node.position = at
	if horizontal:
		node.rotation.x = PI * 0.5
	node.material_override = _material(color, metallic, roughness)
	parent.add_child(node)
	return node


func _add_torus(parent: Node3D, at: Vector3, radius: float, thickness: float, color: Color, metallic: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - thickness
	mesh.outer_radius = radius + thickness
	mesh.rings = 32
	mesh.ring_segments = 12
	node.mesh = mesh
	node.position = at
	node.rotation.x = PI * 0.5
	node.material_override = _material(color, metallic, 0.36)
	parent.add_child(node)
	return node


func _add_pipe(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> void:
	var delta := to - from
	var pipe := _add_cylinder(parent, (from + to) * 0.5, radius, delta.length(), color, 0.48, 0.42)
	pipe.quaternion = Quaternion(Vector3.UP, delta.normalized())


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	if color.b > color.r * 1.7 and color.g > color.r * 1.7:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.9
	elif color.r > color.g * 1.35 and color.g > color.b * 2.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.8
	return material

func _ground_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
varying vec3 world_position;
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = world_position.xz;
	float broad = value_noise(p * 0.11);
	float aggregate = value_noise(p * 0.72 + vec2(4.3, 8.1));
	float micro = value_noise(p * 8.0);
	float grain = value_noise(p * 34.0);
	float damp = smoothstep(0.38, 0.72, value_noise(p * 0.24 + vec2(11.7, 2.4)));
	vec2 panel = fract(p / vec2(7.5, 9.0));
	float seam = max(1.0 - smoothstep(0.006, 0.018, min(panel.x, 1.0 - panel.x)),
		1.0 - smoothstep(0.006, 0.018, min(panel.y, 1.0 - panel.y)));
	float groove_left = abs(abs(p.x) - 3.55);
	float groove_right = abs(abs(p.x) - 4.05);
	float grooves = max(1.0 - smoothstep(0.025, 0.085, groove_left),
		1.0 - smoothstep(0.025, 0.085, groove_right));
	vec3 asphalt = vec3(0.027, 0.041, 0.052) * (0.76 + broad * 0.20 + aggregate * 0.12 + micro * 0.06);
	vec3 damp_reflection = vec3(0.075, 0.092, 0.105) * (0.52 + aggregate * 0.5);
	asphalt = mix(asphalt, damp_reflection, damp * 0.42);
	asphalt = mix(asphalt, vec3(0.012, 0.020, 0.026), seam * 0.52);
	asphalt = mix(asphalt, vec3(0.008, 0.015, 0.019), grooves * 0.88);
	ALBEDO = asphalt;
	METALLIC = 0.22 + damp * 0.24;
	ROUGHNESS = mix(0.72, 0.19, damp) + grain * 0.10;
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result
