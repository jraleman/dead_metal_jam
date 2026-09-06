class_name MicCapture
extends Node

## Owns everything between the microphone and [PitchDetector]: the capture bus,
## the mic stream, the room-noise measurement and the self-test tone.
##
## The bus is built in code rather than added to the project's shared
## `default_bus_layout.tres`, so a game never has to edit the framework to
## listen to an instrument. It is silenced rather than muted: bus volume is
## applied after the effect chain, so the analyser still receives full-scale
## audio while nothing reaches the speakers, which is what stops the microphone
## from hearing the game and firing phantom notes (DESIGN.md §4.3).
##
## Add it as a child, connect the signals, then feed [method poll] straight
## into [method PitchDetector.push_frames].

## Emitted once the room has been measured and analysis can begin.
signal calibrated(noise_floor: float)

## Emitted when no usable audio is arriving. Carries a player-facing reason.
signal capture_failed(reason: String)

enum ToneMode {
	OFF,
	## A held note, for checking the readout and the analyser.
	CONTINUOUS,
	## Silence until [method pluck_now], for rehearsing anything that has to
	## time a note — calibration especially.
	PLUCKS,
}

const BUS_NAME := "DMJCapture"
const SILENT_DB := -80.0

## Seconds of room tone used to set the gate before listening for notes.
const CALIBRATION_SECONDS := 2.0

## Frequency injected by the self-test. A3 sits inside a guitar's range and is
## the fifth-fret harmonic of the low A string, so it is easy to check against
## a real instrument.
const TEST_TONE_HZ := 220.0

## Gate used during the self-test, where there is no room tone to measure.
const TEST_TONE_FLOOR := 0.005

## Queue the held tone runs on. Generous, because nothing about it is timed.
const TEST_TONE_BUFFER := 0.25

## Queue the pluck self-test runs on. Deliberately short: whatever is sitting in
## it is added to every simulated note's latency, so a large buffer would make
## a rehearsal of the calibration screen measure the buffer instead.
const PLUCK_BUFFER := 0.05

## Long enough for the detector to settle on the note and fire its onset, short
## enough to be gone before the next beat of a calibration metronome.
const PLUCK_SECONDS := 0.28

## Bounds for the measured gate: high enough to ignore hum, low enough to still
## hear a softly fingerpicked string.
const MIN_NOISE_FLOOR := 0.004
const MAX_NOISE_FLOOR := 0.05

var _capture: AudioEffectCapture
var _mic_player: AudioStreamPlayer
var _bus_index := -1
var _failed := false
var _calibrating := true
var _calibration_frames := 0
var _calibration_peak := 0.0
var _tone_player: AudioStreamPlayer
var _tone_playback: AudioStreamGeneratorPlayback
var _tone_phase := 0.0
var _tone_mode := ToneMode.OFF
var _pending_pluck := PackedFloat32Array()


func _ready() -> void:
	_open_bus()
	_open_microphone()


## Calibration is driven here rather than from [method poll] so it completes
## whether or not anyone is reading frames yet. The game holds its first round
## back until the room has been measured, so if measuring depended on the round
## already running, neither would ever start.
func _process(_delta: float) -> void:
	_feed_test_tone()
	if _calibrating and not _failed:
		_drain_calibration()


func _drain_calibration() -> void:
	if _capture == null:
		return
	var available := _capture.get_frames_available()
	if available > 0:
		_measure_noise_floor(_capture.get_buffer(available))


## Frames ready for analysis. Returns nothing while the room is still being
## measured or while capture is broken, so callers can pump it unconditionally.
func poll() -> PackedVector2Array:
	if _capture == null or _failed or _calibrating:
		return PackedVector2Array()

	var available := _capture.get_frames_available()
	if available <= 0:
		return PackedVector2Array()
	return _capture.get_buffer(available)


## 0.0 to 1.0 while the room is being measured, 1.0 once listening has started.
func calibration_progress() -> float:
	if not _calibrating:
		return 1.0
	var seconds := float(_calibration_frames) / AudioServer.get_mix_rate()
	return clampf(seconds / CALIBRATION_SECONDS, 0.0, 1.0)


func is_calibrating() -> bool:
	return _calibrating


func has_failed() -> bool:
	return _failed


func input_device() -> String:
	return AudioServer.input_device


## Swaps the microphone for a synthesised A3 on the same bus, which separates
## "the analyser is broken" from "the microphone is broken". Everything
## downstream is exercised exactly as it is for a real instrument. Returns the
## new state.
func toggle_test_tone() -> bool:
	if _tone_player:
		_stop_test_tone()
		_restart_calibration()
		return false

	_open_tone_generator(TEST_TONE_BUFFER)
	_tone_mode = ToneMode.CONTINUOUS
	return true


## Opens the same synthetic path as [method toggle_test_tone] but silent, so
## the caller decides when notes happen.
##
## This is what lets latency calibration be rehearsed with no microphone and no
## instrument: the plucks arrive at times the caller chose, so the number the
## screen produces can be checked against the number it should produce.
func start_test_plucks() -> void:
	if _tone_player:
		_stop_test_tone()
	_open_tone_generator(PLUCK_BUFFER)
	_tone_mode = ToneMode.PLUCKS


## Queues one plucked note, starting with the next samples pushed. Replaces any
## pluck still sounding, so a fast passage cannot pile up.
func pluck_now(midi := 55) -> void:
	if _tone_mode != ToneMode.PLUCKS:
		return
	_pending_pluck = _render_pluck(PitchDetector.midi_to_frequency(float(midi)))


func test_tone_active() -> bool:
	return _tone_player != null


