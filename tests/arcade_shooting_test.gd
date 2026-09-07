extends SceneTree

## godot --headless --path ..\.. --script res://games/dead_metal_jam/tests/arcade_shooting_test.gd
const FIELD := Rect2(40.0, 190.0, 900.0, 480.0)
const STEP := 1.0 / 60.0

var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_attack_deadline()
	_test_arcade_window()
	_test_demo_survives_a_long_frame()
	_test_priority_and_positions()
	_test_arena_layout()
	_test_share_art_bounds()
	_test_plate_impact_position()
	_test_shot_records()
	_test_note_colors()
	_test_hit_reactions()
	_test_particle_feedback()
	await _test_gameplay_shots()
	_finish.call_deferred()


func _test_attack_deadline() -> void:
	for step in [STEP, 0.1, 0.37, 3.0]:
		var drone := RustyClanky.new()
		drone.configure(1, 40, 1.0, 1.0)
		drone.presentation_speed = 0.5
		drone.advance(0.0, FIELD, 3)
		var art: DmjDroneArt = drone.get_node("Art")
		_check(is_zero_approx(art.charge), "The attack bar starts empty without a numeric timer.")
		_check(is_equal_approx(art.beat_in, 2.0), "The bonus-beat cue respects the gameplay speed.")
		var elapsed := 0.0
		var fired := 0
		while elapsed < 3.0:
			var delta := minf(step, 3.0 - elapsed)
			elapsed += delta
			if drone.advance(delta, FIELD, 3):
				fired += 1
				_check(elapsed >= 2.0 - 0.0001, "A shot cannot fire before its advertised deadline.")
			if drone.is_targetable():
				_check(
					is_equal_approx(drone.time_until_fire(), maxf(2.0 - elapsed, 0.0)),
					"The countdown remains honest when a frame crosses the bonus beat."
				)
		_check(fired == 1, "Each attack emits exactly one shot, including a long frame.")
		_check(art.charge < 0.0, "A fired drone no longer advertises a pending attack.")
		drone.free()


func _test_arcade_window() -> void:
	for elapsed in [0.1, 1.6]:
		var director := _opened([_plan(1, 40, 0.0, 1.0, 2.0)])
		_advance(director, elapsed)
		var judgement := director.resolve_note(4, 0, 0.0, true)
		_check(
			int(judgement["kind"]) == EncounterDirector.Judgement.HIT
			and int(judgement["tier"]) == EncounterDirector.Tier.SNAP,
			"Correct Jam notes connect both before and after the strict beat window."
		)
		_check(
			int(judgement["points"]) > 0
			and int(judgement["points"]) < EncounterDirector.note_points(EncounterDirector.Tier.PERFECT, 0, 0.0, true),
			"Snap shots score, but beat-timed shots score more."
		)
		director.free()
	var expired := _opened([_plan(0, 40, 0.0, 0.2, 0.1)])
	_advance(expired, 0.4)
	_check(
		int(expired.resolve_note(4, 0)["kind"]) == EncounterDirector.Judgement.NOISE,
		"A projectile cannot retroactively kill a drone that fired."
	)
	expired.free()


func _test_priority_and_positions() -> void:
	var director := _opened([
		_plan(0, 40, 0.0, 3.0, 4.0),
		_plan(2, 40, 0.0, 4.0, 0.5),
		_plan(0, 45, 0.0, 3.0, 4.0),
	])
	director.set_reduced_motion(true)
	_advance(director, 0.4)
	var live := director.live_drones()
	_check(live[0].lane == 2, "Jam prioritizes the next actual gunshot, not old approach progress.")
	var positions: Array[Vector2] = []
	for drone in live:
		positions.append(drone.position)
	_check(
		not positions[1].is_equal_approx(positions[2]),
		"Simultaneous occupants of one lane receive separate firing positions."
	)
	_advance(director, 1.0)
	for index in range(live.size()):
		_check(
			live[index].position.is_equal_approx(positions[index]),
			"A drone holds its bay instead of walking toward the player."
		)
	var picked := director.resolve_note(4, 0)
	_check((picked["drone"] as JamBot).lane == 2, "Automatic aiming selects the urgent matching threat.")
	director.free()


