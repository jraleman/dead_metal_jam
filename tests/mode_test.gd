extends SceneTree

## Headless tests for the three modes (§3): Jam, Rhythm and Demo.
##
## Split out of `encounter_test.gd`, which covers the rules themselves — which
## drone a note resolves against, what tier it earned, when a wave is done.
## This file asks a different question, and the only question milestone 7
## actually makes a claim about: **are the modes really just flags?**
##
## That claim is falsifiable, which is why it is worth a file. If Rhythm ever
## needs its own matching path, or Demo its own clock, the tests below are the
## ones that stop compiling — not the ones that quietly still pass.
##
## Nothing here renders. Drones are advanced by hand at a fixed timestep, so
## every timing assertion is deterministic rather than frame-rate dependent.
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/mode_test.gd

## A play area big enough that lane maths never degenerates.
const FIELD := Rect2(Vector2(40.0, 190.0), Vector2(800.0, 400.0))

## Fixed timestep, matching a 60 Hz frame.
const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_test_modes_are_only_flags()
	_test_option_modes_match_the_rules()
	_test_jam_is_the_unchanged_default()

	_test_rhythm_has_no_wrong_note()
	_test_rhythm_keeps_timing_strict()

	_test_demo_stops_time_at_the_beat()
	_test_leaving_demo_unfreezes_the_world()
	_test_demo_only_waits_for_the_bot_on_screen()
	_test_demo_freezes_are_always_the_shown_bot()
	_test_demo_resumes_on_the_answer()
	_test_demo_never_lets_a_bot_fire()
	_test_demo_keeps_the_rail_moving_between_waves()
	_test_demo_widens_the_window()
	_test_demo_paces_a_phrase_plate_by_plate()
	_finish()


# --------------------------------------------------------------------------
# Modes


## The claim under test is narrow and worth stating exactly: switching mode
## must change *only* the four documented flags, and must be reversible. If a
## mode ever needs a fifth thing, this test is where that shows up.
func _test_modes_are_only_flags() -> void:
	var director := _director()

	director.apply_mode(EncounterDirector.Mode.JAM)
	_check(director.pitch_matters, "Jam cares which note was played.")
	_check(not director.stop_time, "Jam does not stop time.")
	_check(director.reports_damage, "Jam can cost a life.")
	_check(
		is_equal_approx(director.mode_window_scale, 1.0),
		"Jam does not widen the windows."
	)
	_check(director.mode() == EncounterDirector.Mode.JAM, "And reports itself as Jam.")

	director.apply_mode(EncounterDirector.Mode.RHYTHM)
	_check(not director.pitch_matters, "Rhythm ignores which note was played.")
	_check(not director.stop_time, "Rhythm does not stop time.")
	_check(director.reports_damage, "Rhythm can cost a life.")
	_check(
		is_equal_approx(director.mode_window_scale, 1.0),
		"Rhythm is strict: it does not widen the windows."
	)

	director.apply_mode(EncounterDirector.Mode.DEMO)
	_check(director.pitch_matters, "Demo still cares which note was played.")
	_check(director.stop_time, "Demo stops time.")
	_check(not director.reports_damage, "Demo never costs a life.")
	_check(
		is_equal_approx(
			director.mode_window_scale, EncounterDirector.DEMO_WINDOW_SCALE
		),
		"Demo is forgiving."
	)

	# Reversible, because the mode is a per-round option and a player who tries
	# Demo once must not be stuck in it.
	director.apply_mode(EncounterDirector.Mode.JAM)
	_check(
		director.pitch_matters
		and not director.stop_time
		and director.reports_damage
		and is_equal_approx(director.mode_window_scale, 1.0),
		"Going back to Jam restores every flag."
	)

	_check(
		EncounterDirector.mode_name(EncounterDirector.Mode.JAM) == "JAM"
		and EncounterDirector.mode_name(EncounterDirector.Mode.RHYTHM) == "RHYTHM"
		and EncounterDirector.mode_name(EncounterDirector.Mode.DEMO) == "DEMO",
		"Every mode has a name for the HUD."
	)
	director.free()


