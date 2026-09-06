class_name EncounterDirector
extends Node2D

## Owns the rail, the lanes and every drone on them (§8).
##
## This is where the game's rules live: which drone a played note resolves
## against, what timing tier it earned, when a wave is cleared and when the
## track runs out. It reports all of that as signals and judgement dictionaries
## and never scores anything itself — `gameplay.gd` owns the shell's score,
## streak and lives, and this node owns the field.
##
## Splitting it out this way is what makes the rules testable. `gameplay.gd`
## extends [GameShell], which uses autoload instances, so a headless
## `--script` test can never name it. Nothing in this file touches an autoload,
## so `encounter_test.gd` can drive the real rules directly.

signal drone_spawned(drone: RustDrone)
signal drone_killed(drone: RustDrone, judgement: Dictionary)
signal drone_fired(drone: RustDrone)
signal wave_started(index: int, total: int)
signal wave_cleared(index: int, clean: bool)
signal track_cleared

## A note landed and killed the front-most matching drone.
## A note was played while drones were up but matched none of them.
## A note was played with nothing valid to hit — between waves, or aimed at a
## drone that is not yet in its timing window.
enum Judgement { HIT, WRONG_NOTE, NOISE }

## Timing tiers from §6, measured against the drone's arrival at the strike
## line after latency compensation.
enum Tier { PERFECT, GOOD, EDGE, OUTSIDE }

## What the director is doing right now.
enum Phase {
	## Nothing loaded, or the track is finished.
	IDLE,
	## Rail advancing between waves. Nobody can be hurt here (§8.1).
	ADVANCING,
	## A wave is on the field.
	ENCOUNTER,
}

const LANE_COUNT := 3

## Timing windows in seconds, before the accessibility handicap widens them.
const PERFECT_WINDOW := 0.060
const GOOD_WINDOW := 0.140
const EDGE_WINDOW := 0.260

const PERFECT_POINTS := 100
const GOOD_POINTS := 60
const EDGE_POINTS := 25

## Charged against a note played at a drone that is on the field but wrong.
const WRONG_NOTE_PENALTY := 25
## Awarded for clearing a wave without a single drone getting a shot off.
const SECTION_CLEAR_BONUS := 250

## Streak lengths at which the combo multiplier steps up (§6).
const COMBO_STEPS := [5, 15, 30]
const COMBO_MULTIPLIERS := [1, 2, 4, 8]

## Granted when intonation is within a quarter of a semitone.
const PITCH_BONUS_CENTS := 25.0
const PITCH_BONUS_SCALE := 1.15

## Breathing room between waves. A music game cannot ask for continuous
## sight-reading, and the rail advance is where the player recovers (§8.1).
const RAIL_ADVANCE_SECONDS := 2.2

## Rhythm mode makes every drone accept any note (§3, §8.3). It is a flag on
## the rules, not a separate code path.
var pitch_matters := true

## Widens every timing window by the shared "make it easier" handicap, so the
## game reuses `Settings.target_size_scale()` instead of adding a second dial.
var window_scale := 1.0

## Points charged for a wrong note. Seeded from [constant WRONG_NOTE_PENALTY]
## and overridden per round from the player's own option, which may take it all
## the way to zero.
var wrong_note_penalty := WRONG_NOTE_PENALTY

var _phase: Phase = Phase.IDLE
var _track: Array = []
var _wave_index := -1
var _wave_elapsed := 0.0
var _advance_elapsed := 0.0
var _spawned := 0
var _wave_clean := true
var _drones: Array[RustDrone] = []
var _field := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
var _reduced_motion := false


## Loads a track: an ordered list of waves, each `{"drones": [...]}`, where a
## drone is `{"lane": int, "note": int, "at": float, "approach": float,
## "windup": float}`. `at` is seconds from the start of its own wave.
##
## Keeping the track as plain data is the seam the chart format (§10) will plug
## into — a chart compiles to exactly this, and nothing here needs to change.
func set_track(waves: Array) -> void:
	_track = waves
	_wave_index = -1
	_phase = Phase.IDLE
	_clear_drones()


## Starts the track from the top. Safe to call again to restart a round.
func begin() -> void:
	_wave_index = -1
	_clear_drones()
	if _track.is_empty():
		_phase = Phase.IDLE
		track_cleared.emit()
		return
	_start_advance()


## Stops everything and clears the field, without reporting a cleared track.
func halt() -> void:
	_phase = Phase.IDLE
	_clear_drones()


