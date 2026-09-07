class_name DmjPerformanceHud
extends PanelContainer

## Presentation only. The round supplies notes, judgements and wave events.
const SIGNAL_DECAY := 2.5
const FEEDBACK_SECONDS := 1.1
const COMPACT_WIDTH := 900.0

@onready var _row: BoxContainer = %DmjConsoleRow
@onready var _readouts: BoxContainer = %DmjReadouts
@onready var _target: Label = %DmjTarget
@onready var _note_strip: Range = %DmjNoteStrip
@onready var _wide_note_size := _target.get_theme_font_size("font_size")
@onready var _wide_row_spacing := _row.get_theme_constant("separation")
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
@onready var _score_card: Control = %PlayerOneCard
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
	_feedback.text = "KEEP IT QUIET" if _calibrating else "MAKE SOME NOISE"
	_feedback_detail.text = (
		"MEASURING THE ROOM" if _calibrating else "YOUR INSTRUMENT IS THE WEAPON"
	)
	_feedback.add_theme_color_override("font_color", DmjPalette.TEXT)


func _refresh_layout() -> void:
	_row.vertical = size.x < COMPACT_WIDTH
	_readouts.vertical = size.x < 620.0
	# Keep the stacked target readout from crowding the battlefield.
	_row.add_theme_constant_override("separation", 12 if _row.vertical else _wide_row_spacing)
	_target.add_theme_font_size_override(
		"font_size", roundi(_wide_note_size * 0.68) if _row.vertical else _wide_note_size
	)
	_track_card.visible = size.x >= 1100.0
	_score_card.custom_minimum_size.x = 220.0 if _row.vertical else 300.0
	_feedback_caption.text = (
		"AMPLIFY YOUR ACCURACY" if _track_card.visible else _track_title.text
	)
