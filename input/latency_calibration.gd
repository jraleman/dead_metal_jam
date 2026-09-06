class_name LatencyCalibration
extends RefCounted

## Turns "the player played along with a metronome" into one number: how late
## the game hears a note (`DESIGN.md` §4.6).
##
## Pure arithmetic — no audio, no scene, no clock of its own. Times go in,
## a verdict comes out — which is what lets `tests/latency_calibration_test.gd`
## prove the matching and the statistics with no hardware and no instrument,
## the same way [PitchDetector] is proven.
##
## The number it produces is the *round trip*: the click leaving the speakers,
## travelling to the player's ear, the player's own reaction, the string
## reaching the microphone, and the detector's own window. It is deliberately
## not decomposed. The player is trying to play at the moment they *hear* the
## beat, so the whole loop is what has to be subtracted for the game to judge
## what they experienced rather than what the buffer did.

enum Verdict {
	NOT_ENOUGH,  ## Too few notes landed near a click.
	TOO_LOOSE,  ## Notes landed, but nowhere near consistently.
	IMPLAUSIBLE,  ## A stable answer that cannot be a real latency.
	GOOD,
}

## Beats ignored at the start. The player is finding the tempo, not playing to
## it, and their first note is reliably the worst one they play.
const COUNT_IN_BEATS := 2

## Offsets further from a click than this fraction of a beat are dropped: at
## half a beat there is no honest way to say which click was aimed at.
const MATCH_WINDOW_BEATS := 0.5

## Fewest usable notes for a result. Below this one stray offset moves the
## answer too much to publish it.
const MIN_SAMPLES := 4

## A player who cannot hold the beat this tightly has not produced a latency
## measurement, they have produced noise, and the honest response is to say so
## and offer another go rather than to quietly store the average.
const MAX_SPREAD_MS := 45.0

## Latency beyond this is not credible on any desktop path and almost always
## means notes were matched to the wrong beat.
const MAX_PLAUSIBLE_MS := 400.0

## Never store a negative round trip: hearing a note before it was played is
## the signature of a mis-measurement, not of a fast sound card.
const MIN_PLAUSIBLE_MS := 0.0

var _beat_seconds := 0.5
var _clicks := PackedFloat64Array()
var _onsets := PackedFloat64Array()


func _init(beat_seconds := 0.5) -> void:
	configure(beat_seconds)


func configure(beat_seconds: float) -> void:
	_beat_seconds = maxf(beat_seconds, 0.05)
	clear()


func clear() -> void:
	_clicks = PackedFloat64Array()
	_onsets = PackedFloat64Array()


## The time a click became *audible*, not the time it was requested. The caller
## owns that distinction because only it knows the output latency.
func add_click(time_seconds: float) -> void:
	_clicks.append(time_seconds)


func add_onset(time_seconds: float) -> void:
	_onsets.append(time_seconds)


func click_count() -> int:
	return _clicks.size()


func onset_count() -> int:
	return _onsets.size()


## Signed offsets, in milliseconds, of every note that can be attributed to a
## click. Positive means the game heard the note after the click, which is the
## normal direction.
##
## Each click takes at most one note — its nearest — so a double-picked beat
## contributes one measurement rather than two, and a beat the player missed
## entirely contributes none instead of stealing its neighbour's note.
func offsets_ms() -> PackedFloat64Array:
	var window := _beat_seconds * MATCH_WINDOW_BEATS
	var used := {}
	var offsets := PackedFloat64Array()

	for index in range(COUNT_IN_BEATS, _clicks.size()):
		var click := _clicks[index]
		var best := -1
		var best_distance := window
		for onset_index in _onsets.size():
			if used.has(onset_index):
				continue
			var distance := absf(_onsets[onset_index] - click)
			if distance < best_distance:
				best_distance = distance
				best = onset_index
		if best < 0:
			continue
		used[best] = true
		offsets.append((_onsets[best] - click) * 1000.0)

	return offsets


## The measurement, as a dictionary so a caller can show its working:
## `latency_ms`, `spread_ms`, `samples`, `verdict` and a player-facing
## `message`.
##
## The centre is the **median**, not the mean the first draft of §4.6 called
## for. Eight beats is a small sample and one fumbled note is a large outlier;
## a mean lets that single note move the number by more than the tolerance the
## whole exercise exists to establish. Spread is reported around the median for
## the same reason.
func measure() -> Dictionary:
	var offsets := offsets_ms()
	var result := {
		"latency_ms": 0.0,
		"spread_ms": 0.0,
		"samples": offsets.size(),
		"verdict": Verdict.NOT_ENOUGH,
		"message": "",
	}

	if offsets.size() < MIN_SAMPLES:
		result["message"] = (
			"Only %d of %d beats were played close enough to time. "
			% [offsets.size(), maxi(_clicks.size() - COUNT_IN_BEATS, 0)]
			+ "Play one note on every click."
		)
		return result

	var centre := _median(offsets)
	var spread := _mean_absolute_deviation(offsets, centre)
	result["latency_ms"] = centre
	result["spread_ms"] = spread

	if spread > MAX_SPREAD_MS:
		result["verdict"] = Verdict.TOO_LOOSE
		result["message"] = (
			"Your notes landed %.0f ms apart on average, which is too loose to "
			% spread
			+ "measure. Try again and play right on the click."
		)
		return result

	if centre < MIN_PLAUSIBLE_MS or centre > MAX_PLAUSIBLE_MS:
		result["verdict"] = Verdict.IMPLAUSIBLE
		result["message"] = (
			"Measured %.0f ms, which is outside anything believable. " % centre
			+ "Check the right input device is selected and try again."
		)
		return result

	result["verdict"] = Verdict.GOOD
	result["message"] = "Measured %.0f ms, give or take %.0f. %s" % [
		centre, spread, _quality_note(centre)
	]
	return result


## Read back to the player so the number means something to them.
static func _quality_note(latency_ms: float) -> String:
	if latency_ms <= 60.0:
		return "That is a fast path — timing will feel tight."
	if latency_ms <= 130.0:
		return "That is normal for a microphone."
	return "That is slow; a wired interface or MIDI would feel better."


static func _median(values: PackedFloat64Array) -> float:
	var ordered := values.duplicate()
	ordered.sort()
	var middle := ordered.size() / 2
	if ordered.size() % 2 == 1:
		return ordered[middle]
	return (ordered[middle - 1] + ordered[middle]) * 0.5


static func _mean_absolute_deviation(
	values: PackedFloat64Array, centre: float
) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += absf(value - centre)
	return total / float(values.size())
