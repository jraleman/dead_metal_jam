extends SceneTree

## Headless tests for the staging: how the encounter is *presented* rather than
## what it does (§8.1).
##
## Split out of `encounter_test.gd`, which had grown past the project's
## thousand-line limit, but the line it was split on is a real one. Everything
## here is a claim about what the player is shown — where the floor is, how a
## bot fakes depth, where the camera's head is, what the banner says — and none
## of it changes a rule. A test that fails in this file means the game looks
## wrong; a test that fails next door means it plays wrong.
##
## Nothing here renders. The corridor is geometry before it is pixels, so every
## claim below is checked against the numbers [DmjRail] and [JamBot] draw from,
## which is the part a screenshot could not pin down anyway.
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/staging_test.gd

## A play area big enough that lane maths never degenerates.
const FIELD := Rect2(Vector2(40.0, 190.0), Vector2(800.0, 400.0))

## Fixed timestep, matching a 60 Hz frame.
const STEP := 1.0 / 60.0

## `gameplay.gd` can never be *instantiated* headlessly — it extends
## [GameShell], which uses autoload instances (§9.8). The banner copy is
## deliberately static so it can be reached without an instance.
##
## This must stay a runtime [method @GDScript.load] and never become a
## `preload`: a preload is resolved when *this* script compiles, which drags
## `GameShell`'s `Settings` reference in before the autoloads exist and fails
## the whole file. By the time `_initialize()` runs, they are there.
const GAMEPLAY_PATH := "res://games/dead_metal_jam/gameplay.gd"

var _hud: GDScript
var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_hud = load(GAMEPLAY_PATH)
	_test_corridor_leaves_headroom()
	_test_drones_hold_firing_positions()
	_test_drone_fades_into_the_distance()
	_test_bots_use_the_arena_floor()
	_test_head_bob_moves_and_settles()
	_test_reduced_motion_holds_the_head_still()
	_test_stopped_time_stops_the_head()
	_test_banner_counts_waves()
	_test_advance_copy_never_names_a_section()
	_test_last_advance_gets_its_own_line()
	_test_combo_charge_boundaries()
	_test_rail_effects_can_be_cleared()
	_test_console_scene.call_deferred()


# --------------------------------------------------------------------------
# The corridor


## The floor is the play area minus the ceiling's strip, and both ends of that
## have to hold: too little headroom and there is no room to draw a ceiling in,
## too much and the bots lose the run-up that makes their approach readable.
func _test_corridor_leaves_headroom() -> void:
	var corridor := JamBot.corridor_rect(FIELD)

	_check(
		corridor.position.y > FIELD.position.y,
		"The corridor starts below the top of the play area."
	)
	_check(
		is_equal_approx(corridor.end.y, FIELD.end.y),
		"It still ends on the strike line."
	)
	_check(
		is_equal_approx(corridor.position.x, FIELD.position.x)
		and is_equal_approx(corridor.size.x, FIELD.size.x),
		"Only the top is trimmed; the corridor is as wide as the field."
	)
	_check(
		corridor.size.y > FIELD.size.y * 0.6,
		"Most of the play area is still floor, got %.0f%%."
		% (100.0 * corridor.size.y / FIELD.size.y)
	)

	# A resize can momentarily collapse the available field. A zero-height
	# corridor would divide by zero in every projection helper that reads it.
	var tiny := JamBot.corridor_rect(Rect2(Vector2.ZERO, Vector2(10.0, 0.0)))
	_check(tiny.size.y > 0.0, "A collapsed field still yields a usable corridor.")


# --------------------------------------------------------------------------
# Faking depth


func _test_drones_hold_firing_positions() -> void:
	var drone := RustyClanky.new()
	drone.configure(0, 40, 2.0, 1.0)
	_advance_drone(drone, JamBot.ENTRY_SECONDS + STEP)
	var initial_position := drone.position
	var initial_scale := drone.scale
	_advance_drone(drone, 1.9)
	_check(drone.scale.is_equal_approx(initial_scale), "Aiming does not grow a drone toward the camera.")
	_check(drone.position.is_equal_approx(initial_position), "A drone holds its firing position.")
	_check(
		drone.position.is_equal_approx(DmjArenaLayout.position(FIELD, 0, 3, 0)),
		"Enemy placement agrees with the scenery's firing position."
	)
	_check(drone.z_index > 0, "Depth still controls draw order.")
	drone.free()


