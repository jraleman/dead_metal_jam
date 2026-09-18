class_name EncounterDirector
extends Node2D

## Owns the combat rooms, firing bays and every drone in them (§8).
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

signal drone_spawned(drone: JamBot)
signal drone_killed(drone: JamBot, judgement: Dictionary)
signal drone_fired(drone: JamBot)
## The camera has started repositioning for the section named [param name].
## Emitted before the wave rather than with it, because the advance banner is
## the player's cue that the pressure has stopped for a moment (§5.3, §8.1).
##
## [param name] is authoring metadata and is not shown to the player — the HUD
## uses [param index] and [param total] and writes its own copy (§5.3).
signal section_started(name: String, index: int, total: int)
signal wave_started(index: int, total: int)
signal wave_cleared(index: int, clean: bool)
signal track_cleared

## A note landed on the selected matching drone or armor plate.
## A note was played while drones were up but matched none of them.
## A note was played with nothing valid to hit — between waves, or aimed at a
## drone that is not yet in its timing window.
enum Judgement { HIT, WRONG_NOTE, NOISE }

## Timing bonuses measured against the scheduled beat after latency compensation.
enum Tier { PERFECT, GOOD, EDGE, OUTSIDE, SNAP }

## What the director is doing right now.
enum Phase {
	## Nothing loaded, or the track is finished.
	IDLE,
	## Repositioning between waves. Nobody can be hurt here (§8.1).
	ADVANCING,
	## A wave is on the field.
	ENCOUNTER,
}

## The three modes (§3).
##
## They are the same rules with different flags — not three code paths, and
## not three subclasses. [method apply_mode] is the whole of the difference
## between them, which is a claim `encounter_test.gd` checks directly rather
## than one this comment has to be trusted about.
enum Mode {
	## Pitch and timing both count, and a bot that fires costs a life.
	JAM,
	## Onset only: every bot accepts any note. The honest fallback for a noisy
	## room, an unusual instrument, or a drummer.
	RHYTHM,
	## Time stops at each beat and waits for the player, and nothing costs a
	## life. The tutorial, and a metronome to practise against.
	DEMO,
}

const LANE_COUNT := 3
const MAX_FRAME_STEP := 1.0 / 60.0

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
##
## A chart may lengthen or shorten it per section through its archetype — a
## bridge earns real rail, a late push gets less of it — so this is the default
## rather than the rule (see [constant JamChart.ARCHETYPES]).
const RAIL_ADVANCE_SECONDS := 2.2

## How much Demo widens every timing window on top of the player's own
## handicap. Demo is where somebody finds out the game works at all, and its
## §3 promise is "forgiving", not "free" — the tiers still separate a note
## played on the beat from one scrambled after it.
const DEMO_WINDOW_SCALE := 1.5

## Head bob: how far the camera moves, in pixels, standing still and marching.
##
## Small numbers on purpose. The bob's job is to stop the frame being perfectly
## still — a static frame is what makes a fixed camera read as a diagram rather
## than as a point of view — and the moment it grows past this it starts
## fighting the one thing the player is trying to read, which is where a bot is
## aiming its next shot.
const BOB_IDLE := 1.8
const BOB_ADVANCE := 5.5

## Steps per second at each speed, which sets how fast the bob cycles.
const BOB_RATE_IDLE := 0.6
const BOB_RATE_ADVANCE := 2.1

## How quickly the camera settles between combat and repositioning.
const BOB_BLEND := 4.0

## Roster keys a wave may name (§8.2). Unknown keys stage a Rusty Clanky, so a
## chart typo costs the wrong enemy rather than an empty wave.
const ENEMY_RUSTY_CLANKY := "rusty_clanky"
const ENEMY_PLATED_KNUCKLE := "plated_knuckle"
const ENEMY_SILENCER_SENTRY := "silencer_sentry"
const ENEMY_CONDUCTOR := "conductor"

## Rhythm mode makes every drone accept any note (§3, §8.3). It is a flag on
## the rules, not a separate code path.
var pitch_matters := true
## Jam accepts correct-note shots throughout the attack warning. Other modes
## retain their timing gates; the same timing tiers still reward Jam accuracy.
var arcade_shots := true
var presentation_speed := 1.0

