extends Node3D

const RANGE_LENGTH := 2000.0
const AIR_DENSITY := 1.225 # kg/m^3 at sea level, 15 C
const SEA_LEVEL_SOUND_SPEED := 343.0
const PROJECTILE_TYPES := [
	{"name": "Dense slug", "mass": 42.0, "diameter": 0.18, "cd": 0.24, "shape": "slug", "length": 0.54, "color": Color(0.67, 0.78, 0.83)},
	{"name": "Training sphere", "mass": 24.0, "diameter": 0.20, "cd": 0.47, "shape": "sphere", "length": 0.20, "color": Color(0.86, 0.90, 0.88)},
	{"name": "Drag shuttle", "mass": 12.0, "diameter": 0.15, "cd": 0.92, "shape": "shuttle", "length": 0.375, "color": Color(1.0, 0.54, 0.18)},
]

var camera: Camera3D
var camera_focus := Vector3(0.0, 3.0, -210.0)
var camera_yaw := 0.20
var camera_pitch := 0.22
var camera_distance := 185.0
var status_label: Label
var analysis_label: Label
var projectile_picker: OptionButton
var speed_slider: HSlider
var elevation_slider: HSlider
var wind_slider: HSlider
var speed_value_label: Label
var elevation_value_label: Label
var wind_value_label: Label
var shot_count := 0
var camera_dragging := false
var active_shots: Dictionary = {}
var barrel_pivot: Node3D


func _ready() -> void:
	_build_world()
	_build_cannon()
	_build_range()
	_build_range_details()
	_build_hud()
	set_physics_process(true)


func _build_world() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.08, 0.16, 0.27)
	sky_material.sky_horizon_color = Color(0.46, 0.56, 0.63)
	sky_material.ground_bottom_color = Color(0.11, 0.14, 0.17)
	sky_material.ground_horizon_color = Color(0.38, 0.43, 0.45)
	environment.sky.sky_material = sky_material
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.67, 0.75, 0.84)
	environment.ambient_light_energy = 0.8
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.84, 0.68)
	sun.light_energy = 1.55
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.fov = 43.0
	add_child(camera)
	_update_camera()
	camera.make_current()

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(160.0, 2300.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.12, -950.0)
	ground.material_override = _material(Color(0.29, 0.34, 0.36), 0.08, 0.92)
	add_child(ground)
	var ground_body := StaticBody3D.new()
	ground_body.position = ground.position
	var ground_collision := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(160.0, 0.2, 2300.0)
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
			barrel_pivot = imported.find_child("ElevationPivot", true, false) as Node3D
			if is_instance_valid(barrel_pivot):
				barrel_pivot.set_meta("muzzle_offset", -6.18)
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

	# The barrel pivots in elevation; the muzzle and shot vector share this transform.
	barrel_pivot = Node3D.new()
	barrel_pivot.name = "ElevationPivot"
	barrel_pivot.position = Vector3(0.0, 1.47, 0.18)
	barrel_pivot.set_meta("muzzle_offset", -7.16)
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
	# Long side rails, broken into serviceable sections with illuminated lane markers.
	for side in [-1.0, 1.0]:
		for segment in range(10):
			var z_mid := -100.0 - float(segment) * 200.0
			_add_box(self, Vector3(side * 9.2, 0.36, z_mid), Vector3(0.22, 0.72, 199.0), Color(0.09, 0.17, 0.22), 0.42, 0.46)
			_add_box(self, Vector3(side * 9.2, 0.74, z_mid), Vector3(0.25, 0.045, 199.0), Color(1.0, 0.42, 0.10), 0.1, 0.36)
	for distance in range(250, 2001, 250):
		_add_box(self, Vector3(0.0, 0.02, -float(distance)), Vector3(0.28, 0.035, 2.2), Color(0.84, 0.89, 0.88), 0.05, 0.62)
		_add_box(self, Vector3(0.0, 0.13, -float(distance)), Vector3(4.4, 0.26, 0.16), Color(0.09, 0.16, 0.20), 0.25, 0.58)
		var distance_readout := Label3D.new()
		distance_readout.text = "%d M" % distance
		distance_readout.position = Vector3(-9.3, 1.25, -float(distance))
		distance_readout.font_size = 64
		distance_readout.pixel_size = 0.008
		distance_readout.modulate = Color(0.55, 0.85, 0.92)
		distance_readout.outline_size = 8
		add_child(distance_readout)
		for side in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 2.08, 0.26, -float(distance)), Vector3(0.12, 0.48, 0.18), Color(1.0, 0.52, 0.12), 0.12, 0.45)
	# Distance gates and target stations make the scale legible from the firing deck.
	for distance in [300.0, 700.0, 1100.0, 1500.0, 1900.0]:
		for side in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 8.0, 5.0, -distance), Vector3(0.18, 10.0, 0.22), Color(0.10, 0.18, 0.23), 0.34, 0.5)
			_add_box(self, Vector3(side * 8.0, 9.98, -distance), Vector3(0.24, 0.06, 0.26), Color(1.0, 0.36, 0.12), 0.08, 0.36)
		_add_box(self, Vector3(0.0, 10.02, -distance), Vector3(16.0, 0.16, 0.22), Color(0.12, 0.20, 0.24), 0.36, 0.5)
		_add_box(self, Vector3(0.0, 10.12, -distance), Vector3(3.2, 0.035, 0.25), Color(0.12, 0.84, 0.98), 0.04, 0.28)
	_add_target(Vector3(0.0, 3.1, -250.0), 2.5)
	_add_target(Vector3(-4.8, 2.5, -650.0), 2.1)
	_add_target(Vector3(4.5, 3.3, -1120.0), 1.8)
	_add_target(Vector3(0.0, 2.6, -1880.0), 1.4)
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 12.0, 0.025, -RANGE_LENGTH * 0.5), Vector3(0.16, 0.05, RANGE_LENGTH), Color(0.12, 0.76, 0.89), 0.05, 0.4)


