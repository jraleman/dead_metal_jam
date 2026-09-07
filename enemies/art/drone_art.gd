@tool
class_name DmjDroneArt
extends Node2D

## A character drawing, not an enemy. Gameplay, the gallery and share cards
## feed the same pose without giving the artwork a clock or scoring rules.
const SIZE := Vector2(224.0, 224.0)
const INK := Color("111b20")
const METAL_DARK := Color("293b42")
const METAL := Color("61777c")
const METAL_LIGHT := Color("a8b9b6")
const RUST_DARK := Color("624432")
const RUST := Color("a36b48")
const RUST_LIGHT := Color("d69a67")
const PAPER := Color("f4e6bf")
const NOTE_INK := Color("20282a")
const ACCENT := DmjPalette.AMBER
const HOSTILE := DmjPalette.DANGER

@export var notes: Array[int] = [47]:
	set(value):
		notes = value
		queue_redraw()
@export var active_index := 0:
	set(value):
		active_index = value
		queue_redraw()
@export var targeted := false:
	set(value):
		targeted = value
		queue_redraw()
@export_range(-1.0, 1.0) var charge := -1.0:
	set(value):
		charge = value
		queue_redraw()
@export var reduced_motion := false:
	set(value):
		reduced_motion = value
		queue_redraw()
@export var walking := true:
	set(value):
		walking = value
		queue_redraw()
@export var defeated := false:
	set(value):
		defeated = value
		queue_redraw()

var motion_time := 0.0
var firing := 0.0
var target_color := ACCENT
var combat_pose := false
var beat_in := 0.0
var hit_flash := 0.0
var effects_enabled := true


func set_phrase(phrase: Array[int], cursor := 0) -> void:
	notes = phrase.duplicate()
	active_index = cursor


func set_pose(
	time: float, moving: bool, windup: float, focus: bool,
	fallen: bool, muzzle: float, reduce_motion: bool
) -> void:
	motion_time = time
	walking = moving
	charge = windup
	targeted = focus
	defeated = fallen
	firing = muzzle
	reduced_motion = reduce_motion
	queue_redraw()


func current_note() -> int:
	return notes[active_index] if active_index >= 0 and active_index < notes.size() else -1


func visual_bounds() -> Rect2:
	return Rect2(-SIZE * 0.5, SIZE)


func target_offset() -> Vector2:
	return Vector2(0.0, 10.0)


func muzzle_offset() -> Vector2:
	return Vector2(55.0, -2.0 - firing * 5.0 + _wave(3.0) * 0.9)


func ground_offset() -> Vector2:
	var bounds := visual_bounds()
	return Vector2(bounds.get_center().x, bounds.end.y - 5.0)


## Includes the shared charge bar and targeting brackets for framed previews.
func framed_bounds() -> Rect2:
	var bounds := visual_bounds().grow(10.0)
	var overhead := 14.0
	bounds.position.y -= overhead
	bounds.size.y += overhead
	return bounds


static func fit_scale(available_height: float) -> float:
	return clampf(available_height / (SIZE.y * 2.0), 0.25, 1.0)


static func foot_clearance(visual_scale: float) -> float:
	# Feet stand on the rail; only the shadow, brackets and camera shake
	# extend beneath it.
	return 12.0 * visual_scale + 8.0


func _draw() -> void:
	var bounds := visual_bounds()
	draw_set_transform(ground_offset(), 0.0, Vector2(1.0, 0.15))
	draw_circle(Vector2.ZERO, bounds.size.x * 0.36, Color(0.0, 0.0, 0.0, 0.28))
	draw_set_transform(Vector2.ZERO)
	_draw_character()
	if charge >= 0.0 and not defeated:
		_draw_charge(bounds)
	if targeted and not defeated:
		_draw_target(bounds)
	if firing > 0.0:
		_draw_discharge()


func _draw_character() -> void:
	_note_plate(Rect2(-34.0, -34.0, 68.0, 68.0), current_note())


func _emitter(center: Vector2, radius := 9.0) -> void:
	draw_circle(center, radius + 2.0, INK)
	draw_circle(center, radius, METAL_DARK)
	draw_arc(center, radius - 2.0, 0.0, TAU, 20, METAL_LIGHT, 2.0, true)
	draw_circle(center, radius * 0.42, HOSTILE)
	draw_circle(center - Vector2(1.0, 1.0), radius * 0.17, PAPER)


