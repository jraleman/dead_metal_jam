extends SceneTree

## Proves the onset rule survives the way people actually play, which is the
## half of pitch detection that a tuner never exercises.
##
## Split out of `pitch_detector_test.gd`, which covers the DSP underneath:
## whether a window of audio yields the right frequency. This covers what the
## game is really asking — *a note just started, now* — and those are different
## questions. Every scenario here is a full second-by-second performance pushed
## through the streaming path, and the assertion is always a count of onsets and
## the notes they named.
##
## Two rules earned this file its existence, both learned from a real acoustic
## guitar rather than from theory:
##
## 1. Notes are not separated by silence. Strings ring into each other, get
##    re-struck while still sounding, and are damped by the next note rather
##    than fading out. A rule tuned on isolated plucks missed four re-strikes
##    in six.
## 2. Rooms are not silent. Every scenario is therefore run again over room
##    tone, calibrated the way the shipping code calibrates. This is the half
##    that catches invented notes, and it is strictly harder than the first:
##    the attack tests are ratios, and a ratio cannot tell a quiet note from
##    quiet noise that happens to be moving.
##
## Needs no audio hardware or autoloads. Run it with:
##   godot --headless --path . --import
##   godot --headless --path .
##       --script res://games/dead_metal_jam/tests/playing_techniques_test.gd

const MAX_REPORTED_FAILURES := 20
## go through the streaming path rather than [method PitchDetector.analyse_window].
const TECHNIQUE_RATE := 48000.0

## Well below a plucked string and above the quiet passage's sustain, so the
## gate is doing the same job it does with a measured room.
const TECHNIQUE_NOISE_FLOOR := 0.005

## Room tone as a real microphone delivers it. The silent-background scenarios
## are the easy half of the problem: a purely proportional attack test has
## nothing to hold onto in noise, because a ratio is scale-free and noise
## wandering from 0.02 to 0.03 is the same 1.5x step as a note starting from
## nothing. Every technique is therefore run a second time over this.
##
## Deliberately louder than [constant CALIBRATION_ROOM_RMS]. Calibration happens
## once, in a quiet moment, before the player picks the instrument up; from then
## on the room contains everything holding and playing it produces — handling,
## pick scrape, body thump, reflections, the tails of notes already struck. A
## test that calibrates and plays at the same noise level is testing a room
## nobody plays in, and it is the gap between these two numbers that phantom
## notes live in.
const ROOM_TONE_RMS := 0.02

## What the calibrator gets to listen to: the room at its quietest.
const CALIBRATION_ROOM_RMS := 0.004

## Mirrors [code]mic_capture.gd[/code]: the calibrator takes the loudest sample
## in its listening window, pads it, and clamps. Reproducing the rule rather
## than picking a number keeps the tests honest about what the game will
## actually have in hand at runtime.
const CALIBRATION_SECONDS := 2.0
const CALIBRATION_PAD := 1.6
const MIN_NOISE_FLOOR := 0.004
const MAX_NOISE_FLOOR := 0.05

var _failures := PackedStringArray()
var _failure_count := 0
var _noise_state := 12345


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_playing_techniques()
	_finish()