func _build_range_details() -> void:
	# Raised launch deck gives the cannon a clear, readable silhouette.
	_add_box(self, Vector3(0.0, 0.12, 0.15), Vector3(5.2, 0.24, 7.2), Color(0.25, 0.30, 0.32), 0.22, 0.82)
	_add_box(self, Vector3(0.0, 0.255, 0.15), Vector3(4.8, 0.035, 6.8), Color(0.38, 0.42, 0.42), 0.08, 0.88)
	for side in [-1.0, 1.0]:
		_add_box(self, Vector3(side * 8.8, 0.16, -RANGE_LENGTH * 0.5), Vector3(0.38, 0.32, RANGE_LENGTH), Color(0.25, 0.31, 0.33), 0.12, 0.86)
		_add_box(self, Vector3(side * 8.8, 0.34, -RANGE_LENGTH * 0.5), Vector3(0.42, 0.045, RANGE_LENGTH), Color(0.96, 0.48, 0.10), 0.04, 0.62)
	for distance in [150.0, 400.0, 650.0, 900.0, 1150.0, 1400.0, 1650.0, 1900.0]:
		_add_box(self, Vector3(-7.25, 1.2, -distance), Vector3(0.18, 2.4, 0.18), Color(0.13, 0.19, 0.22), 0.04, 0.68)
		_add_box(self, Vector3(-7.25, 2.45, -distance), Vector3(1.55, 0.78, 0.12), Color(0.08, 0.16, 0.20), 0.05, 0.52)
		_add_box(self, Vector3(-7.25, 2.84, -distance - 0.07), Vector3(0.92, 0.035, 0.03), Color(0.08, 0.80, 0.95), 0.0, 0.28)
	# Side-mounted range lights frame the lane without spanning across the shot path.
	for distance in [-100.0, -400.0, -700.0, -1000.0, -1300.0, -1600.0, -1900.0]:
		for side in [-1.0, 1.0]:
			_add_box(self, Vector3(side * 10.0, 2.4, distance), Vector3(0.14, 4.8, 0.14), Color(0.16, 0.22, 0.25), 0.03, 0.62)
			_add_box(self, Vector3(side * 10.0, 4.85, distance), Vector3(0.9, 0.12, 0.34), Color(0.16, 0.22, 0.25), 0.04, 0.55)
			_add_box(self, Vector3(side * 10.0, 4.77, distance), Vector3(0.65, 0.035, 0.20), Color(0.35, 0.84, 0.96), 0.01, 0.24)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(26.0, 22.0)
	panel.custom_minimum_size = Vector2(370.0, 300.0)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var title := Label.new()
	title.text = "TRAJECTORY WORKS  /  RANGE 01"
	title.add_theme_font_size_override("font_size", 20)
	stack.add_child(title)
	status_label = Label.new()
	status_label.text = "HYPERVELOCITY RANGE  •  WIND: 0.0 M/S"
	status_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.95))
	stack.add_child(status_label)
	var hint := Label.new()
	hint.text = "2 KM BALLISTIC COURSE  •  DRAG TO ORBIT"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(hint)
	projectile_picker = OptionButton.new()
	for projectile_data in PROJECTILE_TYPES:
		projectile_picker.add_item(str(projectile_data.name))
	stack.add_child(projectile_picker)
	speed_value_label = Label.new()
	stack.add_child(speed_value_label)
	speed_slider = HSlider.new()
	speed_slider.min_value = 250.0
	speed_slider.max_value = 1500.0
	speed_slider.step = 10.0
	speed_slider.value = 700.0
	speed_slider.value_changed.connect(_on_speed_changed)
	stack.add_child(speed_slider)
	elevation_value_label = Label.new()
	stack.add_child(elevation_value_label)
	elevation_slider = HSlider.new()
	elevation_slider.min_value = -1.0
	elevation_slider.max_value = 15.0
	elevation_slider.step = 0.1
	elevation_slider.value = 0.7
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
	analysis_label.text = "SHOT DATA  •  No shot recorded"
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
	fire.pressed.connect(_fire_test_shot)
	layer.add_child(fire)
	_on_speed_changed(speed_slider.value)
	_on_elevation_changed(elevation_slider.value)
	_on_wind_changed(wind_slider.value)


