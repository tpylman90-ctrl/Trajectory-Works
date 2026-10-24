extends SceneTree

const RANGE_SCRIPT := preload("res://scripts/range.gd")
const GAS_CONSTANT := 287.05
const GAMMA := 1.4
const ATMOSPHERE_RADIUS := 6356766.0

var failures := 0


func _initialize() -> void:
	var model = RANGE_SCRIPT.new()
	_check_atmosphere(model)
	_check_layer_continuity(model)
	_check_gravity(model)
	_check_dynamic_pressure(model)
	_check_wind_profile(model)
	_check_design_persistence_helpers(model)
	_check_challenge_requirements(model)
	model.free()
	if failures == 0:
		print("Physics validation passed: atmosphere layers, continuity, gravity, dynamic pressure, and wind shear.")
		quit(0)
	else:
		printerr("Physics validation failed: %d check(s)." % failures)
		quit(1)


func _check_atmosphere(model: Object) -> void:
	# Reference checkpoints at geometric altitude, cross-checked with the
	# 1976 U.S. Standard Atmosphere layer equations.
	var checkpoints := [
		[0.0, 1.2250123],
		[11000.0, 0.3647996],
		[20000.0, 0.0889095],
		[32000.0, 0.0135550],
		[47000.0, 0.0014965],
		[51000.0, 0.00090691],
		[71000.0, 0.000071964],
		[84852.0, 0.0000084234],
	]
	var previous_density := INF
	for checkpoint in checkpoints:
		var altitude := float(checkpoint[0])
		var expected_density := float(checkpoint[1])
		var state: Dictionary = model.call("_atmosphere_state", altitude)
		var density := float(state.density)
		var pressure := float(state.pressure)
		var temperature := float(state.temperature)
		var sound_speed := float(state.sound_speed)
		_expect_close("density at %0.0f m" % altitude, density, expected_density, expected_density * 0.015)
		_expect_close("ideal-gas pressure relation at %0.0f m" % altitude, pressure, density * GAS_CONSTANT * temperature, maxf(pressure * 0.00001, 0.000001))
		_expect_close("sound speed at %0.0f m" % altitude, sound_speed, sqrt(GAMMA * GAS_CONSTANT * temperature), 0.001)
		_expect_true("positive viscosity at %0.0f m" % altitude, float(state.dynamic_viscosity) > 0.0)
		_expect_true("density decreases at %0.0f m" % altitude, density < previous_density)
		previous_density = density


func _check_layer_continuity(model: Object) -> void:
	var geopotential_breaks := [11000.0, 20000.0, 32000.0, 47000.0, 51000.0, 71000.0, 84852.0]
	for boundary in geopotential_breaks:
		var boundary_altitude := float(boundary)
		var geometric: float = ATMOSPHERE_RADIUS * boundary_altitude / (ATMOSPHERE_RADIUS - boundary_altitude)
		var below: Dictionary = model.call("_atmosphere_state", geometric - 1.0)
		var above: Dictionary = model.call("_atmosphere_state", geometric + 1.0)
		var density_gap := absf(float(above.density) - float(below.density)) / maxf(float(below.density), 0.000000001)
		_expect_true("atmosphere continuity at %0.0f m" % boundary, density_gap < 0.002)


func _check_gravity(model: Object) -> void:
	_expect_close("sea-level gravity", float(model.call("_local_gravity", 0.0)), 9.80665, 0.00001)
	var expected_100km := 9.80665 * pow(6371000.0 / 6471000.0, 2.0)
	_expect_close("inverse-square gravity at 100 km", float(model.call("_local_gravity", 100000.0)), expected_100km, 0.00001)


func _check_dynamic_pressure(model: Object) -> void:
	_expect_close("dynamic pressure at 100 m/s", float(model.call("_dynamic_pressure", 1.225, 100.0)), 6125.0, 0.00001)
	_expect_close("dynamic pressure scales with speed squared", float(model.call("_dynamic_pressure", 1.225, 200.0)), 24500.0, 0.00001)