## Demo mode's "stop time" (§3). The room, entry poses, wind-up fuses and the
## chart cursor all hold at each beat and resume the instant it is answered.
var stop_time := false

## False in Demo, which never reports a mistake, so nobody can die in it under
## either round mode (§3, §7). The director still emits [signal drone_fired] —
## the world reacts either way — and `gameplay.gd` asks this before spending a
## life, so the mode is read once rather than branched on everywhere.
var reports_damage := true

## Widens every timing window by the shared "make it easier" handicap, so the
## game reuses `Settings.target_size_scale()` instead of adding a second dial.
var window_scale := 1.0

## The mode's own leniency, kept apart from [member window_scale] so the two
## multiply instead of overwriting each other and the order they are set in
## cannot matter.
var mode_window_scale := 1.0

## Points charged for a wrong note. Seeded from [constant WRONG_NOTE_PENALTY]
## and overridden per round from the player's own option, which may take it all
## the way to zero.
var wrong_note_penalty := WRONG_NOTE_PENALTY

## Presentation size only; the chart and judgement clocks never read it.
var visual_scale := 1.0

var _phase: Phase = Phase.IDLE
var _track: Array = []
var _wave_index := -1
var _wave_elapsed := 0.0
var _advance_elapsed := 0.0
var _advance_seconds := RAIL_ADVANCE_SECONDS
var _spawned := 0
var _wave_clean := true
var _drones: Array[JamBot] = []
var _field := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
var _reduced_motion := false
var _effects_enabled := true
var _rail: DmjRail
var _mode: Mode = Mode.JAM
var _time_stopped := false
var _bob_phase := 0.0
var _bob_weight := 0.0
var _bob := Vector2.ZERO
var _world_time := 0.0


## The rail is built here rather than by `gameplay.gd` because the director
## owns the lanes (§8), and because a rail the scene had to remember to add
## would be missing from every other place a director is instanced.
func _ready() -> void:
	_rail = DmjRail.new()
	_rail.name = "Rail"
	_rail.set_reduced_motion(_reduced_motion)
	_rail.set_effects_enabled(_effects_enabled)
	add_child(_rail)


## Loads a track: an ordered list of waves. A wave is
## `{"section": String, "archetype": String, "advance": float,
## "drones": [...]}`, where a drone is `{"lane": int, "note": int,
## "notes": Array, "enemy": String, "at": float, "approach": float,
## "windup": float}`. `at` is seconds from the start of its own wave.
##
## Only `drones` is required; everything else has a default, so the practice
## builder and a compiled chart can both produce this shape.
##
## Keeping the track as plain data is the seam the chart format (§10) plugs
## into — [method JamChart.to_track] compiles to exactly this, and nothing here
## needed to change when it landed.
func set_track(waves: Array) -> void:
	_track = waves
	_wave_index = -1
	_phase = Phase.IDLE
	_clear_drones()


## Starts the track from the top. Safe to call again to restart a round.
func begin() -> void:
	_wave_index = -1
	_world_time = 0.0
	_time_stopped = false
	_clear_drones()
	if _track.is_empty():
		_phase = Phase.IDLE
		track_cleared.emit()
		return
	_start_advance()


## Switches mode (§3).
##
## This function is the entire difference between Jam, Rhythm and Demo. Every
## other line in this file is shared, which is what "one code path with three
## rule flags" has to mean if it is to mean anything — and why the modes are
## set here in one place rather than tested for at each of the four points
## they would otherwise reach.
func apply_mode(mode: Mode) -> void:
	_mode = mode
	pitch_matters = mode != Mode.RHYTHM
	arcade_shots = mode == Mode.JAM
	stop_time = mode == Mode.DEMO
	reports_damage = mode != Mode.DEMO
	mode_window_scale = DEMO_WINDOW_SCALE if mode == Mode.DEMO else 1.0
	if not stop_time:
		_time_stopped = false


func mode() -> Mode:
	return _mode


## Human-readable mode name, for the HUD and the results copy.
static func mode_name(mode: Mode) -> String:
	match mode:
		Mode.RHYTHM:
			return "RHYTHM"
		Mode.DEMO:
			return "DEMO"
		_:
			return "JAM"


