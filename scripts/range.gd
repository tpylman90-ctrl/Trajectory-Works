extends Node3D

const PROJECTILE_SPEED := 31.0

var camera: Camera3D
var status_label: Label
var shot_count := 0
var camera_dragging := false
var last_touch := Vector2.ZERO


func _ready() -> void:
	_build_world()
	_build_cannon()
	_build_range()
	_build_hud()


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
	environment.ambient_light_color = Color(0.56, 0.65, 0.78)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	sun.light_color = Color(1.0, 0.84, 0.68)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.position = Vector3(11.5, 7.2, 14.5)
	camera.fov = 48.0
	add_child(camera)
	camera.look_at(Vector3(0.0, 1.7, -8.0), Vector3.UP)
	camera.make_current()

	var ground := MeshInstance3D.new()
	var ground_mesh := PlaneMesh.new()
	ground_mesh.size = Vector2(70.0, 100.0)
	ground.mesh = ground_mesh
	ground.position = Vector3(0.0, -0.12, -25.0)
	ground.material_override = _material(Color(0.19, 0.23, 0.24), 0.9, 0.0)
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
	# If Blender has already generated the GLB, use that asset. The built-in
	# model below keeps the project runnable before the first CI asset build.
	var glb_path := "res://assets/generated/trajectory_cannon.glb"
	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed != null:
			var imported := packed.instantiate()
			add_child(imported)
			return

	var cannon := Node3D.new()
	cannon.name = "CannonPreview"
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


func _build_range() -> void:
	for distance in [12.0, 24.0, 38.0]:
		_add_box(self, Vector3(0.0, 0.015, -distance), Vector3(0.22, 0.03, 1.0), Color(0.78, 0.83, 0.80), 0.0, 0.9)
		_add_box(self, Vector3(0.0, 0.12, -distance), Vector3(4.2, 0.24, 0.14), Color(0.12, 0.18, 0.22), 0.03, 0.7)
		_add_box(self, Vector3(-1.95, 0.22, -distance), Vector3(0.12, 0.42, 0.18), Color(0.92, 0.55, 0.12), 0.02, 0.58)
		_add_box(self, Vector3(1.95, 0.22, -distance), Vector3(0.12, 0.42, 0.18), Color(0.92, 0.55, 0.12), 0.02, 0.58)
	_add_target(Vector3(0.0, 2.2, -32.0), 2.5)
	_add_target(Vector3(-5.0, 1.6, -46.0), 1.7)
	_add_box(self, Vector3(-8.0, 0.025, -24.0), Vector3(0.12, 0.05, 48.0), Color(0.92, 0.50, 0.12), 0.0, 0.7)
	_add_box(self, Vector3(8.0, 0.025, -24.0), Vector3(0.12, 0.05, 48.0), Color(0.92, 0.50, 0.12), 0.0, 0.7)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(26.0, 22.0)
	panel.custom_minimum_size = Vector2(310.0, 120.0)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	panel.add_child(stack)
	var title := Label.new()
	title.text = "TRAJECTORY WORKS  /  RANGE 01"
	title.add_theme_font_size_override("font_size", 20)
	stack.add_child(title)
	status_label = Label.new()
	status_label.text = "SYSTEM READY  •  PRESSURE: TRAINING"
	status_label.add_theme_color_override("font_color", Color(0.55, 0.88, 0.95))
	stack.add_child(status_label)
	var hint := Label.new()
	hint.text = "Touch-drag to orbit the camera  •  Tap FIRE to test"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	fire.pressed.connect(_fire_test_shot)
	layer.add_child(fire)


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
	mesh_instance.material_override = _material(Color(0.82, 0.87, 0.86), 0.36, 0.16)
	projectile.add_child(mesh_instance)
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
	var outer := _add_cylinder(target, Vector3(0.0, 0.0, -0.10), radius * 0.76, 0.05, Color(0.89, 0.36, 0.10), 0.18, 0.5, true)
	outer.rotation.x = PI * 0.5
	var inner := _add_cylinder(target, Vector3(0.0, 0.0, -0.14), radius * 0.40, 0.05, Color(0.82, 0.84, 0.77), 0.12, 0.45, true)
	inner.rotation.x = PI * 0.5
	var center := _add_cylinder(target, Vector3(0.0, 0.0, -0.18), radius * 0.15, 0.06, Color(0.10, 0.68, 0.82), 0.12, 0.28, true)
	center.rotation.x = PI * 0.5
	target.position = at
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
