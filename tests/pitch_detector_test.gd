extends SceneTree

## Milestone 1 gate for Dead Metal Jam: proves the pitch detector can tell one
## note from another before any of the game is built on top of it.
##
## [PitchDetector] is pure DSP, so this test needs no audio hardware, no
## microphone permission and no autoloads — it synthesises band-limited tones at
## known frequencies and checks what comes back. That makes it fully
## deterministic and safe to run headless in CI.
##
## The corpus is deliberately wider than "does it find A440": it sweeps every
## semitone of the playable range with three timbres and two phases, checks
## intonation on deliberately detuned inputs, and — most importantly — checks
## the ways the detector is allowed to fail. Silence, room noise and a DC
## offset must report *nothing*, because a confident wrong answer is worse for
## the player than an honest blank (§5.1).
##
## Run it with:
##   godot --headless --path . --import
##   godot --headless --path .
##       --script res://games/dead_metal_jam/tests/pitch_detector_test.gd

## Tones for [method PitchDetector.analyse_window] are synthesised at the rate
## the detector works at internally, since that entry point takes decimated
## samples. The streaming tests use 44100 and 48000 instead.
const WORK_RATE := 11025.0

const LOWEST_NOTE := 40
const HIGHEST_NOTE := 84

## Two phases per note, because a peak that lands between two NSDF samples is
## harder to resolve than one that lands on top of a sample, and the phase is
## what decides which happens.
const PHASES: Array[float] = [0.0, 0.31]

const HARMONIC_LIMIT := 12

## Failures are capped so a systematic break prints something readable instead
## of four hundred near-identical lines.
const MAX_REPORTED_FAILURES := 20

## Playing-technique signals are synthesised at a real capture rate, since they

var _failures := PackedStringArray()
var _failure_count := 0
var _noise_state := 12345


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_conversions()
	_test_note_names()
	_test_lag_ranges()
	_test_sweep()
	_test_intonation()
	_test_weak_fundamental()
	_test_silence_and_noise()
	_test_streaming()
	_test_onsets()
	_test_robustness()
	_report_cost()
	_finish()


# --------------------------------------------------------------------------
# Conversions
# --------------------------------------------------------------------------


func _test_conversions() -> void:
	_expect_approx(
		PitchDetector.frequency_to_midi(440.0),
		69.0,
		"A440 must convert to MIDI note 69."
	)
	_expect_approx(
		PitchDetector.midi_to_frequency(69.0),
		440.0,
		"MIDI note 69 must convert back to 440 Hz."
	)
	_expect_within(
		PitchDetector.frequency_to_midi(PitchDetector.MIN_FREQUENCY),
		40.0,
		0.01,
		"The low end of the playable range must be E2."
	)
	_expect_within(
		PitchDetector.frequency_to_midi(PitchDetector.MAX_FREQUENCY),
		84.0,
		0.01,
		"The high end of the playable range must be C6."
	)
	_expect_approx(
		PitchDetector.frequency_to_midi(0.0),
		0.0,
		"A frequency of zero must not produce an infinite MIDI number."
	)


func _test_note_names() -> void:
	_expect(
		PitchDetector.note_name(69) == "A",
		"MIDI note 69 must read out as A."
	)
	_expect(
		PitchDetector.note_label(69) == "A4",
		"MIDI note 69 must read out as A4."
	)
	_expect(
		PitchDetector.note_label(60) == "C4",
		"Middle C must read out as C4."
	)
	_expect(
		PitchDetector.note_label(40) == "E2",
		"The lowest playable note must read out as E2."
	)
	_expect(
		PitchDetector.note_name(-1) == "" and PitchDetector.note_label(-1) == "",
		"An unvoiced reading must produce no note name at all."
	)


## The lag range is derived from the capture rate rather than hardcoded, and it
## carries a semitone of headroom past each end of the playable range so a
## guitar tuned slightly flat still lands inside it.
func _test_lag_ranges() -> void:
	var at_44100 := PitchDetector.new()
	_expect(
		at_44100.lag_range() == Vector2i(9, 142),
		"A 44100 Hz capture must search lags 9 to 142."
	)
	_expect_approx(
		at_44100.work_sample_rate(),
		11025.0,
		"A 44100 Hz capture must decimate to 11025 Hz."
	)

	var at_48000 := PitchDetector.new(48000.0)
	_expect(
		at_48000.lag_range() == Vector2i(10, 155),
		"A 48000 Hz capture must widen the lag range to match."
	)
	_expect_approx(
		at_48000.work_sample_rate(),
		12000.0,
		"A 48000 Hz capture must decimate to 12000 Hz."
	)


