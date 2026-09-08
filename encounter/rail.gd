class_name DmjRail
extends Node2D

## Industrial set dressing for the combat room and the shared opening card.
##
## The scenery is deterministic and frame-contained: the director tells this
## node which arena is active, whether the camera is in an advance, and how
## much of the room change has already happened, and this node only paints.
##
## The public contract stays intentionally small because the same node is
## reused by gameplay, the intro, and share art.

const BACKDROP_PADDING := 16.0
const FLASH_DECAY := 4.5
const LIGHT_REACH := 0.42
const LIGHT_REST := 0.11
const LIGHT_FLASH := 0.40
const ROOM_COUNT := 3
const STAGE_LAMPS: Array[float] = [0.18, 0.5, 0.82]
const AMBIENT_MOTES := 24

var _field := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
var _corridor := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
var _lane_count := 3
var _advancing := false
var _reduced_motion := false
var _effects_enabled := true
var _motion_time := 0.0
var _flash := 0.0
var _arena_index := 0
var _arena_transition := 1.0


func _init() -> void:
	z_index = -20


func update_rail(
	delta: float,
	field: Rect2,
	lane_count: int,
	advancing: bool,
	bob: Vector2 = Vector2.ZERO
) -> void:
	_field = field
	_corridor = JamBot.corridor_rect(field)
	_corridor.position += bob
	_lane_count = maxi(lane_count, 1)
	_advancing = advancing

	if delta > 0.0:
		_flash = maxf(_flash - delta * FLASH_DECAY, 0.0)
		if not _reduced_motion:
			_motion_time += delta
	queue_redraw()


func set_arena(index: int, transition_progress: float = 1.0) -> void:
	_arena_index = index
	_arena_transition = clampf(transition_progress, 0.0, 1.0)
	queue_redraw()


func flash(strength: float) -> void:
	_flash = 0.0 if strength <= 0.0 else clampf(maxf(_flash, strength), 0.0, 1.0)
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		_flash = 0.0
	queue_redraw()


func set_effects_enabled(enabled: bool) -> void:
	_effects_enabled = enabled
	if not enabled:
		_flash = 0.0
	queue_redraw()


func is_advancing() -> bool:
	return _advancing


static func corridor_rect(field: Rect2) -> Rect2:
	return JamBot.corridor_rect(field)


func _draw() -> void:
	var room := posmod(_arena_index, ROOM_COUNT)
	var previous := posmod(room - 1, ROOM_COUNT) if _arena_index > 0 else room
	var transition := clampf(_arena_transition, 0.0, 1.0)

	if _reduced_motion and _advancing and transition < 1.0:
		_draw_room(previous, 1.0 - transition)
		_draw_room(room, transition)
		_draw_reduced_motion_banner(room, transition)
		return

	if _advancing and transition < 1.0:
		var visible := previous if transition < 0.5 else room
		_draw_room(visible, 1.0)
		_draw_transition_cover(room, previous, transition)
	else:
		_draw_room(room, 1.0)


