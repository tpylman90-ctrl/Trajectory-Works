extends Node3D

const RANGE_LENGTH := 2000.0
const AIR_DENSITY := 1.225
const SEA_LEVEL_SOUND_SPEED := 343.0
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


func _ready() -> void:
	Engine.physics_ticks_per_second = 120
	_build_world()
	_build_cannon()
	_add_ambient_steam()
	_build_range()
	_build_range_details()
	_build_range_assets()
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
			# Compress only the imported vertical axis to keep the armored receiver at believable scale.
			imported.scale.z = 0.5
			imported.position.y = 0.385
			add_child(imported)
			barrel_pivot = imported.find_child("ElevationPivot", true, false) as Node3D
			if is_instance_valid(barrel_pivot):
				barrel_pivot_base_rotation = barrel_pivot.rotation
				barrel_pivot.set_meta("muzzle_offset", -6.12)
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
	_on_speed_changed(speed_slider.value)
	_on_elevation_changed(elevation_slider.value)
	_on_wind_changed(wind_slider.value)
	_add_hud_corner_marks(layer, panel)


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
	var design: Dictionary = PROJECTILE_TYPES[projectile_picker.selected]
	status_label.text = "SHOT %02d  •  %s" % [shot_count, str(design.name).to_upper()]
	var projectile := RigidBody3D.new()
	projectile.name = "TestProjectile_%02d" % shot_count
	projectile.mass = float(design.mass)
	projectile.linear_damp = 0.0
	projectile.angular_damp = 1.5
	projectile.continuous_cd = true
	projectile.contact_monitor = true
	projectile.max_contacts_reported = 4
	projectile.body_entered.connect(_on_projectile_body_entered.bind(projectile))
	var mesh_instance := MeshInstance3D.new()
	var radius := float(design.diameter) * 0.5
	var mesh: Mesh
	if design.shape == "sphere":
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
	mesh_instance.rotation.x = PI * 0.5
	var projectile_material := _material(design.color, 0.52, 0.22)
	projectile_material.emission_enabled = true
	projectile_material.emission = Color(0.18, 0.73, 1.0) if design.shape != "shuttle" else Color(1.0, 0.28, 0.06)
	projectile_material.emission_energy_multiplier = 3.0
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
	projectile_light.light_color = Color(0.15, 0.72, 1.0)
	projectile_light.light_energy = 3.0
	projectile_light.omni_range = 4.5
	projectile_light.shadow_enabled = false
	projectile.add_child(projectile_light)
	var collision := CollisionShape3D.new()
	var collision_shape: Shape3D
	if design.shape == "sphere":
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
	projectile.linear_velocity = muzzle_forward * speed_slider.value
	last_projectile = projectile
	if projectile_camera_enabled:
		followed_projectile = projectile
	projectile.set_meta("design", design)
	projectile.set_meta("wind_x", wind_slider.value)
	active_shots[projectile.get_instance_id()] = {"body": projectile, "number": shot_count, "time": 0.0, "max_height": projectile.global_position.y, "origin": projectile.global_position, "design": design}
	analysis_label.text = "IN FLIGHT  •  %0.1f KG / %0.0f MM / Cd %0.2f" % [design.mass, design.diameter * 1000.0, design.cd]
	# Shots remain active until impact; the long failsafe only cleans up runaway bodies.


func _physics_process(delta: float) -> void:
	for shot_id in active_shots.keys():
		var shot: Dictionary = active_shots[shot_id]
		var projectile: RigidBody3D = shot.body
		if not is_instance_valid(projectile):
			active_shots.erase(shot_id)
			continue
		var velocity := projectile.linear_velocity
		var relative_air_velocity := velocity - Vector3(float(projectile.get_meta("wind_x")), 0.0, 0.0)
		var speed := relative_air_velocity.length()
		if speed > 0.01:
			var design: Dictionary = shot.design
			var radius := float(design.diameter) * 0.5
			var projected_area := PI * radius * radius
			var effective_cd := float(design.cd)
			if design.shape != "sphere":
				var axis := -projectile.global_transform.basis.z.normalized()
				var air_direction := relative_air_velocity.normalized()
				var axial_alignment := clampf(absf(axis.dot(air_direction)), 0.0, 1.0)
				var side_on := sqrt(1.0 - axial_alignment * axial_alignment)
				var side_area := float(design.length) * float(design.diameter) * side_on
				projected_area = projected_area * axial_alignment + side_area
				effective_cd *= (axial_alignment + 1.6 * side_on) / maxf(axial_alignment + side_on, 0.001)
			var density := AIR_DENSITY * exp(-maxf(projectile.global_position.y, 0.0) / 8500.0)
			var mach := speed / SEA_LEVEL_SOUND_SPEED
			var mach_drag_factor := 1.0
			if mach >= 0.8 and mach < 1.2:
				mach_drag_factor = lerpf(1.0, 1.28, (mach - 0.8) / 0.4)
			elif mach >= 1.2 and mach < 3.0:
				mach_drag_factor = lerpf(1.28, 0.96, (mach - 1.2) / 1.8)
			elif mach >= 3.0:
				mach_drag_factor = 0.96
			var drag := 0.5 * density * effective_cd * mach_drag_factor * projected_area * speed * speed
			projectile.apply_central_force(-relative_air_velocity.normalized() * drag)
			if velocity.length() > 1.0:
				projectile.look_at(projectile.global_position + velocity.normalized(), Vector3.UP)
		if projectile == followed_projectile:
			if is_instance_valid(ground_visual):
				ground_visual.global_position = Vector3(projectile.global_position.x, ground_home.y, projectile.global_position.z)
				var desired_ground_size := clampf(maxf(100000.0, projectile.global_position.y * 24.0), 100000.0, 12000000.0)
				if absf(desired_ground_size - ground_render_size) > ground_render_size * 0.08:
					ground_render_size = desired_ground_size
					ground_mesh.size = Vector2(ground_render_size, ground_render_size)
			_update_projectile_camera(projectile)
		shot.time = float(shot.time) + delta
		shot.max_height = maxf(float(shot.max_height), projectile.global_position.y)
		if shot.time >= MAX_SHOT_FLIGHT_TIME or projectile.global_position.distance_squared_to(shot.origin) >= MAX_SHOT_TRAVEL * MAX_SHOT_TRAVEL:
			_remove_projectile(projectile)
			continue
		active_shots[shot_id] = shot


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
	var impact_speed := projectile.linear_velocity.length()
	analysis_label.text = "%s\nTIME %0.2f S  •  APEX %0.1f M\nIMPACT %0.0f M/S (MACH %0.2f)\nMASS %0.1f KG  •  Cd %0.2f" % [result, shot.time, shot.max_height, impact_speed, impact_speed / SEA_LEVEL_SOUND_SPEED, shot.design.mass, shot.design.cd]
	active_shots.erase(shot_id)
	if projectile == followed_projectile:
		_toggle_projectile_camera()
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
