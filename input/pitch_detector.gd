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
##
## **Measured, not guessed.** A string re-struck while still ringing adds to
## what is already there rather than replacing it, so the jump is far smaller
## than a note from silence: 1.3x to 1.6x is typical, not the 2x a fresh pluck
## suggests. The original 1.8 missed four of six re-plucks. It is safe this low
## only because of the arm/re-arm rule below — without hysteresis a threshold
## this sensitive would retrigger on the sustain.
const ONSET_RMS_RATIO := 1.4

## How much louder than the recent *trough* a hop must be to count as an attack,
## independently of the trailing average.
##
## The two tests catch different things. Against the average, a note starting
## from near-silence is obvious. Against the recent trough, a string re-struck
## while still ringing is obvious — the level barely changes across the whole
## note, but the attack is a step up from the quietest moment just before it.
##
## The reference is a trough rather than the previous hop because an analysis
## window is about twice a hop: a transient straddles two of them, so a
## hop-to-hop comparison sees half the rise each time and can miss an attack
## that is plainly there in the envelope. Measured on a re-plucked string at
## 0.18 s spacing, hop-to-hop peaked at 1.10 while the same attack stood 1.26
## above the trough it started from.
##
## Swept against the whole scenario set rather than picked: at 1.18 a tremolo
## at 0.18 s lost two of six notes, and at 1.15 with a longer window a held
## note grew a phantom second onset. This value with
## [constant ONSET_RISE_WINDOW_HOPS] at 4 is the only combination that caught
## every re-pluck without inventing one.
const ONSET_RISE_RATIO := 1.15

## Hops the trough reference looks back over. About 90 ms — long enough to sit
## below a beating string's wobble, short enough that the reference follows a
## decaying note down instead of holding a stale peak. Widening it to 6 traded
## a caught tremolo note for a phantom onset on a sustained one.
const ONSET_RISE_WINDOW_HOPS := 4

## The level must fall back to this multiple of the trailing average, and stop
## rising, before another attack can be recognised.
##
## One attack arms exactly one onset. Without this the level stays above the
## threshold for several hops after a pluck and the refractory window is the
## only thing standing between one note and an endless stream of them.
## Comfortably above the ~1.0 a sustaining note sits at.
const ONSET_RMS_REARM_RATIO := 1.15

## Hops after an attack before it may fire an onset.
##
## An analysis window is [constant WINDOW_SIZE] samples — about twice a hop — so
## for the first hop or two after a pluck the window still holds mostly the
## audio that came *before* it, and the detector is still reporting the note
## that was ringing. Firing there labels the new pluck with the old note and
## then fires again when the new one resolves: six clean plucks measured seven
## onsets, the first note doubled.
##
## Physically motivated rather than tuned: it is the window-straddle time. A
## note starting from silence is unaffected, because it needs two stable hops
## anyway and cannot supply them any sooner.
const ONSET_ATTACK_SETTLE_HOPS := 2

## Hops an attack stays usable once it has settled. The window from
## [constant ONSET_ATTACK_SETTLE_HOPS] to here is the detector's chance to name
## the note; past it the attack is stale and a fresh one is required.
const ONSET_ATTACK_LATCH_HOPS := 6

## Hops the trailing average is held still after an attack.
##
## Covers the transient so the reference cannot absorb the evidence for the very
## attack it is measuring, and no longer — every extra hop frozen is a hop
## before the trigger can re-arm for the next pluck.
const ONSET_TRAILING_FREEZE_HOPS := 3

## Consecutive unvoiced hops before the sounding note counts as released.
##
## One unvoiced hop in the middle of a note is a wobble in the analysis, not the
## end of the note. Treating it as the end made the note look new when it came
## back, which fired a second onset for a single pluck — six plucks measured
## eleven onsets before this.
const ONSET_RELEASE_HOPS := 2

## How fast the trailing loudness average follows the signal.
##
## Fast enough that the reference settles onto a sustaining note within a few
## hops, which is what lets the *next* pluck stand out against it. It is safe to
## keep this quick only because the average is frozen while an attack is in
## flight — see [method _update_trailing_rms]. Without that freeze, a reference
## moving this fast absorbs the transient it exists to measure: at the original
## symmetric 0.25 a string re-struck while still ringing peaked *below* the
## threshold, and four of six re-plucks were missed.
const TRAILING_RMS_SMOOTHING := 0.30

## Floor under both attack ratios, so a hop of near-silence divided by a hop of
## near-silence cannot read as an attack.
const MIN_ATTACK_LEVEL := 0.001

