class_name DmjShotFx3D
extends Node3D

## Cosmetic world-space hitscan feedback. No shot keeps a combat actor alive.
enum Kind { DOWN, PLATE, MISS, HOSTILE }

const LIFETIME := 0.72
const DESTRUCTION_LIFETIME := 1.05
const RESULT_SETTLE := 0.32
const KILL_SETTLE := JamBot.DEATH_FADE + 0.08
const MAX_SHOTS := 32
const MAX_PARTICLES := 128
const FLIGHT_SECONDS := 0.1

var muzzle := Vector3(0, 1, 10)
var last_color := DmjPalette.AMBER
var _shots: Array[Dictionary] = []
var _visuals: Array[Node3D] = []
var _particles: Array[Dictionary] = []
var _serial := 0
var _reduced_motion := false
var _effects_enabled := true
var _recoil_age := 1.0
var _flash_strength := 1.0


func _init() -> void:
	set_process(false)


func set_presentation_options(reduced_motion: bool, effects_enabled: bool) -> void:
	_reduced_motion = reduced_motion
	_effects_enabled = effects_enabled
	if not motion_enabled():
		_clear_particles()
		_recoil_age = 1.0
		for shot in _shots:
			shot["animated"] = false
			shot["lifetime"] = LIFETIME
	for index in range(_shots.size()):
		_update_visual(_shots[index], _visuals[index])


func motion_enabled() -> bool:
	return not _reduced_motion and _effects_enabled


func player_shot(
	target: Vector3, killed: bool, note: int, ground: Vector3, hit_label := "PLATE HIT"
) -> void:
	last_color = DmjPalette.note_color(note)
	_add_shot(
		muzzle, target, Kind.DOWN if killed else Kind.PLATE, last_color, ground,
		"DOWN" if killed else hit_label
	)
	_recoil_age = 0.0 if motion_enabled() else 1.0


func miss() -> void:
	last_color = DmjPalette.AMBER
	var side := -1.0 if _serial % 2 == 0 else 1.0
	var destination := Vector3(side * 10.8, 1.6 + float(_serial % 3) * 0.4, muzzle.z - 18.0)
	_add_shot(muzzle, destination, Kind.MISS, DmjPalette.MUTED, destination)
	_recoil_age = 0.0 if motion_enabled() else 1.0


func enemy_shot(origin: Vector3) -> void:
	_add_shot(origin, muzzle, Kind.HOSTILE, DmjPalette.DANGER, muzzle)


func recoil() -> float:
	return sin(clampf(_recoil_age / 0.2, 0.0, 1.0) * PI) * 0.14 if motion_enabled() else 0.0


func flash(strength: float) -> void:
	_flash_strength = clampf(strength, 0.0, 1.0)


func muzzle_flash() -> float:
	return maxf(1.0 - _recoil_age / 0.1, 0.0) * _flash_strength if motion_enabled() else 0.0


func _add_shot(
	from: Vector3, to: Vector3, kind: Kind, color: Color, ground: Vector3, label := ""
) -> void:
	if _shots.size() >= MAX_SHOTS:
		_shots.pop_front()
		_visuals.pop_front().free()
	var shot := {
		"origin": from, "destination": to, "ground": ground, "kind": kind,
		"color": color, "age": 0.0, "animated": motion_enabled(),
		"label": label if not label.is_empty() else ["DOWN", "PLATE HIT", "MISS", "HIT TAKEN"][kind],
		"lifetime": DESTRUCTION_LIFETIME if kind == Kind.DOWN and motion_enabled() else LIFETIME,
	}
	_shots.append(shot)
	_visuals.append(_make_visual(shot))
	_update_visual(shot, _visuals.back())
	_serial += 1
	if motion_enabled() and kind != Kind.HOSTILE:
		_spawn_particles(to, color, kind == Kind.DOWN)
	set_process(true)


func _make_visual(shot: Dictionary) -> Node3D:
	var visual := Node3D.new()
	add_child(visual)
	var from: Vector3 = shot["origin"]
	var to: Vector3 = shot["destination"]
	var color: Color = shot["color"]
	var kind := int(shot["kind"])
	var tracer := DmjMeshKit.beam(visual, from, to, 0.025, color)
	tracer.name = "Tracer"
	var orb := DmjMeshKit.sphere(visual, 0.13, from, color, true)
	orb.name = "Orb"
	var blast := DmjMeshKit.sphere(visual, 0.85 if kind == Kind.DOWN else 0.24, to, DmjPalette.AMBER, true)
	blast.name = "Blast"
	var ring := DmjMeshKit.ring(visual, 0.6, 0.035, to, color)
	ring.name = "Ring"
	ring.rotation.x = PI * 0.5
	var floor_ring := DmjMeshKit.ring(visual, 0.8, 0.035, shot["ground"], color)
	floor_ring.name = "Ground"
	floor_ring.position.y += 0.04
	var label := DmjMeshKit.label(visual, shot["label"], to + Vector3(0, 0.9, 0), 58, color)
	label.name = "Outcome"
	label.pixel_size = 0.014
	label.outline_size = 4
	label.no_depth_test = true
	return visual


