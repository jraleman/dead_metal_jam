extends SceneTree

## Headless tests for the encounter rules: [RustDrone], [EncounterDirector] and
## [DmjTrackBuilder].
##
## These are the game's rules, deliberately kept in scripts that touch no
## autoload instance so they can be driven directly here. `gameplay.gd` extends
## [GameShell], which does use autoloads, so it can never be named in a headless
## `--script` run — which is exactly why the rules do not live in it.
##
## Nothing below renders. Drones are advanced by hand with a fixed timestep, so
## every timing assertion is deterministic rather than frame-rate dependent.
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/encounter_test.gd

## A play area big enough that lane maths never degenerates.
const FIELD := Rect2(Vector2(40.0, 190.0), Vector2(800.0, 400.0))

## Fixed timestep, matching a 60 Hz frame.
const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_test_tier_windows()
	_test_tier_windows_widen()
	_test_combo_multiplier_steps()
	_test_note_points()
	_test_tier_names()

	_test_drone_walks_in()
	_test_drone_fires_once()
	_test_drone_kill_is_single_use()
	_test_drone_pitch_class()
	_test_drone_depth_grows()

	_test_empty_track_finishes()
	_test_rail_advance_precedes_the_first_wave()
	_test_early_note_is_noise()
	_test_note_on_arrival_is_a_hit()
	_test_wrong_note_costs_points()
	_test_note_between_waves_is_noise()
	_test_front_most_target_is_chosen()
	_test_one_note_kills_one_drone()
	_test_windup_fires_and_dirties_the_wave()
	_test_clean_wave_reports_clean()
	_test_track_cleared_after_last_wave()
	_test_rhythm_mode_accepts_any_note()
	_test_window_scale_widens_the_hit()

	_test_track_builder_shape()
	_test_track_builder_avoids_repeats()
	_test_track_builder_is_seedable()
	_test_track_builder_handles_empty_pool()
	_finish()


# --------------------------------------------------------------------------
# Timing tiers and scoring — pure statics, no scene needed.


func _test_tier_windows() -> void:
	_check(
		EncounterDirector.tier_for(0.0) == EncounterDirector.Tier.PERFECT,
		"Dead on the beat is PERFECT."
	)
	_check(
		EncounterDirector.tier_for(-0.059) == EncounterDirector.Tier.PERFECT,
		"Just inside the perfect window, early, is PERFECT."
	)
	_check(
		EncounterDirector.tier_for(0.10) == EncounterDirector.Tier.GOOD,
		"100 ms out is GOOD."
	)
	_check(
		EncounterDirector.tier_for(-0.20) == EncounterDirector.Tier.EDGE,
		"200 ms early is the edge tier."
	)
	_check(
		EncounterDirector.tier_for(0.40) == EncounterDirector.Tier.OUTSIDE,
		"400 ms out is outside every window."
	)


## The accessibility handicap is the only thing that moves the windows, and it
## must move all of them together or the tiers stop nesting.
func _test_tier_windows_widen() -> void:
	# 190 ms sits outside the 140 ms GOOD window but inside the 196 ms it
	# becomes at the maximum handicap.
	var late := 0.19
	_check(
		EncounterDirector.tier_for(late, 1.0) == EncounterDirector.Tier.EDGE,
		"At normal width, 190 ms is the edge tier."
	)
	_check(
		EncounterDirector.tier_for(late, 1.4) == EncounterDirector.Tier.GOOD,
		"At 140% width, 190 ms is promoted to GOOD."
	)
	_check(
		EncounterDirector.tier_for(0.30, 1.4) == EncounterDirector.Tier.EDGE,
		"At 140% width, 300 ms still lands inside the edge window."
	)


func _test_combo_multiplier_steps() -> void:
	var cases := {0: 1, 4: 1, 5: 2, 14: 2, 15: 4, 29: 4, 30: 8, 120: 8}
	for streak: int in cases:
		var expected: int = cases[streak]
		var actual := EncounterDirector.combo_multiplier(streak)
		_check(
			actual == expected,
			"A streak of %d earns x%d, got x%d" % [streak, expected, actual]
		)