func _wave(rate: float, phase := 0.0) -> float:
	return 0.0 if reduced_motion else sin(motion_time * rate + phase)


func _stride(amount: float, phase := 0.0) -> float:
	return _wave(8.0, phase) * amount if walking and not defeated else 0.0


func _panel(points: PackedVector2Array, fill: Color, edge := INK, width := 2.2) -> void:
	if effects_enabled and not reduced_motion:
		fill = fill.lerp(Color.WHITE, hit_flash * 0.8)
	draw_colored_polygon(points, fill)
	var outline := points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, edge, width, true)


func _box_points(area: Rect2, cut := 3.0) -> PackedVector2Array:
	var c := minf(cut, minf(area.size.x, area.size.y) * 0.25)
	var p := area.position
	var e := area.end
	return PackedVector2Array([
		Vector2(p.x + c, p.y), Vector2(e.x - c, p.y),
		Vector2(e.x, p.y + c), Vector2(e.x, e.y - c),
		Vector2(e.x - c, e.y), Vector2(p.x + c, e.y),
		Vector2(p.x, e.y - c), Vector2(p.x, p.y + c),
	])


func _box(area: Rect2, fill: Color, cut := 3.0, edge := INK) -> void:
	_panel(_box_points(area, cut), fill, edge)
	draw_line(
		area.position + Vector2(cut + 1.0, 2.0),
		Vector2(area.end.x - cut - 1.0, area.position.y + 2.0),
		fill.lightened(0.22), 1.2, true
	)


func _joint(center: Vector2, radius: float, fill := METAL) -> void:
	draw_circle(center, radius + 2.0, INK)
	draw_circle(center, radius, fill)
	draw_circle(center, maxf(radius * 0.28, 1.0), INK)


func _limb(from: Vector2, to: Vector2, width: float, fill := METAL, ribs := 0) -> void:
	draw_line(from, to, INK, width + 4.0, true)
	draw_line(from, to, fill, width, true)
	var side := (to - from).normalized().orthogonal() * width * 0.5
	for index in range(1, ribs + 1):
		var center := from.lerp(to, float(index) / float(ribs + 1))
		draw_line(center - side, center + side, INK, 1.6, true)


func _rivet(center: Vector2, radius := 2.0) -> void:
	draw_circle(center, radius + 1.0, INK)
	draw_circle(center, radius, METAL_LIGHT)
	draw_line(center - Vector2(radius * 0.6, 0.0), center + Vector2(radius * 0.6, 0.0), INK, 1.0)


func _eye(area: Rect2, angry := false) -> void:
	if defeated:
		draw_line(area.position, area.end, INK, 2.5, true)
		draw_line(
			Vector2(area.end.x, area.position.y), Vector2(area.position.x, area.end.y),
			INK, 2.5, true
		)
		return
	draw_rect(area.grow(2.0), INK)
	draw_rect(area, HOSTILE if charge >= 0.0 else PAPER)
	if angry:
		draw_line(
			area.position - Vector2(3.0, 4.0),
			Vector2(area.end.x + 2.0, area.position.y + 2.0), INK, 4.0, true
		)
	draw_rect(Rect2(area.position + Vector2(1.0, 1.0), Vector2(2.0, 3.0)), Color.WHITE)


func _text(text: String, area: Rect2, font_size: int, color: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null or text.is_empty():
		return
	var pixels := font_size
	while pixels > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pixels).x > area.size.x:
		pixels -= 1
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pixels).x
	var baseline := area.get_center().y + (font.get_ascent(pixels) - font.get_descent(pixels)) * 0.5
	draw_string(
		font, Vector2(area.get_center().x - width * 0.5, baseline),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pixels, color
	)


func _note_plate(area: Rect2, note: int, active := true, broken := false, number := -1) -> void:
	_plate_face(_box_points(area, 5.0), area.grow(-5.0), note, active, broken, number)