func _update_visual(shot: Dictionary, visual: Node3D) -> void:
	var age := float(shot["age"])
	var animated := bool(shot["animated"])
	var kind := int(shot["kind"])
	var life := float(shot["lifetime"])
	var tracer := visual.get_node("Tracer") as MeshInstance3D
	var orb := visual.get_node("Orb") as MeshInstance3D
	var blast := visual.get_node("Blast") as MeshInstance3D
	var ring := visual.get_node("Ring") as MeshInstance3D
	var ground := visual.get_node("Ground") as MeshInstance3D
	var label := visual.get_node("Outcome") as Label3D
	tracer.visible = age < (0.18 if animated else 0.28)
	orb.visible = animated and age < FLIGHT_SECONDS
	orb.position = (shot["origin"] as Vector3).lerp(shot["destination"], clampf(age / FLIGHT_SECONDS, 0.0, 1.0))
	blast.visible = animated and kind in [Kind.DOWN, Kind.PLATE] and age < 0.4
	blast.scale = Vector3.ONE * maxf(0.001, sin(clampf(age / 0.4, 0.0, 1.0) * PI))
	ring.visible = kind != Kind.HOSTILE and age < 0.5
	ring.scale = Vector3.ONE * (1.0 + age * 3.0 if animated else 0.8)
	ground.visible = animated and kind == Kind.DOWN and age < 0.65
	ground.scale = Vector3.ONE * (0.3 + age * 4.5)
	label.position = (shot["destination"] as Vector3) + Vector3(0, 0.9 + (age * 0.4 if animated else 0.0), 0)
	label.modulate.a = 1.0 - smoothstep(life * 0.65, life, age)


func _spawn_particles(origin: Vector3, color: Color, killed: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _serial * 7919
	for index in range(20 if killed else 7):
		if _particles.size() >= MAX_PARTICLES:
			var oldest: Dictionary = _particles.pop_front()
			(oldest["mesh"] as MeshInstance3D).free()
		var velocity := Vector3(
			rng.randf_range(-3.0, 3.0), rng.randf_range(1.0, 4.5), rng.randf_range(-2.4, 2.4)
		) * (1.0 if killed else 0.6)
		var spark := index % 3 != 0
		var piece := DmjMeshKit.box(
			self, Vector3(0.035, 0.035, 0.2) if spark else Vector3(0.13, 0.1, 0.15),
			origin, color if spark else DmjDrone3D.EDGE, spark
		)
		_particles.append({
			"mesh": piece, "origin": origin, "velocity": velocity, "age": 0.0,
			"lifetime": rng.randf_range(0.45, 0.9),
		})


func _process(delta: float) -> void:
	advance(delta)


## This clock continues through Demo's held beat, but inherits scene pause.
func advance(delta: float) -> void:
	_recoil_age += delta
	for index in range(_shots.size() - 1, -1, -1):
		var shot := _shots[index]
		shot["age"] = float(shot["age"]) + delta
		if float(shot["age"]) >= float(shot["lifetime"]):
			_visuals[index].free()
			_visuals.remove_at(index)
			_shots.remove_at(index)
		else:
			_update_visual(shot, _visuals[index])
	for index in range(_particles.size() - 1, -1, -1):
		var particle := _particles[index]
		particle["age"] = float(particle["age"]) + delta
		var age := float(particle["age"])
		var piece: MeshInstance3D = particle["mesh"]
		var lifetime := float(particle["lifetime"])
		if age >= lifetime:
			piece.free()
			_particles.remove_at(index)
			continue
		piece.position = (particle["origin"] as Vector3) + (particle["velocity"] as Vector3) * age + Vector3.DOWN * age * age * 4.0
		piece.rotation += Vector3(2, 3, 1) * delta
		piece.scale = Vector3.ONE * maxf(0.01, 1.0 - age / lifetime)
	set_process(not _shots.is_empty() or not _particles.is_empty())


func active_count() -> int:
	return _shots.size()


func result_settle_seconds() -> float:
	var remaining := RESULT_SETTLE
	for shot in _shots:
		if int(shot["kind"]) == Kind.DOWN and bool(shot["animated"]):
			remaining = maxf(remaining, KILL_SETTLE - float(shot["age"]))
	return remaining


func clear() -> void:
	for visual in _visuals:
		visual.free()
	_visuals.clear()
	_shots.clear()
	_clear_particles()
	_recoil_age = 1.0
	last_color = DmjPalette.AMBER
	_flash_strength = 1.0
	_serial = 0
	set_process(false)


func _clear_particles() -> void:
	for particle in _particles:
		(particle["mesh"] as MeshInstance3D).free()
	_particles.clear()