## [DmjOptions] repeats the mode numbers rather than importing them, so that it
## keeps its no-dependency rule. This is the check that stops the two drifting.
func _test_option_modes_match_the_rules() -> void:
	_check(
		DmjOptions.MODE_JAM == int(EncounterDirector.Mode.JAM),
		"The Jam option is the Jam rule."
	)
	_check(
		DmjOptions.MODE_RHYTHM == int(EncounterDirector.Mode.RHYTHM),
		"The Rhythm option is the Rhythm rule."
	)
	_check(
		DmjOptions.MODE_DEMO == int(EncounterDirector.Mode.DEMO),
		"The Demo option is the Demo rule."
	)
	_check(
		DmjOptions.DEFAULT_MODE == DmjOptions.MODE_JAM,
		"A player who never opens Settings gets the actual game."
	)


## A director nobody told about modes must behave exactly as it did before
## milestone 7 — the flags default to Jam.
func _test_jam_is_the_unchanged_default() -> void:
	var director := _director()
	_check(
		director.pitch_matters
		and not director.stop_time
		and director.reports_damage
		and is_equal_approx(director.mode_window_scale, 1.0)
		and director.mode() == EncounterDirector.Mode.JAM,
		"An untouched director is already in Jam mode."
	)
	director.free()


## Rhythm scores the attack, not the pitch (§3), so there is no such thing as a
## wrong note in it — the note the player did not mean still hits the robot in
## front of them.
func _test_rhythm_has_no_wrong_note() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.RHYTHM, [_drone_plan(1, 40, 0.0, 1.0)]
	)
	_run(director, 1.0)

	# 7 is G; the bot is asking for E. In Jam this is a wrong note.
	var judgement := director.resolve_note(7, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.HIT,
		"Any note hits in Rhythm mode."
	)
	_check(bool(judgement.get("killed", false)), "And it kills the robot.")
	_check(
		int(judgement.get("points", 0)) > 0,
		"And it scores like any other hit."
	)
	director.free()


## "Strict" in the §3 table is not decoration: Rhythm must not inherit Demo's
## leniency just because both are non-Jam.
func _test_rhythm_keeps_timing_strict() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.RHYTHM, [_drone_plan(1, 40, 0.0, 1.0)]
	)
	# 300 ms before the beat: outside even the edge window.
	_run(director, 0.7)
	_check(
		_kind(director.resolve_note(7, 0)) == EncounterDirector.Judgement.NOISE,
		"An early note in Rhythm is still early."
	)
	director.free()


func _test_demo_stops_time_at_the_beat() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO, [_drone_plan(1, 40, 0.0, 1.0, 1.5)]
	)
	_check(
		not director.is_time_stopped(),
		"A bot still walking in does not stop time."
	)

	_run(director, 1.0 + STEP * 2.0)
	_check(director.is_time_stopped(), "Time stops when the beat arrives.")

	var bot: JamBot = director.live_drones()[0]
	var beat := bot.time_to_beat()
	var walk := bot.approach_progress()
	var fuse := bot.windup_progress()
	_run(director, 3.0)

	_check(
		absf(bot.time_to_beat() - beat) < 0.0001,
		"The beat does not slide out from under the player."
	)
	_check(
		absf(bot.approach_progress() - walk) < 0.0001,
		"The walk holds."
	)
	_check(absf(bot.windup_progress() - fuse) < 0.0001, "The fuse holds.")
	_check(
		beat >= 0.0 and beat < STEP * 3.0,
		"And it freezes on the beat, not somewhere past it: %f" % beat
	)
	# Frozen on the beat means the note the player eventually plays is judged
	# against zero error, which is what "nobody can fail Demo" has to mean.
	_check(
		EncounterDirector.tier_for(beat) == EncounterDirector.Tier.PERFECT,
		"A note played into the freeze is PERFECT."
	)
	director.free()


## `_time_stopped` is sticky state, and mode is reversible, so leaving Demo
## while the world is held has to release it. Nothing else clears the flag
## until the next `advance()`, and in Jam that call would never set it — so
## without the reset in `apply_mode()` the round would be read as frozen by
## every caller that asks between the two, and `gameplay.gd` asks each frame
## to decide whether the round timer is paused.
func _test_leaving_demo_unfreezes_the_world() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO, [_drone_plan(1, 40, 0.0, 1.0, 1.5)]
	)
	_run(director, 1.0 + STEP * 2.0)
	_check(director.is_time_stopped(), "The world is held, as Demo intends.")

	director.apply_mode(EncounterDirector.Mode.JAM)
	_check(
		not director.is_time_stopped(),
		"Switching out of Demo releases the world at once."
	)

	var bot: JamBot = director.live_drones()[0]
	var fuse := bot.windup_progress()
	_run(director, 0.5)
	_check(
		bot.windup_progress() > fuse,
		"And the fuse it was holding starts burning again."
	)
	director.free()


