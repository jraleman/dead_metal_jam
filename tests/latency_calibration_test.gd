extends SceneTree

## Milestone 3 gate: proves latency can be *measured* before anyone is asked to
## trust a measurement.
##
## Two halves, both hardware-free:
##
##   1. [LatencyCalibration] — the matching and the statistics, driven with
##      hand-built times so the right answer is known exactly.
##   2. [member PitchAnalysis.sample_index] — the clock the real measurement
##      keys off. A pluck is synthesised at a known sample and the detector has
##      to report an onset at that sample, not merely "eventually".
##
## The second is the one that matters. Calibration arithmetic that is fed
## sloppy timestamps produces a confident, wrong number, and a wrong latency is
## worse than no latency: it shifts every judgement in the game by a constant
## and the player has no way to see why.
##
## Run it with:
##   godot --headless --path .
##       --script res://games/dead_metal_jam/tests/latency_calibration_test.gd

const RATE := 48000.0
const BEAT := 0.5

var _failures := PackedStringArray()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_perfect_player()
	_test_count_in_is_ignored()
	_test_one_fumble_does_not_move_the_answer()
	_test_missed_and_doubled_beats()
	_test_too_few_notes()
	_test_too_loose()
	_test_implausible()
	_test_sample_index_is_continuous()
	_test_onset_lands_on_the_pluck()
	_test_detection_delay_is_stated_honestly()
	_test_metronome_is_inaudible_to_the_detector()
	_finish()


# --------------------------------------------------------------------------
# The arithmetic
# --------------------------------------------------------------------------


## A player who is exactly 90 ms late on every beat must measure 90 ms.
func _test_perfect_player() -> void:
	var calibration := _with_clicks(10)
	for beat in 10:
		calibration.add_onset(float(beat) * BEAT + 0.09)

	var result := calibration.measure()
	_expect(
		result["verdict"] == LatencyCalibration.Verdict.GOOD,
		"A player on every beat must produce a usable measurement, not %s."
		% result["message"]
	)
	_expect_approx(
		result["latency_ms"], 90.0, 0.001,
		"A steady 90 ms lag must measure as 90 ms."
	)
	_expect_approx(
		result["spread_ms"], 0.0, 0.001, "A steady lag must report no spread."
	)


## The count-in beats are where the player finds the tempo, so a wild note on
## beat one must not reach the result at all.
func _test_count_in_is_ignored() -> void:
	var calibration := _with_clicks(10)
	calibration.add_onset(0.2)
	calibration.add_onset(BEAT + 0.2)
	for beat in range(LatencyCalibration.COUNT_IN_BEATS, 10):
		calibration.add_onset(float(beat) * BEAT + 0.08)

	var result := calibration.measure()
	_expect_approx(
		result["latency_ms"], 80.0, 0.001,
		"Notes played during the count-in must not reach the measurement."
	)
	_expect(
		int(result["samples"]) == 10 - LatencyCalibration.COUNT_IN_BEATS,
		"Every beat after the count-in must be counted, not %d."
		% int(result["samples"])
	)


## The reason the centre is a median: one badly late note out of eight must not
## drag the stored latency with it.
func _test_one_fumble_does_not_move_the_answer() -> void:
	var calibration := _with_clicks(10)
	for beat in 10:
		var lag := 0.09
		if beat == 6:
			lag = 0.22
		calibration.add_onset(float(beat) * BEAT + lag)

	var result := calibration.measure()
	_expect_approx(
		result["latency_ms"], 90.0, 0.001,
		"One fumbled beat must not move the measured latency."
	)
	_expect(
		float(result["spread_ms"]) > 0.0,
		"A fumbled beat must still be visible in the reported spread."
	)


## A beat the player skipped must cost one sample, not corrupt its neighbours,
## and a double-picked beat must not be counted twice.
func _test_missed_and_doubled_beats() -> void:
	var calibration := _with_clicks(10)
	for beat in 10:
		if beat == 5:
			continue
		calibration.add_onset(float(beat) * BEAT + 0.1)
	calibration.add_onset(3.0 * BEAT + 0.115)

	var result := calibration.measure()
	_expect(
		int(result["samples"]) == 7,
		"Eight scored beats minus one missed must leave 7 samples, not %d."
		% int(result["samples"])
	)
	_expect_approx(
		result["latency_ms"], 100.0, 1.0,
		"A missed beat and a double pick must not bend the answer."
	)


