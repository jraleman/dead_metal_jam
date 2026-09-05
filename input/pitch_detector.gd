class_name PitchDetector
extends RefCounted

## Monophonic pitch detection in pure GDScript: the McLeod Pitch Method over
## the Normalised Square Difference Function (NSDF).
##
## This is the load-bearing system of Dead Metal Jam — "tell a C from an E" is
## the whole game — so it is deliberately the most isolated one. It is pure
## DSP: no autoloads, no [AudioServer], no scene tree, no threads. Samples in,
## notes out. That is what lets `tests/pitch_detector_test.gd` prove it against
## synthesised buffers with no audio hardware, in a headless run, before
## anything else in the game exists.
##
## MPM rather than YIN because its peak clarity doubles as the confidence value
## the note readout has to show anyway, and it is markedly less octave-error
## prone on plucked strings than plain autocorrelation.
##
## There is deliberately no separate octave-correction pass. One was written and
## measured against the corpus in `tests/pitch_detector_test.gd`: it rescued
## nothing MPM's first-peak rule did not already get right — including notes
## with a missing or very weak fundamental — while pushing A5 and C6 down an
## octave, because a parabola is a poor fit to an NSDF peak only ~11 samples
## wide. Taking the *first* peak above the threshold is the whole octave defence.
##
## Two entry points:
##   [method analyse_window] — one window, no state, fully deterministic.
##   [method push_frames] — the streaming path a live microphone feeds, which
##                          adds decimation, hop buffering and median smoothing.
##
## Both return a [PitchAnalysis]. See `DESIGN.md` §4.4 for the pipeline.

## Sample rate the capture bus is assumed to run at. Passed in rather than read
## from [AudioServer] so the detector stays pure and testable.
const DEFAULT_INPUT_RATE := 44100.0

## 4:1 decimation with a box pre-filter. Nyquist at 11 kHz is ~5.5 kHz, far
## above the highest fundamental accepted below, and it makes the NSDF inner
## loop 4x cheaper — the difference between "runs in GDScript" and "does not".
const DECIMATION := 4

## ~46 ms of analysis every ~23 ms at 11025 Hz.
const WINDOW_SIZE := 512
const HOP_SIZE := 256

## Playable range: E2 (the low string of a guitar in standard tuning) to C6.
const MIN_FREQUENCY := 82.4069
const MAX_FREQUENCY := 1046.502

## Semitones of lag headroom past each end of the playable range. Without it a
## guitar tuned a little flat drops off the bottom: E2 at -30 cents needs a lag
## of 136, and a range that stops dead at E2 stops at 134 and hears nothing.
const RANGE_PADDING_SEMITONES := 1.0

## MPM's peak rule: take the first key maximum at or above this fraction of the
## strongest one. Taking the *first* rather than the strongest is what stops a
## periodic signal from being read an octave (or two) too low, since the NSDF
## peaks just as hard at every multiple of the true period.
const PEAK_THRESHOLD := 0.9

## Below this clarity the window is called unvoiced. A confident wrong answer
## and an unsure guess must not look the same to the player (§5.1), so anything
## this weak reports nothing at all rather than a note nobody played.
const MIN_CLARITY := 0.5

## Default RMS gate. Soundcheck measures the real room and overrides it.
const DEFAULT_NOISE_FLOOR := 0.01

## Lags past the longest accepted one are still evaluated, so the peak search
## can see both neighbours of every candidate and parabolic interpolation has
## something to interpolate at the very bottom of the range.
const GUARD_LAGS := 4

## Hops kept for the median filter. Three costs one hop (~23 ms) of latency and
## removes the single-hop outliers that plucked strings produce during attack.
const MEDIAN_WINDOW := 3

## An onset is only reported once the same note has held for this many hops.
## A plucked string spends its first few milliseconds as broadband noise, and
## firing on that would spray wrong notes at the moment the player is most
## likely to be looking at the readout.
const ONSET_STABLE_HOPS := 2

## Minimum gap between onsets. Below this a single pluck's amplitude wobble
## reads as a second note.
const ONSET_REFRACTORY_SECONDS := 0.06

## How much louder than the recent average a hop must be to count as a fresh
## attack on the note already sounding. Only re-plucks need this; a *change* of
## note is an onset on its own.
const ONSET_RMS_RATIO := 1.8

