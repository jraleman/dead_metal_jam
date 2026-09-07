@tool
class_name DmjLifeRack
extends Control

## A view of the shell's lives pool, not another health system.
const TUBE_SIZE := Vector2(44.0, 58.0)
const TUBE_GAP := 14.0
const BURN_SECONDS := 0.45
const WIDE_WIDTH := 600.0
const READOUT_WIDTH := 230.0

@onready var _heading: BoxContainer = %LifeHeading
@onready var _count: Label = %LifeCount
@onready var _status: Label = %LifeStatus

var remaining_lives := 3
var capacity := 3
var protected := false
var _reduced_motion := false
var _effects_enabled := true
var _burn_left := 0.0
var _burnt_from := 0
var _pulse_time := 0.0


func _ready() -> void:
	resized.connect(_refresh_layout)
	visibility_changed.connect(_refresh_processing)
	_update_copy()
	_refresh_layout()
	_refresh_processing()


func set_lives(remaining: int, total: int) -> void:
	assert(total > 0 and remaining >= 0 and remaining <= total, "Invalid lives pool.")
	if remaining_lives == remaining and capacity == total:
		return
	var lost := capacity == total and remaining < remaining_lives
	_burnt_from = remaining_lives
	_burn_left = BURN_SECONDS if lost and _can_animate() else 0.0
	remaining_lives = remaining
	capacity = total
	_pulse_time = 0.0
	_update_copy()
	_refresh_processing()
	queue_redraw()


func set_protected(enabled: bool) -> void:
	protected = enabled
	_update_copy()
	_refresh_processing()
	queue_redraw()


func set_presentation_options(reduced_motion: bool, effects_enabled: bool) -> void:
	_reduced_motion = reduced_motion
	_effects_enabled = effects_enabled
	_refresh_processing()
	queue_redraw()


func is_critical() -> bool:
	return remaining_lives == 1 and not protected


func _can_animate() -> bool:
	return not _reduced_motion and _effects_enabled and not protected


func _refresh_processing() -> void:
	if not _can_animate():
		_burn_left = 0.0
		_pulse_time = 0.0
	set_process(
		is_visible_in_tree() and _can_animate()
		and (is_critical() or _burn_left > 0.0)
	)


func _process(delta: float) -> void:
	if not _can_animate():
		return
	_pulse_time += delta
	_burn_left = maxf(_burn_left - delta, 0.0)
	queue_redraw()
	_refresh_processing()


func _update_copy() -> void:
	if not is_node_ready():
		return
	_count.text = "%d / %d %s" % [
		remaining_lives, capacity, "LIFE" if capacity == 1 else "LIVES",
	]
	if protected:
		_status.text = "DEMO / CIRCUIT PROTECTED"
	elif remaining_lives == 0:
		_status.text = "POWER CUT"
	elif is_critical():
		_status.text = "LAST TUBE / STAY LOUD"
	elif remaining_lives < capacity:
		var blown := capacity - remaining_lives
		_status.text = "%d %s BLOWN" % [blown, "TUBE" if blown == 1 else "TUBES"]
	else:
		_status.text = "KEEP THE AMP ALIVE"
	var danger := is_critical() or remaining_lives == 0
	_status.add_theme_color_override(
		"font_color", DmjPalette.DANGER if danger and not protected else DmjPalette.MUTED
	)
	tooltip_text = "%d of %d lives. %s" % [
		remaining_lives, capacity,
		"Demo protects your lives." if protected
		else "Each robot that fires burns one amplifier tube. No tubes means the round is over.",
	]
	accessibility_name = "Amplifier lives"
	accessibility_description = tooltip_text


func _refresh_layout() -> void:
	var wide := size.x >= WIDE_WIDTH
	_heading.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_heading.vertical = wide
	_count.add_theme_font_size_override("font_size", 30 if wide else 24)
	_heading.position = Vector2(0.0, 4.0) if wide else Vector2.ZERO
	_heading.size = Vector2(READOUT_WIDTH, 72.0) if wide else Vector2(size.x, 26.0)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_RIGHT
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if wide else HORIZONTAL_ALIGNMENT_CENTER
	_status.position = Vector2(0.0, size.y - 20.0)
	_status.size = Vector2(READOUT_WIDTH if wide else size.x, 20.0)
	queue_redraw()