func _test_playing_techniques() -> void:
	_expect_onsets(
		_notes_with_gaps(),
		6,
		[40, 45, 50, 55, 59, 64],
		"Six different notes with silence between them must be six onsets, "
		+ "each labelled with the note actually played."
	)
	_expect_onsets(
		_repluck(0.5),
		6,
		[45, 45, 45, 45, 45, 45],
		"A string re-struck every 0.5 s while still ringing must be six onsets."
	)
	_expect_onsets(
		_repluck(0.25),
		6,
		[45, 45, 45, 45, 45, 45],
		"A string re-struck every 0.25 s must be six onsets."
	)
	_expect_onsets(
		_repluck(0.18),
		6,
		[45, 45, 45, 45, 45, 45],
		"Tremolo picking at 0.18 s must be six onsets: the level barely moves "
		+ "between strikes, so this rests entirely on the trough test."
	)
	_expect_onsets(
		_damped_run(),
		6,
		[40, 47, 52, 40, 47, 52],
		"A fast melodic line, each note damped as the next starts, must be six "
		+ "onsets with the right notes."
	)
	_expect_onsets(
		_quiet_picking(),
		6,
		[40, 45, 50, 55, 59, 64],
		"Fingerpicking well below strumming level must still be six onsets: "
		+ "the noise floor is the gate, not the attack ratios."
	)
	_expect_onsets(
		_held_note(),
		1,
		[45],
		"One note struck once and left to ring for four seconds must be exactly "
		+ "one onset. A string's own beating must never read as a re-pluck."
	)
	_expect_onsets(
		_hammer_on(),
		2,
		[40, 45],
		"A hammer-on must still be two onsets. Legato is the real case the old "
		+ "pitch-change rule was protecting, and dropping that rule is only safe "
		+ "because a finger landing on a fret does put energy in: it is a quiet "
		+ "attack, not an absent one, and the trough test is what hears it."
	)
	_expect_onsets(
		_octave_drift(),
		1,
		[40],
		"A string whose fundamental dies before its second harmonic must be one "
		+ "onset. The estimate genuinely moves an octave partway through, while "
		+ "the note is still loud, so neither the noise gate nor the attack "
		+ "tests see anything wrong — only the level, which is falling, tells "
		+ "the truth. This is the shape of the phantom notes a real guitar "
		+ "produced: high, quiet, and long after the player stopped."
	)
	_test_playing_techniques_in_a_room()


## Everything above again, over room tone at a level a real microphone actually
## delivers. This is the half that matters: the silent-background runs prove the
## attack ratios can find a note, these prove they do not invent one.
func _test_playing_techniques_in_a_room() -> void:
	_expect_onsets(
		_room_tone_only(),
		0,
		[],
		"Room tone with nothing played must produce no onsets at all. A "
		+ "proportional attack test alone cannot do this: noise drifting inside "
		+ "its own band clears any ratio, so an onset has to also be audible "
		+ "against the measured floor.",
		_room_floor()
	)
	_expect_onsets(
		_in_a_room(_notes_with_gaps()),
		6,
		[40, 45, 50, 55, 59, 64],
		"Six notes over room tone must still be six onsets with the right "
		+ "labels: the noise gate must not cost real sensitivity.",
		_room_floor()
	)
	_expect_onsets(
		_in_a_room(_repluck(0.25)),
		6,
		[45, 45, 45, 45, 45, 45],
		"Re-strikes every 0.25 s must survive room tone.",
		_room_floor()
	)
	_expect_onsets(
		_in_a_room(_held_note()),
		1,
		[45],
		"A note decaying into room tone must be exactly one onset. As the "
		+ "fundamental dies the estimator starts naming upper partials, so the "
		+ "tail is where phantom high notes appear.",
		_room_floor()
	)
	_expect_onsets(
		_in_a_room(_quiet_picking()),
		6,
		[40, 45, 50, 55, 59, 64],
		"Fingerpicking over room tone is the tightest case in the suite: it "
		+ "sets how quiet a real note may be before the gate swallows it.",
		_room_floor()
	)


## Streams a signal through a detector and checks the onsets it produced.
func _expect_onsets(
	samples: PackedFloat32Array,
	count: int,
	notes: Array,
	message: String,
	noise_floor := TECHNIQUE_NOISE_FLOOR
) -> void:
	var detector := PitchDetector.new()
	detector.configure(TECHNIQUE_RATE)
	detector.set_noise_floor(noise_floor)

	var heard: Array[int] = []
	for analysis: PitchAnalysis in detector.push_samples(samples):
		if analysis.is_onset:
			heard.append(analysis.midi_note)

	if heard.size() != count:
		_expect(false, "%s Got %d onsets: %s" % [message, heard.size(), str(heard)])
		return
	for i in notes.size():
		if heard[i] != int(notes[i]):
			_expect(
				false,
				"%s Onset %d was %s, expected %s." % [
					message,
					i + 1,
					PitchDetector.note_label(heard[i]),
					PitchDetector.note_label(int(notes[i])),
				]
			)
			return