## Demo may only hold the world for the bot the screen is pointing at.
##
## The reticle and the HUD readout both follow the front-most bot, so a freeze
## held for anything else is a freeze the player is never told how to end: they
## play the note they were shown, get NOISE because that bot is not in its
## window, and the world does not move. This is the test that stops
## `_beat_is_waiting()` from quietly growing into "any bot that is waiting".
##
## The arrangement is the one case where the two differ. A phrase that has just
## had a plate broken is front-most but *not* waiting — its next plate is
## 0.8 s out — while a single-note bot behind it reaches its beat inside that
## gap.
func _test_demo_only_waits_for_the_bot_on_screen() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO,
		[
			_plated_plan(0, [40, 45], 0.0, 1.0),
			_drone_plan(1, 55, 0.0, 1.4),
		]
	)
	_run(director, 1.0 + STEP * 2.0)
	_check(director.is_time_stopped(), "The world holds for the phrase.")
	_check(
		_kind(director.resolve_note(40 % 12, 0)) == EncounterDirector.Judgement.HIT,
		"The first plate takes the note it asked for."
	)

	# Into the plate gap, and far enough that the bot behind is clearly past
	# its beat rather than sitting on it to the microsecond.
	_run(director, 0.45)
	var live := director.live_drones()
	_check(live.size() == 2, "Both robots are still up.")

	var front := live[0]
	var behind := live[1]
	_check(
		front.roster_key() == "plated_knuckle",
		"The phrase is still the one on screen."
	)
	_check(front.time_to_beat() < 0.0, "It is between plates, so not waiting.")
	_check(behind.time_to_beat() >= 0.0, "The bot behind has reached its beat.")
	_check(
		not director.is_time_stopped(),
		"The world does not hold for a demand the screen is not making."
	)
	director.free()


## The invariant behind the rule above, checked continuously rather than at one
## arranged moment: whenever Demo has stopped the world, the bot the reticle is
## on is the bot that is waiting. A freeze the player can see is a freeze the
## player can end.
func _test_demo_freezes_are_always_the_shown_bot() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO,
		[
			_drone_plan(0, 40, 0.0, 1.0),
			_plated_plan(1, [45, 50], 0.4, 1.2),
			_drone_plan(2, 55, 0.8, 1.6),
		]
	)
	var frozen_steps := 0
	var violations := 0
	for _index in range(int(round(6.0 / STEP))):
		director.advance(STEP, FIELD)
		if not director.is_time_stopped():
			continue
		frozen_steps += 1
		var live := director.live_drones()
		if live.is_empty() or live[0].time_to_beat() < 0.0:
			violations += 1

	_check(frozen_steps > 0, "A three-robot wave does hold the world at least once.")
	_check(
		violations == 0,
		"Every held frame is held for the bot on screen (%d bad of %d)."
			% [violations, frozen_steps]
	)
	director.free()


func _test_demo_resumes_on_the_answer() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO,
		[_drone_plan(1, 40, 0.0, 1.0, 1.5), _drone_plan(0, 45, 4.0, 1.0, 1.5)]
	)
	_run(director, 1.0 + STEP * 2.0)
	_check(director.is_time_stopped(), "Stopped at the first beat.")

	# The second bot is scheduled four seconds into the wave and must not have
	# spawned while the world was held — the chart cursor stops too (§3).
	_run(director, 6.0)
	_check(
		director.live_drones().size() == 1,
		"The chart cursor is frozen too, so nothing new arrives."
	)

	_check(
		_kind(director.resolve_note(4, 0)) == EncounterDirector.Judgement.HIT,
		"The answer lands."
	)
	_run(director, STEP)
	_check(not director.is_time_stopped(), "And time starts again.")

	_run(director, 4.0)
	_check(
		director.live_drones().size() == 1,
		"The next bot then arrives on the resumed clock."
	)
	director.free()


## The §3 promise is "nobody can die" and "the run always finishes". The fuse
## holding is what makes the first half true without a special case.
func _test_demo_never_lets_a_bot_fire() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO, [_drone_plan(1, 40, 0.0, 1.0, 0.4)]
	)
	var fired := [0]
	director.drone_fired.connect(func(_d: JamBot) -> void: fired[0] += 1)

	# Ten seconds of doing nothing, against a fuse that burns in 0.4.
	_run(director, 1.0 + STEP * 2.0)
	_run(director, 10.0)
	_check(fired[0] == 0, "A held beat never burns down, however long it is held.")
	_check(
		not director.live_drones().is_empty(),
		"And the bot is still there to be played at."
	)
	director.free()