func _test_too_few_notes() -> void:
	var calibration := _with_clicks(10)
	calibration.add_onset(2.0 * BEAT + 0.09)
	calibration.add_onset(3.0 * BEAT + 0.09)

	var result := calibration.measure()
	_expect(
		result["verdict"] == LatencyCalibration.Verdict.NOT_ENOUGH,
		"Two notes must not be enough to publish a latency."
	)
	_expect(
		not str(result["message"]).is_empty(),
		"A refused measurement must tell the player what to do differently."
	)


func _test_too_loose() -> void:
	var calibration := _with_clicks(12)
	var wobble := [0.02, 0.16, 0.03, 0.15, 0.02, 0.17, 0.03, 0.14, 0.02, 0.16]
	for i in wobble.size():
		var beat: int = i + LatencyCalibration.COUNT_IN_BEATS
		calibration.add_onset(float(beat) * BEAT + wobble[i])

	var result := calibration.measure()
	_expect(
		result["verdict"] == LatencyCalibration.Verdict.TOO_LOOSE,
		"Playing all over the beat must be refused, not averaged into %.0f ms."
		% float(result["latency_ms"])
	)


## A stable answer can still be a wrong one. Every note landing just *before*
## its click reads as a negative round trip, which cannot happen.
func _test_implausible() -> void:
	var calibration := _with_clicks(10)
	for beat in 10:
		calibration.add_onset(float(beat) * BEAT - 0.02)

	var result := calibration.measure()
	_expect(
		result["verdict"] == LatencyCalibration.Verdict.IMPLAUSIBLE,
		"A negative round trip must be refused rather than stored."
	)


# --------------------------------------------------------------------------
# The clock
# --------------------------------------------------------------------------


## Hops must be a fixed distance apart on the input stream regardless of how
## the buffer was chopped up on the way in, because a real capture delivers
## whatever the frame rate left it holding.
func _test_sample_index_is_continuous() -> void:
	var detector := PitchDetector.new(RATE)
	var tone := _pluck(220.0, 24000, 0)
	var indices := PackedInt32Array()

	var offset := 0
	var chunk := 1
	while offset < tone.size():
		var size: int = mini(chunk, tone.size() - offset)
		for entry: PitchAnalysis in detector.push_samples(
			tone.slice(offset, offset + size)
		):
			indices.append(entry.sample_index)
		offset += size
		chunk = 1 + (chunk * 7) % 3000

	_expect(indices.size() >= 3, "A half-second tone must produce several hops.")
	var expected := (
		PitchDetector.WINDOW_SIZE * PitchDetector.DECIMATION
	)
	var step := PitchDetector.HOP_SIZE * PitchDetector.DECIMATION
	for i in indices.size():
		_expect(
			indices[i] == expected + i * step,
			"Hop %d must sit at sample %d, not %d — an uneven clock makes "
			% [i, expected + i * step, indices[i]]
			+ "every timing judgement wrong by a different amount."
		)


## The measurement this whole milestone rests on: a note that starts at a known
## sample must be reported a fixed distance after it.
##
## The exact distance matters far less than its *constancy*. A constant delay
## is absorbed by calibration — it is measured once and subtracted forever. A
## delay that wandered with where the attack happened to fall could not be, and
## would put a floor under the timing accuracy no tuning could lift.
func _test_onset_lands_on_the_pluck() -> void:
	var detector := PitchDetector.new(RATE)
	var typical := detector.typical_onset_delay_samples()
	var hop := PitchDetector.HOP_SIZE * PitchDetector.DECIMATION
	var delays := PackedInt32Array()

	for start in [4800, 9601, 12000, 17777, 21173]:
		var fresh := PitchDetector.new(RATE)
		var buffer := PackedFloat32Array()
		buffer.append_array(_room_tone(start))
		buffer.append_array(_pluck(196.0, 24000, start))

		var onset := -1
		for entry: PitchAnalysis in fresh.push_samples(buffer):
			if entry.is_onset:
				onset = entry.sample_index
				break

		if onset < 0:
			_failures.append(
				"A pluck at sample %d fired no onset at all." % start
			)
			continue

		var delay: int = onset - start
		delays.append(delay)
		# The constant exists to be reported to a player, so it has to stay
		# within a hop of what the detector really does.
		_expect(
			absi(delay - typical) <= hop,
			"A pluck at sample %d was reported %.1f ms later, more than a hop "
			% [start, float(delay) / RATE * 1000.0]
			+ "from the %.1f ms PitchDetector claims. Update "
			% (float(typical) / RATE * 1000.0)
			+ "TYPICAL_ONSET_DELAY_SECONDS to match the measurement."
		)

	if delays.size() < 2:
		return

	var lowest := delays[0]
	var highest := delays[0]
	for delay in delays:
		lowest = mini(lowest, delay)
		highest = maxi(highest, delay)
	_expect(
		highest - lowest < hop,
		"The detector's delay must not depend on where the attack falls: it "
		+ "ranged over %d samples (%.1f ms), more than one hop."
		% [highest - lowest, float(highest - lowest) / RATE * 1000.0]
	)
	print(
		"Detector's own delay: %.1f-%.1f ms at %d Hz, jitter %.1f ms."
		% [
			float(lowest) / RATE * 1000.0,
			float(highest) / RATE * 1000.0,
			int(RATE),
			float(highest - lowest) / RATE * 1000.0,
		]
	)