## Distance costs a bot contrast, but never its glyph.
##
## The glyph is the note the player is being asked for, so fogging a far bot
## all the way into the dust would be asking a question in a colour nobody can
## read. The tint is checked at both ends: it has to do something at the far
## end, and nothing at all by the time the bot is worth aiming at.
func _test_drone_fades_into_the_distance() -> void:
	var drone := RustyClanky.new()
	drone.configure(0, 40, 2.0, 1.0)
	drone.firing_slot = 1
	drone.advance(0.0, FIELD, EncounterDirector.LANE_COUNT)
	var far := drone.modulate

	_check(far.v < 1.0, "A bot at the far end is dimmed by the dust between.")
	_check(
		far.v > 0.45,
		"But not so far that its glyph stops being readable, got value %.2f."
		% far.v
	)
	_check(
		is_equal_approx(far.a, 1.0),
		"The fog tints the bot; it must never make it transparent, which is "
		+ "what the death and muzzle fades use."
	)

	var front := RustyClanky.new()
	front.configure(0, 40, 2.0, 1.0)
	front.advance(0.0, FIELD, EncounterDirector.LANE_COUNT)
	_check(
		front.modulate.v > far.v,
		"The closer firing position is brighter."
	)
	_check(
		front.scale.x > drone.scale.x,
		"Back-row occupants are smaller rather than overlapping the front row."
	)
	front.free()
	drone.free()


# --------------------------------------------------------------------------
# The camera


## The play area is not the floor. [constant JamBot.HORIZON_HEADROOM] reserves
## a strip at the top for the ceiling, and a bot that ignored it would spawn in
## it — walking out of the roof rather than out of the far end.
##
## Checked against the shared inset rather than a number, so this test tracks
## the constant instead of having to be retuned alongside it.
func _test_bots_use_the_arena_floor() -> void:
	var director := _opened_director([_drone_plan(1, 45, 0.0, 3.0)])
	_run(director, 0.2)
	var drones := director.live_drones()
	if drones.is_empty():
		_check(false, "A bot must be on the field to place.")
		director.free()
		return

	var corridor := JamBot.corridor_rect(FIELD)
	var top := drones[0].position.y
	_check(
		top >= corridor.position.y - 1.0,
		"A bot spawns on the corridor floor, got y %.1f for a floor at %.1f."
		% [top, corridor.position.y]
	)

	_run(director, 3.0)
	var anchor := DmjArenaLayout.position(corridor, 1, 3, 0)
	_check(
		drones[0].position.distance_to(anchor) < EncounterDirector.BOB_ADVANCE * 2.0
		and drones[0].position.y < corridor.end.y - 24.0,
		"The drone remains in its firing bay instead of reaching the player's feet."
	)
	director.free()


## The head bob has to be motion, and it has to be motion that stays small.
##
## Both halves are the test. A bob that never moves is a static frame with
## extra code in it; a bob that wanders is a camera the player has to fight
## while reading where a bot is against the strike line, which is the one
## judgement the whole game rests on.
func _test_head_bob_moves_and_settles() -> void:
	var director := _opened_director([_drone_plan(1, 45, 4.0, 3.0)])

	var seen: Array[Vector2] = []
	var furthest := 0.0
	for _index in range(90):
		director.advance(STEP, FIELD)
		var bob := director.bob_offset()
		seen.append(bob)
		furthest = maxf(furthest, bob.length())

	var moved := false
	for bob in seen:
		if not bob.is_equal_approx(seen[0]):
			moved = true
			break
	_check(moved, "The camera is not perfectly still.")
	_check(furthest > 0.05, "It moves far enough to be seen at all.")
	_check(
		furthest <= EncounterDirector.BOB_ADVANCE * 1.5,
		"And never further than a march's worth, got %.2f px." % furthest
	)

	var below := 0
	for bob in seen:
		if bob.y <= 0.001:
			below += 1
	_check(
		below == seen.size(),
		"The head only ever dips: a bob that rose above rest would lift the "
		+ "strike line off the floor it marks."
	)
	director.free()