## How fast the trailing loudness average follows the signal. Slow enough to
## still be low when an attack arrives, fast enough to settle during a note.
const TRAILING_RMS_SMOOTHING := 0.25

const NOTE_NAMES: Array[String] = [
	"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
]


var _input_rate := DEFAULT_INPUT_RATE
var _work_rate := DEFAULT_INPUT_RATE / float(DECIMATION)
var _noise_floor := DEFAULT_NOISE_FLOOR
var _min_lag := 10
var _max_lag := 134
var _search_lag := 138
## Raw mono samples not yet consumed by a whole decimation group.
var _raw := PackedFloat32Array()
## Decimated samples not yet consumed by a whole window.
var _pending := PackedFloat32Array()
var _recent_midi := PackedFloat32Array()
## Onset state. Only the streaming path maintains these; [method analyse_window]
## neither reads nor writes them.
var _trailing_rms := 0.0
var _hops_since_onset := 0
var _stable_note := -1
var _stable_hops := 0
var _sounding_note := -1


func _init(
	input_sample_rate := DEFAULT_INPUT_RATE,
	noise_floor := DEFAULT_NOISE_FLOOR
) -> void:
	configure(input_sample_rate, noise_floor)


## Repoints the detector at a capture rate. The lag range is derived rather
## than hardcoded, so a 48 kHz driver stays as correct as a 44.1 kHz one.
func configure(
	input_sample_rate := DEFAULT_INPUT_RATE,
	noise_floor := DEFAULT_NOISE_FLOOR
) -> void:
	_input_rate = maxf(input_sample_rate, 1.0)
	_work_rate = _input_rate / float(DECIMATION)
	_noise_floor = maxf(noise_floor, 0.0)
	var padding := pow(2.0, RANGE_PADDING_SEMITONES / 12.0)
	_min_lag = maxi(int(floor(_work_rate / (MAX_FREQUENCY * padding))), 2)
	_max_lag = int(ceil(_work_rate / (MIN_FREQUENCY / padding)))
	_search_lag = _max_lag + GUARD_LAGS
	reset()


## Drops every buffered sample and the smoothing history. Called between rounds
## and whenever the input device changes, so a new note is never medianed
## against the previous device's tail.
func reset() -> void:
	_raw = PackedFloat32Array()
	_pending = PackedFloat32Array()
	_recent_midi = PackedFloat32Array()
	_trailing_rms = 0.0
	_hops_since_onset = _refractory_hops()
	_stable_note = -1
	_stable_hops = 0
	_sounding_note = -1


func set_noise_floor(rms: float) -> void:
	_noise_floor = maxf(rms, 0.0)


func noise_floor() -> float:
	return _noise_floor


func work_sample_rate() -> float:
	return _work_rate


func input_sample_rate() -> float:
	return _input_rate


func lag_range() -> Vector2i:
	return Vector2i(_min_lag, _max_lag)


# --------------------------------------------------------------------------
# Streaming path
# --------------------------------------------------------------------------


## Feeds interleaved stereo frames straight from [AudioEffectCapture].
##
## Returns one [PitchAnalysis] per completed hop — usually zero or one, but a
## stalled frame that delivers a large buffer produces several, and dropping
## those would silently swallow notes.
func push_frames(frames: PackedVector2Array) -> Array[PitchAnalysis]:
	var mono := PackedFloat32Array()
	mono.resize(frames.size())
	for i in frames.size():
		var frame := frames[i]
		mono[i] = (frame.x + frame.y) * 0.5
	return push_samples(mono)


## Feeds mono samples at the configured input rate, returning one
## [PitchAnalysis] per completed hop.
func push_samples(samples: PackedFloat32Array) -> Array[PitchAnalysis]:
	_raw.append_array(samples)
	_decimate_pending()

	var results: Array[PitchAnalysis] = []
	while _pending.size() >= WINDOW_SIZE:
		var analysis := analyse_window(_pending.slice(0, WINDOW_SIZE))
		_stabilise(analysis)
		_mark_onset(analysis)
		results.append(analysis)
		_pending = _pending.slice(HOP_SIZE)
	return results