func _draw_room(index: int, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var palette := _arena_palette(index)
	_draw_shell(palette, alpha, index)
	_draw_depth_frame(palette, alpha)
	_draw_player_light(palette, alpha)
	_draw_stage_lighting(palette, alpha)
	_draw_room_set_pieces(index, palette, alpha)
	if _effects_enabled and not _reduced_motion:
		_draw_ambient(palette, alpha)
	_draw_foreground_edges(palette, alpha)
	_draw_room_label(index, palette, alpha)


func _draw_depth_frame(palette: Dictionary, alpha: float) -> void:
	for side in range(2):
		var edge := float(side)
		var inward := 1.0 if side == 0 else -1.0
		var inner := edge + inward * 0.065
		draw_polygon(PackedVector2Array([
			_p(edge, 0.0), _p(inner, 0.12), _p(inner, 0.56), _p(edge, 0.82),
		]), PackedColorArray([
			_c(palette["shadow"], alpha), _c(palette["panel"], alpha),
			_c(palette["wall"], alpha), _c(palette["shadow"], alpha),
		]))
		draw_line(_p(inner, 0.12), _p(inner, 0.56), _c(palette["detail"], alpha * 0.65), 2.0, true)
		for brace in range(3):
			var y := 0.22 + float(brace) * 0.15
			draw_line(
				_p(edge, y + 0.08), _p(inner, y),
				_c(palette["detail"], alpha * 0.4), 2.0, true
			)
	var truss := PackedVector2Array([
		_p(0.055, 0.085), _p(0.945, 0.085), _p(0.935, 0.125), _p(0.065, 0.125),
	])
	draw_colored_polygon(truss, _c(palette["shadow"], alpha * 0.9))
	draw_line(truss[3], truss[2], _c(palette["detail"], alpha * 0.75), 2.0, true)
	for brace in range(12):
		var x := 0.065 + float(brace) * 0.0725
		draw_line(_p(x, 0.12), _p(x + 0.036, 0.09), _c(palette["detail"], alpha * 0.45), 1.5, true)
		draw_line(_p(x + 0.036, 0.09), _p(x + 0.072, 0.12), _c(palette["detail"], alpha * 0.3), 1.5, true)


func _draw_stage_lighting(palette: Dictionary, alpha: float) -> void:
	var time := _decorative_time()
	var flare := _flash if _effects_enabled and not _reduced_motion else 0.0
	for index in range(STAGE_LAMPS.size()):
		var lamp := STAGE_LAMPS[index]
		var sweep := sin(time * 0.32 + float(index) * 2.1) * 0.035
		var foot := clampf(lamp + sweep, 0.15, 0.85)
		var color: Color = palette["signal"] if index == 1 else palette["accent"]
		# Vertex alpha feathers each cone down the room without post-processing.
		for band in range(3):
			var spread := 0.09 + float(band) * 0.026
			var strength := alpha * (0.048 + flare * 0.018) / float(band + 1)
			draw_polygon(PackedVector2Array([
				_p(lamp - 0.016, 0.068), _p(lamp + 0.016, 0.068),
				_p(foot + spread, 0.91), _p(foot - spread, 0.91),
			]), PackedColorArray([
				_c(color, strength), _c(color, strength),
				_c(color, strength * 0.22), _c(color, strength * 0.22),
			]))
		var center := _p(foot, 0.88)
		draw_set_transform(center, 0.0, Vector2(1.0, 0.14))
		for band in range(4):
			draw_circle(
				Vector2.ZERO, _field.size.x * (0.12 - float(band) * 0.022),
				_c(color, alpha * (0.013 + flare * 0.009))
			)
		draw_set_transform(Vector2.ZERO)


func _draw_foreground_edges(palette: Dictionary, alpha: float) -> void:
	for side in range(2):
		var edge := float(side)
		var inward := 1.0 if side == 0 else -1.0
		var points := PackedVector2Array([
			_p(edge, 0.47, 1.5), _p(edge + inward * 0.014, 0.50, 1.5),
			_p(edge + inward * 0.024, 1.0, 1.5), _p(edge, 1.0, 1.5),
		])
		draw_colored_polygon(points, _c(palette["shadow"], alpha * 0.9))
		draw_line(points[1], points[2], _c(palette["detail"], alpha * 0.5), 2.0, true)
	draw_line(_p(0.0, 0.998, 1.5), _p(1.0, 0.998, 1.5), _c(palette["shadow"], alpha * 0.8), 3.0, true)


func _draw_ambient(palette: Dictionary, alpha: float) -> void:
	var zoom := minf(1.0, _field.size.y / 360.0)
	for mote in range(AMBIENT_MOTES):
		var point := _mote_position(mote)
		var depth := float(mote % 3) / 2.0
		var radius := lerpf(0.8, 1.8, depth) * zoom
		draw_circle(point, radius * 3.0, _c(palette["accent"], alpha * 0.035))
		draw_circle(point, radius, _c(palette["signal"], alpha * lerpf(0.12, 0.3, depth)))
	for vent in range(2):
		var origin := _p(0.085 if vent == 0 else 0.91, 0.76 if vent == 0 else 0.63)
		for puff in range(5):
			var age := fposmod(_motion_time * 0.35 + float(puff) * 0.2 + vent * 0.4, 1.0)
			var drift := Vector2(sin(age * 4.0 + puff) * 11.0, -age * 75.0) * zoom
			draw_circle(origin + drift, (5.0 + age * 14.0) * zoom,
				_c(palette["detail"], alpha * sin(age * PI) * 0.12))
	var phase := fposmod(_motion_time, 4.0)
	if phase < 0.5:
		var origin := _p(0.30, 0.155)
		for spark in range(7):
			var age := phase + float(spark) * 0.025
			var velocity := Vector2(float(spark - 3) * 18.0, 65.0 + spark * 7.0) * zoom
			var point := origin + velocity * age + Vector2(0.0, age * age * 80.0 * zoom)
			draw_line(point, point - velocity.normalized() * 7.0 * zoom,
				_c(DmjPalette.AMBER, alpha * (1.0 - phase * 2.0)), 1.5, true)


func _mote_position(index: int) -> Vector2:
	var depth := float(index % 3) / 2.0
	var time := _decorative_time()
	var age := fposmod(time * lerpf(0.018, 0.055, depth) + float(index) * 0.618034, 1.0)
	var drift := sin(time * 0.22 + float(index)) * 0.017
	var x := 0.05 + fposmod(float(index) * 0.381966 + drift, 1.0) * 0.9
	return _p(x, lerpf(0.91, 0.15, age))


func _decorative_time() -> float:
	return _motion_time if _effects_enabled and not _reduced_motion else 0.0


func _draw_shell(palette: Dictionary, alpha: float, arena_index: int) -> void:
	var outer := _field.grow(BACKDROP_PADDING)
	draw_rect(outer, _c(palette["back"], alpha))
	draw_rect(Rect2(_p(0.0, 0.0), _field.size * Vector2(1.0, 0.44)), _c(palette["wall"], alpha))
	draw_rect(Rect2(_p(0.0, 0.44), _field.size * Vector2(1.0, 0.56)), _c(palette["floor"], alpha))
	var detail := _c(palette["detail"], alpha * 0.48)
	var shadow := _c(palette["shadow"], alpha * 0.75)
	for panel in range(6):
		var x := 0.04 + float(panel) * 0.156
		var area := Rect2(_p(x, 0.13), _field.size * Vector2(0.146, 0.285))
		draw_rect(area, _c(palette["panel"], alpha * 0.35))
		draw_rect(area, detail, false, 1.0)
		for corner in [Vector2(0.05, 0.07), Vector2(0.95, 0.07), Vector2(0.05, 0.93), Vector2(0.95, 0.93)]:
			draw_circle(area.position + area.size * corner, 1.5, detail)
	draw_line(_p(0.0, 0.44), _p(1.0, 0.44), shadow, 9.0, true)
	draw_line(_p(0.0, 0.435), _p(1.0, 0.435), detail, 2.0, true)

	var ceiling := PackedVector2Array([_p(0.0, 0.0), _p(1.0, 0.0), _p(0.94, 0.12), _p(0.06, 0.12)])
	draw_colored_polygon(ceiling, shadow)
	draw_line(_p(0.06, 0.12), _p(0.94, 0.12), detail, 4.0, true)
	for lamp in STAGE_LAMPS:
		draw_line(_p(lamp - 0.06, 0.065), _p(lamp + 0.06, 0.065), shadow, 12.0, true)
		draw_line(_p(lamp - 0.055, 0.065), _p(lamp + 0.055, 0.065), _c(palette["signal"], alpha * 0.6), 3.0, true)
	for side in [0.015, 0.955]:
		var pillar := Rect2(_p(side, 0.105), _field.size * Vector2(0.03, 0.51))
		draw_rect(pillar, shadow)
		draw_rect(pillar.grow(-3.0), detail, false, 2.0)
		for stripe in range(3):
			var top := pillar.position + Vector2(0.0, pillar.size.y * (0.7 + stripe * 0.07))
			draw_line(top, top + Vector2(pillar.size.x, -pillar.size.x * 0.35), _c(palette["accent"], alpha * 0.4), 4.0, true)

	# Short, staggered deck seams suggest a room, never converging lane rails.
	for seam in range(12):
		var x := 0.07 + float(posmod(seam * 7 + arena_index * 3, 17)) * 0.047
		var y := 0.51 + float(seam % 4) * 0.115
		draw_line(_p(x, y), _p(minf(x + 0.075, 0.94), y), _c(palette["detail"], alpha * 0.17), 1.0, true)
	for lane in range(_lane_count):
		var anchor := DmjArenaLayout.position(_corridor, lane, _lane_count, arena_index)
		var width := minf(_field.size.x / float(_lane_count) * 0.24, 110.0)
		var pad := PackedVector2Array([
			anchor + Vector2(-width * 0.78, -8.0), anchor + Vector2(width * 0.78, -8.0),
			anchor + Vector2(width, 10.0), anchor + Vector2(-width, 10.0),
		])
		draw_colored_polygon(pad, _c(palette["shadow"], alpha * 0.5))
		draw_line(pad[3], pad[2], _c(palette["accent"], alpha * 0.25), 2.0, true)
	var cable := PackedVector2Array([_p(0.06, 0.47), _p(0.11, 0.60), _p(0.09, 0.74), _p(0.02, 0.86)])
	draw_polyline(cable, shadow, 5.0, true)
	draw_polyline(cable, detail, 1.0, true)


func _draw_player_light(palette: Dictionary, alpha: float) -> void:
	for band in range(12):
		var top := lerpf(0.44, 1.0, float(band) / 12.0)
		var bottom := lerpf(0.44, 1.0, float(band + 1) / 12.0)
		var area := Rect2(_p(0.0, top), _field.size * Vector2(1.0, bottom - top))
		draw_rect(area, _c(palette["accent"], alpha * _light_at(bottom) * 0.10))


func _draw_room_set_pieces(index: int, palette: Dictionary, alpha: float) -> void:
	match posmod(index, ROOM_COUNT):
		0:
			_draw_loading_bay(palette, alpha, index)
		1:
			_draw_turbine_hall(palette, alpha, index)
		_:
			_draw_reactor_deck(palette, alpha, index)


func _draw_loading_bay(palette: Dictionary, alpha: float, arena_index: int) -> void:
	_draw_panel_door(
		Rect2(_p(0.37, 0.135), _field.size * Vector2(0.26, 0.30)),
		_c(palette["shadow"], alpha * 0.85),
		_c(palette["accent"], alpha * 0.7),
		_c(palette["detail"], alpha * 0.8)
	)
	_draw_crane_arm(
		_p(0.075, 0.155), _p(0.32, 0.155),
		_c(palette["detail"], alpha * 0.78),
		_c(palette["accent"], alpha * 0.68)
	)
	draw_line(_p(0.30, 0.155), _p(0.30, 0.34), _c(palette["detail"], alpha), 2.0, true)
	_draw_hook(_p(0.30, 0.34), _c(palette["accent"], alpha * 0.8), _c(DmjPalette.TEXT, alpha * 0.5))
	_draw_crate(_p(0.135, 0.55), _field.size * Vector2(0.12, 0.15), palette, alpha)
	_draw_crate(_p(0.10, 0.415), _field.size * Vector2(0.08, 0.12), palette, alpha)
	_draw_crate(_p(0.91, 0.79), _field.size * Vector2(0.11, 0.15), palette, alpha)
	_draw_crate(_p(0.08, 0.89), _field.size * Vector2(0.095, 0.12), palette, alpha)
	var bay := DmjArenaLayout.position(_corridor, 2, _lane_count, arena_index)
	_draw_crate(bay + Vector2(_field.size.x * 0.06, -8.0), _field.size * Vector2(0.07, 0.08), palette, alpha * 0.8)
	_draw_wall_sign(_p(0.50, 0.195), "DOCK A-14", _c(DmjPalette.TEXT, alpha * 0.85), _c(palette["accent"], alpha * 0.7))


func _draw_turbine_hall(palette: Dictionary, alpha: float, arena_index: int) -> void:
	var radius := minf(_field.size.y * 0.155, _field.size.x * 0.085)
	for x in [0.19, 0.50, 0.81]:
		_draw_turbine(_p(x, 0.275), radius, _c(palette["shadow"], alpha),
			_c(palette["detail"], alpha * 0.85), _c(palette["accent"], alpha * 0.65))
	_draw_catwalk(_p(0.065, 0.455), _p(0.935, 0.455), _c(palette["detail"], alpha * 0.7), _c(palette["accent"], alpha * 0.45))
	_draw_crate(_p(0.09, 0.85), _field.size * Vector2(0.12, 0.13), palette, alpha)
	_draw_crate(_p(0.91, 0.66), _field.size * Vector2(0.11, 0.15), palette, alpha)
	var bay := DmjArenaLayout.position(_corridor, 1, _lane_count, arena_index)
	_draw_crate(bay + Vector2(-_field.size.x * 0.09, 10.0), _field.size * Vector2(0.08, 0.08), palette, alpha * 0.8)
	_draw_wall_sign(_p(0.335, 0.19), "VENT ARRAY", _c(DmjPalette.TEXT, alpha * 0.8), _c(palette["accent"], alpha * 0.7))


func _draw_reactor_deck(palette: Dictionary, alpha: float, arena_index: int) -> void:
	for side in [0.10, 0.90]:
		_draw_reactor_pipe(_p(side, 0.17), _p(0.50, 0.33), _c(palette["detail"], alpha * 0.8), _c(palette["accent"], alpha * 0.5))
	_draw_reactor_core(_p(0.50, 0.275), minf(_field.size.y * 0.125, _field.size.x * 0.07),
		_c(palette["shadow"], alpha), _c(palette["detail"], alpha), _c(palette["accent"], alpha * 0.8))
	for x in [0.27, 0.73]:
		var tank := Rect2(_p(x - 0.028, 0.20), _field.size * Vector2(0.056, 0.235))
		draw_rect(tank.grow(3.0), _c(palette["shadow"], alpha))
		draw_rect(tank, _c(palette["panel"], alpha))
		for line in range(5):
			var y := tank.position.y + tank.size.y * (float(line) + 0.5) / 5.0
			draw_line(Vector2(tank.position.x, y), Vector2(tank.end.x, y), _c(palette["accent"], alpha * 0.35), 2.0, true)
	_draw_crate(_p(0.10, 0.82), _field.size * Vector2(0.12, 0.12), palette, alpha)
	_draw_crate(_p(0.91, 0.87), _field.size * Vector2(0.10, 0.16), palette, alpha)
	var bay := DmjArenaLayout.position(_corridor, 0, _lane_count, arena_index)
	_draw_crate(bay + Vector2(_field.size.x * 0.075, -10.0), _field.size * Vector2(0.07, 0.08), palette, alpha * 0.8)
	_draw_wall_sign(_p(0.64, 0.19), "CORE LOCK", _c(DmjPalette.TEXT, alpha * 0.8), _c(palette["accent"], alpha * 0.7))


func _draw_room_label(index: int, palette: Dictionary, alpha: float) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var title := DmjArenaLayout.arena_name(index)
	var subtitle := "SECTOR %02d" % (posmod(index, ROOM_COUNT) + 1)
	var title_size := clampi(int(round(minf(_field.size.x * 0.028, _field.size.y * 0.06))), 10, 18)
	var subtitle_size := maxi(title_size - 2, 8)
	var title_width := font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1.0, title_size).x
	var subtitle_width := font.get_string_size(subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1.0, subtitle_size).x
	var width := maxf(title_width, subtitle_width) + 18.0
	var height := float(title_size + subtitle_size + 14)
	width = clampf(width, 92.0, minf(_field.size.x * 0.42, 300.0))
	var rect := Rect2(
		Vector2(
			clampf(_field.end.x - width - 16.0, _field.position.x + 10.0, _field.end.x - width - 8.0),
			_field.position.y + 14.0
		),
		Vector2(width, height)
	)
	draw_rect(rect, _c(DmjPalette.INK, alpha * 0.72))
	draw_rect(rect.grow(-1.5), _c(palette["panel"], alpha * 0.82))
	draw_line(
		Vector2(rect.position.x + 8.0, rect.end.y - 3.0),
		Vector2(rect.end.x - 8.0, rect.end.y - 3.0),
		_c(palette["accent"], alpha * 0.5),
		2.0,
		true
	)
	_draw_text(
		title,
		Vector2(rect.position.x + 9.0, rect.position.y + float(title_size) + 4.0),
		title_size,
		_c(DmjPalette.TEXT, alpha * 0.96)
	)
	_draw_text(
		subtitle,
		Vector2(rect.position.x + 9.0, rect.position.y + float(title_size + subtitle_size) + 6.0),
		subtitle_size,
		_c(palette["signal"], alpha * 0.72)
	)