func _test_demo_survives_a_long_frame() -> void:
	var director := _opened([_plan(1, 40, 0.0, 0.1, 0.05)])
	director.apply_mode(EncounterDirector.Mode.DEMO)
	var fired := [0]
	director.drone_fired.connect(func(_drone: JamBot) -> void: fired[0] += 1)
	director.advance(3.0, FIELD)
	_check(
		fired[0] == 0 and director.is_time_stopped() and director.live_drones().size() == 1,
		"Even a multi-second frame cannot bypass Demo's stop-time."
	)
	_check(
		int(director.resolve_note(4, 0)["kind"]) == EncounterDirector.Judgement.HIT,
		"The held beat remains answerable after the long frame."
	)
	director.free()


func _test_arena_layout() -> void:
	var names: Array[String] = []
	for room in range(3):
		names.append(DmjArenaLayout.arena_name(room))
		_check(names[room] == DmjArenaLayout.arena_name(room + 3), "Room identities cycle with the waves.")
		for count in [1, 3]:
			var floor_rect := JamBot.corridor_rect(FIELD)
			for lane in range(count):
				var anchors: Array[Vector2] = []
				for slot in range(3):
					var anchor := DmjArenaLayout.position(floor_rect, lane, count, room, slot)
					_check(floor_rect.has_point(anchor), "Every firing slot stays on the room's floor.")
					_check(not anchors.has(anchor), "Back-row anchors are distinct, including one-lane layouts.")
					anchors.append(anchor)
		for raw_field in [FIELD, Rect2(30, 160, 1100, 300)]:
			for lane in range(3):
				for slot in range(3):
					var drone := PlatedKnuckle.new()
					drone.configure_sequence(lane, [48, 52, 55], 3.0, 3.0)
					drone.arena_index = room
					drone.firing_slot = slot
					drone.visual_scale = DmjDroneArt.fit_scale(raw_field.size.y)
					drone.set_reduced_motion(true)
					drone.advance(0.0, JamBot.corridor_rect(raw_field), 3)
					var art: DmjDroneArt = drone.get_node("Art")
					var bounds: Rect2 = drone.transform * (art.transform * art.framed_bounds())
					_check(
						raw_field.grow(DmjRail.BACKDROP_PADDING).encloses(bounds),
						"Armor, note plates and firing labels fit the room at every deployed depth."
					)
					drone.free()
	_check(names[0] != names[1] and names[1] != names[2] and names[0] != names[2], "The three combat rooms have distinct names.")


func _test_plate_impact_position() -> void:
	var director := _opened([{
		"enemy": "plated_knuckle", "lane": 1, "notes": [48, 52, 55],
		"at": 0.0, "approach": 3.0, "windup": 3.0,
	}])
	_advance(director, 0.4)
	var drone := director.live_drones()[0]
	var before := drone.aim_point()
	var hit := director.resolve_note(0, 0)
	var impact: Vector2 = hit["shot_position"]
	_check(
		not bool(hit["killed"]) and impact.is_equal_approx(before),
		"A plate shot records the old plate position before the cursor advances."
	)
	_check(
		not drone.aim_point().is_equal_approx(before) and drone.required_note == 52,
		"The next note targets the next plate without moving the previous impact."
	)
	director.free()


func _test_share_art_bounds() -> void:
	var packed := load("res://games/dead_metal_jam/ui/share_art.tscn") as PackedScene
	var card := packed.instantiate() as Control
	card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	get_root().add_child(card)
	for dimensions: Vector2 in [Vector2(240, 290), Vector2(640, 360), Vector2(320, 180)]:
		card.size = dimensions
		card.call("_refresh_corridor")
		var portraits: Array = card.get("_portraits")
		for art: DmjDroneArt in portraits:
			var bounds: Rect2 = art.transform * art.framed_bounds()
			_check(
				Rect2(Vector2.ZERO, dimensions).encloses(bounds),
				"Share portraits keep their weapons and note plates inside the artwork frame."
			)
	card.free()