## Reduced motion is the one setting a swaying viewport is squarely aimed at,
## so the bob does not shrink — it stops. Nothing is lost: the rail still
## scrolls, which is what tells an advance from a stall.
func _test_reduced_motion_holds_the_head_still() -> void:
	var director := _opened_director([_drone_plan(1, 45, 4.0, 3.0)])
	director.set_reduced_motion(true)

	var moved := 0
	for _index in range(120):
		director.advance(STEP, FIELD)
		if not director.bob_offset().is_zero_approx():
			moved += 1
	_check(moved == 0, "Reduced motion holds the camera exactly still.")

	director.set_reduced_motion(false)
	var woke := false
	for _index in range(90):
		director.advance(STEP, FIELD)
		if not director.bob_offset().is_zero_approx():
			woke = true
			break
	_check(woke, "And gives it back when the setting is turned off.")
	director.free()


## Demo stops the world at the beat. If the camera kept bobbing through the
## freeze, the one moment the game is asking the player to stop and look would
## be the one moment the picture would not hold still.
func _test_stopped_time_stops_the_head() -> void:
	var director := _opened_director([_drone_plan(1, 45, 0.5, 0.5)])
	director.apply_mode(EncounterDirector.Mode.DEMO)
	_run(director, 1.4)
	_check(director.is_time_stopped(), "The world is frozen to test this.")

	var held := director.bob_offset()
	var drifted := false
	for _index in range(60):
		director.advance(STEP, FIELD)
		if not director.bob_offset().is_equal_approx(held):
			drifted = true
	_check(not drifted, "The camera is frozen with everything else.")
	_check(
		director.is_time_stopped(),
		"And the freeze is still the reason it is."
	)
	director.free()


# --------------------------------------------------------------------------
# The HUD's words


## The banner counts waves, and counts them the way a person does.
##
## Off-by-one here is the kind of bug nobody files and everybody notices: a
## five-section song that opens on "WAVE 0 / 5" or ends on "WAVE 4 / 5" reads
## as broken even though every rule underneath it is correct.
func _test_banner_counts_waves() -> void:
	_check(
		_hud._progress_caption(0, 5) == "WAVE 1 / 5",
		"The first wave is wave 1, got '%s'." % _hud._progress_caption(0, 5)
	)
	_check(
		_hud._progress_caption(4, 5) == "WAVE 5 / 5",
		"And the last wave is the total, got '%s'."
		% _hud._progress_caption(4, 5)
	)
	_check(
		_hud._progress_caption(0, 1) == "WAVE 1 / 1",
		"A one-wave track still reads sensibly."
	)


## Section names are authoring vocabulary and must not reach the player (§5.3).
##
## Checked against the shipped chart's own names rather than a hardcoded list,
## so renaming a section in `track_01.tres` cannot quietly slip a new word past
## this test. The names must still *exist* — they are how the chart is read by
## whoever is editing it — they just must not be quoted back at the player.
func _test_advance_copy_never_names_a_section() -> void:
	var chart: JamChart = load("res://games/dead_metal_jam/chart/charts/track_01.tres")
	if chart == null:
		_check(false, "The shipped chart must load to check its names.")
		return

	var names: Array[String] = []
	for section in chart.sections:
		var nm := str(section.name).strip_edges()
		if not nm.is_empty():
			names.append(nm.to_upper())
	_check(not names.is_empty(), "The chart still names its sections for authors.")

	var lines: Array = _hud.ADVANCE_LINES.duplicate()
	lines.append(_hud.LAST_ADVANCE_LINE)
	for line: String in lines:
		_check(not line.strip_edges().is_empty(), "No advance line is blank.")
		for nm in names:
			_check(
				not line.to_upper().contains(nm),
				"Advance copy must not name a section, but '%s' contains '%s'."
				% [line, nm]
			)