func _draw_reduced_motion_banner(index: int, transition: float) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var text := DmjArenaLayout.arena_name(index)
	var size := clampi(int(round(minf(_field.size.x * 0.022, _field.size.y * 0.045))), 10, 16)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x + 24.0
	var rect := Rect2(
		Vector2(
			_field.get_center().x - width * 0.5,
			_field.position.y + 12.0
		),
		Vector2(width, float(size) + 14.0)
	)
	draw_rect(rect, _c(DmjPalette.INK, 0.48 * transition))
	draw_rect(rect.grow(-1.5), _c(DmjPalette.PANEL, 0.82 * transition))
	_draw_text(
		text,
		Vector2(rect.position.x + 12.0, rect.position.y + float(size) + 3.0),
		size,
		_c(DmjPalette.TEXT, 0.9 * transition)
	)


func _draw_transition_cover(room: int, previous: int, transition: float) -> void:
	var cover := 1.0 - absf(transition * 2.0 - 1.0)
	var frame := _field.grow(BACKDROP_PADDING)
	var blade := lerpf(frame.size.x * 0.03, frame.size.x * 0.5, cover)
	var left := Rect2(frame.position, Vector2(blade, frame.size.y))
	var right := Rect2(Vector2(frame.end.x - blade, frame.position.y), Vector2(blade, frame.size.y))
	draw_rect(left, _c(DmjPalette.INK, 0.9 * cover))
	draw_rect(right, _c(DmjPalette.INK, 0.9 * cover))

	var left_edge := left.end.x
	var right_edge := right.position.x
	if right_edge > left_edge:
		var gap := Rect2(Vector2(left_edge, frame.position.y), Vector2(right_edge - left_edge, frame.size.y))
		draw_rect(gap, _c(DmjPalette.PANEL, 0.28 * cover))

	var seam := lerpf(frame.position.x + 8.0, frame.end.x - 8.0, transition)
	draw_line(
		Vector2(seam, frame.position.y),
		Vector2(seam, frame.end.y),
		_c(DmjPalette.AMBER, 0.65 * cover),
		2.0,
		true
	)
	var room_text := DmjPalette.AMBER if transition < 0.5 else DmjPalette.SIGNAL
	draw_circle(_field.get_center(), lerpf(10.0, 32.0, cover), _c(room_text, 0.08 * cover))