## True while Demo is holding the world at a beat, waiting to be answered.
##
## `gameplay.gd` pauses the shell's round timer on this. Without that, "the run
## always finishes" (§3) would be false the moment a player stopped to work out
## a fingering — the backstop would run out underneath them.
func is_time_stopped() -> bool:
	return _time_stopped


## Stops everything and clears the field, without reporting a cleared track.
func halt() -> void:
	_phase = Phase.IDLE
	_time_stopped = false
	_clear_drones()


## Re-read the play area every frame so the room survives a window resize.
func advance(delta: float, field: Rect2) -> void:
	# A long frame must not skip Demo's held beat and let a drone fire through it.
	if delta <= MAX_FRAME_STEP:
		_advance_step(delta, field)
		return
	var remaining := delta
	while remaining > 0.0:
		var slice := minf(remaining, MAX_FRAME_STEP)
		_advance_step(slice, field)
		remaining -= slice
		if _time_stopped:
			break


## Fits the room to a new play area without letting the encounter clock move.
##
## The corridor is drawn from the field, and the field only ever reached this
## node through [method advance]. That is fine once a round is running, but a
## round is on screen before it is running — behind the router's fade, and for
## the two seconds the microphone spends measuring the room — and in those
## windows nothing advanced, so the room stayed at the placeholder size it was
## built with: a small corridor in the corner of the screen that snapped to
## full size the moment the soundcheck ended.
##
## Deliberately not `advance(0.0, field)`: a zero step would move nothing, but
## it would still run the phase through spawning and wave completion, so
## re-reading the screen could report events. This re-places the room and the
## bots standing in it, and nothing else.
func refresh_layout(field: Rect2) -> void:
	_field = JamBot.corridor_rect(field)
	_place_room(0.0, field)
	_advance_drones(0.0)
	_mark_front_target()


func _advance_step(delta: float, field: Rect2) -> void:
	# Firing anchors use the inset floor; the room fills the untrimmed frame.
	_field = JamBot.corridor_rect(field)

	# Demo stops the world at the beat and waits (§3). It is scoped to this
	# clock on purpose: a global `Engine.time_scale` would fight the shell's
	# round timer, its tweens and the pause overlay. Everything downstream is
	# driven from `step`, so the room, entry poses, wind-up fuses and the
	# chart cursor stop together and cannot drift apart while they are held.
	_time_stopped = (
		stop_time and _phase == Phase.ENCOUNTER and _beat_is_waiting()
	)
	var step := 0.0 if _time_stopped else delta
	_world_time += step

	match _phase:
		Phase.ADVANCING:
			_advance_elapsed += step
			if _advance_elapsed >= _advance_seconds:
				_start_wave()
		Phase.ENCOUNTER:
			_wave_elapsed += step
			_spawn_due_drones()
		Phase.IDLE:
			pass

	_place_room(step, field)

	_advance_drones(step)
	_mark_front_target()

	if _phase == Phase.ENCOUNTER and _wave_is_over():
		_finish_wave()


## Sways the camera and hands the room its frame for this step.
##
## Bobbing the field rather than this node's `position` is what keeps the
## corridor and the bots in one piece: they are placed from the same rect, so
## they sway together, while the rail's backdrop stays pinned to the frame and
## no gap can open at the edge of the screen.
func _place_room(step: float, field: Rect2) -> void:
	_update_bob(step, _phase == Phase.ADVANCING)
	_field.position += _bob

	if _rail == null:
		return
	var arena := _upcoming_index() if _phase == Phase.ADVANCING else maxi(_wave_index, 0)
	var transition := (
		clampf(_advance_elapsed / maxf(_advance_seconds, 0.001), 0.0, 1.0)
		if _phase == Phase.ADVANCING else 1.0
	)
	_rail.set_arena(arena, transition)
	_rail.update_rail(step, field, LANE_COUNT, _phase == Phase.ADVANCING, _bob)