func _test_shot_records() -> void:
	var fx := DmjShotFx.new()
	get_root().add_child(fx)
	fx.set_field(FIELD)
	var target := FIELD.position + FIELD.size * Vector2(0.3, 0.5)
	fx.player_shot(target, false)
	fx.player_shot(target, true)
	fx.miss()
	fx.enemy_shot(target)
	var records: Array = fx.get("_shots")
	var expected := [DmjShotFx.Kind.PLATE, DmjShotFx.Kind.DOWN, DmjShotFx.Kind.MISS, DmjShotFx.Kind.HOSTILE]
	_check(records.size() == 4, "The four visual outcomes are represented independently.")
	for index in range(records.size()):
		var record: Dictionary = records[index]
		_check(int(record["kind"]) == expected[index], "The tracer agrees with the actual judgement.")
		for value in record.values():
			_check(not value is Node, "A shot cannot retain or damage a stale enemy node.")
	var restored: Vector2 = fx.call("_point", records[0]["destination"])
	_check(
		restored.is_equal_approx(target),
		"An impact lands on the supplied plate position."
	)
	fx.set_presentation_options(true, false)
	_check(fx.active_count() == 4, "Reduced effects retain essential shot-outcome markers.")
	fx.advance(DmjShotFx.LIFETIME + 0.01)
	_check(fx.active_count() == 0 and not fx.is_processing(), "Expired effects release their records and stop ticking.")
	for _index in range(DmjShotFx.MAX_SHOTS * 3):
		fx.miss()
	_check(fx.active_count() == DmjShotFx.MAX_SHOTS, "Rapid input cannot allocate unbounded effects.")
	fx.clear()
	_check(fx.active_count() == 0, "Replay can clear every tracer in one operation.")
	fx.free()