func _arena_palette(index: int) -> Dictionary:
	match posmod(index, ROOM_COUNT):
		0:
			return {
				"name": "LOADING BAY",
				"back": Color("0a1217"),
				"wall": Color("17262d"),
				"floor": Color("16232a"),
				"panel": Color("21373f"),
				"accent": DmjPalette.AMBER,
				"signal": DmjPalette.SIGNAL,
				"detail": Color("4c6670"),
				"shadow": Color("060b10"),
			}
		1:
			return {
				"name": "TURBINE HALL",
				"back": Color("081018"),
				"wall": Color("13232c"),
				"floor": Color("122029"),
				"panel": Color("203642"),
				"accent": DmjPalette.SIGNAL,
				"signal": DmjPalette.AMBER,
				"detail": Color("58737b"),
				"shadow": Color("05090d"),
			}
		_:
			return {
				"name": "REACTOR DECK",
				"back": Color("0b1412"),
				"wall": Color("172e29"),
				"floor": Color("13211e"),
				"panel": Color("254238"),
				"accent": Color("b7d071"),
				"signal": DmjPalette.AMBER,
				"detail": Color("54746a"),
				"shadow": Color("050b08"),
			}


func _draw_panel_door(area: Rect2, fill: Color, accent: Color, detail: Color) -> void:
	draw_rect(area.grow(3.0), detail)
	draw_rect(area, fill)
	draw_line(area.position, Vector2(area.end.x, area.position.y), accent, 3.0, true)
	draw_line(
		Vector2(area.position.x, area.get_center().y),
		Vector2(area.end.x, area.get_center().y),
		detail,
		2.0,
		true
	)
	for rib in range(7):
		var y := lerpf(area.position.y, area.end.y, float(rib + 1) / 8.0)
		draw_line(Vector2(area.position.x, y), Vector2(area.end.x, y), _c(detail, 0.45), 2.0, true)
	for side in [area.position.x - 8.0, area.end.x + 5.0]:
		draw_line(Vector2(side, area.position.y), Vector2(side, area.end.y), accent, 3.0, true)