func test_tone_mode() -> int:
	return _tone_mode


## Note the self-test tone should be reported as, for checking the readout.
static func test_tone_label() -> String:
	return PitchDetector.note_label(
		int(round(PitchDetector.frequency_to_midi(TEST_TONE_HZ)))
	)


func _open_bus() -> void:
	_bus_index = AudioServer.bus_count
	AudioServer.add_bus(_bus_index)
	AudioServer.set_bus_name(_bus_index, BUS_NAME)
	AudioServer.set_bus_volume_db(_bus_index, SILENT_DB)
	AudioServer.set_bus_send(_bus_index, "Master")

	_capture = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus_index, _capture)


## The bus is opened even when the microphone cannot be, so the self-test stays
## available as a way to prove the rest of the chain works.
func _open_microphone() -> void:
	if not bool(ProjectSettings.get_setting("audio/driver/enable_input", false)):
		_fail("audio/driver/enable_input is off, so the microphone can only return silence.")
		return

	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = BUS_NAME
	add_child(_mic_player)
	_mic_player.play()


func _measure_noise_floor(frames: PackedVector2Array) -> void:
	for frame in frames:
		_calibration_peak = maxf(_calibration_peak, absf(frame.x + frame.y) * 0.5)
	_calibration_frames += frames.size()

	if float(_calibration_frames) / AudioServer.get_mix_rate() < CALIBRATION_SECONDS:
		return

	# A working microphone always delivers some self-noise, so perfect digital
	# silence means the input device never opened. The capture effect taps the
	# bus rather than the device, so frames keep arriving either way and this is
	# the only tell a dead microphone leaves.
	if _calibration_peak <= 0.0:
		_fail(
			"\"%s\" is delivering pure silence, so no microphone is open. " % input_device()
			+ "Connect one, select it in the system sound settings, and allow "
			+ "desktop apps to use it."
		)
		return

	_calibrating = false
	calibrated.emit(
		clampf(_calibration_peak * 1.6, MIN_NOISE_FLOOR, MAX_NOISE_FLOOR)
	)


## Feeds the synthetic path. Both modes push every frame the generator will
## take, so the queue length — and therefore the delay before an injected note
## is heard — stays predictable.
func _feed_test_tone() -> void:
	if _tone_playback == null:
		return

	if _tone_mode == ToneMode.CONTINUOUS:
		var increment := TEST_TONE_HZ / AudioServer.get_mix_rate()
		for _i in _tone_playback.get_frames_available():
			var sample := sin(_tone_phase * TAU) * 0.5
			_tone_playback.push_frame(Vector2(sample, sample))
			_tone_phase = fmod(_tone_phase + increment, 1.0)
		return

	var taken := 0
	for _i in _tone_playback.get_frames_available():
		var value := 0.0
		if taken < _pending_pluck.size():
			value = _pending_pluck[taken]
			taken += 1
		_tone_playback.push_frame(Vector2(value, value))
	if taken > 0:
		_pending_pluck = _pending_pluck.slice(taken)


## A plucked string: harmonics under a fast attack and an exponential decay.
## The envelope is what makes it usable for timing — a note that simply
## switches on has no moment that can be called its start.
func _render_pluck(frequency: float) -> PackedFloat32Array:
	var rate := AudioServer.get_mix_rate()
	var count := int(rate * PLUCK_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var attack := rate * 0.004
	for i in count:
		var seconds := float(i) / rate
		var envelope := exp(-seconds * 4.0)
		if float(i) < attack:
			envelope *= float(i) / attack
		var value := 0.0
		for harmonic in range(1, 6):
			value += (
				sin(TAU * frequency * float(harmonic) * seconds)
				/ float(harmonic)
			)
		samples[i] = value * envelope * 0.35

	return samples


func _open_tone_generator(buffer_length: float) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = AudioServer.get_mix_rate()
	generator.buffer_length = buffer_length

	_tone_player = AudioStreamPlayer.new()
	_tone_player.stream = generator
	_tone_player.bus = BUS_NAME
	add_child(_tone_player)
	_tone_player.play()
	_tone_playback = _tone_player.get_stream_playback()

	# The synthetic path has a known floor, so there is no room to measure and
	# nothing downstream should wait for one.
	_failed = false
	_calibrating = false
	_pending_pluck = PackedFloat32Array()
	if _capture:
		_capture.clear_buffer()
	calibrated.emit(TEST_TONE_FLOOR)


func _restart_calibration() -> void:
	_failed = false
	_calibrating = true
	_calibration_frames = 0
	_calibration_peak = 0.0
	if _capture:
		_capture.clear_buffer()


func _stop_test_tone() -> void:
	if _tone_player == null:
		return
	_tone_player.stop()
	_tone_player.stream = null
	_tone_player.queue_free()
	_tone_player = null
	_tone_playback = null
	_tone_mode = ToneMode.OFF
	_pending_pluck = PackedFloat32Array()


## Measurement is over, just not successfully, so anything waiting on the
## soundcheck stops waiting.
func _fail(reason: String) -> void:
	_failed = true
	_calibrating = false
	push_warning("MicCapture: %s" % reason)
	capture_failed.emit(reason)


## The mic stream, its playback and the capture effect are held by the
## AudioServer rather than by the tree, so dropping the node is not enough to
## release them.
func _exit_tree() -> void:
	_stop_test_tone()
	if is_instance_valid(_mic_player):
		_mic_player.stop()
		_mic_player.stream = null
	_capture = null
	if _bus_index >= 0 and _bus_index < AudioServer.bus_count:
		AudioServer.remove_bus(_bus_index)
		_bus_index = -1
