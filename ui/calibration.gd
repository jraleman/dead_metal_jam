extends Control

## Latency calibration — milestone 3 of `DESIGN.md` §4.6.
##
## Measures the one number the game cannot derive: how long it takes between a
## string being plucked and this code knowing about it. That covers the room,
## the microphone, the driver, the OS buffer and [PitchDetector]'s own window,
## and it is measured as a single round trip because that is what the player
## experiences — they play when they *hear* the beat, so the outbound half of
## the loop is as real to them as the inbound half.
##
## The arithmetic lives in [LatencyCalibration] and the audio in [MicCapture],
## both tested without hardware. This scene is the part that cannot be: a
## metronome, a clock, and somebody with an instrument.
##
## Run it with:
##   godot --path . res://games/dead_metal_jam/ui/calibration.tscn
##   godot --path . res://games/dead_metal_jam/ui/calibration.tscn -- --selftest

enum Phase { SOUNDCHECK, READY, RUNNING, DONE }

## 100 BPM. Slow enough to play accurately on any instrument, which matters
## more than covering ground: a player rushing to keep up produces spread, and
## spread is the thing that makes a measurement unusable.
const BEAT_SECONDS := 0.6

## Two are eaten by [constant LatencyCalibration.COUNT_IN_BEATS], leaving ten
## measured notes — enough for the median to be stable without asking anyone to
## play a metronome for half a minute.
const TOTAL_BEATS := 12

## Grace after the final click before reading the result, so the last note's
## detection delay does not cost it its place.
const TAIL_SECONDS := 0.5

## Note the player is asked for. The open A string is reachable on guitar,
## bass and piano, and it sits comfortably inside the detector's range.
const TARGET_MIDI := 45

## Simulated hardware latency for `--selftest`, in milliseconds, on top of what
## the synthetic path really costs. Lets a rehearsal prove the screen measures
## an *offset* rather than always reporting the same number.
@export var simulated_latency_ms := 0.0

var _detector := PitchDetector.new()
var _calibration := LatencyCalibration.new(BEAT_SECONDS)
var _mic: MicCapture
var _metronome: AudioStreamPlayer

var _phase := Phase.SOUNDCHECK
var _self_test := false
var _rate := 48000.0
var _samples_pushed := 0
var _started_at := 0.0
var _next_pluck := 0
var _heard := 0

@onready var _status: Label = %Status
@onready var _reading: Label = %Reading
@onready var _units: Label = %Units
@onready var _detail: Label = %Detail
@onready var _progress: ProgressBar = %Progress
@onready var _hint: Label = %Hint


func _ready() -> void:
	_rate = AudioServer.get_mix_rate()
	_detector.configure(_rate)
	_progress.max_value = TOTAL_BEATS

	_metronome = AudioStreamPlayer.new()
	_metronome.name = "Metronome"
	add_child(_metronome)

	_mic = MicCapture.new()
	_mic.name = "MicCapture"
	_mic.calibrated.connect(_on_calibrated)
	_mic.capture_failed.connect(_on_capture_failed)
	add_child(_mic)

	_self_test = OS.get_cmdline_user_args().has("--selftest")
	if _self_test:
		_mic.start_test_plucks()

	_reading.text = "—"
	_units.text = ""
	_status.text = "Measuring the room on \"%s\". Stay quiet…" % _mic.input_device()
	_detail.text = _previous_measurement()
	_hint.text = "Esc quits"


func _process(_delta: float) -> void:
	_drain_audio()
	if _phase == Phase.RUNNING:
		_update_run()


## Onsets are placed on the audio's own clock, not the frame's.
##
## The newest sample in a drained block was captured essentially now, so
## everything earlier in it can be dated exactly by counting backwards at the
## sample rate. Timestamping a note with the frame it happened to be drained on
## would smear it across the whole frame — tens of milliseconds against a
## judgement window of sixty.
func _drain_audio() -> void:
	var frames := _mic.poll()
	if frames.is_empty():
		return

	var now := _now()
	_samples_pushed += frames.size()
	for analysis: PitchAnalysis in _detector.push_frames(frames):
		if not analysis.is_onset:
			continue
		var age := float(_samples_pushed - analysis.sample_index) / _rate
		_on_onset(now - age)


func _on_onset(at: float) -> void:
	if _phase != Phase.RUNNING:
		return
	_calibration.add_onset(at)
	_heard += 1
	_status.text = "Heard %d note%s" % [_heard, "" if _heard == 1 else "s"]