func _draw_crane_arm(from: Vector2, to: Vector2, arm: Color, accent: Color) -> void:
	draw_line(from, to, arm, 5.0, true)
	draw_line(from + Vector2(0.0, 3.0), to + Vector2(0.0, 3.0), accent, 1.5, true)


func _draw_hook(anchor: Vector2, accent: Color, light: Color) -> void:
	draw_line(anchor + Vector2(0.0, -32.0), anchor, accent, 2.0, true)
	draw_circle(anchor, 4.0, light)
	draw_line(anchor - Vector2(6.0, 0.0), anchor + Vector2(6.0, 0.0), accent, 2.0, true)


func _draw_turbine(center: Vector2, radius: float, body: Color, accent: Color, glow: Color) -> void:
	draw_circle(center, radius + 6.0, body)
	draw_circle(center, radius, _c(DmjPalette.INK, body.a))
	draw_arc(center, radius + 3.0, 0.0, TAU, 48, accent, 2.5, true)
	for blade in range(6):
		var angle := float(blade) * TAU / 6.0 + PI * 0.08 + _decorative_time() * 0.9
		var direction := Vector2.from_angle(angle)
		var tangent := direction.orthogonal()
		var points := PackedVector2Array([
			center + (direction * 0.2 - tangent * 0.08) * radius,
			center + (direction * 0.9 - tangent * 0.21) * radius,
			center + (direction * 0.78 + tangent * 0.15) * radius,
			center + (direction * 0.28 + tangent * 0.12) * radius,
		])
		draw_colored_polygon(points, body.lerp(accent, 0.65))
		draw_line(
			points[0], points[1], _c(DmjPalette.TEXT, accent.a * 0.4), 1.4, true
		)
	draw_circle(center, radius * 0.23, body)
	draw_arc(center, radius * 0.23, 0.0, TAU, 24, accent, 2.0, true)
	draw_circle(center - Vector2(radius * 0.03, radius * 0.03), radius * 0.1, glow)
	for bolt in range(8):
		var point := center + Vector2.from_angle(float(bolt) * TAU / 8.0) * (radius + 3.0)
		draw_circle(point, 1.6, _c(DmjPalette.TEXT, accent.a * 0.65))