## The same fitted envelope drives drawing and layout coverage.
func tube_rect(index: int) -> Rect2:
	var top := _heading.get_rect().end.y + 4.0
	var bottom := _status.get_rect().position.y - 4.0
	var area := Rect2(8.0, top, maxf(size.x - 16.0, 0.0), maxf(bottom - top, 0.0))
	var max_zoom := 1.0
	if size.x >= WIDE_WIDTH:
		var left := READOUT_WIDTH + 24.0
		area = Rect2(left, 4.0, size.x - left - 8.0, maxf(size.y - 8.0, 0.0))
		max_zoom = 1.75
	var width := TUBE_SIZE.x * float(capacity) + TUBE_GAP * float(capacity - 1)
	var zoom := minf(max_zoom, minf(area.size.x / width, area.size.y / TUBE_SIZE.y))
	var origin := Vector2(
		area.get_center().x - width * zoom * 0.5
		+ float(index) * (TUBE_SIZE.x + TUBE_GAP) * zoom,
		area.get_center().y - TUBE_SIZE.y * zoom * 0.5
	)
	return Rect2(origin, TUBE_SIZE * zoom)


func _draw() -> void:
	if not is_node_ready():
		return
	var first := tube_rect(0)
	var last := tube_rect(capacity - 1)
	var bus_y := first.end.y - first.size.y / TUBE_SIZE.y
	draw_line(
		Vector2(first.position.x + 2.0, bus_y), Vector2(last.end.x - 2.0, bus_y),
		DmjPalette.LINE, 1.0
	)
	for index in range(capacity):
		var bounds := tube_rect(index)
		if bounds.size.y <= 0.0:
			continue
		draw_set_transform(bounds.position, 0.0, Vector2.ONE * bounds.size.y / TUBE_SIZE.y)
		_draw_tube(index)
	draw_set_transform(Vector2.ZERO)


func _draw_tube(index: int) -> void:
	var powered := index < remaining_lives
	var color := DmjPalette.SIGNAL if protected else (
		DmjPalette.DANGER if is_critical() else DmjPalette.AMBER
	)
	var glow := 0.13
	if powered and is_critical() and _can_animate():
		glow += (sin(_pulse_time * 3.0) + 1.0) * 0.035
	if powered:
		draw_circle(Vector2(22.0, 25.0), 20.0, Color(color, glow))

	var glass := PackedVector2Array([
		Vector2(12, 4), Vector2(32, 4), Vector2(38, 11),
		Vector2(38, 44), Vector2(6, 44), Vector2(6, 11),
	])
	draw_colored_polygon(glass, DmjPalette.STEEL if powered else DmjPalette.INK)
	var outline := glass.duplicate()
	outline.append(glass[0])
	draw_polyline(outline, DmjPalette.MUTED if powered else DmjPalette.LINE, 1.4, true)
	draw_line(Vector2(10, 14), Vector2(10, 37), Color(DmjPalette.TEXT, 0.22), 2.0, true)

	for x in [17.0, 27.0]:
		draw_line(Vector2(x, 14), Vector2(x, 43), DmjPalette.LINE, 2.0)
	if powered:
		var filament := PackedVector2Array([
			Vector2(22, 42), Vector2(22, 35), Vector2(16, 31),
			Vector2(28, 26), Vector2(16, 21), Vector2(22, 17), Vector2(22, 12),
		])
		draw_polyline(filament, Color(color, 0.16), 7.0, true)
		draw_polyline(filament, color, 2.4, true)
		draw_circle(Vector2(22, 12), 2.0, DmjPalette.TEXT)
	else:
		# The broken wire, cracked glass and cross remain legible in greyscale.
		draw_polyline(PackedVector2Array([
			Vector2(22, 12), Vector2(18, 20), Vector2(23, 23),
		]), DmjPalette.MUTED, 1.6, true)
		draw_polyline(PackedVector2Array([
			Vector2(25, 31), Vector2(20, 36), Vector2(22, 42),
		]), DmjPalette.MUTED, 1.6, true)
		draw_polyline(PackedVector2Array([
			Vector2(31, 5), Vector2(26, 13), Vector2(32, 17), Vector2(29, 22),
		]), DmjPalette.LINE, 1.2, true)
		draw_line(Vector2(16, 24), Vector2(28, 34), DmjPalette.MUTED, 2.2, true)
		draw_line(Vector2(28, 24), Vector2(16, 34), DmjPalette.MUTED, 2.2, true)

	draw_rect(Rect2(5, 43, 34, 9), DmjPalette.INK)
	draw_rect(Rect2(5, 43, 34, 9), DmjPalette.LINE, false, 1.0)
	draw_line(Vector2(8, 46), Vector2(36, 46), color if powered else DmjPalette.LINE, 2.0)
	for x in [14.0, 22.0, 30.0]:
		draw_line(Vector2(x, 52), Vector2(x, 56), DmjPalette.MUTED, 2.0)
	draw_line(Vector2(2, 57), Vector2(42, 57), DmjPalette.LINE, 1.0)

	if _burn_left > 0.0 and index >= remaining_lives and index < _burnt_from:
		var fade := _burn_left / BURN_SECONDS
		draw_circle(
			Vector2(22, 25), 17.0 + (1.0 - fade) * 3.0,
			Color(DmjPalette.AMBER, fade * 0.7), false, 1.8, true
		)