func _test_gameplay_shots() -> void:
	var settings := get_root().get_node("Settings")
	var values: Dictionary = settings.get("_values")
	var saved := values.duplicate(true)
	var save_timer: Timer = settings.get("_save_timer")
	var save_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	values.merge({
		DmjOptions.NOTE_SOURCE_KEY: DmjOptions.SOURCE_KEYBOARD,
		DmjOptions.MODE_KEY: DmjOptions.MODE_JAM,
		DmjOptions.TRACK_KEY: DmjOptions.TRACK_PRACTICE,
		Settings.ROUND_MODE_KEY: Settings.RoundMode.LIVES,
		Settings.STARTING_LIVES_KEY: 3,
		Settings.REDUCED_MOTION_KEY: true,
		Settings.VISUAL_EFFECTS_KEY: false,
	}, true)
	GameCatalog.select("dead_metal_jam")
	get_root().get_node("GameSession").call("configure_single_player")
	var packed := load("res://games/dead_metal_jam/gameplay.tscn") as PackedScene
	var game := packed.instantiate()
	_check(game.has_method("_on_drone_fired"), "The arcade scene script compiles.")
	if game.has_method("_on_drone_fired"):
		get_root().add_child(game)
		await process_frame
		await process_frame
		game.set_process(false)
		var fx: DmjShotFx = game.get("_shot_fx")
		fx.set_process(false)
		var director: EncounterDirector = game.get("_director")
		var router: NoteRouter = game.get("_router")
		director.set_track([{"drones": [
			{"enemy": "plated_knuckle", "lane": 1, "notes": [48, 52, 55],
				"at": 0.0, "approach": 3.0, "windup": 3.0},
			_plan(2, 57, 8.0, 1.0, 0.4),
		]}])
		director.begin()
		for _frame in range(180):
			game.call("_update_round", STEP, 60.0)
			if not director.live_drones().is_empty():
				break
		_check(
			(game.get_node("%DmjAttackBar") as Range).visible
			and not (game.get_node("%DmjThreat") as Label).text.contains("FIRE"),
			"The main HUD uses an attack bar, not a numeric FIRE timer."
		)
		_check(
			(game.get_node("%DmjTarget") as Label).get_theme_color("font_color") == DmjPalette.note_color(48)
			and (game.get_node("%DmjNoteStrip") as Range).value == 0.0,
			"The target and color key agree with the robot's C plate."
		)
		router.note_started.emit(NoteEvent.make(48, NoteEvent.Source.KEYBOARD))
		var shots: Array = fx.get("_shots")
		_check(
			int(shots.back()["kind"]) == DmjShotFx.Kind.PLATE
			and director.live_drones()[0].required_note == 52
			and shots.back()["color"] == DmjPalette.note_color(48),
			"A real musical input produces a plate-hit tracer and advances the phrase."
		)
		game.call("_update_target_readout")
		_check(
			(game.get_node("%DmjTarget") as Label).get_theme_color("font_color") == DmjPalette.note_color(52)
			and (game.get_node("%DmjHeard") as Label).get_theme_color("font_color") == DmjPalette.note_color(48),
			"The next target becomes E-colored while the heard note and previous shot remain C-colored."
		)
		router.note_started.emit(NoteEvent.make(59, NoteEvent.Source.KEYBOARD))
		shots = fx.get("_shots")
		_check(
			int(shots.back()["kind"]) == DmjShotFx.Kind.MISS
			and int((game.get("_lives") as Array)[0]) == 3,
			"A wrong note makes a miss tracer, never incoming damage."
		)
		for note in [48, 52, 55]:
			router.note_started.emit(NoteEvent.make(note, NoteEvent.Source.KEYBOARD))
		shots = fx.get("_shots")
		_check(int(shots.back()["kind"]) == DmjShotFx.Kind.DOWN, "A killing note has a distinct DOWN impact.")
		game.call("_update_target_readout")
		_check(
			(game.get_node("%DmjPromptCaption") as Label).text == "NO ACTIVE TARGETS"
			and not (game.get_node("%DmjAttackBar") as Range).visible
			and (game.get_node("%DmjNoteStrip") as Range).value == -1.0,
			"Breaking the last plate clears the phrase prompt and all active-target cues."
		)
		for _frame in range(700):
			game.call("_update_round", STEP, 60.0)
			if int((game.get("_lives") as Array)[0]) < 3:
				break
		shots = fx.get("_shots")
		_check(
			int((game.get("_lives") as Array)[0]) == 2
			and int(shots.back()["kind"]) == DmjShotFx.Kind.HOSTILE,
			"A real enemy gunshot is visible and spends exactly one life."
		)
		_check(
			float(game.get("_ending_left")) > 0.0,
			"The final shot remains visible briefly before results cover the battlefield."
		)
		game.call("_update_target_readout")
		_check(
			(game.get_node("%DmjPromptCaption") as Label).text == "TRACK CLEARED",
			"The final-shot interval does not keep asking for a completed phrase."
		)
		for _frame in range(ceili(DmjShotFx.RESULT_SETTLE / STEP) + 2):
			if not bool(game.get("_round_active")):
				break
			game.call("_update_round", STEP, 60.0)
		_check(not bool(game.get("_round_active")), "The feedback delay settles the round without a timer callback.")
		game.call("_on_play_again_pressed")
		_check(fx.active_count() == 0, "Replay leaves no previous-round bullets or callbacks.")
		game.set("_round_active", false)
		game.call("_finish_round")
		game.queue_free()
		await process_frame
		await process_frame
	else:
		game.free()
	values.clear()
	values.merge(saved, true)
	save_timer.stop()
	save_timer.process_mode = save_mode


func _test_note_colors() -> void:
	var colors: Array[Color] = []
	for note in range(12):
		var color := DmjPalette.note_color(note)
		_check(not colors.has(color), "Each chromatic note has its own color.")
		colors.append(color)
		_check(color == DmjPalette.note_color(note + 60), "The same note has the same color in every octave.")
		var light := color.srgb_to_linear().get_luminance()
		for background in [DmjDroneArt.NOTE_INK, DmjPalette.PANEL]:
			var dark: float = background.srgb_to_linear().get_luminance()
			_check((light + 0.05) / (dark + 0.05) >= 4.5, "Note colors retain readable glyph/HUD contrast.")
	_check(DmjPalette.note_color(-1) == DmjPalette.MUTED, "An absent note never impersonates a pitch color.")