func _draw_catwalk(from: Vector2, to: Vector2, body: Color, accent: Color) -> void:
	draw_line(from, to, body, 5.0, true)
	draw_line(from + Vector2(0.0, 4.0), to + Vector2(0.0, 4.0), accent, 1.5, true)
	for bar in range(4):
		var x := lerpf(from.x, to.x, float(bar) / 3.0)
		draw_line(Vector2(x, from.y - 12.0), Vector2(x, from.y + 12.0), body, 2.0, true)


func _draw_reactor_core(center: Vector2, radius: float, body: Color, accent: Color, glow: Color) -> void:
	var time := _decorative_time()
	var pulse := 0.85 + sin(time * 1.8) * 0.15
	for band in range(4):
		draw_circle(center, radius * (1.5 - float(band) * 0.18), _c(glow, 0.035 * pulse))
	draw_circle(center, radius + 10.0, body)
	draw_arc(center, radius + 4.0, 0.0, TAU, 48, accent, 3.0, true)
	draw_circle(center, radius * 0.72, body.lightened(0.18))
	draw_circle(center - Vector2(radius * 0.08, radius * 0.1), radius * 0.53, _c(glow, pulse * 0.55))
	draw_circle(center - Vector2(radius * 0.15, radius * 0.18), radius * 0.3, _c(DmjPalette.TEXT, glow.a * pulse * 0.75))
	for ring in range(2):
		var angle := (0.55 + time * 0.28) * (-1.0 if ring == 0 else 1.0)
		draw_set_transform(center, angle, Vector2(1.0, 0.4))
		draw_arc(Vector2.ZERO, radius * 1.1, 0.0, TAU, 48, _c(glow, 0.8), 2.5, true)
		var orbit := Vector2.from_angle(time * 0.8 + float(ring) * PI) * radius * 1.1
		draw_circle(orbit, 3.0, _c(DmjPalette.TEXT, glow.a * 0.8))
	draw_set_transform(Vector2.ZERO)
	draw_line(center - Vector2(0.0, radius * 1.8), center + Vector2(0.0, radius * 1.8), accent, 6.0, true)
	draw_line(center - Vector2(radius * 1.1, 0.0), center + Vector2(radius * 1.1, 0.0), accent, 6.0, true)