# --------------------------------------------------------------------------
# The corpus
# --------------------------------------------------------------------------


## Every semitone of the playable range, three timbres, two phases.
func _test_sweep() -> void:
	var detector := PitchDetector.new()
	for wave: String in ["sine", "saw", "square"]:
		for note in range(LOWEST_NOTE, HIGHEST_NOTE + 1):
			for phase: float in PHASES:
				var frequency := PitchDetector.midi_to_frequency(float(note))
				var window := _wave(
					wave, frequency, WORK_RATE, PitchDetector.WINDOW_SIZE, phase
				)
				var analysis := detector.analyse_window(window)
				var label := "%s at %s" % [
					wave, PitchDetector.note_label(note)
				]
				if not analysis.voiced:
					_expect(false, "A clean %s must be heard at all." % label)
					continue
				_expect(
					analysis.midi_note == note,
					"A clean %s must be read as %s, not %s." % [
						label,
						PitchDetector.note_label(note),
						PitchDetector.note_label(analysis.midi_note),
					]
				)
				_expect(
					analysis.pitch_class == note % 12,
					"A clean %s must report the pitch class gameplay matches on."
					% label
				)
				_expect(
					absf(analysis.cents_off) <= _cents_tolerance(note),
					"A clean %s must land near the centre of the note, not %.1f cents off."
					% [label, analysis.cents_off]
				)
				_expect(
					analysis.confidence >= 0.85,
					"A clean %s must be reported confidently, not at %.2f."
					% [label, analysis.confidence]
				)


## Deliberately detuned inputs, because the readout has to show *how* flat a
## string is, not just which note it is closest to.
func _test_intonation() -> void:
	var detector := PitchDetector.new()
	for note in range(LOWEST_NOTE, HIGHEST_NOTE + 1, 3):
		for offset: float in [-30.0, -10.0, 10.0, 30.0]:
			var frequency := PitchDetector.midi_to_frequency(
				float(note) + offset / 100.0
			)
			var window := _wave(
				"saw", frequency, WORK_RATE, PitchDetector.WINDOW_SIZE, 0.0
			)
			var analysis := detector.analyse_window(window)
			var label := "%s detuned by %+.0f cents" % [
				PitchDetector.note_label(note), offset
			]
			if not analysis.voiced:
				_expect(false, "%s must still be heard." % label)
				continue
			_expect(
				analysis.midi_note == note,
				"%s must still be read as %s." % [
					label, PitchDetector.note_label(note)
				]
			)
			_expect(
				absf(analysis.cents_off - offset) <= _intonation_tolerance(note),
				"%s must read close to %+.0f cents, not %+.1f." % [
					label, offset, analysis.cents_off
				]
			)


## A plucked string heard through a small speaker can arrive with almost no
## fundamental left in it. Taking the first NSDF peak above the threshold — not
## the strongest one — is what keeps these on the right note instead of an
## octave up, so the behaviour is pinned here rather than left to chance.
func _test_weak_fundamental() -> void:
	var detector := PitchDetector.new()
	for note: int in [40, 45, 52, 57, 64, 69, 76]:
		var frequency := PitchDetector.midi_to_frequency(float(note))
		for strength: float in [0.0, 0.05, 0.15, 0.3]:
			var harmonics: Array[Vector2] = [
				Vector2(2.0, 1.0), Vector2(3.0, 0.8),
				Vector2(4.0, 0.6), Vector2(5.0, 0.4),
			]
			if strength > 0.0:
				harmonics.push_front(Vector2(1.0, strength))
			var window := _render(
				frequency,
				harmonics,
				WORK_RATE,
				PitchDetector.WINDOW_SIZE,
				0.0
			)
			var analysis := detector.analyse_window(window)
			_expect(
				analysis.voiced and analysis.midi_note == note,
				"%s must stay on pitch with a fundamental at %.2f strength, not become %s."
				% [
					PitchDetector.note_label(note),
					strength,
					PitchDetector.note_label(analysis.midi_note),
				]
			)