## The final advance says something different, and only the final advance does.
##
## The boundary is the test: `index >= total - 1` is one character away from
## announcing the last stretch a wave early, or never announcing it at all.
func _test_last_advance_gets_its_own_line() -> void:
	var last: String = _hud.LAST_ADVANCE_LINE
	_check(
		_hud._advance_line(4, 5) == last,
		"The fifth of five advances is the last stretch."
	)
	for index in range(4):
		_check(
			_hud._advance_line(index, 5) != last,
			"But advance %d of 5 is not, got '%s'."
			% [index + 1, _hud._advance_line(index, 5)]
		)

	# A one-wave track's only advance is the opening one, which shows no
	# banner at all — so "last stretch" would be a line nobody ever earns.
	_check(
		_hud._advance_line(0, 1) != last,
		"A single-wave track does not open on the last stretch."
	)

	# The rotation has to survive a track longer than the list of lines.
	for index in range(12):
		_check(
			not str(_hud._advance_line(index, 13)).is_empty(),
			"A long track never runs out of things to say."
		)


# --------------------------------------------------------------------------
# The instrument console


func _test_combo_charge_boundaries() -> void:
	var cases := {
		0: Vector2i(0, 5), 4: Vector2i(0, 5),
		5: Vector2i(5, 15), 14: Vector2i(5, 15),
		15: Vector2i(15, 30), 29: Vector2i(15, 30),
		30: Vector2i(30, 30), 80: Vector2i(30, 30),
	}
	for streak: int in cases:
		_check(
			DmjPerformanceHud.combo_band(streak) == cases[streak],
			"Combo charge must use the scoring ladder at streak %d." % streak
		)


func _test_rail_effects_can_be_cleared() -> void:
	var rail := DmjRail.new()
	var resting := rail._light_at(1.0)
	rail.flash(1.0)
	_check(rail._light_at(1.0) > resting, "A note lights the near floor.")
	rail.flash(0.0)
	_check(
		is_equal_approx(rail._light_at(1.0), resting),
		"Disabling effects clears an in-flight flare."
	)
	rail.flash(1.0)
	rail.set_reduced_motion(true)
	rail.flash(1.0)
	_check(
		is_equal_approx(rail._light_at(1.0), resting),
		"Reduced motion keeps the floor at its resting brightness."
	)
	rail.free()


func _test_console_scene() -> void:
	var packed := load("res://games/dead_metal_jam/gameplay.tscn") as PackedScene
	if packed == null:
		_check(false, "The console's gameplay scene must load.")
		_finish()
		return
	var settings := get_root().get_node("Settings")
	var values: Dictionary = settings.get("_values")
	var saved := values.duplicate(true)
	values[DmjOptions.NOTE_SOURCE_KEY] = DmjOptions.SOURCE_KEYBOARD
	values[DmjOptions.MODE_KEY] = DmjOptions.MODE_JAM
	values[DmjOptions.TRACK_KEY] = DmjOptions.TRACK_SONG_02
	values["accessibility/audio_captions"] = false
	GameCatalog.select("dead_metal_jam")
	get_root().get_node("GameSession").call("configure_single_player")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	get_root().add_child(viewport)
	var game := packed.instantiate()
	viewport.add_child(game)
	await process_frame
	await process_frame
	await process_frame
	await _check_room_is_fitted_while_the_round_waits(game, viewport)
	game.set_process(false)
	(game.get_node("%RoundTimer") as Timer).stop()
	var console: DmjPerformanceHud = game.get_node("%DmjPrompt")
	console.set_process(false)
	_check_console_feedback(game, console)
	await _check_console_layouts(game, console, viewport)

	game.set("_round_active", false)
	game.call("_finish_round")
	get_root().get_node("AudioManager").call("stop_music", 0.0)
	viewport.queue_free()
	await process_frame
	await process_frame
	values.clear()
	values.merge(saved, true)
	_finish.call_deferred()


## A round is on screen before it is advancing: behind the router's fade, and
## for the two seconds the microphone spends measuring the room. The corridor
## is drawn from the play area, and the play area used to be re-read only by
## the advance, so for all of that the room stayed at the placeholder size
## [EncounterDirector] is built with — a small corridor in the corner of the
## screen that snapped to full size the moment the soundcheck ended.
func _check_room_is_fitted_while_the_round_waits(
	game: Node, viewport: SubViewport
) -> void:
	var director: EncounterDirector = game.get("_director")
	var rail: DmjRail = director.get_node("Rail")
	var was_active := bool(game.get("_round_active"))
	game.set("_round_active", false)
	for dimensions: Vector2i in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		viewport.size = dimensions
		for _frame in range(3):
			await process_frame
		var play_area: Rect2 = game.call("_playfield_bounds")
		var room: Rect2 = rail.get("_field")
		_check(
			room.is_equal_approx(play_area),
			"A round on screen but not yet advancing still fills the %s play "
			% dimensions + "area: expected %s, got %s." % [play_area, room]
		)
	game.set("_round_active", was_active)