## The camera's walk cycle.
##
## Vertical is `abs(sin)` rather than `sin` because a head drops on each
## footfall and rises between them — two dips per stride, not one — while the
## side-to-side sway is one full swing per stride, so it runs at half the rate.
## Getting that relationship wrong is what makes a bob read as a wobble.
##
## It is driven by `step`, so Demo's frozen world freezes the camera with it:
## stop-time has to stop *everything* or the freeze looks like a bug.
func _update_bob(step: float, advancing: bool) -> void:
	if _reduced_motion:
		# The room/banner still identifies an advance without camera movement.
		_bob = Vector2.ZERO
		return

	_bob_weight = lerpf(
		_bob_weight,
		1.0 if advancing else 0.0,
		clampf(step * BOB_BLEND, 0.0, 1.0)
	)
	var rate := lerpf(BOB_RATE_IDLE, BOB_RATE_ADVANCE, _bob_weight)
	var amount := lerpf(BOB_IDLE, BOB_ADVANCE, _bob_weight)
	_bob_phase = fposmod(_bob_phase + step * rate * TAU, TAU * 2.0)
	_bob = Vector2(
		sin(_bob_phase * 0.5) * amount * 0.8,
		-absf(sin(_bob_phase)) * amount
	)


## Where the camera's head is this frame, in pixels from rest.
func bob_offset() -> Vector2:
	return _bob


## A note was played: flare the player's own light on the rail (§5.2).
##
## Routed through the director rather than letting `gameplay.gd` reach into
## `_rail` directly, because the rail is the director's to own — the scene
## never learns it exists, and a future director that draws its world some
## other way stays a drop-in replacement.
func flash_rail(strength: float) -> void:
	if _rail != null:
		_rail.flash(strength)


## True when the front-most targetable bot has reached its beat and is waiting
## for an answer.
##
## Only the front-most is asked, because it is the only demand the player can
## see. `_mark_front_target()` puts the reticle on it and the HUD readout names
## its note, so a freeze held for a bot further back would stop the world for a
## note nothing on screen is asking for. The player would keep playing what
## they were told to play, keep getting NOISE because that bot is not in its
## window yet, and have no way to learn what the world is waiting for.
##
## It is worth being exact about what this is *not*: a bot further back is
## perfectly hittable, because `_front_most_in_window()` skips matches that are
## out of window. So this is not about what the rules allow. It is about what
## the screen says, which in Demo — a mode whose whole promise is that it
## teaches — is the part that matters.
func _beat_is_waiting() -> bool:
	var live := _live_drones()
	if live.is_empty():
		return false
	return live[0].time_to_beat() >= 0.0


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
		# costs points and the combo but never a life (§7.3). A phrase already
		# in progress is broken by it, which is the one place a wrong note
		# changes the field (§8.3).
		for drone in live:
			drone.on_wrong_note()
		_mark_front_target()
		return _judgement(
			Judgement.WRONG_NOTE, Tier.OUTSIDE, null, 0.0, -wrong_note_penalty
		)

	var target: JamBot = matches[0] if arcade_shots else _front_most_in_window(matches)
	if target == null:
		# The right note, but nothing is in its window yet. Treated as noise
		# rather than a wrong note: the player aimed at a real drone and was
		# only early, and punishing that teaches hesitation.
		return _judgement(Judgement.NOISE, Tier.OUTSIDE, null, 0.0, 0)

	var error := target.time_to_beat()
	var tier := tier_for(error, _effective_window())
	if arcade_shots and tier == Tier.OUTSIDE:
		tier = Tier.SNAP
	var points := note_points(tier, streak, cents_off, exact)
	var shot_position := target.aim_point()
	var shot_scale := target.scale.x
	var shot_ground := target.position
	# `strike()`, not `kill()`: most of the roster dies to one note, but a
	# [PlatedKnuckle] breaks one plate and keeps aiming. Asking the bot what a
	# correct note does to it is what let the roster grow without the matching
	# rule learning a second shape (§8.2).
	if not target.strike():
		return _judgement(Judgement.NOISE, Tier.OUTSIDE, null, 0.0, 0)

	var killed := not target.is_targetable()
	if not killed:
		target.react_to_hit()
	var judgement := _judgement(Judgement.HIT, tier, target, error, points, killed)
	judgement["shot_position"] = shot_position
	judgement["shot_scale"] = shot_scale
	judgement["shot_ground"] = shot_ground
	_mark_front_target()
	if killed:
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
		Tier.EDGE, Tier.SNAP:
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
		Tier.SNAP:
			return "HIT"
		_:
			return "MISS"


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if _rail != null:
		_rail.set_reduced_motion(enabled)
	for drone in _drones:
		drone.set_reduced_motion(enabled)