func _test_note_points() -> void:
	# Base tier, no combo, no intonation bonus.
	_check(
		EncounterDirector.note_points(EncounterDirector.Tier.PERFECT, 0, 60.0) == 100,
		"A cold PERFECT out of tune is the base 100."
	)
	# Exact sources always earn the intonation bonus.
	_check(
		EncounterDirector.note_points(EncounterDirector.Tier.PERFECT, 0, 0.0, true) == 115,
		"MIDI is exact, so it always takes the 15% pitch bonus."
	)
	# Combo multiplies before the bonus is applied.
	_check(
		EncounterDirector.note_points(EncounterDirector.Tier.GOOD, 15, 90.0) == 240,
		"A GOOD at x4 combo is 60 * 4 = 240."
	)
	_check(
		EncounterDirector.note_points(EncounterDirector.Tier.OUTSIDE, 30) == 0,
		"A note outside every window scores nothing."
	)


func _test_tier_names() -> void:
	_check(
		EncounterDirector.tier_name(EncounterDirector.Tier.PERFECT) == "PERFECT",
		"Tier names reach the HUD as words, never as colour alone."
	)
	_check(
		EncounterDirector.tier_name(EncounterDirector.Tier.OUTSIDE) == "MISS",
		"The outside tier reads as MISS."
	)


# --------------------------------------------------------------------------
# RustDrone


func _test_drone_walks_in() -> void:
	var drone := RustDrone.new()
	drone.configure(1, 40, 2.0, 1.0)

	_check(drone.state == RustDrone.State.APPROACH, "A fresh drone is approaching.")
	_check(drone.time_to_beat() < 0.0, "Before arrival the beat is in the future.")
	_check(drone.is_targetable(), "An approaching drone can be shot.")

	_advance_drone(drone, 1.0)
	_check(
		absf(drone.approach_progress() - 0.5) < 0.02,
		"Halfway through the approach reads ~0.5, got %.3f" % drone.approach_progress()
	)

	# Stepped just past the boundary rather than exactly onto it: 60 steps of
	# 1/60 accumulate to slightly under a second, and a test that depends on
	# float addition landing on the nose is testing arithmetic, not the drone.
	_advance_drone(drone, 1.02)
	_check(drone.state == RustDrone.State.WINDUP, "Arrival starts the wind-up.")
	_check(
		absf(drone.time_to_beat()) < 0.05,
		"At arrival the timing error is ~0, got %.3f" % drone.time_to_beat()
	)
	drone.free()


## The fire transition is returned rather than polled, so a caller running at
## any frame rate sees it exactly once.
func _test_drone_fires_once() -> void:
	var drone := RustDrone.new()
	drone.configure(0, 45, 0.5, 0.5)

	var fires := 0
	for _index in range(120):
		if drone.advance(STEP, FIELD, EncounterDirector.LANE_COUNT):
			fires += 1

	_check(fires == 1, "A drone fires exactly once, got %d" % fires)
	_check(drone.state == RustDrone.State.FIRED, "It stays fired afterwards.")
	_check(not drone.is_targetable(), "A drone that fired is no longer a target.")
	_check(drone.is_finished(), "It leaves the field rather than lingering.")
	drone.free()


func _test_drone_kill_is_single_use() -> void:
	var drone := RustDrone.new()
	drone.configure(2, 50, 2.0, 1.0)

	_check(drone.kill(), "The first kill lands.")
	_check(not drone.kill(), "A second note cannot score the same drone twice.")
	_check(drone.state == RustDrone.State.DEAD, "A killed drone is dead.")
	_check(not drone.is_targetable(), "A dead drone is not a target.")

	_advance_drone(drone, RustDrone.DEATH_FADE + 0.05)
	_check(drone.is_finished(), "It is freed once the fade is done.")
	drone.free()

	var fired := RustDrone.new()
	fired.configure(0, 55, 0.2, 0.2)
	_advance_drone(fired, 1.0)
	_check(
		not fired.kill(),
		"A drone that already fired cannot be killed retroactively."
	)
	fired.free()


