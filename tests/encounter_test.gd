extends SceneTree

## Headless tests for the encounter rules: the [JamBot] roster and the
## [EncounterDirector] that runs them.
##
## These are the game's rules, deliberately kept in scripts that touch no
## autoload instance so they can be driven directly here. `gameplay.gd` extends
## [GameShell], which does use autoloads, so it can never be named in a headless
## `--script` run — which is exactly why the rules do not live in it.
##
## Two neighbours cover the rest of the encounter: `jam_chart_test.gd` covers
## what *produces* a track, and `mode_test.gd` covers what the three modes
## change about the rules below. A third, `staging_test.gd`, covers how the
## encounter is drawn — the corridor, the depth cues and the camera — none of
## which changes a rule, which is why it is not in here.
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

	_test_plated_knuckle_needs_every_note()
	_test_plated_knuckle_paces_its_plates()
	_test_plated_knuckle_falls_back_to_one_note()
	_test_wrong_note_breaks_a_started_phrase()
	_test_wrong_note_spares_an_untouched_phrase()
	_test_broken_phrase_stays_hittable()

	_test_director_spawns_the_charted_roster()
	_test_plate_hit_is_not_a_kill()
	_test_sections_are_announced_in_order()
	_test_unnamed_track_has_no_section()
	_test_wave_sets_its_own_advance()
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
# RustyClanky


func _test_drone_walks_in() -> void:
	var drone := RustyClanky.new()
	drone.configure(1, 40, 2.0, 1.0)

	_check(drone.state == RustyClanky.State.APPROACH, "A fresh drone is approaching.")
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
	_check(drone.state == RustyClanky.State.WINDUP, "Arrival starts the wind-up.")
	_check(
		absf(drone.time_to_beat()) < 0.05,
		"At arrival the timing error is ~0, got %.3f" % drone.time_to_beat()
	)
	drone.free()


## The fire transition is returned rather than polled, so a caller running at
## any frame rate sees it exactly once.
func _test_drone_fires_once() -> void:
	var drone := RustyClanky.new()
	drone.configure(0, 45, 0.5, 0.5)

	var fires := 0
	for _index in range(120):
		if drone.advance(STEP, FIELD, EncounterDirector.LANE_COUNT):
			fires += 1

	_check(fires == 1, "A drone fires exactly once, got %d" % fires)
	_check(drone.state == RustyClanky.State.FIRED, "It stays fired afterwards.")
	_check(not drone.is_targetable(), "A drone that fired is no longer a target.")
	_check(drone.is_finished(), "It leaves the field rather than lingering.")
	drone.free()


func _test_drone_kill_is_single_use() -> void:
	var drone := RustyClanky.new()
	drone.configure(2, 50, 2.0, 1.0)

	_check(drone.kill(), "The first kill lands.")
	_check(not drone.kill(), "A second note cannot score the same drone twice.")
	_check(drone.state == RustyClanky.State.DEAD, "A killed drone is dead.")
	_check(not drone.is_targetable(), "A dead drone is not a target.")

	_advance_drone(drone, RustyClanky.DEATH_FADE + 0.05)
	_check(drone.is_finished(), "It is freed once the fade is done.")
	drone.free()

	var fired := RustyClanky.new()
	fired.configure(0, 55, 0.2, 0.2)
	_advance_drone(fired, 1.0)
	_check(
		not fired.kill(),
		"A drone that already fired cannot be killed retroactively."
	)
	fired.free()


func _test_drone_pitch_class() -> void:
	var drone := RustyClanky.new()
	drone.configure(0, 64, 1.0, 1.0)
	_check(drone.pitch_class() == 4, "E4 is pitch class 4, got %d" % drone.pitch_class())

	drone.configure(0, -1, 1.0, 1.0)
	_check(drone.pitch_class() == -1, "A drone with no note has no pitch class.")
	drone.free()


## Depth is faked with scale and draw order, so both must move with the walk or
## the lanes read flat (§8.1).
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
		func(_drone: RustyClanky, _j: Dictionary) -> void: killed[0] += 1
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
	var front: RustyClanky = live[0]
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
	director.drone_fired.connect(func(_d: RustyClanky) -> void: fired[0] += 1)
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
# PlatedKnuckle — the roster's second demand (§8.2).


