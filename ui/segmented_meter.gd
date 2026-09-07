class_name DmjSegmentedMeter
extends Range

## One meter for input level, combo charge and completed waves.
@export_range(1, 64) var segments := 20:
	set(count):
		segments = maxi(count, 1)
		queue_redraw()

@export var fill_color := DmjPalette.SIGNAL:
	set(color):
		fill_color = color
		queue_redraw()

var marker := -1:
	set(index):
		marker = index
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_changed.connect(func(_value: float) -> void: queue_redraw())
	resized.connect(queue_redraw)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var gap := minf(4.0, size.x / float(segments) * 0.28)
	var width := (size.x - gap * float(segments - 1)) / float(segments)
	for index in range(segments):
		var bar := Rect2(Vector2(float(index) * (width + gap), 0.0), Vector2(width, size.y))
		draw_rect(bar, Color(DmjPalette.LINE, 0.55))
		var filled := clampf(ratio * float(segments) - float(index), 0.0, 1.0)
		if filled > 0.0:
			draw_rect(Rect2(bar.position, Vector2(width * filled, size.y)), fill_color)
		if index == marker:
			draw_rect(bar, DmjPalette.TEXT, false, 1.0)
