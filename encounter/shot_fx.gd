class_name DmjShotFx
extends Node2D

## Hitscan judgements get an immediate impact marker and a short energy tracer.
## These records never judge notes, retain enemies, or apply damage.
enum Kind { DOWN, PLATE, MISS, HOSTILE }
enum Particle { SPARK, DEBRIS, SMOKE, CASING }

const PLAYER_FLIGHT := 0.12
const ENEMY_FLIGHT := 0.075
const LIFETIME := 0.72
const DESTRUCTION_LIFETIME := 1.15
const BURST_SECONDS := 0.85
const RESULT_SETTLE := 0.32
const KILL_SETTLE := DmjDroneArt.DESTRUCTION_SECONDS + 0.08
const MAX_SHOTS := 48
const MAX_PARTICLES := 256
const PLAYER_ORIGIN := Vector2(0.5, 0.955)
const SHOT_LAYER := 250
const GROUND_SQUASH := 0.24
const BLAST_ORANGE := Color("ff702e")
const BLAST_GOLD := Color("ffd36a")
const BLAST_CORE := Color("fff8df")

var _field := Rect2(0.0, 0.0, 640.0, 360.0)
var _shots: Array[Dictionary] = []
var _particles: Array[Dictionary] = []
var _serial := 0
var _reduced_motion := false
var _effects_enabled := true
var _muzzle_left := 0.0
var _muzzle_color := DmjPalette.AMBER
var _ground_layer: Node2D
var _glow_layer: Node2D


func _init() -> void:
	z_index = SHOT_LAYER
	# Floor light and shockwaves sit above the room but underneath its actors.
	_ground_layer = Node2D.new()
	_ground_layer.name = "GroundEffects"
	_ground_layer.z_index = -SHOT_LAYER
	_ground_layer.draw.connect(_draw_ground_impacts)
	add_child(_ground_layer)
	_glow_layer = Node2D.new()
	_glow_layer.name = "BlastGlow"
	_glow_layer.z_index = -1
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = glow
	_glow_layer.draw.connect(_draw_blast_glow)
	add_child(_glow_layer)
	set_process(false)


func _ready() -> void:
	set_process(not _shots.is_empty() or not _particles.is_empty())


func set_field(field: Rect2) -> void:
	_field = field
	_redraw()


func set_presentation_options(reduced_motion: bool, effects_enabled: bool) -> void:
	_reduced_motion = reduced_motion
	_effects_enabled = effects_enabled
	if not motion_enabled():
		_particles.clear()
		_muzzle_left = 0.0
		for shot in _shots:
			shot["animated"] = false
			shot["lifetime"] = LIFETIME
	_redraw()


func motion_enabled() -> bool:
	return _effects_enabled and not _reduced_motion


func player_shot(
	target: Vector2, killed: bool, note := -1, impact_scale := 1.0,
	ground: Vector2 = Vector2.INF
) -> void:
	var color := DmjPalette.note_color(note) if note >= 0 else DmjPalette.AMBER
	_add_shot(
		PLAYER_ORIGIN, _normalized(target), Kind.DOWN if killed else Kind.PLATE,
		color, impact_scale, _normalized(ground) if ground.is_finite() else Vector2.INF
	)
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


func _add_shot(
	origin: Vector2, destination: Vector2, kind: Kind, color: Color,
	impact_scale: float, ground: Vector2 = Vector2.INF
) -> void:
	# Dense MIDI input can produce many cosmetic misses, never unbounded nodes.
	if _shots.size() >= MAX_SHOTS:
		_shots.pop_front()
	var size := clampf(impact_scale, 0.25, 1.5)
	_shots.append({
		"origin": origin, "destination": destination, "kind": kind, "age": 0.0,
		"color": color, "scale": size, "ground": ground, "seed": _serial + 1,
		"animated": motion_enabled(),
		"lifetime": DESTRUCTION_LIFETIME if kind == Kind.DOWN and motion_enabled() else LIFETIME,
	})
	_serial += 1
	if motion_enabled():
		_spawn_burst(destination, kind, color, size)
	set_process(true)
	_redraw()