## The failure modes. Every one of these has to report nothing rather than a
## note nobody played.
func _test_silence_and_noise() -> void:
	var detector := PitchDetector.new()

	var silence := PackedFloat32Array()
	silence.resize(PitchDetector.WINDOW_SIZE)
	var quiet := detector.analyse_window(silence)
	_expect(not quiet.voiced, "Silence must not be heard as a note.")
	_expect(
		quiet.midi_note == -1 and quiet.pitch_class == -1,
		"Silence must report no note and no pitch class."
	)
	_expect(
		is_zero_approx(quiet.confidence) and is_zero_approx(quiet.cents_off),
		"Silence must not carry a stale confidence or tuning reading."
	)

	var direct_current := PackedFloat32Array()
	direct_current.resize(PitchDetector.WINDOW_SIZE)
	direct_current.fill(0.7)
	_expect(
		not detector.analyse_window(direct_current).voiced,
		"A DC offset with no signal in it must not be heard as a note."
	)

	var whisper := _scaled(
		_wave("saw", 220.0, WORK_RATE, PitchDetector.WINDOW_SIZE, 0.0), 0.02
	)
	_expect(
		not detector.analyse_window(whisper).voiced,
		"A note quieter than the noise floor must be gated out."
	)

	for trial in 20:
		var noise := PackedFloat32Array()
		noise.resize(PitchDetector.WINDOW_SIZE)
		for i in PitchDetector.WINDOW_SIZE:
			noise[i] = _next_noise() * 0.5
		var heard := detector.analyse_window(noise)
		_expect(
			not heard.voiced,
			"Room noise must not be reported as a note (got %s at %.2f confidence)."
			% [PitchDetector.note_label(heard.midi_note), heard.confidence]
		)

	# A measured room floor must be able to gate out a signal the default would
	# have accepted, which is the whole point of the soundcheck step.
	var loud := _wave(
		"saw",
		PitchDetector.midi_to_frequency(57.0),
		WORK_RATE,
		PitchDetector.WINDOW_SIZE,
		0.0
	)
	detector.set_noise_floor(0.9)
	_expect(
		not detector.analyse_window(loud).voiced,
		"Raising the noise floor must gate out quieter playing."
	)
	detector.set_noise_floor(PitchDetector.DEFAULT_NOISE_FLOOR)
	_expect(
		detector.analyse_window(loud).voiced,
		"Restoring the noise floor must let playing through again."
	)


# --------------------------------------------------------------------------
# Streaming
# --------------------------------------------------------------------------


## The live path: undecimated samples in, one reading per hop out.
func _test_streaming() -> void:
	var detector := PitchDetector.new()
	var quarter_second := _wave(
		"saw", PitchDetector.midi_to_frequency(57.0), 44100.0, 11025, 0.0
	)
	var results := detector.push_samples(quarter_second)
	_expect(
		results.size() == 9,
		"A quarter second of audio must produce 9 hops, not %d." % results.size()
	)
	for entry: PitchAnalysis in results:
		_expect(
			entry.voiced and entry.midi_note == 57,
			"Every hop of a held A3 must read as A3, not %s."
			% PitchDetector.note_label(entry.midi_note)
		)
		_expect(
			entry.pitch_class == 9,
			"Every hop of a held A3 must report pitch class 9."
		)

	# Stereo frames straight from AudioEffectCapture must behave identically.
	var stereo := PackedVector2Array()
	stereo.resize(quarter_second.size())
	for i in quarter_second.size():
		stereo[i] = Vector2(quarter_second[i], quarter_second[i])
	var from_frames := PitchDetector.new().push_frames(stereo)
	_expect(
		from_frames.size() == results.size(),
		"Stereo frames must produce the same number of hops as mono samples."
	)
	for entry: PitchAnalysis in from_frames:
		_expect(
			entry.voiced and entry.midi_note == 57,
			"A held A3 must survive the stereo mono-sum."
		)

	# Samples arriving in awkwardly sized chunks must not lose or shift a note,
	# because a real capture buffer never arrives in tidy window-sized pieces.
	var chunked := PitchDetector.new()
	var chunk_results: Array[PitchAnalysis] = []
	var cursor := 0
	while cursor < quarter_second.size():
		var span := mini(37, quarter_second.size() - cursor)
		chunk_results.append_array(
			chunked.push_samples(quarter_second.slice(cursor, cursor + span))
		)
		cursor += span
	_expect(
		chunk_results.size() == results.size(),
		"Ragged capture buffers must produce the same hops as one big buffer."
	)
	for entry: PitchAnalysis in chunk_results:
		_expect(
			entry.voiced and entry.midi_note == 57,
			"A held A3 must survive being fed in 37-sample chunks."
		)

	# The whole range has to survive decimation, not just the middle of it.
	for note: int in [40, 52, 64, 69, 81, 84]:
		var detector_for_note := PitchDetector.new()
		var samples := _wave(
			"saw",
			PitchDetector.midi_to_frequency(float(note)),
			44100.0,
			8192,
			0.0
		)
		for entry: PitchAnalysis in detector_for_note.push_samples(samples):
			_expect(
				entry.voiced and entry.midi_note == note,
				"%s must survive decimation from 44100, not become %s." % [
					PitchDetector.note_label(note),
					PitchDetector.note_label(entry.midi_note),
				]
			)

	var at_48000 := PitchDetector.new(48000.0)
	var samples_48 := _wave(
		"saw", PitchDetector.midi_to_frequency(81.0), 48000.0, 12000, 0.0
	)
	var results_48 := at_48000.push_samples(samples_48)
	_expect(
		not results_48.is_empty(),
		"A 48000 Hz capture must still produce readings."
	)
	for entry: PitchAnalysis in results_48:
		_expect(
			entry.voiced and entry.midi_note == 81,
			"A held A5 must be read correctly at a 48000 Hz capture rate."
		)