## How far above the calibrated room floor a hop must reach before it is allowed
## to be an attack at all.
##
## Both attack tests are *ratios*, and a ratio is scale-free: noise drifting
## from 0.02 to 0.03 is the same 1.5x step as a note starting from nothing, so
## on its own the rule fires continuously on room tone. The voiced check is not
## enough either — it compares against the floor measured during a quiet
## calibration, while a player's room also contains handling, pick scrape and
## the tails of notes already struck, all comfortably above it.
##
## So proportion says *something changed* and this says *there is a note here to
## change*. Both must agree.
##
## Swept against the playing-technique corpus rather than guessed. At 1.0 and
## 1.5 a decaying string's tail still put a phantom semitone neighbour into a
## six-note phrase; at 3.0 a real fingerpicked note was swallowed. 2.0 and 2.5
## both pass, so this sits between them instead of on either edge — the corpus
## is synthesised, and a value that only just passes it would be a value tuned
## to the model rather than to the instrument.
const ONSET_NOISE_MARGIN := 2.25

const NOTE_NAMES: Array[String] = [
	"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
]


## Typical delay between a note physically starting and the hop that reports it
## as an onset, in seconds.
##
## **Measured, not derived.** `tests/latency_calibration_test.gd` synthesises
## plucks at known samples and asserts the real figure stays within a hop of
## this, so changing the window or the stability rule fails the test rather
## than quietly invalidating the number.
##
## A formula was tried first and abandoned: a window turns voiced once the note
## fills roughly a third of it, not half or all, so anything derived from the
## window size overstates the delay by 15 ms or more.
##
## Only ever used to *report* — to tell a player which part of their measured
## latency is this code and which part is their hardware. Judgement uses the
## calibrated round trip (§4.6), never this.
const TYPICAL_ONSET_DELAY_SECONDS := 0.042


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
## Decimated samples consumed by windows already emitted. Counted rather than
## derived so a hop can be placed exactly on the input stream's own clock.
var _work_consumed := 0
## Onset state. Only the streaming path maintains these; [method analyse_window]
## neither reads nor writes them.
var _trailing_rms := 0.0
## Hops an unspent attack has left to live; see [method _track_attack].
var _attack_hops := 0
## False between an attack and the level falling back to the sustain, so one
## pluck cannot be counted twice.
var _attack_armed := true
## Consecutive unvoiced hops, so a one-hop wobble does not end the note.
var _unvoiced_hops := 0
## Previous hops' loudness, newest last, for the trough the rise test measures
## against. Capped at [constant ONSET_RISE_WINDOW_HOPS].
var _recent_rms: Array[float] = []
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
	_work_consumed = 0
	_trailing_rms = 0.0
	_attack_hops = 0
	_attack_armed = true
	_unvoiced_hops = 0
	_recent_rms.clear()
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
		# Decimation always consumes whole groups, so a decimated index maps
		# back onto the input stream exactly rather than approximately.
		analysis.sample_index = (_work_consumed + WINDOW_SIZE) * DECIMATION
		_stabilise(analysis)
		_mark_onset(analysis)
		results.append(analysis)
		_pending = _pending.slice(HOP_SIZE)
		_work_consumed += HOP_SIZE
	return results


## Seconds of audio the detector has consumed, on the same clock as
## [member PitchAnalysis.sample_index].
func sample_index_to_seconds(index: int) -> float:
	return float(index) / _input_rate


## Smallest delay, in input-rate samples, between a note physically starting
## and the hop that can first report it as an onset.
##
## See [constant TYPICAL_ONSET_DELAY_SECONDS]. What matters for calibration is
## that this is *constant*: a fixed delay is measured once and subtracted
## forever, where a delay that wandered with where the attack fell would put a
## floor under timing accuracy that no tuning could lift.
func typical_onset_delay_samples() -> int:
	return int(round(TYPICAL_ONSET_DELAY_SECONDS * _input_rate))


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

	# Recorded before the smoothing below moves it, so the field holds the
	# value this hop was actually judged against rather than the one the next
	# hop will be.
	analysis.trailing_rms = _trailing_rms

	# Loudness is judged here — before the average is updated, and whether or
	# not the pitch is nameable yet — because the first hop of a pluck is the
	# loudest and the least identifiable. The verdict is latched and spent when
	# the note settles a hop or two later.
	_track_attack(analysis.rms)
	_update_trailing_rms(analysis.rms)

	if not analysis.voiced:
		_stable_note = -1
		_stable_hops = 0
		_unvoiced_hops += 1
		if _unvoiced_hops >= ONSET_RELEASE_HOPS:
			_sounding_note = -1
		return

	_unvoiced_hops = 0
	if analysis.midi_note == _stable_note:
		_stable_hops += 1
	else:
		_stable_note = analysis.midi_note
		_stable_hops = 1

	analysis.stable_hops = _stable_hops
	# An onset always requires an attack. Accepting a bare change of note here
	# instead — "the pitch is different, so it must be new" — was wrong in a way
	# silence hid completely: with nothing to corroborate it, any wobble in the
	# estimate becomes a note. Room tone drifts the reading a semitone and emits
	# one. Worse, a real string sheds energy from its fundamental fastest, so
	# partway through a long note the second harmonic is the loudest thing left
	# and the estimator starts naming that instead — a phantom an octave up, on a
	# note still loud enough to pass any noise gate. A real guitar produced a
	# steady drip of exactly those, high and quiet, long after the player
	# stopped.
	#
	# Only this path sees a microphone; keyboard and MIDI notes arrive already
	# separated, through their own sources. So the question can be the physical
	# one, and there is no need to also serve a synthesiser sliding between
	# pitches at constant volume: you cannot start a note on a string without
	# putting energy into it, and that includes fretted ones — a finger landing
	# on a fret is a quiet attack, not an absent one.
	if (
		_stable_hops >= ONSET_STABLE_HOPS
		and _hops_since_onset >= _refractory_hops()
		and _attack_settled()
	):
		analysis.is_onset = true
		_sounding_note = analysis.midi_note
		_hops_since_onset = 0
		# One attack is one note, however many hops it stays loud for.
		_attack_hops = 0
		# The average is frozen through an attack, so at this moment it still
		# describes the silence *before* the note. Left to converge on its own it
		# spends about five hops climbing, and for every one of those the ratio
		# reads high enough to look like an ongoing attack — which holds the
		# Schmitt trigger disarmed and makes the detector deaf to the next note.
		# A fast run lost its second note exactly this way. Once a note has been
		# accepted it *is* the background the next attack must beat, so say so.
		_trailing_rms = analysis.rms