func _on_speed_changed(value: float) -> void:
	if is_instance_valid(speed_value_label):
		speed_value_label.text = "MUZZLE VELOCITY  •  %.0f M/S  (MACH %.1F)" % [value, value / SEA_LEVEL_SOUND_SPEED]


func _on_wind_changed(value: float) -> void:
	if is_instance_valid(wind_value_label):
		wind_value_label.text = "CROSSWIND  •  %+.1f M/S" % value
	if is_instance_valid(status_label):
		status_label.text = "HYPERVELOCITY RANGE  •  WIND: %+.1f M/S" % value


func _on_elevation_changed(value: float) -> void:
	if is_instance_valid(elevation_value_label):
		elevation_value_label.text = "BARREL ELEVATION  •  %+.1f°" % value
	if is_instance_valid(barrel_pivot):
		barrel_pivot.rotation.x = deg_to_rad(value)


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
	var design: Dictionary = PROJECTILE_TYPES[projectile_picker.selected]
	status_label.text = "SHOT %02d  •  %s" % [shot_count, str(design.name).to_upper()]
	var projectile := RigidBody3D.new()
	projectile.name = "TestProjectile_%02d" % shot_count
	projectile.mass = float(design.mass)
	projectile.position = Vector3(0.0, 1.52, -6.92)
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
	mesh_instance.material_override = _material(design.color, 0.52, 0.22)
	projectile.add_child(mesh_instance)
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
	var speed := speed_slider.value
	var elevation := deg_to_rad(elevation_slider.value)
	var muzzle_forward := Vector3(0.0, sin(elevation), -cos(elevation))
	if is_instance_valid(barrel_pivot):
		var muzzle_offset := float(barrel_pivot.get_meta("muzzle_offset", -6.18))
		projectile.global_position = barrel_pivot.to_global(Vector3(0.0, 0.0, muzzle_offset))
		muzzle_forward = -barrel_pivot.global_transform.basis.z.normalized()
	projectile.linear_velocity = muzzle_forward * speed
	projectile.set_meta("design", design)
	projectile.set_meta("wind_x", wind_slider.value)
	active_shots[projectile.get_instance_id()] = {"body": projectile, "time": 0.0, "max_height": projectile.position.y, "origin": projectile.global_position, "design": design}
	if is_instance_valid(analysis_label):
		analysis_label.text = "IN FLIGHT  •  Cd %.2f / %.1F KG / %.0F MM" % [design.cd, design.mass, design.diameter * 1000.0]
	get_tree().create_timer(20.0).timeout.connect(func(): _remove_projectile(projectile))