func _check_console_feedback(game: Node, console: DmjPerformanceHud) -> void:
	var router: NoteRouter = game.get("_router")
	var signal_meter: DmjSegmentedMeter = game.get_node("%DmjSignalMeter")
	var wave_meter: DmjSegmentedMeter = game.get_node("%DmjWaveMeter")
	var combo_meter: DmjSegmentedMeter = game.get_node("%DmjComboMeter")
	var feedback: Label = game.get_node("%DmjFeedback")
	var detail: Label = game.get_node("%DmjFeedbackDetail")
	var combo_hint: Label = game.get_node("%DmjComboHint")

	router.input_level_changed.emit(0.1)
	_check(is_equal_approx(signal_meter.value, 0.4), "The router drives the live input meter.")
	console._process(1.0)
	_check(is_zero_approx(signal_meter.value), "The signal decays to silence, not fake activity.")
	console.set_calibrating(true)
	_check(feedback.text == "KEEP IT QUIET", "Soundcheck must not invite the player to make noise.")
	console.set_calibrating(false)

	var director: EncounterDirector = game.get("_director")
	director.set_track([{"drones": [
		_drone_plan(1, 40, 0.0, 1.0), _drone_plan(0, 45, 0.0, 4.0),
	]}])
	director.begin()
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + 1.0)
	router.note_started.emit(NoteEvent.make(40, NoteEvent.Source.KEYBOARD, 0.8))
	_check(feedback.text == "PERFECT", "A real scored note reaches the console.")
	_check(detail.text.begins_with("+"), "The judgement includes its awarded points.")
	_check(is_equal_approx(signal_meter.value, 0.8), "Keyboard velocity also drives the meter.")
	_check(combo_hint.text == "4 NOTES TO x2", "The next multiplier counts actual scoring notes.")
	router.note_started.emit(NoteEvent.make(43, NoteEvent.Source.KEYBOARD))
	_check(feedback.text == "WRONG NOTE", "A wrong note is identified in text, not just colour.")
	_check(is_zero_approx(combo_meter.value), "A wrong note also clears combo charge.")

	director.apply_mode(EncounterDirector.Mode.RHYTHM)
	game.call("_update_target_readout")
	_check(
		(game.get_node("%DmjTarget") as Label).text == "ANY",
		"The large note display still describes Rhythm's rules."
	)
	director.apply_mode(EncounterDirector.Mode.DEMO)
	_run(director, 3.2)
	game.call("_update_target_readout")
	_check(
		(game.get_node("%DmjPromptCaption") as Label).text == "WAITING FOR YOU",
		"The console explains Demo's frozen beat."
	)
	director.halt()

	console.set_wave(2, 5)
	_check(
		wave_meter.value == 2.0 and wave_meter.marker == 2,
		"The third wave marks two completed waves and one current wave."
	)
	console.clear_wave(2)
	_check(wave_meter.value == 3.0, "A cleared wave fills its segment.")
	console.set_combo(30)
	_check(combo_hint.text == "MAX MULTIPLIER", "The combo ladder has an explicit ceiling.")
	_check(is_equal_approx(combo_meter.ratio, 1.0), "Maximum combo keeps a full meter.")
	console.reset_performance(5)
	_check(
		is_zero_approx(signal_meter.value) and is_zero_approx(wave_meter.value)
		and is_zero_approx(combo_meter.value) and wave_meter.marker == -1,
		"A replay clears every meter and the active wave marker."
	)
	console.set_track(null, "DEMO")
	_check(
		(game.get_node("%DmjTrackTitle") as Label).text == "FREE PLAY"
		and (game.get_node("%DmjTrackDetail") as Label).text.contains("DEMO"),
		"Practice tracks and mode changes have honest metadata."
	)

	var rail: DmjRail = director.get_node("Rail")
	game.call("_set_reduced_motion_enabled", true)
	_check(bool(rail.get("_reduced_motion")), "Reduced motion reaches the live rail immediately.")
	game.call("_set_reduced_motion_enabled", false)
	director.flash_rail(1.0)
	game.call("_set_intense_effects_enabled", false)
	_check(is_zero_approx(float(rail.get("_flash"))), "Switching effects off clears the live flare.")