func _test_hit_reactions() -> void:
	var drone := PlatedKnuckle.new()
	drone.configure_sequence(1, [48, 52, 55], 3.0, 3.0)
	drone.advance(0.4, FIELD, 3)
	var art: DmjDroneArt = drone.get_node("Art")
	var deadline := drone.time_until_fire()
	drone.react_to_hit()
	drone.advance_feedback(0.045)
	_check(not is_zero_approx(art.rotation) and art.hit_flash > 0.0, "Hits visibly rock and flash the armor.")
	_check((art.transform * art.ground_offset()).is_zero_approx(), "Hit recoil keeps the feet planted.")
	_check(
		drone.aim_point().is_equal_approx(drone.transform * (art.transform * art.target_offset())),
		"Auto-aim follows the recoiling plate instead of its old pose."
	)
	_check(is_equal_approx(deadline, drone.time_until_fire()), "Cosmetic recoil never changes the firing deadline.")
	drone.set_reduced_motion(true)
	_check(art.rotation == 0.0 and art.scale == Vector2.ONE and art.hit_flash == 0.0, "Reduced motion removes recoil and hit flashes.")
	drone.set_reduced_motion(false)
	drone.set_effects_enabled(false)
	_check(art.rotation == 0.0 and art.hit_flash == 0.0, "The effects toggle also suppresses intensive hit reactions.")
	drone.kill()
	drone.advance_feedback(JamBot.DEATH_FADE + 0.01)
	_check(is_zero_approx(art.self_modulate.a), "A confirmed kill finishes fading even during Demo's held beat.")
	drone.free()


func _test_particle_feedback() -> void:
	var fx := DmjShotFx.new()
	get_root().add_child(fx)
	fx.set_field(FIELD)
	fx.player_shot(FIELD.get_center(), true, 52)
	_check(not (fx.get("_particles") as Array).is_empty(), "A kill creates sparks, debris, smoke and a shell casing.")
	var kinds: Array[int] = []
	for particle: Dictionary in fx.get("_particles"):
		if not kinds.has(int(particle["kind"])):
			kinds.append(int(particle["kind"]))
	_check(kinds.size() == 4, "All four cosmetic particle types are exercised by a kill.")
	fx.set_presentation_options(true, true)
	_check((fx.get("_particles") as Array).is_empty() and fx.active_count() == 1, "Reduced motion clears particles without hiding the hit.")
	fx.player_shot(FIELD.get_center(), false, 48)
	_check((fx.get("_particles") as Array).is_empty(), "Reduced motion cannot emit new particles.")
	fx.set_presentation_options(false, false)
	fx.miss()
	_check((fx.get("_particles") as Array).is_empty(), "Disabled effects keep only essential static feedback.")
	fx.set_presentation_options(false, true)
	for _index in range(100):
		fx.player_shot(FIELD.get_center(), true, 67)
	_check(
		(fx.get("_particles") as Array).size() <= DmjShotFx.MAX_PARTICLES
		and fx.active_count() <= DmjShotFx.MAX_SHOTS,
		"Dense musical input stays within both effect budgets."
	)
	fx.advance(DmjShotFx.LIFETIME + 0.01)
	_check((fx.get("_particles") as Array).is_empty() and not fx.is_processing(), "Expired particles stop processing and release their records.")
	fx.player_shot(FIELD.get_center(), true, 48)
	fx.clear()
	_check((fx.get("_particles") as Array).is_empty() and fx.active_count() == 0, "Replay clears particle trails and shots together.")
	fx.free()


func _opened(plans: Array) -> EncounterDirector:
	var director := EncounterDirector.new()
	get_root().add_child(director)
	director.set_track([{"drones": plans}])
	director.begin()
	_advance(director, EncounterDirector.RAIL_ADVANCE_SECONDS + STEP)
	return director


func _advance(director: EncounterDirector, seconds: float) -> void:
	for _frame in range(int(round(seconds / STEP))):
		director.advance(STEP, FIELD)


func _plan(lane: int, note: int, at: float, approach: float, windup: float) -> Dictionary:
	return {"lane": lane, "note": note, "at": at, "approach": approach, "windup": windup}


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		printerr("ERROR: %s" % failure)
	if _failures.is_empty():
		print("Arcade shooting tests passed. (%d checks)" % _checks)
	quit(0 if _failures.is_empty() else 1)