## Hops elapsed since the current attack was latched, or -1 when none is live.
func _attack_age() -> int:
	if _attack_hops <= 0:
		return -1
	return ONSET_ATTACK_LATCH_HOPS - _attack_hops


## True when an attack is live *and* the analysis window has moved past the
## audio that preceded it, so the note being reported is the one just played.
func _attack_settled() -> bool:
	return _attack_age() >= ONSET_ATTACK_SETTLE_HOPS


## Arms on a rise past [constant ONSET_RMS_RATIO] and will not arm again until
## the level has fallen back to [constant ONSET_RMS_REARM_RATIO] — a Schmitt
## trigger on loudness. The latch then keeps the verdict alive for a few hops so
## the pitch has time to settle without the attack expiring.
func _track_attack(rms: float) -> void:
	if _attack_hops > 0:
		_attack_hops -= 1

	var floor_level := maxf(_noise_floor, MIN_ATTACK_LEVEL)
	var against_average := rms / maxf(_trailing_rms, floor_level)
	var against_trough := rms / maxf(_rise_trough(), floor_level)
	# Proportion alone cannot tell a note from noise that happens to be moving,
	# because it is scale-free. Requiring the hop to also stand clear of the
	# measured room is what separates "something got louder" from "something was
	# played" — see ONSET_NOISE_MARGIN.
	var audible := rms >= floor_level * ONSET_NOISE_MARGIN
	var attacking := (
		audible
		and (against_average >= ONSET_RMS_RATIO or against_trough >= ONSET_RISE_RATIO)
	)

	if _attack_armed and attacking:
		_attack_hops = ONSET_ATTACK_LATCH_HOPS
		_attack_armed = false
		# Loudness moves a hop or two before the pitch estimator lets go of the
		# note that was already ringing, so at the moment of an attack the
		# current reading still names the *old* note. Clearing the run forces
		# the note to be re-established, and ONSET_ATTACK_SETTLE_HOPS keeps the
		# attack unusable until the window has moved past the old audio.
		_stable_note = -1
		_stable_hops = 0
		# This attack was measured against the history, so keeping it would leave
		# the trough sitting below the new note and retrigger on the sustain.
		# Filled rather than emptied: an empty window disables the trough test
		# until it refills, which is a blind spot exactly where fast repeated
		# notes live. Seeding it with the present level keeps the test live and
		# lets the trough follow the new note down as it decays.
		_seed_rise_history(rms)

	elif not attacking and against_average <= ONSET_RMS_REARM_RATIO:
		_attack_armed = true

	_recent_rms.append(rms)
	while _recent_rms.size() > ONSET_RISE_WINDOW_HOPS:
		_recent_rms.remove_at(0)


## Quietest of the last few hops — the level this note had settled to before
## anything happened to it. Zero until enough history exists, which disables the
## trough test rather than letting it fire on a single hop.
func _rise_trough() -> float:
	if _recent_rms.size() < ONSET_RISE_WINDOW_HOPS:
		return 0.0
	var lowest: float = _recent_rms[0]
	for value in _recent_rms:
		lowest = minf(lowest, value)
	return lowest


## Refills the window with one level, so the trough test stays live from the
## next hop instead of going blind while history rebuilds.
func _seed_rise_history(rms: float) -> void:
	_recent_rms.clear()
	for _i in ONSET_RISE_WINDOW_HOPS:
		_recent_rms.append(rms)


## The average follows the signal at one rate, but is held still for the first
## few hops of an attack so it cannot absorb the transient the attack is
## measured against. Once the freeze lifts it catches up to the new sustain
## quickly, which is what re-arms the trigger in time for the next pluck.
func _update_trailing_rms(rms: float) -> void:
	var age := _attack_age()
	if age >= 0 and age < ONSET_TRAILING_FREEZE_HOPS and rms > _trailing_rms:
		return
	_trailing_rms = lerpf(_trailing_rms, rms, TRAILING_RMS_SMOOTHING)


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