## Per-frame update. `field` is the play area the drones walk down; it is
## re-read every frame so the rail survives a window resize.
func advance(delta: float, field: Rect2) -> void:
	_field = field

	match _phase:
		Phase.ADVANCING:
			_advance_elapsed += delta
			if _advance_elapsed >= RAIL_ADVANCE_SECONDS:
				_start_wave()
		Phase.ENCOUNTER:
			_wave_elapsed += delta
			_spawn_due_drones()
		Phase.IDLE:
			pass

	_advance_drones(delta)
	_mark_front_target()

	if _phase == Phase.ENCOUNTER and _wave_is_over():
		_finish_wave()


## Rules on one played note and returns the judgement. The caller applies the
## result to the score; this never mutates anything but the drone it kills.
##
## `cents_off` is the intonation error and `exact` is true for MIDI and the
## computer keyboard, which are exact by construction.
func resolve_note(
	played_pitch_class: int,
	streak: int,
	cents_off := 0.0,
	exact := false
) -> Dictionary:
	var live := _live_drones()
	if live.is_empty():
		return _judgement(Judgement.NOISE, Tier.OUTSIDE, null, 0.0, 0)

	var matches := _matching_drones(live, played_pitch_class)
	if matches.is_empty():
		# Drones are up and the player named none of them: a wrong note, which
		# costs points and the combo but never a life (§7.3).
		return _judgement(
			Judgement.WRONG_NOTE, Tier.OUTSIDE, null, 0.0, -wrong_note_penalty
		)

	var target := _front_most_in_window(matches)
	if target == null:
		# The right note, but nothing is in its window yet. Treated as noise
		# rather than a wrong note: the player aimed at a real drone and was
		# only early, and punishing that teaches hesitation.
		return _judgement(Judgement.NOISE, Tier.OUTSIDE, null, 0.0, 0)

	var error := target.time_to_beat()
	var tier := tier_for(error, window_scale)
	var points := note_points(tier, streak, cents_off, exact)
	if not target.kill():
		return _judgement(Judgement.NOISE, Tier.OUTSIDE, null, 0.0, 0)

	var judgement := _judgement(Judgement.HIT, tier, target, error, points)
	drone_killed.emit(target, judgement)
	return judgement


## Which timing tier an error in seconds falls into. Static and pure so the
## windows can be tested without a scene.
static func tier_for(time_error: float, scale := 1.0) -> Tier:
	var error := absf(time_error)
	var widen := maxf(scale, 0.01)
	if error <= PERFECT_WINDOW * widen:
		return Tier.PERFECT
	if error <= GOOD_WINDOW * widen:
		return Tier.GOOD
	if error <= EDGE_WINDOW * widen:
		return Tier.EDGE
	return Tier.OUTSIDE


## Base points before the combo multiplier and the intonation bonus.
static func tier_points(tier: Tier) -> int:
	match tier:
		Tier.PERFECT:
			return PERFECT_POINTS
		Tier.GOOD:
			return GOOD_POINTS
		Tier.EDGE:
			return EDGE_POINTS
		_:
			return 0


## The combo multiplier earned by a streak of consecutive kills (§6).
static func combo_multiplier(streak: int) -> int:
	var multiplier := int(COMBO_MULTIPLIERS[0])
	for step_index in range(COMBO_STEPS.size()):
		if streak >= int(COMBO_STEPS[step_index]):
			multiplier = int(COMBO_MULTIPLIERS[step_index + 1])
	return multiplier


## Full score for one kill: tier, combo multiplier and the intonation bonus.
## `streak` is the streak *before* this kill, so the multiplier a player sees
## on screen is the one they are about to be paid at.
static func note_points(
	tier: Tier,
	streak: int,
	cents_off := 0.0,
	exact := false
) -> int:
	var base := tier_points(tier)
	if base <= 0:
		return 0
	var total := float(base * combo_multiplier(streak))
	if exact or absf(cents_off) <= PITCH_BONUS_CENTS:
		total *= PITCH_BONUS_SCALE
	return int(round(total))


## Human-readable tier name for the HUD callout.
static func tier_name(tier: Tier) -> String:
	match tier:
		Tier.PERFECT:
			return "PERFECT"
		Tier.GOOD:
			return "GOOD"
		Tier.EDGE:
			return "LATE"
		_:
			return "MISS"


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	for drone in _drones:
		drone.set_reduced_motion(enabled)


## True once the track has no waves left and nothing is still shootable.
## `gameplay.gd` uses the `track_cleared` signal for the TRACK CLEARED early
## end (§7.4); this is the polled form of the same question.
##
## Deliberately asks about *targetable* drones, not every child: a killed drone
## lingers for a couple of frames while it fades, and a corpse must not make
## the director claim the track is still running.
func is_finished() -> bool:
	return _phase == Phase.IDLE and _live_drones().is_empty()


## Drones currently on the field, front-most first. Exposed for tests and for
## the HUD's "next note" hint.
func live_drones() -> Array[RustDrone]:
	return _live_drones()


