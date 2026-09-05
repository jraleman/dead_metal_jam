extends Control

## Live tuner harness — the standalone soundcheck for Dead Metal Jam.
##
## [PitchDetector] was validated against synthesised tones, which is not the
## same as an instrument in a room: a real acoustic guitar brings body
## resonance, fret noise, room reflections and a decaying envelope. This scene
## puts the detector in front of that signal on its own, away from the game, so
## a bad reading can be blamed on the analyser rather than on the round.
##
## The audio plumbing lives in [MicCapture], which the game scene uses too.
##
## Run it with:
##   godot --path . res://games/dead_metal_jam/ui/tuner.tscn

## Open strings of a guitar in standard tuning, low to high.
const OPEN_STRINGS: Array[int] = [40, 45, 50, 55, 59, 64]

## Cents within which the note counts as in tune.
const IN_TUNE_CENTS := 5.0

## How long a reading stays on screen after the string stops sounding, so a
## decaying note does not flicker away mid-read.
const HOLD_SECONDS := 0.6

var _detector := PitchDetector.new()
var _mic: MicCapture

var _hold := 0.0
var _last_note := -1
var _last_cents := 0.0
var _onset_flash := 0.0
var _onset_count := 0

@onready var _note: Label = %Note
@onready var _octave: Label = %Octave
@onready var _cents: Label = %Cents
@onready var _needle: ColorRect = %Needle
@onready var _needle_track: Control = %NeedleTrack
@onready var _confidence: ProgressBar = %Confidence
@onready var _level: ProgressBar = %Level
@onready var _status: Label = %Status
@onready var _strings: Label = %Strings
@onready var _onset_lamp: ColorRect = %OnsetLamp


func _ready() -> void:
	_note.text = "—"
	_detector.configure(AudioServer.get_mix_rate())

	_mic = MicCapture.new()
	_mic.name = "MicCapture"
	_mic.calibrated.connect(_on_calibrated)
	_mic.capture_failed.connect(_on_capture_failed)
	add_child(_mic)

	_status.text = "Listening on \"%s\" at %d Hz. Measuring room noise, stay quiet…" % [
		_mic.input_device(), int(AudioServer.get_mix_rate())
	]

	# `-- --selftest` starts in tone mode, so the pipeline can be checked on a
	# machine that has no microphone attached.
	if OS.get_cmdline_user_args().has("--selftest"):
		_toggle_test_tone()


func _process(delta: float) -> void:
	for analysis: PitchAnalysis in _detector.push_frames(_mic.poll()):
		_consume(analysis)

	if _mic.is_calibrating():
		_level.value = _mic.calibration_progress() * 100.0

	_hold = maxf(_hold - delta, 0.0)
	if is_zero_approx(_hold) and _last_note >= 0:
		_clear_reading()

	_onset_flash = maxf(_onset_flash - delta * 4.0, 0.0)
	_onset_lamp.color = Color(1.0, 0.35, 0.3, _onset_flash)
	_place_needle()


func _consume(analysis: PitchAnalysis) -> void:
	_level.value = clampf(analysis.rms * 400.0, 0.0, 100.0)
	if not analysis.voiced:
		return

	_hold = HOLD_SECONDS
	_last_note = analysis.midi_note
	_last_cents = analysis.cents_off
	_note.text = PitchDetector.note_name(analysis.midi_note)
	_octave.text = PitchDetector.note_label(analysis.midi_note)
	_confidence.value = analysis.confidence * 100.0

	var direction := "in tune"
	if analysis.cents_off > IN_TUNE_CENTS:
		direction = "sharp"
	elif analysis.cents_off < -IN_TUNE_CENTS:
		direction = "flat"
	_cents.text = "%+.0f cents · %s · %.1f Hz" % [
		analysis.cents_off, direction, analysis.frequency
	]
	_note.add_theme_color_override(
		"font_color",
		StudioInfo.SKY if absf(analysis.cents_off) <= IN_TUNE_CENTS else StudioInfo.CREAM
	)
	_strings.text = _string_hint(analysis.midi_note)

	if analysis.is_onset:
		_onset_flash = 1.0
		_onset_count += 1
		_status.text = "%sOnsets detected: %d" % [
			"Self-test tone · " if _mic.test_tone_active() else "", _onset_count
		]


## Names the open string when one is being played, which is the quickest way to
## tell whether the detector agrees with the instrument in your hands.
func _string_hint(midi_note: int) -> String:
	var index := OPEN_STRINGS.find(midi_note)
	if index < 0:
		return ""
	return "open string %d — %s" % [
		OPEN_STRINGS.size() - index, PitchDetector.note_label(midi_note)
	]


func _clear_reading() -> void:
	_last_note = -1
	_last_cents = 0.0
	_note.text = "—"
	_octave.text = ""
	_cents.text = ""
	_strings.text = ""
	_confidence.value = 0.0


func _place_needle() -> void:
	var span := _needle_track.size.x
	if span <= 0.0:
		return
	var offset := clampf(_last_cents / 50.0, -1.0, 1.0) if _last_note >= 0 else 0.0
	_needle.position.x = (span - _needle.size.x) * 0.5 * (1.0 + offset)
	_needle.position.y = 0.0


func _toggle_test_tone() -> void:
	_onset_count = 0
	_clear_reading()
	if _mic.toggle_test_tone():
		_status.text = "Self-test: injecting %.0f Hz, which should read %s. Press T to stop." % [
			MicCapture.TEST_TONE_HZ, MicCapture.test_tone_label()
		]
	else:
		_status.text = "Back on the microphone. Measuring room noise, stay quiet…"


func _on_calibrated(noise_floor: float) -> void:
	_detector.set_noise_floor(noise_floor)
	_detector.reset()
	_level.value = 0.0
	if not _mic.test_tone_active():
		_status.text = "Noise floor %.4f — play a string. Esc quits." % noise_floor


func _on_capture_failed(reason: String) -> void:
	_status.text = "%s\nPress T to inject a test tone instead." % reason
	_clear_reading()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).keycode == KEY_T:
			_toggle_test_tone()