func _test_drone_pitch_class() -> void:
	var drone := RustDrone.new()
	drone.configure(0, 64, 1.0, 1.0)
	_check(drone.pitch_class() == 4, "E4 is pitch class 4, got %d" % drone.pitch_class())

	drone.configure(0, -1, 1.0, 1.0)
	_check(drone.pitch_class() == -1, "A drone with no note has no pitch class.")
	drone.free()


## Depth is faked with scale and draw order, so both must move with the walk or
## the lanes read flat (§8.1).
func _test_drone_depth_grows() -> void:
	var drone := RustDrone.new()
	drone.configure(0, 40, 2.0, 1.0)
	drone.advance(0.0, FIELD, EncounterDirector.LANE_COUNT)
	var near_horizon := drone.scale.x
	var horizon_y := drone.position.y
	var horizon_x := drone.position.x

	_advance_drone(drone, 2.0)
	_check(drone.scale.x > near_horizon, "A drone grows as it approaches.")
	_check(drone.position.y > horizon_y, "It walks down the screen.")
	_check(
		absf(drone.position.x - FIELD.get_center().x)
		> absf(horizon_x - FIELD.get_center().x),
		"Lanes spread apart as they near the camera."
	)
	_check(drone.z_index > 0, "Nearer drones draw over further ones.")
	drone.free()


# --------------------------------------------------------------------------
# EncounterDirector


func _test_empty_track_finishes() -> void:
	var director := _director()
	var cleared := [0]
	director.track_cleared.connect(func() -> void: cleared[0] += 1)

	director.set_track([])
	director.begin()

	_check(cleared[0] == 1, "An empty track is cleared immediately.")
	_check(director.is_finished(), "An empty track is finished on arrival.")
	director.free()


## The rail advance is the breathing room a music game needs; a wave must never
## land the instant the round starts (§8.1).
func _test_rail_advance_precedes_the_first_wave() -> void:
	var director := _director()
	director.set_track([_wave([_drone_plan(0, 40, 0.0, 2.0)])])
	director.begin()

	_check(
		director.phase() == EncounterDirector.Phase.ADVANCING,
		"The track opens on a rail advance."
	)
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS * 0.5)
	_check(director.live_drones().is_empty(), "Nothing has spawned mid-advance.")

	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS * 0.6)
	_check(
		director.phase() == EncounterDirector.Phase.ENCOUNTER,
		"The wave starts once the rail stops."
	)
	_check(director.live_drones().size() == 1, "And its first drone is on the field.")
	director.free()


func _test_early_note_is_noise() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	_run(director, 0.3)

	var judgement := director.resolve_note(4, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.NOISE,
		"The right note played far too early is noise, not a mistake."
	)
	_check(int(judgement.get("points", -1)) == 0, "Early notes cost nothing.")
	_check(director.live_drones().size() == 1, "The drone is still standing.")
	director.free()


func _test_note_on_arrival_is_a_hit() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	var killed := [0]
	director.drone_killed.connect(
		func(_drone: RustDrone, _j: Dictionary) -> void: killed[0] += 1
	)
	_run(director, 2.0)

	var judgement := director.resolve_note(4, 0, 0.0, true)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.HIT,
		"The right note at the strike line is a hit."
	)
	_check(
		int(judgement.get("tier", -1)) == EncounterDirector.Tier.PERFECT,
		"Landing on arrival is PERFECT."
	)
	_check(int(judgement.get("points", 0)) == 115, "PERFECT + exact source is 115.")
	_check(killed[0] == 1, "The kill is announced once.")
	_check(director.live_drones().is_empty(), "The drone is off the field.")
	director.free()


func _test_wrong_note_costs_points() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	_run(director, 2.0)

	var judgement := director.resolve_note(9, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.WRONG_NOTE,
		"A note matching no drone on the field is a wrong note."
	)
	_check(
		int(judgement.get("points", 0)) == -EncounterDirector.WRONG_NOTE_PENALTY,
		"A wrong note costs points."
	)
	_check(director.live_drones().size() == 1, "It kills nothing.")
	director.free()