func active_count() -> int:
	return _shots.size()


func result_settle_seconds() -> float:
	var remaining := RESULT_SETTLE
	if motion_enabled():
		for shot in _shots:
			if int(shot["kind"]) == Kind.DOWN and bool(shot["animated"]):
				remaining = maxf(remaining, KILL_SETTLE - float(shot["age"]))
	return remaining


func clear() -> void:
	_shots.clear()
	_particles.clear()
	_muzzle_left = 0.0
	_muzzle_color = DmjPalette.AMBER
	_serial = 0
	set_process(false)
	_redraw()


func _process(delta: float) -> void:
	advance(delta)


## Feedback finishes during Demo's held beat and hit-stop, but inherits pause.
func advance(delta: float) -> void:
	_muzzle_left = maxf(_muzzle_left - delta, 0.0)
	var alive: Array[Dictionary] = []
	for shot in _shots:
		shot["age"] = float(shot["age"]) + delta
		if float(shot["age"]) < float(shot["lifetime"]):
			alive.append(shot)
	_shots = alive
	var surviving_particles: Array[Dictionary] = []
	for particle in _particles:
		particle["age"] = float(particle["age"]) + delta
		if float(particle["age"]) < float(particle["lifetime"]):
			surviving_particles.append(particle)
	_particles = surviving_particles
	set_process(not _shots.is_empty() or not _particles.is_empty())
	_redraw()


func _redraw() -> void:
	queue_redraw()
	_ground_layer.queue_redraw()
	_glow_layer.queue_redraw()