# --------------------------------------------------------------------------
# Onsets
# --------------------------------------------------------------------------


## Onsets are what the game actually shoots with, so the boundary between "the
## player is holding a note" and "the player played a note" is pinned here.
## Getting this wrong is either a machine gun or a dead trigger.
func _test_onsets() -> void:
	var a3 := PitchDetector.midi_to_frequency(57.0)
	var d4 := PitchDetector.midi_to_frequency(62.0)

	var held := _joined(_silence(4410), _wave("saw", a3, 44100.0, 22050, 0.0))
	var results := PitchDetector.new().push_samples(held)
	_expect(
		_onset_count(results) == 1,
		"Holding one note must fire exactly one onset, not %d."
		% _onset_count(results)
	)
	for entry: PitchAnalysis in results:
		_expect(
			not entry.is_onset or entry.voiced,
			"An onset must never be reported on a hop with no note in it."
		)

	_expect(
		_onset_count(PitchDetector.new().push_samples(_silence(22050))) == 0,
		"Silence must never fire an onset."
	)

	# Two tones butted together at identical amplitude: the pitch changes and
	# nothing else does. This once asserted two onsets, on the reasoning that a
	# different note must be a new note. A real guitar disproved it. With no
	# attack to corroborate it, a changed reading is the estimator moving rather
	# than the player — and it moves constantly, because a string sheds energy
	# from its fundamental fastest and its second harmonic eventually wins. That
	# produced a steady drip of phantom notes an octave up, on notes still loud
	# enough to pass any noise gate.
	#
	# Only a microphone reaches this code; keyboard and MIDI notes arrive
	# already separated through their own sources. So there is no synthesiser
	# sliding between pitches at constant volume to serve, and the rule can be
	# the physical one. See `playing_techniques_test.gd`, which pins both sides:
	# `_octave_drift()` for the phantom and `_hammer_on()` for the quietest real
	# note that must still count.
	var changed := _joined(
		_wave("saw", a3, 44100.0, 11025, 0.0),
		_wave("saw", d4, 44100.0, 11025, 0.0)
	)
	var change_results := PitchDetector.new().push_samples(changed)
	var onset_notes := PackedInt32Array()
	for entry: PitchAnalysis in change_results:
		if entry.is_onset:
			onset_notes.append(entry.midi_note)
	_expect(
		onset_notes.size() == 1,
		"A pitch change with no attack behind it is the estimator moving, not a "
		+ "new note, so this must be 1 onset, not %d." % onset_notes.size()
	)
	if onset_notes.size() >= 1:
		_expect(
			onset_notes[0] == 57,
			"The onset must report A3, not %s."
			% PitchDetector.note_label(onset_notes[0])
		)

	var replayed := _joined(
		_wave("saw", a3, 44100.0, 11025, 0.0),
		_silence(11025),
		_wave("saw", a3, 44100.0, 11025, 0.0)
	)
	_expect(
		_onset_count(PitchDetector.new().push_samples(replayed)) == 2,
		"Playing the same note again after a rest must fire a second onset."
	)

	# A re-pluck with no gap is the case pitch alone cannot see, which is why
	# the loudness transient is part of the rule.
	var replucked := _joined(
		_scaled(_wave("saw", a3, 44100.0, 11025, 0.0), 0.25),
		_wave("saw", a3, 44100.0, 11025, 0.0)
	)
	_expect(
		_onset_count(PitchDetector.new().push_samples(replucked)) >= 2,
		"Re-plucking a sounding note must fire another onset."
	)

	var single_window := _wave(
		"saw", a3, WORK_RATE, PitchDetector.WINDOW_SIZE, 0.0
	)
	_expect(
		not PitchDetector.new().analyse_window(single_window).is_onset,
		"A single analysed window has no history and must not claim an onset."
	)


