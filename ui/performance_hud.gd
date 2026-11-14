class_name DmjPerformanceHud
extends PanelContainer

## Presentation only. The round supplies notes, judgements and wave events.
const NoteStrip = preload("res://games/dead_metal_jam/ui/note_strip.gd")
const SIGNAL_DECAY := 2.5
const FEEDBACK_SECONDS := 1.1

@onready var _row: BoxContainer = %DmjConsoleRow
@onready var _readouts: BoxContainer = %DmjReadouts
@onready var _target: Label = %DmjTarget
@onready var _note_strip: NoteStrip = %DmjNoteStrip
@onready var _signal_meter: DmjSegmentedMeter = %DmjSignalMeter
@onready var _wave_meter: DmjSegmentedMeter = %DmjWaveMeter
@onready var _combo_meter: DmjSegmentedMeter = %DmjComboMeter
@onready var _combo_group: Control = %DmjComboGroup
@onready var _combo_label: Label = %DmjCombo
@onready var _combo_hint: Label = %DmjComboHint
@onready var _feedback: Label = %DmjFeedback
@onready var _feedback_caption: Label = %DmjFeedbackCaption
@onready var _feedback_detail: Label = %DmjFeedbackDetail
@onready var _track_card: Control = %DmjTrackCard
@onready var _track_title: Label = %DmjTrackTitle
@onready var _track_detail: Label = %DmjTrackDetail
@onready var _audio_caption: PanelContainer = %AudioCaption
@onready var _caption_label: Label = _audio_caption.get_node("CaptionLabel")
@onready var _hud_layout: VBoxContainer = get_parent()

var _signal_level := 0.0
var _feedback_left := 0.0
var _feedback_color := DmjPalette.AMBER
var _calibrating := false
var _caption_clearance := 0.0


func _ready() -> void:
	# Changing minimum sizes during a container's sort can leave stale geometry.
	resized.connect(_refresh_layout, CONNECT_DEFERRED)
	get_viewport().size_changed.connect(_refresh_layout, CONNECT_DEFERRED)
	_refresh_layout()
	reset_performance(1)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_signal_level = maxf(_signal_level - delta * SIGNAL_DECAY, 0.0)
	_signal_meter.value = _signal_level
	if _feedback_left > 0.0:
		_feedback_left = maxf(_feedback_left - delta, 0.0)
		if is_zero_approx(_feedback_left):
			_rest_feedback()
		queue_redraw()


func _draw() -> void:
	# A local, fading edge instead of another full-screen flash.
	if _feedback_left > 0.0:
		draw_line(
			Vector2(18.0, 1.0), Vector2(size.x - 18.0, 1.0),
			Color(_feedback_color, _feedback_left / FEEDBACK_SECONDS), 2.0
		)
	for x in [10.0, size.x - 10.0]:
		for y in [10.0, size.y - 10.0]:
			draw_circle(Vector2(x, y), 2.0, DmjPalette.LINE)


func reset_performance(waves: int) -> void:
	_signal_level = 0.0
	_signal_meter.value = 0.0
	_signal_meter.fill_color = DmjPalette.SIGNAL
	set_called_note(-1)
	_feedback_left = 0.0
	_caption_clearance = 0.0
	_wave_meter.segments = maxi(waves, 1)
	_wave_meter.max_value = float(maxi(waves, 1))
	_wave_meter.value = 0.0
	_wave_meter.marker = -1
	set_combo(0)
	_rest_feedback()
	queue_redraw()


func set_round_visible(shown: bool) -> void:
	visible = shown
	_combo_group.visible = shown


func set_track(chart: JamChart, mode: String) -> void:
	_track_title.text = chart.title.to_upper() if chart != null else "FREE PLAY"
	_track_detail.text = (
		"%s BPM  /  %s MODE" % [str(snappedf(chart.bpm, 0.1)), mode]
		if chart != null else "PRACTICE TRACK  /  %s MODE" % mode
	)
	_refresh_layout()


func set_calibrating(calibrating: bool) -> void:
	if _calibrating == calibrating:
		return
	_calibrating = calibrating
	_feedback_left = 0.0
	_rest_feedback()
	queue_redraw()


## Reserve captions while enabled, not just while visible. Otherwise every
## fading caption would move the room and its firing positions.
func caption_clearance(enabled: bool) -> float:
	if not enabled:
		_caption_clearance = 0.0
		return 0.0
	var font := _caption_label.get_theme_font("font")
	var line_height := font.get_height(_caption_label.get_theme_font_size("font_size"))
	var padding := _audio_caption.get_theme_stylebox("panel").get_minimum_size().y
	var height := maxf(
		line_height * 2.0 + padding, _audio_caption.get_combined_minimum_size().y
	)
	_caption_clearance = maxf(
		_caption_clearance, height + float(_hud_layout.get_theme_constant("separation"))
	)
	return _caption_clearance


func set_input_level(rms: float) -> void:
	register_note(clampf(rms * 4.0, 0.0, 1.0))


func register_note(velocity: float, note := -1) -> void:
	_signal_level = maxf(_signal_level, clampf(velocity, 0.0, 1.0))
	_signal_meter.value = _signal_level
	if note >= 0:
		_signal_meter.fill_color = DmjPalette.note_color(note)


func set_called_note(note: int) -> void:
	_note_strip.value = posmod(note, 12) if note >= 0 else -1
	_target.add_theme_color_override("font_color", DmjPalette.note_color(note))