## Between waves there is no valid target at all, so warming up must be free —
## that is the whole point of separating noise from a wrong note (§6).
func _test_note_between_waves_is_noise() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	_run(director, 2.0)
	director.resolve_note(4, 0)
	_run(director, 0.5)

	var judgement := director.resolve_note(9, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.NOISE,
		"With the field empty, any note is noise."
	)
	_check(int(judgement.get("points", -1)) == 0, "Noise never costs points.")
	director.free()


## Front-most is also the most urgent, so the intuitive read and the optimal
## read agree (§8.3).
func _test_front_most_target_is_chosen() -> void:
	var director := _opened_director([
		_drone_plan(0, 40, 0.0, 2.0),
		_drone_plan(2, 40, 0.6, 2.0),
	])
	_run(director, 2.0)

	var live := director.live_drones()
	_check(live.size() == 2, "Both drones are up, got %d" % live.size())
	var front: RustDrone = live[0]
	_check(front.lane == 0, "The drone that spawned first is front-most.")

	var judgement := director.resolve_note(4, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.HIT,
		"The note resolves against the front-most match."
	)
	_check(
		judgement.get("drone") == front,
		"And it is the front-most drone that dies."
	)
	director.free()


func _test_one_note_kills_one_drone() -> void:
	var director := _opened_director([
		_drone_plan(0, 40, 0.0, 2.0),
		_drone_plan(2, 40, 0.05, 2.0),
	])
	_run(director, 2.0)

	director.resolve_note(4, 0)
	_check(
		director.live_drones().size() == 1,
		"One note kills exactly one drone, front to back."
	)
	director.free()


func _test_windup_fires_and_dirties_the_wave() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 0.5, 0.4)])
	var fired := [0]
	var cleared: Array = []
	director.drone_fired.connect(func(_d: RustDrone) -> void: fired[0] += 1)
	director.wave_cleared.connect(
		func(_index: int, clean: bool) -> void: cleared.append(clean)
	)

	_run(director, 2.0)
	_check(fired[0] == 1, "An un-killed drone fires exactly once, got %d" % fired[0])
	_check(cleared.size() == 1, "The wave still ends.")
	_check(cleared[0] == false, "But it is not clean, so no section bonus is due.")
	director.free()


func _test_clean_wave_reports_clean() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 1.0, 2.0)])
	var cleared: Array = []
	director.wave_cleared.connect(
		func(_index: int, clean: bool) -> void: cleared.append(clean)
	)

	_run(director, 1.0)
	director.resolve_note(4, 0)
	_run(director, 0.5)

	_check(cleared.size() == 1, "Killing the last drone clears the wave.")
	_check(cleared[0] == true, "Nothing fired, so the wave is clean.")
	director.free()


func _test_track_cleared_after_last_wave() -> void:
	var director := _director()
	director.set_track([
		_wave([_drone_plan(0, 40, 0.0, 1.0, 2.0)]),
		_wave([_drone_plan(1, 45, 0.0, 1.0, 2.0)]),
	])
	var cleared := [0]
	var waves := [0]
	director.track_cleared.connect(func() -> void: cleared[0] += 1)
	director.wave_started.connect(
		func(_index: int, _total: int) -> void: waves[0] += 1
	)
	director.begin()

	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + 1.0)
	director.resolve_note(4, 0)
	_check(cleared[0] == 0, "One wave down is not the whole track.")

	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + 1.1)
	director.resolve_note(9, 0)
	_run(director, 0.2)

	_check(waves[0] == 2, "Both waves ran, got %d" % waves[0])
	_check(cleared[0] == 1, "The track is cleared once, got %d" % cleared[0])
	_check(
		director.is_finished(),
		"A drone still fading out must not hold the finished track open."
	)
	director.free()


## Rhythm mode is a flag on the rules, not a second code path (§3).
func _test_rhythm_mode_accepts_any_note() -> void:
	var director := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	director.pitch_matters = false
	_run(director, 2.0)

	var judgement := director.resolve_note(9, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.HIT,
		"With pitch off, any note kills the front-most drone."
	)
	director.free()