func _physics_process(delta: float) -> void:
	for shot_id in active_shots.keys():
		var shot: Dictionary = active_shots[shot_id]
		var projectile: RigidBody3D = shot.body
		if not is_instance_valid(projectile):
			active_shots.erase(shot_id)
			continue
		var velocity := projectile.linear_velocity
		var wind_speed := float(projectile.get_meta("wind_x"))
		var relative_air_velocity := velocity - Vector3(wind_speed, 0.0, 0.0)
		var speed := relative_air_velocity.length()
		if speed > 0.01:
			var design: Dictionary = shot.design
			var radius := float(design.diameter) * 0.5
			var frontal_area := PI * radius * radius
			var effective_area := frontal_area
			var effective_cd := float(design.cd)
			if design.shape != "sphere":
				var long_axis := -projectile.global_transform.basis.z.normalized()
				var air_direction := relative_air_velocity.normalized()
				var axial_alignment := clampf(absf(long_axis.dot(air_direction)), 0.0, 1.0)
				var side_on := sqrt(1.0 - axial_alignment * axial_alignment)
				var side_area := float(design.length) * float(design.diameter) * side_on
				effective_area = frontal_area * axial_alignment + side_area
				effective_cd *= (axial_alignment + 1.6 * side_on) / maxf(axial_alignment + side_on, 0.001)
			# Approximate standard-atmosphere density falloff and transonic drag rise.
			var altitude := maxf(projectile.global_position.y, 0.0)
			var air_density := AIR_DENSITY * exp(-altitude / 8500.0)
			var mach := speed / SEA_LEVEL_SOUND_SPEED
			var mach_drag_factor := 1.0
			if mach >= 0.8 and mach < 1.2:
				mach_drag_factor = lerpf(1.0, 1.28, (mach - 0.8) / 0.4)
			elif mach >= 1.2 and mach < 3.0:
				mach_drag_factor = lerpf(1.28, 0.96, (mach - 1.2) / 1.8)
			elif mach >= 3.0:
				mach_drag_factor = 0.96
			var drag_magnitude := 0.5 * air_density * effective_cd * mach_drag_factor * effective_area * speed * speed
			projectile.apply_central_force(-relative_air_velocity.normalized() * drag_magnitude)
			# Orient long projectiles along their actual path while drag uses air-relative speed.
			if velocity.length() > 1.0:
				projectile.look_at(projectile.global_position + velocity.normalized(), Vector3.UP)
		shot.time = float(shot.time) + delta
		shot.max_height = maxf(float(shot.max_height), projectile.global_position.y)
		active_shots[shot_id] = shot


func _on_projectile_body_entered(body: Node, projectile: RigidBody3D) -> void:
	if not active_shots.has(projectile.get_instance_id()):
		return
	var shot: Dictionary = active_shots[projectile.get_instance_id()]
	var displacement: Vector3 = projectile.global_position - shot.origin
	var range_m := -displacement.z
	var result := "IMPACT • %.1f M • X %+.1f M" % [range_m, displacement.x]
	if body.is_in_group("range_targets"):
		result = "TARGET HIT • %.1f M • X %+.1f M" % [range_m, displacement.x]
	status_label.text = "SHOT %02d  •  %s" % [shot_count, result]
	analysis_label.text = "%s\nTIME %.2F S  •  APEX %.1F M\nMASS %.1F KG  •  Cd %.2F" % [result, shot.time, shot.max_height, shot.design.mass, shot.design.cd]
	active_shots.erase(projectile.get_instance_id())


func _remove_projectile(projectile: RigidBody3D) -> void:
	if is_instance_valid(projectile):
		active_shots.erase(projectile.get_instance_id())
		projectile.queue_free()


func _add_target(at: Vector3, radius: float) -> void:
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
	var hit_shape := CollisionShape3D.new()
	var hit_disc := CylinderShape3D.new()
	hit_disc.radius = radius
	hit_disc.height = 0.24
	hit_shape.shape = hit_disc
	hit_shape.rotation.x = PI * 0.5
	target_body.add_child(hit_shape)
	target.add_child(target_body)
	target.position = at
	_add_box(target, Vector3(0.0, -radius - 0.42, 0.05), Vector3(radius * 1.4, 0.72, 0.4), Color(0.12, 0.20, 0.24), 0.28, 0.62)
	_add_pipe(self, at + Vector3(0.0, -radius, 0.0), at + Vector3(0.0, -radius - 0.8, 0.0), 0.07, Color(0.22, 0.28, 0.30))


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
		material.emission = color * 0.45
	return material
