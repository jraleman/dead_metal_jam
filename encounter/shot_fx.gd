class_name DmjShotFx
extends Node2D

## Hitscan judgements get an immediate impact marker and a short energy tracer.
## These records never judge notes, retain enemies, or apply damage.
enum Kind { DOWN, PLATE, MISS, HOSTILE }
enum Particle { SPARK, DEBRIS, SMOKE, CASING }

const PLAYER_FLIGHT := 0.12
const ENEMY_FLIGHT := 0.075
const LIFETIME := 0.72
const RESULT_SETTLE := 0.32
const MAX_SHOTS := 48
const MAX_PARTICLES := 256
const PLAYER_ORIGIN := Vector2(0.5, 0.955)

var _field := Rect2(0.0, 0.0, 640.0, 360.0)
var _shots: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _serial := 0
var _reduced_motion := false
var _effects_enabled := true
var _muzzle_left := 0.0
var _muzzle_color := DmjPalette.AMBER


func _init() -> void:
	z_index = 250
	set_process(false)


func _ready() -> void:
	set_process(not _shots.is_empty() or not _particles.is_empty())


func set_field(field: Rect2) -> void:
	_field = field
	queue_redraw()


func set_presentation_options(reduced_motion: bool, effects_enabled: bool) -> void:
	_reduced_motion = reduced_motion
	_effects_enabled = effects_enabled
	if not motion_enabled():
		_particles.clear()
	queue_redraw()


func motion_enabled() -> bool:
	return _effects_enabled and not _reduced_motion


func player_shot(target: Vector2, killed: bool, note := -1, impact_scale := 1.0) -> void:
	var color := DmjPalette.note_color(note) if note >= 0 else DmjPalette.AMBER
	_add_shot(PLAYER_ORIGIN, _normalized(target), Kind.DOWN if killed else Kind.PLATE, color, impact_scale)
	_muzzle_left = PLAYER_FLIGHT
	_muzzle_color = color
	_eject_casing()


func miss() -> void:
	var side := 0.04 if _serial % 2 == 0 else 0.96
	var destination := Vector2(side, 0.32 + float(_serial % 3) * 0.08)
	_add_shot(PLAYER_ORIGIN, destination, Kind.MISS, DmjPalette.MUTED, 0.6)
	_muzzle_left = PLAYER_FLIGHT
	_muzzle_color = DmjPalette.AMBER
	_eject_casing()


func enemy_shot(origin: Vector2) -> void:
	_add_shot(_normalized(origin), PLAYER_ORIGIN, Kind.HOSTILE, DmjPalette.DANGER, 0.9)


func _add_shot(origin: Vector2, destination: Vector2, kind: Kind, color: Color, impact_scale: float) -> void:
	# Dense MIDI input can produce many cosmetic misses, never unbounded nodes.
	if _shots.size() >= MAX_SHOTS:
		_shots.pop_front()
	var size := clampf(impact_scale, 0.25, 1.5)
	_shots.append({
		"origin": origin, "destination": destination, "kind": kind, "age": 0.0,
		"color": color, "scale": size,
	})
	_serial += 1
	if motion_enabled():
		_spawn_burst(destination, kind, color, size)
	set_process(true)
	queue_redraw()


func active_count() -> int:
	return _shots.size()


func clear() -> void:
	_shots.clear()
	_particles.clear()
	_muzzle_left = 0.0
	_muzzle_color = DmjPalette.AMBER
	_serial = 0
	set_process(false)
	queue_redraw()


func _process(delta: float) -> void:
	advance(delta)


## Feedback finishes during Demo's held beat and hit-stop, but inherits pause.
func advance(delta: float) -> void:
	_muzzle_left = maxf(_muzzle_left - delta, 0.0)
	var alive: Array[Dictionary] = []
	for shot in _shots:
		shot["age"] = float(shot["age"]) + delta
		if float(shot["age"]) < LIFETIME:
			alive.append(shot)
	_shots = alive
	var surviving_particles: Array[Dictionary] = []
	for particle in _particles:
		particle["age"] = float(particle["age"]) + delta
		if float(particle["age"]) < float(particle["lifetime"]):
			surviving_particles.append(particle)
	_particles = surviving_particles
	set_process(not _shots.is_empty() or not _particles.is_empty())
	queue_redraw()