## Box-filters and downsamples every whole group of [constant DECIMATION]
## samples, keeping the remainder for the next call so the stream has no seams.
func _decimate_pending() -> void:
	var usable := _raw.size() - (_raw.size() % DECIMATION)
	if usable <= 0:
		return

	var produced := usable / DECIMATION
	var start := _pending.size()
	_pending.resize(start + produced)
	for i in produced:
		var sum := 0.0
		var offset := i * DECIMATION
		for k in DECIMATION:
			sum += _raw[offset + k]
		_pending[start + i] = sum / float(DECIMATION)
	_raw = _raw.slice(usable)


## Median-of-3 across hops. Rewrites the analysis in place from the smoothed
## fractional MIDI value so `midi_note`, `pitch_class` and `cents_off` stay
## consistent with each other.
func _stabilise(analysis: PitchAnalysis) -> void:
	if not analysis.voiced:
		_recent_midi = PackedFloat32Array()
		return

	_recent_midi.append(analysis.midi)
	while _recent_midi.size() > MEDIAN_WINDOW:
		_recent_midi.remove_at(0)
	if _recent_midi.size() < MEDIAN_WINDOW:
		return

	var ordered := _recent_midi.duplicate()
	ordered.sort()
	_apply_midi(analysis, ordered[MEDIAN_WINDOW / 2])


## Flags the hop that starts a note, which is what the game turns into a shot.
##
## Two things count as a start: a *different* note settling, and a fresh attack
## on the note already sounding. The first needs no loudness test at all — the
## pitch changed, so something was played. The second does, because a held note
## and a re-plucked one look identical apart from the transient.
func _mark_onset(analysis: PitchAnalysis) -> void:
	_hops_since_onset += 1

	if not analysis.voiced:
		_stable_note = -1
		_stable_hops = 0
		_sounding_note = -1
		_trailing_rms = lerpf(_trailing_rms, analysis.rms, TRAILING_RMS_SMOOTHING)
		return

	if analysis.midi_note == _stable_note:
		_stable_hops += 1
	else:
		_stable_note = analysis.midi_note
		_stable_hops = 1

	var attacked := analysis.rms > _trailing_rms * ONSET_RMS_RATIO
	var changed := analysis.midi_note != _sounding_note
	if (
		_stable_hops >= ONSET_STABLE_HOPS
		and _hops_since_onset >= _refractory_hops()
		and (changed or attacked)
	):
		analysis.is_onset = true
		_sounding_note = analysis.midi_note
		_hops_since_onset = 0

	_trailing_rms = lerpf(_trailing_rms, analysis.rms, TRAILING_RMS_SMOOTHING)


## The refractory window in hops, derived so it stays ~60 ms whatever rate the
## capture device runs at.
func _refractory_hops() -> int:
	return int(ceil(ONSET_REFRACTORY_SECONDS * _work_rate / float(HOP_SIZE)))


# --------------------------------------------------------------------------
# Single window
# --------------------------------------------------------------------------


## Analyses one window of decimated mono samples. Reads configuration but no
## streaming state, and writes none at all, so the same buffer always produces
## the same answer — which is what makes the unit test meaningful.
func analyse_window(window: PackedFloat32Array) -> PitchAnalysis:
	var analysis := PitchAnalysis.new()
	if window.size() < WINDOW_SIZE:
		return analysis

	var mean := 0.0
	for i in WINDOW_SIZE:
		mean += window[i]
	mean /= float(WINDOW_SIZE)

	# Removing the window mean is an exact DC notch and needs no state, so a
	# capture bus with a DC bias cannot bend the correlation.
	var centred := PackedFloat32Array()
	centred.resize(WINDOW_SIZE)
	var energy := 0.0
	for i in WINDOW_SIZE:
		var value := window[i] - mean
		centred[i] = value
		energy += value * value
	analysis.rms = sqrt(energy / float(WINDOW_SIZE))
	if analysis.rms < _noise_floor:
		return analysis

	var nsdf := _normalised_square_difference(centred)
	var lag := _pick_peak(nsdf)
	if lag < 0:
		return analysis

	var refined := _interpolate_peak(nsdf, lag)
	var refined_lag := refined.x
	if refined_lag < float(_min_lag) - 1.0 or refined_lag > float(_max_lag) + 1.0:
		return analysis

	analysis.voiced = true
	analysis.confidence = clampf(refined.y, 0.0, 1.0)
	_apply_midi(analysis, frequency_to_midi(_work_rate / refined_lag))
	return analysis