# --------------------------------------------------------------------------
# Playing techniques
# --------------------------------------------------------------------------


## What the detector does with the things a player actually does, as opposed to
## the isolated attacks the rest of this file synthesises.
##
## Every case here is a regression. The onset rule was originally tuned against
## single plucks separated by silence, which is the one thing a rhythm game
## player never does, and it showed: a re-struck string went unheard four times
## in six, and a note change fired twice — once labelled with the note that was
## still ringing. The tuner hid all of it, because a tuner draws every voiced
## hop and a game only reacts to onsets.
##
## The false-positive case is the load-bearing one. Catching a re-pluck is easy
## if invented notes are free; it is only interesting alongside a held note that
## must produce exactly one.

func _test_robustness() -> void:
	var detector := PitchDetector.new()

	_expect(
		not detector.analyse_window(PackedFloat32Array()).voiced,
		"An empty buffer must be handled without a reading."
	)
	var stub := PackedFloat32Array()
	stub.resize(100)
	stub.fill(0.1)
	_expect(
		not detector.analyse_window(stub).voiced,
		"A buffer shorter than one window must be handled without a reading."
	)

	var window := _wave(
		"saw",
		PitchDetector.midi_to_frequency(64.0),
		WORK_RATE,
		PitchDetector.WINDOW_SIZE,
		0.0
	)
	var first := detector.analyse_window(window)
	var second := detector.analyse_window(window)
	_expect(
		first.midi == second.midi and first.confidence == second.confidence,
		"Analysing the same window twice must give the same answer."
	)

	# A capture bus with a DC bias must not bend the reading.
	var biased := PackedFloat32Array()
	biased.resize(window.size())
	for i in window.size():
		biased[i] = window[i] + 0.4
	var offset_reading := detector.analyse_window(biased)
	_expect(
		offset_reading.voiced and offset_reading.midi_note == 64,
		"A DC offset must not change which note is heard."
	)
	_expect_within(
		offset_reading.midi,
		first.midi,
		0.01,
		"A DC offset must not change the tuning reading."
	)

	var streaming := PitchDetector.new()
	streaming.push_samples(
		_wave("saw", 220.0, 44100.0, 1000, 0.0)
	)
	streaming.reset()
	_expect(
		streaming.push_samples(
			_wave("saw", 220.0, 44100.0, 1000, 0.0)
		).is_empty(),
		"Resetting must drop buffered audio instead of completing a stale window."
	)


## Milestone 1 exists to answer "is GDScript fast enough for this", so the cost
## is printed rather than asserted: a slow CI machine should not fail the suite,
## but the number needs to be visible every run. The budget is one hop, ~23 ms.
func _report_cost() -> void:
	var detector := PitchDetector.new()
	var window := _wave(
		"saw",
		PitchDetector.midi_to_frequency(57.0),
		WORK_RATE,
		PitchDetector.WINDOW_SIZE,
		0.0
	)
	var runs := 60
	var started := Time.get_ticks_usec()
	for i in runs:
		detector.analyse_window(window)
	var each := float(Time.get_ticks_usec() - started) / float(runs) / 1000.0
	var budget := float(PitchDetector.HOP_SIZE) * 1000.0 / WORK_RATE
	print(
		"Pitch analysis costs %.2f ms per window against a %.1f ms hop budget (%.0f%%)."
		% [each, budget, 100.0 * each / budget]
	)


# --------------------------------------------------------------------------
# Signal synthesis
# --------------------------------------------------------------------------