## One plucked string: a harmonic stack under a fast attack and an exponential
## decay. Added to whatever is already in the buffer, so notes ring together.
func _add_pluck(
	buffer: PackedFloat32Array, start: int, midi: int, gain: float, decay: float
) -> void:
	var frequency := PitchDetector.midi_to_frequency(float(midi))
	var attack := TECHNIQUE_RATE * 0.004
	for i in range(start, buffer.size()):
		var seconds := float(i - start) / TECHNIQUE_RATE
		var envelope: float = exp(-seconds * decay)
		if envelope < 0.001:
			break
		if float(i - start) < attack:
			envelope *= float(i - start) / attack
		var value := 0.0
		for harmonic in range(1, 6):
			value += sin(TAU * frequency * float(harmonic) * seconds) / float(harmonic)
		buffer[i] += value * envelope * gain


## Damps whatever is ringing, then plucks — what a pick does to the string it is
## about to re-excite. Modelling a re-pluck as a sum instead is not merely less
## realistic, it is misleading: two plucks of one note a whole number of
## half-cycles apart superpose out of phase and partly cancel, which reads as a
## strike that produced no attack at all.
func _add_pluck_replacing(
	buffer: PackedFloat32Array, start: int, midi: int, gain: float, decay: float
) -> void:
	var damp := int(TECHNIQUE_RATE * 0.002)
	for i in range(start, buffer.size()):
		var offset := i - start
		if offset >= damp:
			buffer[i] = 0.0
		else:
			buffer[i] *= 1.0 - float(offset) / float(damp)
	_add_pluck(buffer, start, midi, gain, decay)


func _silent_buffer(seconds: float) -> PackedFloat32Array:
	var buffer := PackedFloat32Array()
	buffer.resize(int(TECHNIQUE_RATE * seconds))
	buffer.fill(0.0)
	return buffer


## Mixes room tone in at [param rms]. The generator is uniform, so its peak is a
## fixed multiple of its RMS and the floor the calibrator derives below is
## predictable rather than a lucky draw.
func _add_room_tone(buffer: PackedFloat32Array, rms := ROOM_TONE_RMS) -> void:
	var amplitude: float = rms * sqrt(3.0)
	for i in buffer.size():
		buffer[i] += _next_noise() * amplitude


## Puts an existing technique signal in a real room.
func _in_a_room(buffer: PackedFloat32Array) -> PackedFloat32Array:
	_add_room_tone(buffer)
	return buffer


func _room_tone_only() -> PackedFloat32Array:
	return _in_a_room(_silent_buffer(4.0))


## The floor the game will actually be holding: what [code]mic_capture.gd[/code]
## hands the detector after listening to this room, with nothing played, for
## [constant CALIBRATION_SECONDS]. Derived by replaying that rule rather than
## chosen, so the tests cannot quietly assume a better floor than shipping code
## can measure.
func _room_floor() -> float:
	var quiet := _silent_buffer(CALIBRATION_SECONDS)
	_add_room_tone(quiet, CALIBRATION_ROOM_RMS)
	var peak := 0.0
	for value in quiet:
		peak = maxf(peak, absf(value))
	return clampf(peak * CALIBRATION_PAD, MIN_NOISE_FLOOR, MAX_NOISE_FLOOR)


func _notes_with_gaps() -> PackedFloat32Array:
	var buffer := _silent_buffer(6.0)
	var notes := [40, 45, 50, 55, 59, 64]
	for i in notes.size():
		_add_pluck(buffer, int(TECHNIQUE_RATE * (0.4 + float(i) * 0.9)), notes[i], 0.35, 3.0)
	return buffer


func _repluck(gap: float) -> PackedFloat32Array:
	var buffer := _silent_buffer(0.4 + gap * 7.0)
	for i in 6:
		_add_pluck_replacing(
			buffer, int(TECHNIQUE_RATE * (0.4 + float(i) * gap)), 45, 0.35, 1.2
		)
	return buffer