func set_effects_enabled(enabled: bool) -> void:
	_effects_enabled = enabled
	if _rail != null:
		_rail.set_effects_enabled(enabled)
	for drone in _drones:
		drone.set_effects_enabled(enabled)


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
func live_drones() -> Array[JamBot]:
	return _live_drones()


func staged_drones() -> Array[JamBot]:
	return _drones.duplicate()


func arena_index() -> int:
	return maxi(_upcoming_index() if _phase == Phase.ADVANCING else _wave_index, 0)


func travel_progress() -> float:
	return (
		clampf(_advance_elapsed / maxf(_advance_seconds, 0.001), 0.0, 1.0)
		if _phase == Phase.ADVANCING else 1.0
	)


func world_time() -> float:
	return _world_time


func wave_number() -> int:
	return _wave_index + 1


func wave_total() -> int:
	return _track.size()


## Name of the section being played, or the one the rail is travelling toward
## during an advance. Empty for a track with no sections — the practice builder
## makes one (§9.1).
##
## Authoring and diagnostics only. The HUD deliberately does not show it (§5.3).
func section_name() -> String:
	return _section_name_at(_upcoming_index() if _phase == Phase.ADVANCING else _wave_index)


## How long the current rail advance lasts. A chart's archetype sets it per
## section, so pacing is data (§8.5).
func advance_seconds() -> float:
	return _advance_seconds


func phase() -> Phase:
	return _phase


func _section_name_at(index: int) -> String:
	if index < 0 or index >= _track.size():
		return ""
	var wave: Dictionary = _track[index]
	return str(wave.get("section", ""))


## The wave the rail is currently travelling toward.
func _upcoming_index() -> int:
	return _wave_index + 1


func _start_advance() -> void:
	_phase = Phase.ADVANCING
	_advance_elapsed = 0.0

	var upcoming := _upcoming_index()
	_advance_seconds = RAIL_ADVANCE_SECONDS
	if upcoming >= 0 and upcoming < _track.size():
		var wave: Dictionary = _track[upcoming]
		_advance_seconds = maxf(
			float(wave.get("advance", RAIL_ADVANCE_SECONDS)), 0.0
		)
		var name := str(wave.get("section", ""))
		if not name.is_empty():
			section_started.emit(name, upcoming, _track.size())


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


## Stages one planned bot. This is the only place in the rules that names a
## roster key: everything after it asks the bot what it wants rather than
## checking what it is (§8.2).
func _spawn(plan: Dictionary) -> void:
	var lane := clampi(int(plan.get("lane", 1)), 0, LANE_COUNT - 1)
	var approach := float(plan.get("approach", 4.0))
	var windup := float(plan.get("windup", 1.6))
	var drone := _build_bot(plan, lane, approach, windup)

	drone.set_reduced_motion(_reduced_motion)
	drone.set_effects_enabled(_effects_enabled)
	drone.visual_scale = visual_scale
	drone.arena_index = _wave_index
	drone.firing_slot = _free_firing_slot(lane)
	drone.presentation_speed = presentation_speed
	drone.show_attack_bar = reports_damage
	_drones.append(drone)
	add_child(drone)
	# Placed once immediately so it never renders a frame at the origin.
	drone.advance(0.0, _field, LANE_COUNT)
	drone_spawned.emit(drone)


func _free_firing_slot(lane: int) -> int:
	var occupied: Array[int] = []
	for drone in _drones:
		if (
			is_instance_valid(drone) and drone.arena_index == _wave_index
			and drone.lane == lane and drone.occupies_firing_slot()
		):
			occupied.append(drone.firing_slot)
	var slot := 0
	while occupied.has(slot):
		slot += 1
	return slot