func _test_plated_knuckle_needs_every_note() -> void:
	var bot := PlatedKnuckle.new()
	bot.configure_sequence(1, [40, 45, 50], 2.0, 3.0)

	_check(bot.plate_count() == 3, "It carries the phrase it was given.")
	_check(bot.demand_size() == 3, "Its demand is how many notes are left.")
	_check(bot.required_note == 40, "It asks for the first note first.")
	_check(bot.accepts_pitch_class(4), "E is what it wants right now.")
	_check(not bot.accepts_pitch_class(9), "A is not, even though it comes later.")

	_check(bot.strike(), "The first note breaks a plate.")
	_check(bot.is_targetable(), "One plate off is not a kill.")
	_check(bot.required_note == 45, "It now asks for the second note.")
	_check(bot.demand_size() == 2, "Two notes to go.")

	_check(bot.strike(), "The second note breaks the second plate.")
	_check(bot.is_targetable(), "Still standing.")

	_check(bot.strike(), "The last note lands.")
	_check(not bot.is_targetable(), "And that one kills it.")
	_check(bot.state == PlatedKnuckle.State.DEAD, "It is dead, not fired.")
	_check(not bot.strike(), "A dead bot cannot be struck again.")
	bot.free()


## Each plate is its own beat. Without that the phrase is a mash, not a rhythm,
## and the timing tiers stop meaning anything after the first note.
func _test_plated_knuckle_paces_its_plates() -> void:
	var bot := PlatedKnuckle.new()
	bot.configure_sequence(1, [40, 45], 2.0, 2.0, 0.5)
	_advance_drone(bot, 2.0)
	_check(
		absf(bot.time_to_beat()) <= STEP,
		"The first plate's beat is the arrival, got %.3f" % bot.time_to_beat()
	)

	bot.strike()
	_check(
		bot.time_to_beat() < -0.4,
		"Breaking a plate pushes the next beat out by one interval."
	)
	_advance_drone(bot, 0.5)
	_check(
		absf(bot.time_to_beat()) <= STEP * 2.0,
		"And that beat arrives one interval later, got %.3f" % bot.time_to_beat()
	)

	# The wind-up has to cover the whole phrase, or the last plate is a coin
	# flip against the fire frame.
	_check(
		not bot.advance(STEP, FIELD, EncounterDirector.LANE_COUNT),
		"It has not fired while the phrase is still playable."
	)
	bot.free()


func _test_plated_knuckle_falls_back_to_one_note() -> void:
	var bot := PlatedKnuckle.new()
	bot.configure_sequence(0, [], 2.0, 2.0)
	_check(bot.plate_count() == 1, "An empty phrase is not an empty bot.")
	_check(bot.strike(), "It can still be struck.")
	_check(not bot.is_targetable(), "One note kills it.")
	bot.free()

	var widened := PlatedKnuckle.new()
	widened.configure_sequence(0, [40, 45, 50], 2.0, 0.1)
	_check(
		widened.windup_seconds >= PlatedKnuckle.windup_for(3),
		"A wind-up too short for the phrase is widened rather than trusted."
	)
	widened.free()


func _test_wrong_note_breaks_a_started_phrase() -> void:
	var director := _opened_director([_plated_plan(1, [40, 45], 0.0, 2.0)])
	_run(director, 2.0)

	var bot: PlatedKnuckle = director.live_drones()[0]
	_check(
		_kind(director.resolve_note(4, 0)) == EncounterDirector.Judgement.HIT,
		"The first note of the phrase lands."
	)
	_check(bot.cursor() == 1, "The phrase is one note in.")

	var judgement := director.resolve_note(7, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.WRONG_NOTE,
		"A note nothing on the field wants is a wrong note."
	)
	_check(bot.cursor() == 0, "It breaks the phrase back to the start.")
	_check(bot.required_note == 40, "So the readout asks for the first note again.")
	director.free()