func _draw_reactor_pipe(from: Vector2, to: Vector2, body: Color, accent: Color) -> void:
	var elbow := lerpf(from.x, to.x, 0.6)
	var points := PackedVector2Array([from, Vector2(elbow, from.y), Vector2(elbow, to.y), to])
	draw_polyline(points, _c(DmjPalette.INK, body.a), 13.0, true)
	draw_polyline(points, body, 7.0, true)
	draw_polyline(points, accent, 1.5, true)


func _draw_crate(anchor: Vector2, size: Vector2, palette: Dictionary, alpha: float) -> void:
	var rect := Rect2(anchor - Vector2(size.x * 0.5, size.y), size)
	var bevel := Vector2(size.x * 0.14, -minf(size.y * 0.24, 18.0))
	var top := PackedVector2Array([rect.position, rect.position + bevel, Vector2(rect.end.x, rect.position.y) + bevel, Vector2(rect.end.x, rect.position.y)])
	var side := PackedVector2Array([Vector2(rect.end.x, rect.position.y), Vector2(rect.end.x, rect.position.y) + bevel, rect.end + bevel, rect.end])
	draw_rect(Rect2(anchor - Vector2(size.x * 0.48, 2.0), Vector2(size.x * 1.15, 8.0)), _c(palette["shadow"], alpha * 0.6))
	draw_colored_polygon(top, _c(palette["detail"], alpha * 0.75))
	draw_colored_polygon(side, _c(palette["shadow"], alpha * 0.85))
	draw_rect(rect, _c(palette["panel"], alpha))
	draw_rect(rect, _c(palette["detail"], alpha * 0.6), false, 1.5)
	for rail: float in [0.16, 0.84]:
		var x := rect.position.x + rect.size.x * rail
		draw_line(Vector2(x, rect.position.y + 3.0), Vector2(x, rect.end.y - 3.0), _c(palette["shadow"], alpha * 0.8), 4.0, true)
	var badge := Rect2(rect.position + rect.size * Vector2(0.33, 0.30), rect.size * Vector2(0.34, 0.24))
	draw_rect(badge, _c(palette["shadow"], alpha))
	draw_line(badge.position, badge.end, _c(palette["accent"], alpha * 0.55), 2.0, true)