func _check_console_layouts(
	game: Node, console: DmjPerformanceHud, viewport: SubViewport
) -> void:
	var captions: Control = game.get_node("%AudioCaption")
	var director: EncounterDirector = game.get("_director")
	var values: Dictionary = get_root().get_node("Settings").get("_values")
	var attack_bar: Range = game.get_node("%DmjAttackBar")
	captions.set_process(false)
	attack_bar.show()
	for dimensions: Vector2i in [
		Vector2i(1920, 1080), Vector2i(960, 1700),
		Vector2i(1280, 720), Vector2i(2560, 1080), Vector2i(720, 960),
	]:
		viewport.size = dimensions
		values["accessibility/audio_captions"] = false
		captions.hide()
		console.show()
		for _frame in range(4):
			await process_frame
		var panel := console.get_global_rect()
		var screen := Rect2(Vector2.ZERO, Vector2(dimensions))
		_check(screen.encloses(panel), "The console fits the %s viewport." % dimensions)
		var top: Control = game.get_node("HUD/Overlay/Margins/Layout/TopBar")
		_check(screen.encloses(top.get_global_rect()), "The top bar fits %s." % dimensions)
		for name in [
			"DmjTarget", "DmjPromptCaption", "DmjHeard",
			"DmjFeedback", "DmjFeedbackDetail", "DmjStatus", "DmjThreat",
		]:
			var label: Label = game.get_node("%%%s" % name)
			_check(
				panel.grow(0.5).encloses(label.get_global_rect()),
				"%s stays inside the console at %s." % [name, dimensions]
			)
		for name in ["DmjAttackBar", "DmjNoteStrip"]:
			var meter: Range = game.get_node("%%%s" % name)
			_check(
				panel.grow(0.5).encloses(meter.get_global_rect()),
				"%s stays inside the console at %s." % [name, dimensions]
			)
		var bounds: Rect2 = game.call("_playfield_bounds")
		_check(
			bounds.end.y + DmjDroneArt.foot_clearance(director.visual_scale) <= panel.position.y + 0.5,
			"Drone feet clear the console at %s." % dimensions
		)
		captions.custom_minimum_size.y = 64.0
		values["accessibility/audio_captions"] = true
		var reserved: Rect2 = game.call("_playfield_bounds")
		captions.show()
		for _frame in range(3):
			await process_frame
		bounds = game.call("_playfield_bounds")
		_check(
			bounds.end.y + DmjDroneArt.foot_clearance(director.visual_scale) <= captions.get_global_rect().position.y + 0.5,
			"Audio captions also reserve playfield room at %s." % dimensions
		)
		_check(
			is_equal_approx(bounds.end.y, reserved.end.y),
			"Showing a caption keeps the firing floor at %s: expected %.3f, got %.3f." % [
				dimensions, reserved.end.y, bounds.end.y,
			]
		)
		captions.hide()
		await process_frame
		bounds = game.call("_playfield_bounds")
		_check(
			is_equal_approx(bounds.end.y, reserved.end.y),
			"Hiding a caption keeps the firing floor at %s: expected %.3f, got %.3f." % [
				dimensions, reserved.end.y, bounds.end.y,
			]
		)
		for shown: bool in [false, true]:
			attack_bar.visible = shown
			for _frame in range(3):
				await process_frame
			bounds = game.call("_playfield_bounds")
			_check(
				is_equal_approx(bounds.end.y, reserved.end.y),
				"Attack-bar visibility does not move the firing floor at %s." % dimensions
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
	director.set_track([{"drones": plans}])
	director.begin()
	_run(director, EncounterDirector.RAIL_ADVANCE_SECONDS + STEP)
	return director


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


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Staging tests passed. (%d checks)" % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr("ERROR: %s" % failure)
	printerr("Staging tests FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)