func _check_wind_profile(model: Object) -> void:
	_expect_close("surface wind at ground", float(model.call("_wind_at_altitude", 3.0, 8.0, 0.0)), 3.0, 0.00001)
	_expect_close("linear wind shear at 5 km", float(model.call("_wind_at_altitude", 3.0, 8.0, 5000.0)), 7.0, 0.00001)
	_expect_close("full wind shear at 10 km", float(model.call("_wind_at_altitude", 3.0, 8.0, 10000.0)), 11.0, 0.00001)
	_expect_close("wind profile clamps below ground", float(model.call("_wind_at_altitude", 3.0, 8.0, -100.0)), 3.0, 0.00001)
	_expect_close("wind profile caps above 10 km", float(model.call("_wind_at_altitude", 3.0, 8.0, 25000.0)), 11.0, 0.00001)


func _check_design_persistence_helpers(model: Object) -> void:
	var sample := {
		"name": "Test Twist Round", "shape": "custom", "mass": 19.5, "diameter": 0.12,
		"length": 0.72, "cd": 0.25, "nose": "Ogive", "material": "Tungsten alloy",
		"density": 18000.0, "tip_length": 0.17,
		"stations": [{"pull": 0.82, "bend_x": 0.1, "bend_y": -0.1, "twist": 0.6}],
		"surface_pattern": "grooves", "rib_count": 8, "rib_depth": 0.004,
		"tip_surface_pattern": "ribs", "tip_rib_depth": 0.003, "spiral_turns": 1.5,
	}
	var saved: Dictionary = model.call("_serialize_design", sample)
	var restored: Dictionary = model.call("_deserialize_saved_design", saved)
	_expect_true("saved round keeps custom geometry", str(restored.get("shape", "")) == "custom")
	_expect_true("saved round keeps material", str(restored.get("material", "")) == "Tungsten alloy")
	_expect_true("saved round keeps spiral channels", is_equal_approx(float(restored.get("spiral_turns", 0.0)), 1.5))
	_expect_true("saved round keeps sculpt stations", (restored.get("stations", []) as Array).size() == 1)
	_expect_true("round-trip mass remains physical", float(restored.get("mass", 0.0)) > 0.0)


func _check_challenge_requirements(model: Object) -> void:
	var challenge := {"min_score": 25, "requires_custom": true, "requires_gate": true, "target_m": 8000, "gate_m": 4000, "gate_material": 0, "gate_thickness": 100}
	var summary := {
		"outcome": "TARGET HIT • 50 PTS", "target_score": 50, "target_distance_m": 8000,
		"design": {"shape": "custom"}, "gate_log": ["ARMOR STEEL 100 MM PERFORATED"],
		"gate_passes": [{"material_index": 0, "thickness_mm": 100, "distance_m": 4000}],
	}
	_expect_true("challenge accepts valid custom gate hit", str(model.call("_challenge_failure_reason", challenge, summary)).is_empty())
	var missing_gate := summary.duplicate(true)
	missing_gate["gate_passes"] = []
	_expect_true("challenge requires gate perforation", not str(model.call("_challenge_failure_reason", challenge, missing_gate)).is_empty())
	var low_score := summary.duplicate(true)
	low_score["target_score"] = 10
	_expect_true("challenge enforces target score", not str(model.call("_challenge_failure_reason", challenge, low_score)).is_empty())


func _expect_close(label: String, actual: float, expected: float, tolerance: float) -> void:
	if not is_finite(actual) or absf(actual - expected) > tolerance:
		failures += 1
		printerr("%s: expected %0.8f ± %0.8f, got %0.8f" % [label, expected, tolerance, actual])


func _expect_true(label: String, condition: bool) -> void:
	if not condition:
		failures += 1
		printerr("Failed: %s" % label)