## Stop-time is scoped to the encounter, not to the round. Between waves there
## is no beat to answer, so freezing there would be a deadlock: nothing the
## player could play would ever start the clock again.
func _test_demo_keeps_the_rail_moving_between_waves() -> void:
	var director := _director()
	director.apply_mode(EncounterDirector.Mode.DEMO)
	director.set_track([
		_wave([_drone_plan(1, 40, 0.0, 1.0)]),
		_wave([_drone_plan(0, 45, 0.0, 1.0)]),
	])
	director.begin()
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + STEP)
	_run(director, 1.0 + STEP * 2.0)
	director.resolve_note(4, 0)
	_run(director, STEP)

	_check(
		director.phase() == EncounterDirector.Phase.ADVANCING,
		"The wave is cleared and the rail is travelling."
	)
	_check(
		not director.is_time_stopped(),
		"Nothing is waiting to be answered, so time runs."
	)
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + STEP)
	_check(
		director.phase() == EncounterDirector.Phase.ENCOUNTER,
		"So the advance completes and the next wave starts."
	)
	director.free()


## Demo is forgiving *before* the beat as well as at it — a player who rushes
## should be told they were early, not that they missed.
func _test_demo_widens_the_window() -> void:
	var early := 0.7  # 300 ms before the beat: outside Jam's edge window.

	var jam := _mode_director(
		EncounterDirector.Mode.JAM, [_drone_plan(1, 40, 0.0, 1.0)]
	)
	_run(jam, early)
	_check(
		_kind(jam.resolve_note(4, 0)) == EncounterDirector.Judgement.NOISE,
		"300 ms early is outside every Jam window."
	)
	jam.free()

	var demo := _mode_director(
		EncounterDirector.Mode.DEMO, [_drone_plan(1, 40, 0.0, 1.0)]
	)
	_run(demo, early)
	var judgement := demo.resolve_note(4, 0)
	_check(
		_kind(judgement) == EncounterDirector.Judgement.HIT,
		"The same note in Demo counts."
	)
	_check(
		int(judgement.get("tier", -1)) == EncounterDirector.Tier.EDGE,
		"And is honestly reported as late, not as perfect."
	)
	demo.free()


## The phrase enemy is where Demo earns its keep: each plate gets its own hold,
## so an armoured robot becomes a metronome the player can practise against.
func _test_demo_paces_a_phrase_plate_by_plate() -> void:
	var director := _mode_director(
		EncounterDirector.Mode.DEMO, [_plated_plan(1, [40, 45], 0.0, 1.0)]
	)
	_run(director, 1.0 + STEP * 2.0)
	_check(director.is_time_stopped(), "Stopped at the first plate's beat.")

	_check(
		_kind(director.resolve_note(4, 0)) == EncounterDirector.Judgement.HIT,
		"The first plate breaks."
	)
	_run(director, STEP)
	_check(
		not director.is_time_stopped(),
		"Breaking a plate hands the next beat back to the clock."
	)

	_run(director, PlatedKnuckle.PLATE_SECONDS + STEP * 2.0)
	_check(director.is_time_stopped(), "And time stops again at the second plate.")
	_check(
		_kind(director.resolve_note(9, 0)) == EncounterDirector.Judgement.HIT,
		"Which the second note answers."
	)
	_run(director, STEP)
	_check(director.live_drones().is_empty(), "The robot is down.")
	_check(not director.is_time_stopped(), "And nothing is holding the clock.")
	director.free()




# --------------------------------------------------------------------------
# Harness


func _director() -> EncounterDirector:
	var director := EncounterDirector.new()
	get_root().add_child(director)
	return director


## A director in one mode, already past its opening rail advance.
func _mode_director(mode: EncounterDirector.Mode, plans: Array) -> EncounterDirector:
	var director := _director()
	director.apply_mode(mode)
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


func _run(director: EncounterDirector, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for _index in range(steps):
		director.advance(STEP, FIELD)


func _kind(judgement: Dictionary) -> int:
	return int(judgement.get("kind", -1))


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Mode tests passed. (%d checks)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("Mode tests FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)