## A bot the player has not engaged has nothing to lose. Charging it anyway
## would make every stray note a penalty against the whole field.
func _test_wrong_note_spares_an_untouched_phrase() -> void:
	var director := _opened_director([_plated_plan(1, [40, 45], 0.0, 2.0)])
	_run(director, 2.0)

	var bot: PlatedKnuckle = director.live_drones()[0]
	var beat_before := bot.time_to_beat()
	director.resolve_note(7, 0)
	_check(bot.cursor() == 0, "A phrase that never started cannot be broken.")
	_check(bot.required_note == 40, "It still wants its first note.")
	_check(bot.is_targetable(), "And it is still a target.")
	_check(
		absf(bot.time_to_beat() - beat_before) < 0.001,
		"Nor is its beat pushed out, which would cost the player the note they "
		+ "were about to play."
	)
	var judgement := director.resolve_note(4, 0, 0.0, true)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.HIT
		and int(judgement["tier"]) == EncounterDirector.Tier.PERFECT,
		"So the note they were lining up still lands PERFECT."
	)
	director.free()


## Resetting the cursor alone would leave the next beat already in the past,
## turning one wrong note into a guaranteed hit taken.
func _test_broken_phrase_stays_hittable() -> void:
	var director := _opened_director([_plated_plan(1, [40, 45], 0.0, 2.0)])
	_run(director, 2.0)
	director.resolve_note(4, 0)
	_run(director, PlatedKnuckle.PLATE_SECONDS)
	director.resolve_note(7, 0)

	var bot: PlatedKnuckle = director.live_drones()[0]
	_check(
		bot.time_to_beat() < 0.0,
		"The re-based beat is ahead of the player, not behind them."
	)
	_run(director, PlatedKnuckle.PLATE_SECONDS)
	_check(
		_kind(director.resolve_note(4, 0)) == EncounterDirector.Judgement.HIT,
		"So the phrase can be restarted and scored."
	)
	director.free()


# --------------------------------------------------------------------------
# Sections and the roster in the director (§8.5, §10).


func _test_director_spawns_the_charted_roster() -> void:
	var director := _opened_director([
		_drone_plan(0, 40, 0.0, 2.0),
		_plated_plan(1, [45, 50], 0.0, 2.0),
	])
	var live := director.live_drones()
	_check(live.size() == 2, "Both planned bots are on the field.")
	_check(
		live[0].roster_key() == "rusty_clanky",
		"A plan with no enemy key stages the default."
	)
	_check(
		live[1] is PlatedKnuckle and live[1].roster_key() == "plated_knuckle",
		"A plan that names an enemy stages that enemy."
	)
	_check(live[1].demand_size() == 2, "And it arrives carrying its phrase.")
	director.free()


## Scoring counts notes; the results screen counts robots. A plate hit is one
## and not the other, so the judgement has to say which it was.
func _test_plate_hit_is_not_a_kill() -> void:
	var director := _opened_director([_plated_plan(1, [40, 45], 0.0, 2.0)])
	var killed := [0]
	director.drone_killed.connect(
		func(_drone: JamBot, _j: Dictionary) -> void: killed[0] += 1
	)
	_run(director, 2.0)

	var first := director.resolve_note(4, 0)
	_check(_kind(first) == EncounterDirector.Judgement.HIT, "A plate hit scores.")
	_check(not bool(first["killed"]), "But it did not kill anything.")
	_check(int(first.get("points", 0)) > 0, "It is worth points all the same.")
	_check(killed[0] == 0, "No kill is announced for a plate.")
	_check(director.live_drones().size() == 1, "The bot is still walking.")

	_run(director, PlatedKnuckle.PLATE_SECONDS)
	var last := director.resolve_note(9, 0)
	_check(bool(last["killed"]), "The last note of the phrase kills.")
	_check(killed[0] == 1, "And that kill is announced exactly once.")
	director.free()