## The detector's own contribution has to be stateable, because it is the part
## of a measured latency the player cannot fix by buying a better interface.
func _test_detection_delay_is_stated_honestly() -> void:
	var detector := PitchDetector.new(RATE)
	var delay_ms := (
		float(detector.typical_onset_delay_samples()) / RATE * 1000.0
	)
	_expect(
		delay_ms > 0.0 and delay_ms < 100.0,
		"The detector's own delay must be a sane figure, not %.1f ms."
		% delay_ms
	)


## The metronome is played out loud, so unless the player wears headphones the
## microphone hears every click. If a click read as a note the game would
## measure the round trip of its *own* audio — a stable, plausible, completely
## wrong number that nothing downstream could detect.
##
## So the click must fire no onsets at all, and must not stop a real note
## played on top of it from firing exactly one.
func _test_metronome_is_inaudible_to_the_detector() -> void:
	var beat_samples := int(RATE * BEAT)
	var track := PackedFloat32Array()
	track.resize(beat_samples * 8)
	for beat in 8:
		var click := MetronomeClick.click_samples(RATE, beat % 4 == 0)
		for i in click.size():
			track[beat * beat_samples + i] = click[i]

	var clicks_only := PitchDetector.new(RATE).push_samples(track)
	var onsets := 0
	for entry: PitchAnalysis in clicks_only:
		if entry.is_onset:
			onsets += 1
	_expect(
		onsets == 0,
		"The metronome must fire no onsets, not %d — a click the detector "
		% onsets
		+ "hears as a note makes calibration measure the game's own audio."
	)

	# A note played over the click must still be the only thing heard.
	var start := beat_samples * 3
	var pluck := _pluck(196.0, beat_samples * 2, start)
	var mixed := track.duplicate()
	for i in pluck.size():
		if start + i < mixed.size():
			mixed[start + i] += pluck[i]

	var played := PitchDetector.new(RATE).push_samples(mixed)
	var notes := PackedInt32Array()
	for entry: PitchAnalysis in played:
		if entry.is_onset:
			notes.append(entry.midi_note)
	_expect(
		notes.size() == 1 and notes[0] == 55,
		"A G3 played over the metronome must fire exactly one onset for G3, "
		+ "not %d onsets %s." % [notes.size(), str(notes)]
	)


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------


func _with_clicks(beats: int) -> LatencyCalibration:
	var calibration := LatencyCalibration.new(BEAT)
	for beat in beats:
		calibration.add_click(float(beat) * BEAT)
	return calibration


## A plucked string: a sawtooth under a sharp attack and an exponential decay.
## The envelope is the point — a detector fed a tone that simply switches on
## has never been asked where the note *started*.
func _pluck(
	frequency: float, count: int, start_index: int
) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(count)
	var attack := RATE * 0.004
	for i in count:
		var t := float(i) / RATE
		var envelope := exp(-t * 3.5)
		if float(i) < attack:
			envelope *= float(i) / attack
		var value := 0.0
		for harmonic in range(1, 7):
			value += sin(
				TAU * frequency * float(harmonic) * (
					float(start_index + i) / RATE
				)
			) / float(harmonic)
		samples[i] = value * envelope * 0.4
	return samples


## Quiet enough to stay under the gate, loud enough that the buffer is not
## digital silence — which is what a real room sounds like before a note.
func _room_tone(count: int) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	samples.resize(count)
	var state := 987654321
	for i in count:
		state = (1103515245 * state + 12345) % 2147483648
		samples[i] = ((float(state) / 2147483648.0) * 2.0 - 1.0) * 0.0008
	return samples


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_approx(
	value: float, expected: float, tolerance: float, message: String
) -> void:
	_expect(
		absf(value - expected) <= tolerance,
		"%s (got %.3f, wanted %.3f)" % [message, value, expected]
	)


func _finish() -> void:
	if _failures.is_empty():
		print("Latency calibration tests passed.")
		quit(0)
		return
	for failure in _failures:
		printerr(failure)
	quit(1)
