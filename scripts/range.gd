extends Node3D

const PROJECTILE_SPEED := 31.0

var camera: Camera3D
var camera_focus := Vector3(0.0, 1.55, -10.0)
var camera_yaw := 0.30
var camera_pitch := 0.18
var camera_distance := 25.0
var status_label: Label
var shot_count := 0
var camera_dragging := false
var last_touch := Vector2.ZERO


func _ready() -> void:
	_build_world()
	_build_cannon()
	_build_range()
	_build_range_details()
	_build_range_assets()
	_build_hud()


func _build_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.035, 0.075, 0.14)
	sky_material.sky_horizon_color = Color(0.32, 0.43, 0.52)
	sky_material.ground_bottom_color = Color(0.045, 0.075, 0.095)
	sky_material.ground_horizon_color = Color(0.22, 0.30, 0.34)
	environment.sky.sky_material = sky_material
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_color = Color(0.45, 0.60, 0.76)
	environment.ambient_light_energy = 0.9
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.32, 0.43, 0.52)
	environment.fog_density = 0.012
	environment.fog_sun_scatter = 0.12
	environment.glow_enabled = true
	environment.glow_levels = 31
	environment.glow_intensity = 0.8
	environment.glow_strength = 1.0
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.72, 0.49)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 43.0
	add_child(camera)
	_update_camera()
	camera.make_current()

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(70.0, 100.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.12, -25.0)
	ground.material_override = _ground_material()
	add_child(ground)
	var ground_body := StaticBody3D.new()
	ground_body.position = ground.position
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(70.0, 0.2, 100.0)
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
			imported.position.y = 0.385
			add_child(imported)
			var mesh_points: Array[Vector3] = []
			_collect_mesh_points(imported, Transform3D.IDENTITY, mesh_points)
			if not mesh_points.is_empty():
				var bounds := AABB(mesh_points[0], Vector3.ZERO)
				for point in mesh_points:
					bounds = bounds.expand(point)
				var looks_like_cannon := bounds.size.y > 0.8 and bounds.size.y < 3.2 and bounds.size.z > 6.0 and bounds.position.z < -5.5 and bounds.end.z > 1.0 and bounds.position.y > -0.8 and bounds.end.y < 3.5
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

	# Long barrel points downrange along -Z.
	_add_cylinder(cannon, Vector3(0.0, 1.47, -3.95), 0.36, 5.8, Color(0.42, 0.49, 0.54), 0.22, 0.72, true)
	_add_cylinder(cannon, Vector3(0.0, 1.47, -6.82), 0.48, 0.38, Color(0.10, 0.16, 0.20), 0.32, 0.48, true)
	_add_cylinder(cannon, Vector3(0.0, 1.47, -6.98), 0.34, 0.07, Color(0.15, 0.87, 1.0), 0.2, 0.24, true)

	# Exposed copper coil stack and luminous containment bands.
	for i in range(8):
		var z := -0.95 - float(i) * 0.28
		_add_torus(cannon, Vector3(0.0, 1.47, z), 0.48, 0.075, Color(0.77, 0.34, 0.14), 0.26)
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
	_add_target(Vector3(0.0, 2.9, -32.0), 2.5)
	_add_target(Vector3(-5.0, 1.6, -46.0), 1.7)
	_add_box(self, Vector3(-8.0, 0.025, -24.0), Vector3(0.12, 0.05, 48.0), Color(0.96, 0.48, 0.10), 0.0, 0.7)
	_add_box(self, Vector3(8.0, 0.025, -24.0), Vector3(0.12, 0.05, 48.0), Color(0.96, 0.48, 0.10), 0.0, 0.7)