func _plate_face(
	points: PackedVector2Array, glyph_area: Rect2, note: int,
	active: bool, broken := false, number := -1
) -> void:
	var note_color := DmjPalette.note_color(note)
	var fill := note_color if active else METAL_DARK.lerp(note_color, 0.28)
	if broken:
		fill = METAL_DARK
	_panel(points, fill, note_color.lightened(0.3) if active and not broken else INK, 3.0 if active else 2.2)
	if broken:
		var c := glyph_area.get_center()
		draw_polyline(PackedVector2Array([
			glyph_area.position.lerp(c, 0.3), c + Vector2(4.0, -9.0),
			c - Vector2(7.0, 1.0), glyph_area.end.lerp(c, 0.3),
		]), INK, 3.0, true)
		return
	if note >= 0:
		_text(
			PitchDetector.note_name(note), glyph_area, 44 if active else 30,
			NOTE_INK if active else note_color.lightened(0.25)
		)
	if number >= 0:
		_text(
			str(number + 1), Rect2(glyph_area.position, Vector2(10.0, 10.0)), 9,
			NOTE_INK if active else METAL_LIGHT
		)
	if active:
		var y := glyph_area.end.y - 1.0
		draw_line(
			Vector2(glyph_area.get_center().x - 8.0, y),
			Vector2(glyph_area.get_center().x + 8.0, y), NOTE_INK, 2.0, true
		)


func _draw_charge(bounds: Rect2) -> void:
	var bar := Rect2(bounds.position - Vector2(0.0, 17.0), Vector2(bounds.size.x, 9.0))
	draw_rect(bar.grow(2.0), INK)
	draw_rect(bar, METAL_DARK)
	var progress := clampf(charge, 0.0, 1.0)
	var color := HOSTILE if progress >= 0.78 else DmjPalette.AMBER
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), color)
	for division in range(1, 5):
		var x := bar.position.x + bar.size.x * float(division) / 5.0
		draw_line(Vector2(x, bar.position.y), Vector2(x, bar.end.y), INK, 1.0)
	if effects_enabled and not reduced_motion and progress >= 0.78:
		draw_rect(bar.grow(3.0), Color(HOSTILE, 0.15 + _wave(5.0) * 0.06), false, 2.0)


func _draw_target(bounds: Rect2) -> void:
	var frame := bounds.grow(6.0)
	var accent := DmjPalette.note_color(current_note()) if current_note() >= 0 else target_color
	var length := 15.0
	for corner: Vector2 in [
		frame.position, Vector2(frame.end.x, frame.position.y),
		frame.end, Vector2(frame.position.x, frame.end.y),
	]:
		var dx := 1.0 if corner.x < frame.get_center().x else -1.0
		var dy := 1.0 if corner.y < frame.get_center().y else -1.0
		draw_polyline(PackedVector2Array([
			corner + Vector2(dx * length, 0.0), corner,
			corner + Vector2(0.0, dy * length),
		]), accent, 3.0, true)
	if combat_pose:
		var radius := 30.0 if reduced_motion else 30.0 + clampf(beat_in / 2.0, 0.0, 1.0) * 24.0
		var on_beat := absf(beat_in) <= 0.14
		draw_arc(
			target_offset(), radius, 0.0, TAU, 40,
			Color(PAPER if on_beat else accent, 0.9 if on_beat else 0.55),
			2.5 if on_beat else 1.4, true
		)


func _draw_discharge() -> void:
	if combat_pose:
		var center := muzzle_offset()
		var muzzle_radius := 16.0 if reduced_motion else lerpf(20.0, 12.0, firing)
		draw_circle(center, muzzle_radius, Color(HOSTILE, firing * 0.3))
		draw_circle(center, muzzle_radius * 0.35, Color(PAPER, firing))
		draw_arc(center, muzzle_radius, 0.0, TAU, 24, Color(HOSTILE, firing), 2.0, true)
		return
	var radius := 62.0 if reduced_motion else lerpf(76.0, 54.0, firing)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, Color(HOSTILE, firing), 3.0, true)
	for index in range(6):
		var direction := Vector2.from_angle(float(index) * TAU / 6.0)
		draw_line(direction * (radius + 5.0), direction * (radius + 13.0), Color(HOSTILE, firing), 2.0, true)
