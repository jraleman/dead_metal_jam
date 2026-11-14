extends Range

## A compact pitch-color key. Range.value selects the currently called pitch class.
var _unit := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip_text = "Same note, same color in every octave. Letters identify every pitch."
	accessibility_description = "Note color key: C, C sharp, D, D sharp, E, F, F sharp, G, G sharp, A, A sharp, B."
	value_changed.connect(func(_value: float) -> void: queue_redraw())
	resized.connect(queue_redraw)


## Keep pitch letters legible in the console's physical UI units.
func fit_units(unit: float) -> void:
	_unit = unit
	custom_minimum_size = Vector2(140, 22) * unit
	queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var width := minf(size.x, 540.0 * _unit) / 12.0
	var font := ThemeDB.fallback_font
	var pixels := clampi(roundi(width * 0.5), roundi(8 * _unit), roundi(14 * _unit))
	for note in range(12):
		var area := Rect2(Vector2(note * width, 2.0 * _unit),
			Vector2(width - 3.0 * _unit, size.y - 4.0 * _unit))
		var color := DmjPalette.note_color(note)
		var selected := int(value) == note
		draw_rect(area, color if selected else DmjPalette.STEEL.lerp(color, 0.45))
		draw_line(area.position, Vector2(area.end.x, area.position.y), color, 2.0 * _unit)
		if selected:
			draw_rect(area.grow(_unit), DmjPalette.TEXT, false, _unit)
		var text := PitchDetector.note_name(note)
		var text_width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pixels).x
		var baseline := area.get_center().y + (font.get_ascent(pixels) - font.get_descent(pixels)) * 0.5
		draw_string(font, Vector2(area.get_center().x - text_width * 0.5, baseline),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, pixels,
			DmjDroneArt.NOTE_INK if selected else DmjPalette.TEXT)