func _spawn_burst(origin: Vector2, kind: Kind, color: Color, size: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _serial * 7919
	var killed := kind == Kind.DOWN
	var count := 48 if killed else (16 if kind == Kind.PLATE else 9)
	for index in range(count):
		var type := Particle.SPARK if index % 3 != 0 else Particle.DEBRIS
		var direction := Vector2.from_angle(rng.randf_range(-PI, PI))
		var speed := rng.randf_range(150.0, 420.0) if killed else rng.randf_range(95.0, 290.0)
		var velocity := direction * speed * size
		velocity.y -= (110.0 if killed else 65.0) * size
		var scrap := DmjDroneArt.RUST if index % 2 == 0 else DmjPalette.MUTED
		var fragment_size := rng.randf_range(6.0, 14.0) if type == Particle.DEBRIS else rng.randf_range(3.0, 5.0)
		var lifetime := rng.randf_range(0.6, 1.1) if killed else rng.randf_range(0.28, 0.65)
		_add_particle(
			origin, velocity, type, color if type == Particle.SPARK else scrap,
			fragment_size * size, lifetime,
			rng.randf_range(-PI, PI), rng.randf_range(-12.0, 12.0), size,
			rng.randf_range(-0.8, 0.9)
		)
	if kind == Kind.DOWN or kind == Kind.PLATE:
		for index in range(8 if killed else 2):
			_add_particle(
				origin, Vector2(rng.randf_range(-45.0, 45.0), rng.randf_range(-85.0, -35.0)) * size,
				Particle.SMOKE, DmjPalette.LINE.lightened(0.16).lerp(color, 0.12),
				rng.randf_range(18.0, 32.0) * size if killed else rng.randf_range(10.0, 20.0) * size,
				DESTRUCTION_LIFETIME if killed else LIFETIME, 0.0, 0.0, size
			)


func _eject_casing() -> void:
	if not motion_enabled():
		return
	var zoom := minf(1.0, _field.size.y / 320.0)
	var origin := _normalized(_point(PLAYER_ORIGIN) + Vector2(24.0, 0.0) * zoom)
	_add_particle(origin, Vector2(150.0, -155.0) * zoom, Particle.CASING,
		DmjPalette.AMBER, 5.0 * zoom, 0.5, 0.0, 13.0, zoom, 0.6)


func _add_particle(
	origin: Vector2, velocity: Vector2, kind: Particle, color: Color,
	size: float, lifetime: float, angle: float, spin: float, effect_scale: float,
	depth_velocity := 0.0
) -> void:
	if _particles.size() >= MAX_PARTICLES:
		_particles.pop_front()
	var dimensions := _field.size.max(Vector2.ONE)
	_particles.append({
		"origin": origin, "velocity": velocity / dimensions, "kind": kind,
		"color": color, "size": size, "lifetime": lifetime, "age": 0.0,
		"angle": angle, "spin": spin, "depth_velocity": depth_velocity,
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
	for shot in _shots:
		_draw_result(shot)


func _draw_ground_impacts() -> void:
	if not motion_enabled() or _field.size.x <= 0.0 or _field.size.y <= 0.0:
		return
	for shot in _shots:
		var ground: Vector2 = shot["ground"]
		if not ground.is_finite() or not bool(shot["animated"]):
			continue
		var center := _point(ground)
		var progress := clampf(float(shot["age"]) / float(shot["lifetime"]), 0.0, 1.0)
		var fade := pow(1.0 - progress, 2.0)
		var color: Color = shot["color"]
		var size: float = shot["scale"]
		var reach := 155.0 if int(shot["kind"]) == Kind.DOWN else 55.0
		var radius := _ground_radius(center, lerpf(14.0, reach, pow(progress, 0.45)) * size)
		if radius <= 0.0:
			continue
		_ground_layer.draw_set_transform(center, 0.0, Vector2(1.0, GROUND_SQUASH))
		_ground_layer.draw_circle(Vector2.ZERO, radius, Color(color, fade * 0.20))
		_ground_layer.draw_circle(Vector2.ZERO, minf(28.0 * size, radius), Color(DmjPalette.INK, fade * 0.45))
		_ground_layer.draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(color, fade * 0.95), 3.5, true)
		_ground_layer.draw_arc(Vector2.ZERO, radius * 0.72, 0.0, TAU, 40, Color(DmjPalette.TEXT, fade * 0.35), 1.2, true)
	_ground_layer.draw_set_transform(Vector2.ZERO)


func _draw_blast_glow() -> void:
	if not motion_enabled():
		return
	for shot in _shots:
		if int(shot["kind"]) != Kind.DOWN or not bool(shot["animated"]):
			continue
		var age: float = shot["age"]
		if age >= BURST_SECONDS:
			continue
		var center := _point(shot["destination"])
		var radius := minf(_blast_radius(age, float(shot["scale"])) * 1.15, _edge_distance(center))
		var heat := _blast_heat(age)
		for band in range(8):
			var inset := float(band) / 8.0
			var color := BLAST_ORANGE.lerp(BLAST_CORE, inset * 0.6)
			_glow_layer.draw_circle(
				center, radius * (1.0 - inset * 0.7),
				Color(color, heat * (0.02 + inset * 0.025))
			)


func _blast_radius(age: float, size: float) -> float:
	var expansion := 1.0 - pow(1.0 - clampf(age / 0.24, 0.0, 1.0), 3.0)
	return lerpf(36.0, 165.0, expansion) * size


func _blast_heat(age: float) -> float:
	return 1.0 - smoothstep(0.18, BURST_SECONDS, age)


func _ground_radius(center: Vector2, desired: float) -> float:
	var horizontal := minf(center.x - _field.position.x, _field.end.x - center.x)
	var vertical := minf(center.y - _field.position.y, _field.end.y - center.y)
	return maxf(0.0, minf(desired, minf(horizontal - 3.0, (vertical - 3.0) / GROUND_SQUASH)))


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
	var lifetime: float = shot["lifetime"]
	var fade := clampf(1.0 - age / lifetime, 0.0, 1.0)
	var flight := ENEMY_FLIGHT if hostile else PLAYER_FLIGHT
	var moving := motion_enabled() and bool(shot["animated"])
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

	var burst_duration := BURST_SECONDS if kind == Kind.DOWN else 0.24
	if moving and not missed and age < burst_duration:
		_draw_impact(destination, kind, color, age, size, int(shot["seed"]))
	var radius := 12.0 if not moving else lerpf(9.0, 32.0, age / lifetime) * size
	radius = minf(radius, _edge_distance(destination))
	var marker := Color(color, fade)
	if missed:
		draw_arc(destination, 8.0, 0.0, TAU, 16, marker, 1.5, true)
		draw_line(destination - Vector2(5, 0), destination + Vector2(5, 0), marker, 1.5)
	else:
		draw_arc(destination, radius, 0.0, TAU, 28, marker, 2.0, true)
		for side: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			draw_line(destination + side * 5.0, destination + side * 12.0, marker, 2.5, true)


func _draw_result(shot: Dictionary) -> void:
	var kind: int = shot["kind"]
	var age: float = shot["age"]
	var lifetime: float = shot["lifetime"]
	var fade := 1.0 - smoothstep(lifetime * 0.6, lifetime, age)
	var color: Color = shot["color"]
	var moving := motion_enabled() and bool(shot["animated"])
	var rise := 24.0 * (1.0 - pow(1.0 - age / lifetime, 2.0)) if moving else 0.0
	var height := 72.0 * float(shot["scale"]) if kind == Kind.DOWN and moving else 34.0
	var label := "HIT TAKEN" if kind == Kind.HOSTILE else ("MISS" if kind == Kind.MISS else (
		"DOWN" if kind == Kind.DOWN else "PLATE HIT"
	))
	_draw_label(
		label, _point(shot["destination"]) + Vector2(0.0, -height - rise),
		Color(color, fade), 20 if kind == Kind.DOWN else 16
	)


func _edge_distance(point: Vector2) -> float:
	return maxf(0.0, minf(
		minf(point.x - _field.position.x, _field.end.x - point.x),
		minf(point.y - _field.position.y, _field.end.y - point.y)
	) - 3.0)


func _draw_impact(center: Vector2, kind: int, color: Color, age: float, size: float, seed: int) -> void:
	var killed := kind == Kind.DOWN
	var progress := clampf(age / (BURST_SECONDS if killed else 0.24), 0.0, 1.0)
	var radius := (
		_blast_radius(age, size) if killed
		else lerpf(12.0, 43.0, 1.0 - pow(1.0 - progress, 3.0)) * size
	)
	radius = minf(radius, _edge_distance(center))
	var fade := 1.0 - progress
	draw_circle(center, radius, Color(color, fade * 0.12))
	draw_arc(center, radius, 0.0, TAU, 48, Color(color, fade), 3.5 if killed else 2.0, true)
	if killed:
		_draw_fireball(center, radius, age, seed)
		draw_set_transform(center, float(seed % 5) * 0.32, Vector2(1.0, 0.46))
		draw_arc(Vector2.ZERO, radius * 0.9, 0.0, TAU, 40, Color(DmjPalette.TEXT, fade * 0.5), 1.8, true)
		draw_set_transform(Vector2.ZERO)
	else:
		for arc in range(4):
			var angle := float(arc) * TAU / 4.0 + float(seed) * 0.7
			var points := PackedVector2Array()
			for joint in range(5):
				var direction := Vector2.from_angle(angle + float(joint) * 0.18)
				points.append(center + direction * radius * (0.52 if joint % 2 == 0 else 0.85))
			draw_polyline(points, Color(color, fade), 2.0, true)
	if age < 0.07:
		draw_circle(center, radius * 0.28, Color(DmjPalette.TEXT, (1.0 - age / 0.07) * 0.8))


func _draw_fireball(center: Vector2, radius: float, age: float, seed: int) -> void:
	var heat := _blast_heat(age)
	var progress := clampf(age / BURST_SECONDS, 0.0, 1.0)
	for lobe in range(9):
		var angle := float(lobe) * TAU / 9.0 + float(seed) * 1.3 + sin(float(seed + lobe)) * 0.15
		var direction := Vector2.from_angle(angle)
		var variation := 0.86 + float(posmod(lobe * 7 + seed, 5)) * 0.065
		var offset := direction * radius * (0.2 + progress * 0.2)
		var size := radius * (0.36 - progress * 0.08) * variation
		var point := center + offset - Vector2(0.0, progress * radius * 0.12)
		draw_circle(point, size, Color(BLAST_ORANGE, heat * 0.95))
		draw_circle(point - Vector2(size * 0.12, size * 0.16), size * 0.82, Color(BLAST_GOLD, heat))
		draw_circle(point - Vector2(size * 0.22, size * 0.26), size * 0.46, Color(BLAST_CORE, heat * 0.95))
	draw_circle(center, radius * 0.56, Color(BLAST_GOLD, heat * 0.9))
	draw_circle(center - Vector2(radius * 0.04, radius * 0.06), radius * 0.32, Color(BLAST_CORE, heat))


func _particle_perspective(particle: Dictionary) -> float:
	# Positive Z travels toward the camera; no 3D scene or physics is involved.
	return 1.0 / maxf(1.0 - float(particle["depth_velocity"]) * float(particle["age"]), 0.55)


func _draw_particle(particle: Dictionary) -> void:
	var age: float = particle["age"]
	var progress := age / float(particle["lifetime"])
	var velocity: Vector2 = particle["velocity"]
	var gravity: float = particle["gravity"]
	var perspective := _particle_perspective(particle)
	var normalized: Vector2 = particle["origin"] + (
		velocity * age + Vector2(0.0, gravity * age * age * 0.5)
	) * perspective
	var center := _point(normalized)
	if not _field.has_point(center):
		return
	var kind: int = particle["kind"]
	var color: Color = particle["color"]
	var size := float(particle["size"]) * perspective
	var fade := 1.0 - smoothstep(0.2, 1.0, progress)
	if kind == Particle.SMOKE:
		var radius := minf(size * (1.0 + progress * 1.8), _edge_distance(center))
		draw_circle(center, radius, Color(DmjPalette.INK, fade * 0.38))
		draw_circle(center + Vector2(radius * 0.12, radius * 0.1), radius * 0.82, Color(color, fade * 0.42))
		draw_circle(center - Vector2(radius * 0.16, radius * 0.18), radius * 0.64, Color(color.lightened(0.14), fade * 0.25))
	elif kind == Particle.SPARK:
		var direction := (velocity * _field.size + Vector2(0.0, gravity * _field.size.y * age)).normalized()
		var tail := (center - direction * (size * 4.0 + 6.0)).clamp(_field.position, _field.end)
		draw_line(tail, center, Color(color, fade), 2.0 + minf(size * 0.15, 1.5), true)
		draw_circle(center, minf(size * 1.6, _edge_distance(center)), Color(color, fade * 0.18))
		draw_circle(center, minf(size * 0.65, _edge_distance(center)), Color(BLAST_CORE, fade))
	else:
		var angle := float(particle["angle"]) + float(particle["spin"]) * age
		var axis := Vector2.from_angle(angle) * size
		var tumble := cos(angle * 0.7)
		var side := axis.orthogonal() * (0.25 if kind == Particle.CASING else 0.18 + absf(tumble) * 0.52)
		var bevel := Vector2(0.28, -0.22) * size
		if _edge_distance(center) < size * 1.8:
			return
		draw_colored_polygon(PackedVector2Array([
			center + axis - side, center + axis - side + bevel,
			center + axis + side + bevel, center + axis + side,
		]), Color(color.darkened(0.5), fade))
		draw_colored_polygon(PackedVector2Array([
			center - axis - side, center + axis - side,
			center + axis - side + bevel, center - axis - side + bevel,
		]), Color(color.lightened(0.2), fade))
		draw_colored_polygon(PackedVector2Array([
			center - axis - side, center + axis - side,
			center + axis + side, center - axis + side,
		]), Color(color.darkened((1.0 - tumble) * 0.16), fade))
		draw_line(center - axis - side, center + axis - side, Color(DmjPalette.TEXT, fade * 0.65), 1.0, true)


func _draw_label(text: String, center: Vector2, color: Color, font_size := 16) -> void:
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
	var x := clampf(center.x - width * 0.5, _field.position.x + 4.0, _field.end.x - width - 4.0)
	var y := clampf(center.y, _field.position.y + font_size + 4.0, _field.end.y - 4.0)
	draw_rect(
		Rect2(Vector2(x - 3.0, y - font_size - 1.0), Vector2(width + 6.0, font_size + 6.0)),
		Color(DmjPalette.INK, color.a * 0.95)
	)
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)