func _update_run() -> void:
	var elapsed := _now() - _started_at
	_progress.value = clampf(elapsed / BEAT_SECONDS, 0.0, TOTAL_BEATS)

	if _self_test:
		_feed_self_test(elapsed)

	var beat := int(floor(elapsed / BEAT_SECONDS))
	if beat < LatencyCalibration.COUNT_IN_BEATS:
		_reading.text = str(LatencyCalibration.COUNT_IN_BEATS - beat)
		_units.text = "count in"
	elif beat < TOTAL_BEATS:
		_reading.text = str(beat - LatencyCalibration.COUNT_IN_BEATS + 1)
		_units.text = "of %d" % (TOTAL_BEATS - LatencyCalibration.COUNT_IN_BEATS)

	if elapsed >= float(TOTAL_BEATS) * BEAT_SECONDS + TAIL_SECONDS:
		_finish_run()


## Plays the part of the guitarist, exactly on the beat plus whatever latency
## the rehearsal is pretending to have.
func _feed_self_test(elapsed: float) -> void:
	if _next_pluck >= TOTAL_BEATS:
		return
	var due := float(_next_pluck) * BEAT_SECONDS + simulated_latency_ms / 1000.0
	if elapsed < due:
		return
	_mic.pluck_now(TARGET_MIDI)
	_next_pluck += 1


func _start_run() -> void:
	_detector.reset()
	_samples_pushed = 0
	_heard = 0
	_next_pluck = 0
	_calibration.configure(BEAT_SECONDS)

	_metronome.stream = MetronomeClick.render(_rate, TOTAL_BEATS, BEAT_SECONDS)
	_metronome.play()

	# The click is not audible when `play()` returns — it is audible one output
	# buffer later, and that delay is part of the round trip the player is
	# reacting to, so it belongs in the click times rather than in the result.
	_started_at = _now() + AudioServer.get_output_latency()
	for beat in TOTAL_BEATS:
		_calibration.add_click(_started_at + float(beat) * BEAT_SECONDS)

	_phase = Phase.RUNNING
	_status.text = "Play %s on every click." % PitchDetector.note_name(TARGET_MIDI)
	_hint.text = "Esc quits"


func _finish_run() -> void:
	_phase = Phase.DONE
	_metronome.stop()
	_progress.value = TOTAL_BEATS

	var result := _calibration.measure()
	var latency := float(result["latency_ms"])
	_detail.text = str(result["message"])

	if result["verdict"] == LatencyCalibration.Verdict.GOOD:
		DmjProfile.set_input_latency_ms(latency)
		_reading.text = "%.0f" % latency
		_units.text = "ms round trip"
		_status.text = "Saved. %s" % _detector_share(latency)
	else:
		_reading.text = "—"
		_units.text = ""
		_status.text = "Not saved — the last measurement stands."

	_hint.text = "Space to measure again · Esc quits"


## Splits the result into the part the player could change and the part they
## could not, so a slow number does not read as an accusation.
func _detector_share(latency_ms: float) -> String:
	var detector_ms := PitchDetector.TYPICAL_ONSET_DELAY_SECONDS * 1000.0
	if latency_ms <= detector_ms:
		return "That is as fast as this analyser can report."
	return "About %.0f ms of that is the analyser; the rest is your audio path." % detector_ms


func _previous_measurement() -> String:
	if not DmjProfile.has_latency():
		return "Not calibrated yet."
	return "Last measured: %.0f ms." % DmjProfile.input_latency_ms()


func _now() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


func _ready_to_start(message: String) -> void:
	_phase = Phase.READY
	_status.text = message
	_hint.text = "Space to start · Esc quits"


func _on_calibrated(noise_floor: float) -> void:
	_detector.set_noise_floor(noise_floor)
	_detector.reset()
	if _phase != Phase.SOUNDCHECK:
		return
	_ready_to_start(
		"Ready. Headphones help — %s"
		% "if the microphone can hear the clicks it is measuring itself."
	)


## A dead microphone still leaves the screen usable: the self-test can be
## rehearsed, and the player can read why nothing is being heard.
func _on_capture_failed(reason: String) -> void:
	if _phase == Phase.RUNNING:
		_finish_run()
	_phase = Phase.READY
	_status.text = reason
	_hint.text = "Esc quits"


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode == KEY_SPACE and _phase in [Phase.READY, Phase.DONE]:
		_start_run()