func _test_sections_are_announced_in_order() -> void:
	var director := _director()
	director.set_track([
		_named_wave("INTRO", [_drone_plan(0, 40, 0.0, 1.0, 2.0)], 1.0),
		_named_wave("CHORUS", [_drone_plan(1, 45, 0.0, 1.0, 2.0)], 0.5),
	])

	var announced: Array[String] = []
	var indices: Array[int] = []
	director.section_started.connect(
		func(name: String, index: int, total: int) -> void:
			announced.append(name)
			indices.append(index)
			_check(total == 2, "Every announcement knows the track length.")
	)
	director.begin()

	_check(
		",".join(announced) == "INTRO",
		"The opening advance names the first section."
	)
	_check(indices.size() == 1 and indices[0] == 0, "And numbers it from zero.")
	_check(director.section_name() == "INTRO", "The rail is travelling toward INTRO.")

	_run(director, 1.0 + 1.0)
	_check(director.section_name() == "INTRO", "The wave being played is INTRO.")
	director.resolve_note(4, 0)
	_run(director, STEP)

	_check(
		",".join(announced) == "INTRO,CHORUS",
		"Clearing a wave announces the next section, got %s" % str(announced)
	)
	_check(director.section_name() == "CHORUS", "And the banner follows the rail.")
	director.free()


## The practice ramp is a generated ramp, not a song, so it has no sections at
## all. This is the case that keeps "no section" distinguishable from "a
## section called something".
func _test_unnamed_track_has_no_section() -> void:
	var director := _director()
	var fired := [0]
	director.section_started.connect(
		func(_n: String, _i: int, _t: int) -> void: fired[0] += 1
	)
	director.set_track([_wave([_drone_plan(0, 40, 0.0, 1.0, 2.0)])])
	director.begin()

	_check(fired[0] == 0, "An unnamed wave announces nothing.")
	_check(director.section_name().is_empty(), "And reports no section name.")
	director.free()

	# A generated ramp has no structure to name, and naming it anyway would put
	# invented musicology in the chart data for no reader — the HUD stopped
	# showing section names, so nothing downstream would even surface the lie.
	var named := 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for wave: Dictionary in DmjTrackBuilder.build([40, 45, 50], 3, rng):
		if not str(wave.get("section", "")).is_empty():
			named += 1
	_check(named == 0, "The practice ramp names none of its waves.")


## Pacing is data: a section's archetype sets how much rail sits in front of it
## (§8.5), so the advance cannot be a constant any more.
func _test_wave_sets_its_own_advance() -> void:
	var director := _director()
	director.set_track([
		_named_wave("SLOW", [_drone_plan(0, 40, 0.0, 1.0, 2.0)], 3.0),
	])
	director.begin()

	_check(
		absf(director.advance_seconds() - 3.0) < 0.001,
		"The advance is the one the wave asked for, got %.2f" % director.advance_seconds()
	)
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + STEP)
	_check(
		director.phase() == EncounterDirector.Phase.ADVANCING,
		"A longer advance is still running when the default one would have ended."
	)
	_run(director, 3.0 - EncounterDirector.RAIL_ADVANCE_SECONDS)
	_check(
		director.phase() == EncounterDirector.Phase.ENCOUNTER,
		"And it ends when the wave's own advance is spent."
	)
	director.free()

	var quick := _director()
	quick.set_track([_named_wave("FAST", [_drone_plan(0, 40, 0.0, 1.0, 2.0)], 0.25)])
	quick.begin()
	_run(quick, 0.3)
	_check(
		quick.phase() == EncounterDirector.Phase.ENCOUNTER,
		"A short advance does not borrow the default's length."
	)
	quick.free()


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


## A wave the way a chart compiles one: named, and carrying its own rail.
func _named_wave(name: String, plans: Array, advance: float) -> Dictionary:
	return {"section": name, "advance": advance, "drones": plans}


func _plated_plan(
	lane: int,
	phrase: Array,
	at: float,
	approach: float,
	windup := 0.0
) -> Dictionary:
	return {
		"lane": lane,
		"note": phrase[0],
		"notes": phrase,
		"at": at,
		"approach": approach,
		"windup": maxf(windup, PlatedKnuckle.windup_for(phrase.size())),
		"enemy": "plated_knuckle",
	}


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


func _advance_drone(drone: JamBot, seconds: float) -> void:
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