func wave_number() -> int:
	return _wave_index + 1


func wave_total() -> int:
	return _track.size()


func phase() -> Phase:
	return _phase


func _start_advance() -> void:
	_phase = Phase.ADVANCING
	_advance_elapsed = 0.0


func _start_wave() -> void:
	_wave_index += 1
	if _wave_index >= _track.size():
		_phase = Phase.IDLE
		track_cleared.emit()
		return
	_phase = Phase.ENCOUNTER
	_wave_elapsed = 0.0
	_spawned = 0
	_wave_clean = true
	wave_started.emit(_wave_index, _track.size())
	_spawn_due_drones()


func _finish_wave() -> void:
	var clean := _wave_clean
	var index := _wave_index
	if _wave_index + 1 >= _track.size():
		_phase = Phase.IDLE
		wave_cleared.emit(index, clean)
		track_cleared.emit()
		return
	_start_advance()
	wave_cleared.emit(index, clean)


func _current_wave_drones() -> Array:
	if _wave_index < 0 or _wave_index >= _track.size():
		return []
	var wave: Dictionary = _track[_wave_index]
	var listed: Variant = wave.get("drones", [])
	return listed if listed is Array else []


func _spawn_due_drones() -> void:
	var planned := _current_wave_drones()
	while _spawned < planned.size():
		var plan: Dictionary = planned[_spawned]
		if float(plan.get("at", 0.0)) > _wave_elapsed:
			return
		_spawn(plan)
		_spawned += 1


func _spawn(plan: Dictionary) -> void:
	var drone := RustDrone.new()
	drone.configure(
		clampi(int(plan.get("lane", 1)), 0, LANE_COUNT - 1),
		int(plan.get("note", -1)),
		float(plan.get("approach", 4.0)),
		float(plan.get("windup", 1.6))
	)
	drone.set_reduced_motion(_reduced_motion)
	_drones.append(drone)
	add_child(drone)
	# Placed once immediately so it never renders a frame at the origin.
	drone.advance(0.0, _field, LANE_COUNT)
	drone_spawned.emit(drone)


func _advance_drones(delta: float) -> void:
	var survivors: Array[RustDrone] = []
	for drone in _drones:
		if not is_instance_valid(drone):
			continue
		if drone.advance(delta, _field, LANE_COUNT):
			_wave_clean = false
			drone_fired.emit(drone)
		if drone.is_finished():
			drone.queue_free()
			continue
		survivors.append(drone)
	_drones = survivors


## Outlines the drone a note would hit right now — the "one bright target"
## convention Target Rush already uses (§5.2).
func _mark_front_target() -> void:
	var live := _live_drones()
	var front: RustDrone = null
	if not live.is_empty():
		front = live[0]
	for drone in _drones:
		drone.set_targeted(drone == front)


## A wave is over once everything it planned has spawned and nothing on the
## field can still be shot. Drones mid-fade do not hold it open.
func _wave_is_over() -> bool:
	if _spawned < _current_wave_drones().size():
		return false
	return _live_drones().is_empty()


## Targetable drones, front-most first. Front-most means furthest along its
## approach, which is also the most urgent, so the intuitive read and the
## optimal read agree (§8.3).
func _live_drones() -> Array[RustDrone]:
	var live: Array[RustDrone] = []
	for drone in _drones:
		if is_instance_valid(drone) and drone.is_targetable():
			live.append(drone)
	live.sort_custom(
		func(a: RustDrone, b: RustDrone) -> bool:
			return a.approach_progress() > b.approach_progress()
	)
	return live


func _matching_drones(
	live: Array[RustDrone],
	played_pitch_class: int
) -> Array[RustDrone]:
	if not pitch_matters:
		return live
	var matches: Array[RustDrone] = []
	for drone in live:
		if drone.pitch_class() == played_pitch_class:
			matches.append(drone)
	return matches


## The front-most matching drone that is actually inside a timing window.
## Front-most decides *which* drone; the window decides whether it is hittable
## yet, so a note played long before a drone arrives is early, not a mistake.
func _front_most_in_window(matches: Array[RustDrone]) -> RustDrone:
	for drone in matches:
		if tier_for(drone.time_to_beat(), window_scale) != Tier.OUTSIDE:
			return drone
	return null


func _clear_drones() -> void:
	for drone in _drones:
		if is_instance_valid(drone):
			drone.queue_free()
	_drones = []


func _judgement(
	kind: Judgement,
	tier: Tier,
	drone: RustDrone,
	time_error: float,
	points: int
) -> Dictionary:
	return {
		"kind": kind,
		"tier": tier,
		"drone": drone,
		"time_error": time_error,
		"points": points,
	}