func _build_range_details() -> void:
	# Raised launch deck gives the cannon a clear, readable silhouette.
	_add_box(self, Vector3(0.0, 0.12, 0.15), Vector3(5.2, 0.24, 7.2), Color(0.25, 0.30, 0.32), 0.22, 0.82)
	_add_box(self, Vector3(0.0, 0.255, 0.15), Vector3(4.8, 0.035, 6.8), Color(0.38, 0.42, 0.42), 0.08, 0.88)
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 8.8, 0.16, -24.0), Vector3(0.38, 0.32, 50.0), Color(0.25, 0.31, 0.33), 0.12, 0.86)
		_add_box(self, Vector3(side * 8.8, 0.34, -24.0), Vector3(0.42, 0.045, 50.0), Color(0.96, 0.48, 0.10), 0.04, 0.62)
	for distance in [12.0, 24.0, 38.0]:
		_add_box(self, Vector3(-7.25, 1.2, -distance), Vector3(0.18, 2.4, 0.18), Color(0.13, 0.19, 0.22), 0.04, 0.68)
		_add_box(self, Vector3(-7.25, 2.45, -distance), Vector3(1.55, 0.78, 0.12), Color(0.08, 0.16, 0.20), 0.05, 0.52)
		_add_box(self, Vector3(-7.25, 2.84, -distance - 0.07), Vector3(0.92, 0.035, 0.03), Color(0.08, 0.80, 0.95), 0.0, 0.28)
	# Recessed lane strips and deck edge markings give the firing line a designed, industrial read.
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 2.34, 0.285, 0.15), Vector3(0.055, 0.025, 6.45), Color(0.96, 0.39, 0.09), 0.28, 0.38)
		_add_box(self, Vector3(side * 2.22, 0.284, 0.15), Vector3(0.035, 0.022, 6.18), Color(0.15, 0.75, 0.90), 0.35, 0.32)
	# Launch-deck jacks, flush panel seams, and hazard corners make the cannon feel installed.
	for side in [-1.0, 1.0]:
		for fore in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 2.05, 0.13, 0.15 + fore * 2.75), Vector3(0.34, 0.34, 0.42), Color(0.065, 0.10, 0.13), 0.64, 0.55)
			_add_box(self, Vector3(side * 2.34, 0.282, 0.15 + fore * 3.05), Vector3(0.18, 0.025, 0.62), Color(0.94, 0.35, 0.08), 0.2, 0.42)
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
	# Distant utility buildings and stacked luminaires break up the bare horizon.
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 14.3, 2.8, -51.5), Vector3(5.6, 5.6, 7.4), Color(0.075, 0.12, 0.16), 0.42, 0.72)
		_add_box(self, Vector3(side * 14.3, 5.65, -51.5), Vector3(6.0, 0.18, 7.8), Color(0.12, 0.19, 0.23), 0.66, 0.48)
		for floor_y in [1.7, 2.65, 3.6]:
			_add_box(self, Vector3(side * 14.3, floor_y, -47.72), Vector3(3.8, 0.38, 0.035), Color(0.13, 0.53, 0.64), 0.22, 0.32)
		for side_offset in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 14.3 + side_offset * 1.7, 1.0, -47.6), Vector3(0.12, 1.8, 0.10), Color(0.20, 0.29, 0.33), 0.65, 0.45)
	# Side-mounted range lights frame the lane without spanning across the shot path.
	for distance in [-5.0, -22.0, -40.0]:
		for side in [-1.0, 1.0]:
			if distance != -40.0:
				var flood := OmniLight3D.new()
				flood.position = Vector3(side * 9.65, 4.58, distance)
				flood.light_color = Color(1.0, 0.54, 0.30)
				flood.light_energy = 2.4
				flood.omni_range = 13.0
				flood.shadow_enabled = false
				add_child(flood)
				var beam := SpotLight3D.new()
				beam.position = Vector3(side * 9.65, 4.55, distance)
				beam.light_color = Color(1.0, 0.68, 0.43)
				beam.light_energy = 5.0
				beam.spot_range = 28.0
				beam.spot_angle = 48.0
				beam.shadow_enabled = false
				add_child(beam)
				beam.look_at(Vector3(0.0, 0.0, distance - 15.0), Vector3.UP)


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
	glass.bg_color = Color(0.018, 0.038, 0.055, 0.86)
	glass.border_color = Color(0.20, 0.78, 0.91, 0.82)
	glass.set_border_width_all(1)
	glass.border_width_left = 3
	glass.set_corner_radius_all(7)
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
	status_label.text = "SYSTEM READY  •  PRESSURE: TRAINING"
	status_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.95))
	stack.add_child(status_label)
	var hint := Label.new()
	hint.text = "Drag to orbit the range  •  Fire a test shot to inspect its flight"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.75, 0.86, 0.90))
	stack.add_child(hint)
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
	button_normal.bg_color = Color(0.015, 0.075, 0.095, 0.92)
	button_normal.border_color = Color(0.12, 0.76, 0.91, 0.9)
	button_normal.set_border_width_all(2)
	button_normal.set_corner_radius_all(4)
	var button_hover := StyleBoxFlat.new()
	button_hover.bg_color = Color(0.04, 0.23, 0.29, 0.96)
	button_hover.border_color = Color(0.35, 0.91, 1.0)
	button_hover.set_border_width_all(2)
	button_hover.set_corner_radius_all(4)
	fire.add_theme_stylebox_override("normal", button_normal)
	fire.add_theme_stylebox_override("hover", button_hover)
	fire.add_theme_color_override("font_color", Color(0.55, 0.94, 1.0))
	fire.pressed.connect(_fire_test_shot)
	layer.add_child(fire)


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
	var horizontal := camera_distance * cos(camera_pitch)
	camera.position = camera_focus + Vector3(sin(camera_yaw) * horizontal, sin(camera_pitch) * camera_distance, cos(camera_yaw) * horizontal)
	camera.look_at(camera_focus, Vector3.UP)