## A fast line on one string: each note stops as the next begins.
func _damped_run() -> PackedFloat32Array:
	var buffer := _silent_buffer(2.0)
	var notes := [40, 47, 52, 40, 47, 52]
	var gap := 0.15
	for i in notes.size():
		_add_pluck_replacing(
			buffer, int(TECHNIQUE_RATE * (0.3 + float(i) * gap)), notes[i], 0.35, 3.5
		)
	return buffer


func _quiet_picking() -> PackedFloat32Array:
	var buffer := _silent_buffer(3.0)
	var notes := [40, 45, 50, 55, 59, 64]
	for i in notes.size():
		_add_pluck_replacing(
			buffer, int(TECHNIQUE_RATE * (0.3 + float(i) * 0.4)), notes[i], 0.04, 2.5
		)
	return buffer


## A note picked normally, then a second sounded by slamming a finger onto a
## higher fret while the string is still ringing. Legato is the one real
## technique that starts a note without a fresh strike, so it is the case that
## decides whether "an onset needs an attack" is too strict a rule.
##
## It is not, but the margin is real and worth stating. The string is down to
## about 0.105 when the finger lands; measured against this corpus the hammer-on
## is heard from roughly 0.15 and missed at 0.12, so the limit is a fretting
## hand that arrives at about 1.4x what is already ringing. A firm hammer-on
## clears that comfortably and a limp one does not register — which is also true
## of a real guitar, and is the right way round for a game that has to tell a
## played note from a decaying one.
func _hammer_on() -> PackedFloat32Array:
	var buffer := _silent_buffer(2.5)
	_add_pluck(buffer, int(TECHNIQUE_RATE * 0.3), 40, 0.35, 2.0)
	_add_pluck_replacing(buffer, int(TECHNIQUE_RATE * 0.9), 45, 0.18, 2.0)
	return buffer


## A plucked string whose partials decay at different rates, which is what real
## strings do: energy leaves the fundamental fastest, so partway through a long
## note the second harmonic is the loudest thing present and a monophonic
## estimator starts naming it instead. The note is still perfectly audible while
## this happens, so no amount of noise gating catches it — the only evidence
## that nothing was played is that the level is on its way down.
func _octave_drift() -> PackedFloat32Array:
	var buffer := _silent_buffer(3.0)
	var start := int(TECHNIQUE_RATE * 0.3)
	var frequency := PitchDetector.midi_to_frequency(40.0)
	var attack := TECHNIQUE_RATE * 0.004
	for i in range(start, buffer.size()):
		var offset := float(i - start)
		var seconds := offset / TECHNIQUE_RATE
		var ramp: float = minf(offset / attack, 1.0)
		var fundamental: float = 0.42 * exp(-seconds * 7.0)
		var second: float = 0.30 * exp(-seconds * 0.7)
		buffer[i] += ramp * (
			sin(TAU * frequency * seconds) * fundamental
			+ sin(TAU * frequency * 2.0 * seconds) * second
		)
	return buffer


func _held_note() -> PackedFloat32Array:
	var buffer := _silent_buffer(4.0)
	_add_pluck(buffer, int(TECHNIQUE_RATE * 0.3), 45, 0.35, 0.7)
	return buffer


# --------------------------------------------------------------------------
# Robustness
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# Plumbing
# --------------------------------------------------------------------------


## A fixed linear congruential generator, so "room noise" is the same noise on
## every machine and a failure here is always reproducible.
func _next_noise() -> float:
	_noise_state = (1103515245 * _noise_state + 12345) % 2147483648
	return (float(_noise_state) / 2147483648.0) * 2.0 - 1.0


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _finish() -> void:
	if _failure_count == 0:
		print("Playing technique tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	if _failure_count > _failures.size():
		push_error(
			"...and %d further failures." % (_failure_count - _failures.size())
		)
	quit(1)