func show_feedback(title: String, detail: String, color: Color) -> void:
	_feedback.text = title
	_feedback_detail.text = detail
	_feedback.add_theme_color_override("font_color", color)
	_feedback_color = color
	_feedback_left = FEEDBACK_SECONDS
	queue_redraw()


func set_wave(index: int, total: int) -> void:
	_wave_meter.segments = maxi(total, 1)
	_wave_meter.max_value = float(maxi(total, 1))
	_wave_meter.value = float(index)
	_wave_meter.marker = index


func clear_wave(index: int) -> void:
	_wave_meter.value = float(index + 1)
	_wave_meter.marker = -1


func set_combo(streak: int) -> void:
	var multiplier := EncounterDirector.combo_multiplier(streak)
	var band := combo_band(streak)
	var at_max := band.x == band.y
	_combo_label.text = "COMBO x%d" % multiplier
	_combo_hint.text = (
		"MAX MULTIPLIER" if at_max
		else "%d NOTES TO x%d" % [
			band.y - streak, EncounterDirector.combo_multiplier(band.y),
		]
	)
	_combo_meter.min_value = 0.0
	_combo_meter.max_value = float(maxi(band.y - band.x, 1))
	_combo_meter.value = (
		_combo_meter.max_value if at_max else float(streak - band.x)
	)


static func combo_band(streak: int) -> Vector2i:
	var previous := 0
	for threshold: int in EncounterDirector.COMBO_STEPS:
		if streak < threshold:
			return Vector2i(previous, threshold)
		previous = threshold
	return Vector2i(previous, previous)


func _rest_feedback() -> void:
	_feedback.text = "KEEP IT QUIET" if _calibrating else ""
	_feedback_detail.text = (
		"MEASURING THE ROOM" if _calibrating else ""
	)
	_feedback.add_theme_color_override("font_color", DmjPalette.TEXT)


func _refresh_layout() -> void:
	var settings := get_node_or_null("/root/Settings")
	var preference := float(settings.call("get_value", "ui/scale", 1.0)) \
		if settings != null else 1.0
	var unit := get_viewport_rect().size.x / maxf(get_window().size.x, 1.0) * preference
	var expanded := controls_tray().visible
	var short := get_window().size.y < 480
	(%DmjLifeRack as DmjLifeRack).fit_units(unit)
	custom_minimum_size.y = 0
	(_row.get_parent() as BoxContainer).add_theme_constant_override(
		"separation", roundi((2 if short else 8) * unit))
	_row.add_theme_constant_override("separation", roundi(12 * unit))
	_readouts.add_theme_constant_override("separation", roundi(12 * unit))
	_target.add_theme_font_size_override("font_size", roundi((26 if short else 36) * unit))
	(%DmjPromptCaption as Control).visible = expanded
	var note_row := _target.get_parent() as BoxContainer
	note_row.vertical = expanded and not short
	note_row.add_theme_constant_override("separation", roundi(8 * unit))
	var target_group := note_row.get_parent() as BoxContainer
	target_group.custom_minimum_size.x = 180 * unit
	target_group.add_theme_constant_override("separation", roundi(4 * unit))
	controls_tray().custom_minimum_size.x = 140 * unit
	(controls_tray() as BoxContainer).add_theme_constant_override(
		"separation", roundi(4 * unit) if short else 10)
	(controls_tray().get_node("Caption") as Control).visible = not short
	_signal_meter.tooltip_text = "Input signal strength"
	_signal_meter.accessibility_name = _signal_meter.tooltip_text
	(_feedback.get_parent() as Control).custom_minimum_size.x = 120 * unit
	_note_strip.fit_units(unit)
	for label: Label in [%DmjPromptCaption, %DmjThreat, %DmjHeard, %DmjStatus,
		%DmjProgress, _combo_label, _combo_hint, _feedback_caption, _feedback_detail,
		controls_tray().get_node("Caption") as Label]:
		label.add_theme_font_size_override("font_size", roundi(12 * unit))
	_feedback.add_theme_font_size_override("font_size", roundi(22 * unit))
	(%DmjStatus as Control).custom_minimum_size.y = 18 * unit
	(%Callout as Control).custom_minimum_size.y = 30 * unit
	_track_card.visible = expanded and size.x >= 900 * unit
	_combo_hint.visible = expanded
	_feedback_caption.visible = expanded and not short
	var style := get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color.a = 0.18
	style.border_color.a = 0.25
	style.shadow_size = 0
	style.set_content_margin_all((4 if short else 8) * unit)
	add_theme_stylebox_override("panel", style)
	_feedback_caption.text = (
		"AMPLIFY YOUR ACCURACY" if _track_card.visible else _track_title.text
	)
	var margins := _hud_layout.get_parent() as MarginContainer
	var viewport_width := get_viewport_rect().size.x \
		- margins.get_theme_constant("margin_left") - margins.get_theme_constant("margin_right")
	var available := maxf(0, minf(size.x, viewport_width) - style.get_minimum_size().x)
	_readouts.vertical = expanded and _row_width(_readouts) > available
	_row.vertical = _row_width(_row) > available


func _row_width(box: BoxContainer) -> float:
	var width := 0.0
	var count := 0
	for child in box.get_children():
		if child is Control and child.visible:
			width += child.get_combined_minimum_size().x
			count += 1
	return width + maxi(0, count - 1) * box.get_theme_constant("separation")


## Input diagnostics are optional; the requested note and failures stay visible.
func controls_tray() -> Control:
	return _readouts.get_node("Input") as Control


## Help changes the view only, never the active note router or encounter clock.
func refresh_layout() -> void:
	_refresh_layout()