## NSDF over lag 0 to [member _search_lag]:
## `n(t) = 2 * sum(x[j] * x[j+t]) / sum(x[j]^2 + x[j+t]^2)`, which is bounded to
## -1.0 to 1.0 and therefore directly usable as a clarity score.
func _normalised_square_difference(
	samples: PackedFloat32Array
) -> PackedFloat32Array:
	var size := samples.size()
	var result := PackedFloat32Array()
	result.resize(_search_lag + 1)
	for lag in range(_search_lag + 1):
		var correlation := 0.0
		var magnitude := 0.0
		var limit := size - lag
		for j in limit:
			var a := samples[j]
			var b := samples[j + lag]
			correlation += a * b
			magnitude += a * a + b * b
		result[lag] = 0.0 if magnitude <= 0.0 else 2.0 * correlation / magnitude
	return result


## First key maximum at or above [constant PEAK_THRESHOLD] of the strongest one,
## searched only across the lags the playable range can produce. Returns -1 when
## nothing in the window is periodic enough to call a note.
##
## Candidates are compared after interpolation. Comparing raw samples instead
## quietly loses the top octave: A5 is 12.5 samples per period, so its true peak
## falls between two samples and reads ~0.85 while the doubled lag — landing
## almost exactly on a sample — reads ~1.0, and the real note fails the
## threshold against its own harmonic.
func _pick_peak(nsdf: PackedFloat32Array) -> int:
	var peaks := PackedInt32Array()
	var clarities := PackedFloat32Array()
	var strongest := 0.0
	for lag in range(_min_lag, _max_lag + 1):
		var value := nsdf[lag]
		if value > nsdf[lag - 1] and value >= nsdf[lag + 1]:
			var clarity := _interpolate_peak(nsdf, lag).y
			peaks.append(lag)
			clarities.append(clarity)
			strongest = maxf(strongest, clarity)

	if peaks.is_empty() or strongest < MIN_CLARITY:
		return -1

	var threshold := strongest * PEAK_THRESHOLD
	for i in peaks.size():
		if clarities[i] >= threshold:
			return peaks[i]
	return -1


## Parabolic interpolation through the peak and its two neighbours, returning
## `(lag, value)`. Without this the top octave would quantise to whole samples:
## C6 is only ~10.5 samples per period at 11 kHz, so a half-sample error there
## is most of a semitone.
func _interpolate_peak(nsdf: PackedFloat32Array, lag: int) -> Vector2:
	var before := nsdf[lag - 1]
	var here := nsdf[lag]
	var after := nsdf[lag + 1]
	var curvature := before - 2.0 * here + after
	if absf(curvature) < 0.000001:
		return Vector2(float(lag), here)

	var shift := clampf(0.5 * (before - after) / curvature, -1.0, 1.0)
	return Vector2(float(lag) + shift, here - 0.25 * (before - after) * shift)


func _apply_midi(analysis: PitchAnalysis, midi: float) -> void:
	analysis.midi = midi
	analysis.midi_note = int(round(midi))
	analysis.pitch_class = ((analysis.midi_note % 12) + 12) % 12
	analysis.cents_off = (midi - float(analysis.midi_note)) * 100.0
	analysis.frequency = midi_to_frequency(midi)


# --------------------------------------------------------------------------
# Conversions
# --------------------------------------------------------------------------


static func frequency_to_midi(frequency: float) -> float:
	if frequency <= 0.0:
		return 0.0
	return 69.0 + 12.0 * log(frequency / 440.0) / log(2.0)


static func midi_to_frequency(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)


## Letter name only, which is what the readout shows: the player reads "E",
## never a staff (§5.1).
static func note_name(midi_note: int) -> String:
	if midi_note < 0:
		return ""
	return NOTE_NAMES[((midi_note % 12) + 12) % 12]


## Letter plus octave, for the readout's secondary line: "E3".
static func note_label(midi_note: int) -> String:
	if midi_note < 0:
		return ""
	return "%s%d" % [note_name(midi_note), midi_note / 12 - 1]