func _spawn_burst(origin: Vector2, kind: Kind, color: Color, size: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _serial * 7919
	var count := 28 if kind == Kind.DOWN else (16 if kind == Kind.PLATE else 9)
	for index in range(count):
		var type := Particle.SPARK if index % 3 != 0 else Particle.DEBRIS
		var direction := Vector2.from_angle(rng.randf_range(-PI, PI))
		var velocity := direction * rng.randf_range(95.0, 290.0) * size
		velocity.y -= 65.0 * size
		_add_particle(
			origin, velocity, type, color if type == Particle.SPARK else DmjPalette.MUTED,
			rng.randf_range(2.0, 6.0) * size, rng.randf_range(0.28, 0.65),
			rng.randf_range(-PI, PI), rng.randf_range(-12.0, 12.0), size
		)
	if kind == Kind.DOWN or kind == Kind.PLATE:
		for index in range(5 if kind == Kind.DOWN else 2):
			_add_particle(
				origin, Vector2(rng.randf_range(-45.0, 45.0), rng.randf_range(-85.0, -35.0)) * size,
				Particle.SMOKE, DmjPalette.INK, rng.randf_range(10.0, 20.0) * size,
				LIFETIME, 0.0, 0.0, size
			)


func _eject_casing() -> void:
	if not motion_enabled():
		return
	var zoom := minf(1.0, _field.size.y / 320.0)
	var origin := _normalized(_point(PLAYER_ORIGIN) + Vector2(24.0, 0.0) * zoom)
	_add_particle(origin, Vector2(150.0, -155.0) * zoom, Particle.CASING,
		DmjPalette.AMBER, 5.0 * zoom, 0.5, 0.0, 13.0, zoom)


func _add_particle(
	origin: Vector2, velocity: Vector2, kind: Particle, color: Color,
	size: float, lifetime: float, angle: float, spin: float, effect_scale: float
) -> void:
	if _particles.size() >= MAX_PARTICLES:
		_particles.pop_front()
	var dimensions := _field.size.max(Vector2.ONE)
	_particles.append({
		"origin": origin, "velocity": velocity / dimensions, "kind": kind,
		"color": color, "size": size, "lifetime": lifetime, "age": 0.0,
		"angle": angle, "spin": spin,
		"gravity": 0.0 if kind == Particle.SMOKE else 430.0 * effect_scale / dimensions.y,
	})


func _normalized(point: Vector2) -> Vector2:
	return (point - _field.position) / Vector2(
		maxf(_field.size.x, 1.0), maxf(_field.size.y, 1.0)
	)


func _point(normalized: Vector2) -> Vector2:
	return _field.position + normalized * _field.size


func _draw() -> void:
	if _field.size.x <= 0.0 or _field.size.y <= 0.0:
		return
	_draw_emitter()
	for particle in _particles:
		if int(particle["kind"]) == Particle.SMOKE:
			_draw_particle(particle)
	for shot in _shots:
		_draw_shot(shot)
	for particle in _particles:
		if int(particle["kind"]) != Particle.SMOKE:
			_draw_particle(particle)


func _draw_emitter() -> void:
	var center := _point(Vector2(0.5, 0.985))
	var zoom := minf(1.0, minf(_field.size.x / 700.0, _field.size.y / 320.0))
	var recoil := sin(clampf(_muzzle_left / PLAYER_FLIGHT, 0.0, 1.0) * PI) if motion_enabled() else 0.0
	center.y += recoil * 3.0 * zoom
	var half := Vector2(88.0, 15.0) * zoom
	var chassis := PackedVector2Array([
		center + Vector2(-half.x, half.y * 0.3),
		center + Vector2(-half.x * 0.7, -half.y),
		center + Vector2(half.x * 0.7, -half.y),
		center + Vector2(half.x, half.y * 0.3),
	])
	draw_colored_polygon(chassis, DmjPalette.INK)
	draw_polyline(chassis, DmjPalette.MUTED, 1.5, true)
	var muzzle := _point(PLAYER_ORIGIN) + Vector2(0.0, recoil * 3.0 * zoom)
	for side in [-1.0, 1.0]:
		draw_line(center + Vector2(side * 24.0, 0.0) * zoom,
			muzzle + Vector2(side * 12.0, 0.0) * zoom, DmjPalette.STEEL, 9.0 * zoom, true)
		draw_line(center + Vector2(side * 25.0, -2.0) * zoom,
			muzzle + Vector2(side * 12.0, -1.0) * zoom, DmjPalette.MUTED, 1.5, true)
	draw_line(center, muzzle, DmjPalette.STEEL, 18.0 * zoom, true)
	for vent in range(3):
		draw_line(center + Vector2(-9.0 + vent * 9.0, 1.0) * zoom,
			center + Vector2(-9.0 + vent * 9.0, 5.0) * zoom, _muzzle_color, 3.0 * zoom, true)
	draw_circle(muzzle, 8.0 * zoom, DmjPalette.INK)
	draw_circle(muzzle, 5.5 * zoom, _muzzle_color)
	if _muzzle_left > 0.0 and motion_enabled():
		var flash := _muzzle_left / PLAYER_FLIGHT
		draw_circle(muzzle, 23.0 * zoom, Color(_muzzle_color, flash * 0.18))
		draw_circle(muzzle, 9.0 * zoom, Color(DmjPalette.TEXT, flash))


func _draw_shot(shot: Dictionary) -> void:
	var kind: int = shot["kind"]
	var age: float = shot["age"]
	var origin := _point(shot["origin"])
	var destination := _point(shot["destination"])
	var hostile := kind == Kind.HOSTILE
	var missed := kind == Kind.MISS
	var color: Color = shot["color"]
	var size: float = shot["scale"]
	var fade := clampf(1.0 - age / LIFETIME, 0.0, 1.0)
	var flight := ENEMY_FLIGHT if hostile else PLAYER_FLIGHT
	var moving := motion_enabled()
	var thickness := 1.4 if missed else 3.0
	# The whole path and outcome are visible immediately, matching hitscan damage.
	draw_line(origin, destination, Color(color, fade * 0.45), thickness, true)
	if moving and age < flight:
		var progress := clampf(age / flight, 0.0, 1.0)
		var head := origin.lerp(destination, progress)
		var tail := origin.lerp(destination, maxf(progress - 0.24, 0.0))
		var orb_radius := lerpf(4.0, 13.0, progress) if hostile else lerpf(8.0, 4.0, progress)
		draw_line(tail, head, Color(color, 0.24), 11.0, true)
		draw_line(tail, head, color, 3.0, true)
		draw_circle(head, orb_radius * 1.8, Color(color, 0.15))
		draw_circle(head, orb_radius, color)
		draw_circle(head, orb_radius * 0.42, DmjPalette.TEXT)

	if moving and not missed and age < 0.24:
		_draw_impact(destination, kind, color, age, size)
	var radius := 12.0 if not moving else lerpf(9.0, 32.0, age / LIFETIME) * size
	radius = minf(radius, _edge_distance(destination))
	var marker := Color(color, fade)
	if missed:
		draw_arc(destination, 8.0, 0.0, TAU, 16, marker, 1.5, true)
		draw_line(destination - Vector2(5, 0), destination + Vector2(5, 0), marker, 1.5)
	else:
		draw_arc(destination, radius, 0.0, TAU, 28, marker, 2.0, true)
		for side: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			draw_line(destination + side * 5.0, destination + side * 12.0, marker, 2.5, true)
	var label := "HIT TAKEN" if hostile else ("MISS" if missed else (
		"DOWN" if kind == Kind.DOWN else "PLATE HIT"
	))
	_draw_label(label, destination + Vector2(0.0, -34.0), marker)


func _edge_distance(point: Vector2) -> float:
	return maxf(0.0, minf(
		minf(point.x - _field.position.x, _field.end.x - point.x),
		minf(point.y - _field.position.y, _field.end.y - point.y)
	) - 3.0)


func _draw_impact(center: Vector2, kind: int, color: Color, age: float, size: float) -> void:
	var progress := clampf(age / 0.24, 0.0, 1.0)
	var radius := lerpf(12.0, 85.0 if kind == Kind.DOWN else 43.0, progress) * size
	radius = minf(radius, _edge_distance(center))
	var fade := 1.0 - progress
	draw_circle(center, radius, Color(color, fade * 0.15))
	draw_arc(center, radius, 0.0, TAU, 36, Color(color, fade), 3.0, true)
	if kind == Kind.DOWN:
		draw_circle(center, radius * 0.65, Color(DmjPalette.AMBER, fade * 0.6))
	if age < 0.08:
		draw_circle(center, radius * 0.45, Color(DmjPalette.TEXT, 1.0 - age / 0.08))


func _draw_particle(particle: Dictionary) -> void:
	var age: float = particle["age"]
	var progress := age / float(particle["lifetime"])
	var velocity: Vector2 = particle["velocity"]
	var gravity: float = particle["gravity"]
	var normalized: Vector2 = particle["origin"] + velocity * age + Vector2(0.0, gravity * age * age * 0.5)
	var center := _point(normalized)
	if not _field.has_point(center):
		return
	var kind: int = particle["kind"]
	var color: Color = particle["color"]
	var size: float = particle["size"]
	var fade := 1.0 - progress
	if kind == Particle.SMOKE:
		var radius := minf(size * (1.0 + progress * 1.8), _edge_distance(center))
		draw_circle(center, radius, Color(color, fade * 0.34))
	elif kind == Particle.SPARK:
		var direction := (velocity * _field.size + Vector2(0.0, gravity * _field.size.y * age)).normalized()
		var tail := (center - direction * (size * 4.0 + 6.0)).clamp(_field.position, _field.end)
		draw_line(tail, center, Color(color, fade), 2.0, true)
		draw_circle(center, minf(size * 0.5, _edge_distance(center)), Color(DmjPalette.TEXT, fade))
	else:
		var angle := float(particle["angle"]) + float(particle["spin"]) * age
		var axis := Vector2.from_angle(angle) * size
		var side := axis.orthogonal() * (0.4 if kind == Particle.CASING else 0.7)
		if _edge_distance(center) < size * 1.3:
			return
		draw_colored_polygon(PackedVector2Array([
			center - axis - side, center + axis - side,
			center + axis + side, center - axis + side,
		]), Color(color, fade))
		draw_line(center - axis - side, center + axis - side, Color(DmjPalette.TEXT, fade * 0.65), 1.0, true)


func _draw_label(text: String, center: Vector2, color: Color) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16).x
	var x := clampf(center.x - width * 0.5, _field.position.x + 4.0, _field.end.x - width - 4.0)
	var y := clampf(center.y, _field.position.y + 20.0, _field.end.y - 4.0)
	draw_rect(Rect2(Vector2(x - 3.0, y - 17.0), Vector2(width + 6.0, 22.0)), Color(DmjPalette.INK, color.a * 0.85))
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, color)