## Renders a band-limited tone, so the corpus contains only harmonics the
## sample rate can actually represent. An aliased test signal would be testing
## the synthesiser, not the detector.
func _render(
	frequency: float,
	harmonics: Array[Vector2],
	rate: float,
	count: int,
	phase: float
) -> PackedFloat32Array:
	var usable: Array[Vector2] = []
	var total := 0.0
	for harmonic: Vector2 in harmonics:
		if frequency * harmonic.x < rate * 0.5:
			usable.append(harmonic)
			total += absf(harmonic.y)
	if total <= 0.0:
		total = 1.0

	var samples := PackedFloat32Array()
	samples.resize(count)
	var offset := phase / maxf(frequency, 1.0)
	for i in count:
		var moment := float(i) / rate + offset
		var value := 0.0
		for harmonic: Vector2 in usable:
			value += harmonic.y * sin(TAU * frequency * harmonic.x * moment)
		samples[i] = 0.5 * value / total
	return samples


func _wave(
	kind: String,
	frequency: float,
	rate: float,
	count: int,
	phase: float
) -> PackedFloat32Array:
	return _render(frequency, _harmonics(kind), rate, count, phase)


## A sine has nothing to help the detector; a sawtooth has every harmonic; a
## square has only the odd ones, which is the timbre most likely to be misread
## an octave out. Between them they bracket what an instrument sounds like.
func _harmonics(kind: String) -> Array[Vector2]:
	var series: Array[Vector2] = []
	if kind == "sine":
		series.append(Vector2(1.0, 1.0))
		return series
	var step := 1 if kind == "saw" else 2
	var index := 1
	while index <= HARMONIC_LIMIT:
		series.append(Vector2(float(index), 1.0 / float(index)))
		index += step
	return series


func _scaled(samples: PackedFloat32Array, factor: float) -> PackedFloat32Array:
	var scaled := PackedFloat32Array()
	scaled.resize(samples.size())
	for i in samples.size():
		scaled[i] = samples[i] * factor
	return scaled


func _silence(count: int) -> PackedFloat32Array:
	var quiet := PackedFloat32Array()
	quiet.resize(count)
	return quiet


## Takes the parts explicitly rather than an array of buffers: an untyped array
## literal at the call site would rely on the compiler converting it, and this
## test has to compile on the first try to be worth anything.
func _joined(
	first: PackedFloat32Array,
	second: PackedFloat32Array,
	third := PackedFloat32Array()
) -> PackedFloat32Array:
	var joined := PackedFloat32Array()
	joined.append_array(first)
	joined.append_array(second)
	joined.append_array(third)
	return joined


func _onset_count(results: Array[PitchAnalysis]) -> int:
	var total := 0
	for entry in results:
		if entry.is_onset:
			total += 1
	return total


## A fixed linear congruential generator, so "room noise" is the same noise on
## every machine and a failure here is always reproducible.
func _next_noise() -> float:
	_noise_state = (1103515245 * _noise_state + 12345) % 2147483648
	return (float(_noise_state) / 2147483648.0) * 2.0 - 1.0


# --------------------------------------------------------------------------
# Tolerances
# --------------------------------------------------------------------------


## Accuracy falls off with pitch: C6 is only ~10.5 samples per period once the
## audio is decimated, so the interpolated peak has far less to work with than
## it does at E2. These are the measured worst cases with room to spare, not
## aspirations — tightening them means improving the detector first.
func _cents_tolerance(note: int) -> float:
	if note <= 64:
		return 4.0
	if note <= 76:
		return 10.0
	return 12.0


func _intonation_tolerance(note: int) -> float:
	if note <= 64:
		return 4.0
	if note <= 76:
		return 10.0
	return 14.0


# --------------------------------------------------------------------------
# Harness
# --------------------------------------------------------------------------


func _expect_within(
	actual: float,
	expected: float,
	tolerance: float,
	message: String
) -> void:
	_expect(absf(actual - expected) <= tolerance, message)


func _expect_approx(actual: float, expected: float, message: String) -> void:
	_expect(is_equal_approx(actual, expected), message)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failure_count += 1
	if _failures.size() < MAX_REPORTED_FAILURES:
		_failures.append(message)


func _finish() -> void:
	if _failure_count == 0:
		print("Pitch detector tests passed.")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	if _failure_count > _failures.size():
		push_error(
			"...and %d further failures." % (_failure_count - _failures.size())
		)
	quit(1)