func _fire_test_shot() -> void:
	shot_count += 1
	status_label.text = "SHOT %02d  •  SIMULATION RUNNING" % shot_count
	var projectile := RigidBody3D.new()
	projectile.name = "TestProjectile_%02d" % shot_count
	projectile.mass = 0.45
	projectile.position = Vector3(0.0, 1.48, -6.9)
	projectile.linear_damp = 0.02
	projectile.angular_damp = 0.08
	var mesh_instance := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	mesh_instance.mesh = mesh
	var projectile_material := _material(Color(0.82, 0.90, 0.94), 0.45, 0.16)
	projectile_material.emission_enabled = true
	projectile_material.emission = Color(0.18, 0.73, 1.0)
	projectile_material.emission_energy_multiplier = 2.5
	mesh_instance.material_override = projectile_material
	projectile.add_child(mesh_instance)
	var projectile_light := OmniLight3D.new()
	projectile_light.light_color = Color(0.15, 0.72, 1.0)
	projectile_light.light_energy = 3.0
	projectile_light.omni_range = 4.5
	projectile_light.shadow_enabled = false
	projectile.add_child(projectile_light)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.22
	collision.shape = shape
	projectile.add_child(collision)
	add_child(projectile)
	projectile.apply_central_impulse(Vector3(0.0, 8.0, -PROJECTILE_SPEED))
	get_tree().create_timer(5.0).timeout.connect(func(): _remove_projectile(projectile))


func _remove_projectile(projectile: RigidBody3D) -> void:
	if is_instance_valid(projectile):
		projectile.queue_free()
	if is_instance_valid(status_label):
		status_label.text = "SHOT %02d  •  READY FOR ANALYSIS" % shot_count


func _add_target(at: Vector3, radius: float) -> void:
	var target := Node3D.new()
	add_child(target)
	var backing := _add_cylinder(target, Vector3.ZERO, radius, 0.16, Color(0.11, 0.16, 0.19), 0.24, 0.65, true)
	backing.rotation.x = PI * 0.5
	var outer := _add_cylinder(target, Vector3(0.0, 0.0, 0.10), radius * 0.76, 0.05, Color(0.96, 0.42, 0.11), 0.18, 0.5, true)
	outer.rotation.x = PI * 0.5
	var inner := _add_cylinder(target, Vector3(0.0, 0.0, 0.16), radius * 0.40, 0.05, Color(0.92, 0.94, 0.87), 0.12, 0.45, true)
	inner.rotation.x = PI * 0.5
	var center := _add_cylinder(target, Vector3(0.0, 0.0, 0.22), radius * 0.15, 0.06, Color(0.10, 0.78, 0.96), 0.12, 0.28, true)
	center.rotation.x = PI * 0.5
	target.position = at
	var target_glow := OmniLight3D.new()
	target_glow.position = at + Vector3(0.0, 0.0, 0.9)
	target_glow.light_color = Color(0.16, 0.66, 0.88)
	target_glow.light_energy = 1.4
	target_glow.omni_range = radius * 2.2
	target_glow.shadow_enabled = false
	add_child(target_glow)


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
		material.emission_energy_multiplier = 2.3
	elif color.r > color.g * 1.35 and color.g > color.b * 2.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.5
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
	float broad = value_noise(p * 0.22);
	float aggregate = value_noise(p * 1.1);
	float grain = value_noise(p * 12.0);
	vec2 panel = fract(p / vec2(7.5, 9.0));
	float seam = max(1.0 - smoothstep(0.006, 0.018, min(panel.x, 1.0 - panel.x)),
		1.0 - smoothstep(0.006, 0.018, min(panel.y, 1.0 - panel.y)));
	vec3 concrete = vec3(0.115, 0.155, 0.178);
	concrete *= 0.76 + broad * 0.20 + aggregate * 0.09 + grain * 0.035;
	concrete = mix(concrete, vec3(0.035, 0.055, 0.068), seam * 0.82);
	ALBEDO = concrete;
	METALLIC = 0.16 + aggregate * 0.08;
	ROUGHNESS = 0.80 + grain * 0.15;
}
"""
	var result := ShaderMaterial.new()
	result.shader = shader
	return result