## The handicap has to reach the encounter, not just the tier maths, or the
## accessibility setting is decorative.
func _test_window_scale_widens_the_hit() -> void:
	var strict := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	_run(strict, 1.68)
	_check(
		_kind(strict.resolve_note(4, 0)) == EncounterDirector.Judgement.NOISE,
		"320 ms early is outside the default window."
	)
	strict.free()

	var eased := _opened_director([_drone_plan(1, 40, 0.0, 2.0)])
	eased.window_scale = 1.4
	_run(eased, 1.68)
	_check(
		_kind(eased.resolve_note(4, 0)) == EncounterDirector.Judgement.HIT,
		"The same note lands once the handicap widens the window."
	)
	eased.free()


# --------------------------------------------------------------------------
# DmjTrackBuilder


func _test_track_builder_shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pool: Array = [40, 45, 50, 55, 59, 64]
	var track := DmjTrackBuilder.build(pool, 4, rng)

	_check(track.size() == 4, "Four waves were asked for, got %d" % track.size())

	var previous_count := 0
	for wave_index in range(track.size()):
		var drones: Array = track[wave_index]["drones"]
		_check(not drones.is_empty(), "Wave %d has drones." % wave_index)
		_check(
			drones.size() >= previous_count,
			"Waves never get easier as the track goes on."
		)
		previous_count = drones.size()

		var last_at := -1.0
		for plan: Dictionary in drones:
			var lane := int(plan["lane"])
			_check(
				lane >= 0 and lane < EncounterDirector.LANE_COUNT,
				"Lane %d is on the field." % lane
			)
			_check(pool.has(int(plan["note"])), "Notes come from the game's pool.")
			var at := float(plan["at"])
			_check(at >= last_at, "Spawns are ordered, so arrivals are too.")
			last_at = at
			_check(
				float(plan["approach"]) >= DmjTrackBuilder.MIN_APPROACH_SECONDS,
				"No wave asks for an unreadable approach."
			)


## A repeat inside a wave would leave the readout unchanged after a kill, so
## the player cannot tell whether their note registered.
func _test_track_builder_avoids_repeats() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var track := DmjTrackBuilder.build([40, 45], 6, rng)

	for wave: Dictionary in track:
		var drones: Array = wave["drones"]
		for index in range(1, drones.size()):
			_check(
				int(drones[index]["note"]) != int(drones[index - 1]["note"]),
				"A wave never calls the same note twice in a row."
			)


func _test_track_builder_is_seedable() -> void:
	var first := RandomNumberGenerator.new()
	first.seed = 1234
	var second := RandomNumberGenerator.new()
	second.seed = 1234

	var left := DmjTrackBuilder.build([40, 45, 50], 3, first)
	var right := DmjTrackBuilder.build([40, 45, 50], 3, second)
	_check(str(left) == str(right), "The same seed builds the same track.")


func _test_track_builder_handles_empty_pool() -> void:
	var rng := RandomNumberGenerator.new()
	_check(
		DmjTrackBuilder.build([], 3, rng).is_empty(),
		"No notes means no track, rather than a crash."
	)
	_check(
		DmjTrackBuilder.build([40], 0, rng).is_empty(),
		"Zero waves means no track."
	)


# --------------------------------------------------------------------------
# Harness


func _director() -> EncounterDirector:
	var director := EncounterDirector.new()
	get_root().add_child(director)
	return director


## A director already past its opening rail advance, with one wave loaded.
func _opened_director(plans: Array) -> EncounterDirector:
	var director := _director()
	director.set_track([_wave(plans)])
	director.begin()
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + STEP)
	return director


func _wave(plans: Array) -> Dictionary:
	return {"drones": plans}


func _drone_plan(
	lane: int,
	note: int,
	at: float,
	approach: float,
	windup := 1.5
) -> Dictionary:
	return {
		"lane": lane,
		"note": note,
		"at": at,
		"approach": approach,
		"windup": windup,
	}


func _run(director: EncounterDirector, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _index in range(steps):
		director.advance(STEP, FIELD)


func _advance_drone(drone: RustDrone, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _index in range(steps):
		drone.advance(STEP, FIELD, EncounterDirector.LANE_COUNT)


func _kind(judgement: Dictionary) -> int:
	return int(judgement.get("kind", -1))


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Encounter tests passed. (%d checks)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("Encounter tests FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)
