class_name MicNoteSource
extends NoteSource

## The microphone path: any acoustic instrument, no gear beyond a mic.
##
## Wraps the two halves that already existed — [MicCapture] for the audio
## plumbing and [PitchDetector] for the analysis — and presents them as an
## ordinary [NoteSource], so gameplay stops knowing that pitch detection is
## involved at all.
##
## This is the only source that can be *wrong* about a note, and the only one
## with meaningful latency, so it is the one [member NoteEvent.confidence],
## [member NoteEvent.cents_off] and [method latency_ms] exist for.

signal calibrated(noise_floor: float)
signal capture_failed(reason: String)

## Every analysed hop, not just the ones that became notes. The tuner and the
## note readout use it to show a live pitch; gameplay does not, because a
## decaying string is not a new note.
signal pitch_observed(analysis: PitchAnalysis)

## Turns loudness into a rough 0-1 velocity. A hard pluck measures around 0.35
## RMS, so this puts a strong note near the top of the range without clipping
## every ordinary one there. Deliberately approximate: velocity colours the hit
## reaction and never gates scoring, so being a little off costs nothing.
const VELOCITY_SCALE := 2.5

var _detector := PitchDetector.new()
var _mic: MicCapture
var _latency_ms := 0.0
var _failure := ""

## The note currently ringing, so a note-off can be emitted when it stops.
var _sounding := -1


func _ready() -> void:
	_detector.configure(AudioServer.get_mix_rate())
	_latency_ms = DmjProfile.input_latency_ms()

	_mic = MicCapture.new()
	_mic.name = "MicCapture"
	_mic.calibrated.connect(_on_calibrated)
	_mic.capture_failed.connect(_on_capture_failed)
	add_child(_mic)


func _process(_delta: float) -> void:
	if _mic == null:
		return
	for analysis: PitchAnalysis in _detector.push_frames(_mic.poll()):
		_consume(analysis)


func source_kind() -> NoteEvent.Source:
	return NoteEvent.Source.MIC


func display_name() -> String:
	if _mic == null:
		return "Microphone"
	return "Microphone: %s" % _mic.input_device()


func is_available() -> bool:
	return _failure.is_empty()


func unavailable_reason() -> String:
	return _failure


## The measured round trip from [DmjProfile], written by the calibration screen
## (`DESIGN.md` §4.6). Zero until the player has calibrated, which is honest:
## an uncalibrated guess would be worse than no correction at all.
func latency_ms() -> float:
	return _latency_ms


## Re-reads the stored latency. Called after calibration so a fresh measurement
## takes effect without rebuilding the source.
func reload_latency() -> void:
	_latency_ms = DmjProfile.input_latency_ms()


func is_calibrating() -> bool:
	return _mic != null and _mic.is_calibrating()


func calibration_progress() -> float:
	return 0.0 if _mic == null else _mic.calibration_progress()


func toggle_test_tone() -> bool:
	return _mic != null and _mic.toggle_test_tone()


func test_tone_active() -> bool:
	return _mic != null and _mic.test_tone_active()


## Exposed so a diagnostic screen can log the hops this source is judging
## (see [OnsetLog]).
func detector() -> PitchDetector:
	return _detector


func _consume(analysis: PitchAnalysis) -> void:
	input_level_changed.emit(analysis.rms)
	pitch_observed.emit(analysis)

	if not analysis.voiced:
		# Silence ends whatever was ringing. Without this a note started on the
		# microphone would never end, and anything watching for sustain would
		# believe the string was still going.
		if _sounding >= 0:
			note_ended.emit(_sounding)
			_sounding = -1
		return

	if not analysis.is_onset:
		return

	# A new attack while something is ringing ends the old note first, so the
	# started/ended pairs stay balanced.
	if _sounding >= 0 and _sounding != analysis.midi_note:
		note_ended.emit(_sounding)

	_sounding = analysis.midi_note
	emit_note(
		analysis.midi_note,
		clampf(analysis.rms * VELOCITY_SCALE, 0.0, 1.0),
		analysis.cents_off,
		analysis.confidence
	)


func _on_calibrated(noise_floor: float) -> void:
	_failure = ""
	_detector.set_noise_floor(noise_floor)
	_detector.reset()
	calibrated.emit(noise_floor)


func _on_capture_failed(reason: String) -> void:
	_failure = reason
	capture_failed.emit(reason)