func _draw_wall_sign(anchor: Vector2, text: String, text_color: Color, line_color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var size := clampi(int(round(minf(_field.size.x * 0.016, _field.size.y * 0.036))), 9, 14)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size).x + 14.0
	var rect := Rect2(Vector2(anchor.x - width * 0.5, anchor.y - 12.0), Vector2(width, float(size) + 10.0))
	draw_rect(rect, _c(DmjPalette.INK, 0.56))
	draw_rect(rect.grow(-1.0), _c(DmjPalette.STEEL, 0.78))
	draw_line(
		Vector2(rect.position.x + 5.0, rect.end.y - 3.0),
		Vector2(rect.end.x - 5.0, rect.end.y - 3.0),
		line_color,
		2.0,
		true
	)
	_draw_text(text, Vector2(rect.position.x + 7.0, rect.position.y + float(size) + 2.0), size, text_color)


func _draw_text(text: String, baseline: Vector2, size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null or text.is_empty():
		return
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)


func _p(x: float, y: float, parallax := 1.0) -> Vector2:
	var bob := _corridor.position - JamBot.corridor_rect(_field).position
	return _field.position + bob * parallax + _field.size * Vector2(x, y)


func _light_at(progress: float) -> float:
	if progress <= LIGHT_REACH:
		return 0.0
	var fall := inverse_lerp(LIGHT_REACH, 1.0, progress)
	var flare := 0.0 if _reduced_motion or not _effects_enabled else _flash
	return (LIGHT_REST + LIGHT_FLASH * flare) * fall * fall


func _c(color: Color, alpha: float) -> Color:
	return Color(color.r, color.g, color.b, color.a * clampf(alpha, 0.0, 1.0))