func _build_bot(
	plan: Dictionary,
	lane: int,
	approach: float,
	windup: float
) -> JamBot:
	var enemy := str(plan.get("enemy", ENEMY_RUSTY_CLANKY))
	var phrase: Variant = plan.get("notes", [])
	var sequence: Array = phrase if phrase is Array and not (phrase as Array).is_empty() else [
		int(plan.get("note", -1))
	]
	if enemy == ENEMY_PLATED_KNUCKLE:
		var knuckle := PlatedKnuckle.new()
		knuckle.configure_sequence(lane, sequence, approach, windup)
		return knuckle
	if enemy == ENEMY_SILENCER_SENTRY:
		var sentry := SilencerSentry.new()
		sentry.configure_echo(lane, int(plan.get("note", -1)), approach, windup)
		return sentry
	if enemy == ENEMY_CONDUCTOR:
		var conductor := DmjConductor.new()
		conductor.configure_motif(lane, sequence, approach, windup)
		return conductor
	if enemy != ENEMY_RUSTY_CLANKY:
		push_warning("Dead Metal Jam: unknown enemy '%s'; using Rusty Clanky." % enemy)

	var clanky := RustyClanky.new()
	clanky.configure(lane, int(plan.get("note", -1)), approach, windup)
	return clanky


func _advance_drones(delta: float) -> void:
	var survivors: Array[JamBot] = []
	for drone in _drones:
		if not is_instance_valid(drone):
			continue
		drone.visual_scale = visual_scale
		drone.presentation_speed = presentation_speed
		drone.show_attack_bar = reports_damage
		if drone.advance(delta, _field, LANE_COUNT):
			_wave_clean = false
			drone_fired.emit(drone)
		if drone.is_finished():
			drone.queue_free()
			continue
		survivors.append(drone)
	_drones = survivors


## Outlines the drone a note would hit right now — the "one bright target"
## convention Triangle Rush already uses (§5.2).
func _mark_front_target() -> void:
	var live := _live_drones()
	var front: JamBot = null
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


## Jam prioritizes gunshots; practice prioritizes the next unanswered beat.
## A partially answered phrase must not hold Demo past another bot's first beat.
func _live_drones() -> Array[JamBot]:
	var live: Array[JamBot] = []
	for drone in _drones:
		if is_instance_valid(drone) and drone.is_targetable():
			live.append(drone)
	live.sort_custom(
		func(a: JamBot, b: JamBot) -> bool:
			if arcade_shots:
				return a.time_until_fire() < b.time_until_fire()
			return a.time_to_beat() > b.time_to_beat()
	)
	return live


## Bots whose *current* demand is this pitch class. A multi-note enemy answers
## for the plate it is on, not for its whole phrase, so the front-most rule
## keeps working unchanged (§8.3).
func _matching_drones(
	live: Array[JamBot],
	played_pitch_class: int
) -> Array[JamBot]:
	if not pitch_matters:
		return live
	var matches: Array[JamBot] = []
	for drone in live:
		if drone.accepts_pitch_class(played_pitch_class):
			matches.append(drone)
	return matches


## The front-most matching drone that is actually inside a timing window.
## Front-most decides *which* drone; the window decides whether it is hittable
## yet, so a note played long before a drone arrives is early, not a mistake.
func _front_most_in_window(matches: Array[JamBot]) -> JamBot:
	var widen := _effective_window()
	for drone in matches:
		if tier_for(drone.time_to_beat(), widen) != Tier.OUTSIDE:
			return drone
	return null


## The window every judgement is actually measured against: the player's
## handicap and the mode's leniency multiplied, never one replacing the other.
func _effective_window() -> float:
	return window_scale * mode_window_scale


func _clear_drones() -> void:
	for drone in _drones:
		if is_instance_valid(drone):
			drone.queue_free()
	_drones = []


func _judgement(
	kind: Judgement,
	tier: Tier,
	drone: JamBot,
	time_error: float,
	points: int,
	killed := false
) -> Dictionary:
	return {
		"kind": kind,
		"tier": tier,
		"drone": drone,
		"time_error": time_error,
		"points": points,
		# True only when the bot actually died. A plate broken off a
		# [PlatedKnuckle] is a scoring hit that leaves the enemy standing, and
		# the HUD has to be able to tell those apart.
		"killed": killed,
	}
