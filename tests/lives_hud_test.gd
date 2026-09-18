extends SceneTree

## godot --headless --path ..\.. --script res://games/dead_metal_jam/tests/lives_hud_test.gd
const GAME_ID := "dead_metal_jam"
const GAME_SCENE := "res://games/dead_metal_jam/gameplay.tscn"
const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _checks := 0
var _settings: Node
var _values: Dictionary
var _game: Node
var _viewport: SubViewport


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_settings = get_root().get_node("Settings")
	_values = _settings.get("_values")
	var saved := _values.duplicate(true)
	var save_timer: Timer = _settings.get("_save_timer")
	var save_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	var original_game := GameCatalog.current_id()

	_test_defaults()
	_test_saved_preferences()
	await _test_menu_and_briefing()
	if await _open_game():
		_test_lives_round()
		await _test_timer_and_replay()
		await _test_layouts()
		_test_accessibility()
		_test_demo()
		_test_track_clear()
		_game.set("_round_active", false)
		_game.call("_finish_round")
		_viewport.queue_free()
		await process_frame
		await process_frame

	_values.clear()
	_values.merge(saved, true)
	save_timer.stop()
	save_timer.process_mode = save_mode
	GameCatalog.select(original_game)
	_finish.call_deferred()


func _test_defaults() -> void:
	_values.erase(Settings.ROUND_MODE_KEY)
	for manifest in GameCatalog.all():
		GameCatalog.select(manifest.id)
		# Read the rule from the manifest rather than naming the games that
		# use it: several already default to lives, and a new one must not
		# have to edit this test to be allowed its own default.
		var expected := (
			Settings.RoundMode.LIVES
			if manifest.default_lives_mode
			else Settings.RoundMode.TIMER
		)
		_check(
			int(_settings.call("round_mode")) == expected,
			"An unset preference falls back to what %s declares." % manifest.id
		)
		_check(
			int(_settings.call("get_value", Settings.ROUND_MODE_KEY)) == expected,
			"Generic settings reads agree with %s's effective default." % manifest.id
		)
	_check(
		bool(_settings.call("lives_mode_enabled", GAME_ID)),
		"A directly run scene resolves its own default before catalog selection."
	)
	for choice in [Settings.RoundMode.TIMER, Settings.RoundMode.LIVES]:
		_values[Settings.ROUND_MODE_KEY] = choice
		for manifest in GameCatalog.all():
			_check(
				int(_settings.call("round_mode", manifest.id)) == choice,
				"An explicit round-mode preference wins in %s." % manifest.id
			)
	_values.erase(Settings.ROUND_MODE_KEY)
	_values[Settings.STARTING_LIVES_KEY] = Settings.DEFAULT_STARTING_LIVES


func _test_saved_preferences() -> void:
	GameCatalog.select(GAME_ID)
	var path := "user://dmj_lives_defaults_test_%d.cfg" % OS.get_process_id()
	var config := ConfigFile.new()
	config.set_value("game", "round_mode", Settings.RoundMode.TIMER)
	config.set_value("other_build", "retained", true)
	_check(config.save(path) == OK, "The isolated settings fixture can be written.")

	_settings.call("load_settings", path)
	_check(
		int(_settings.call("round_mode")) == Settings.RoundMode.TIMER,
		"A previously saved Timer preference is not migrated away."
	)
	_settings.call("reset_to_defaults")
	_check(
		not _values.has(Settings.ROUND_MODE_KEY)
		and int(_settings.call("round_mode")) == Settings.RoundMode.LIVES,
		"Reset restores the game default rather than an explicit Timer override."
	)
	_settings.call("save", path)
	config.clear()
	_check(config.load(path) == OK, "Reset settings can be read back.")
	_check(
		not config.has_section_key("game", "round_mode"),
		"Saving unrelated settings does not freeze a game's default into a shared preference."
	)
	_check(
		bool(config.get_value("other_build", "retained", false)),
		"Saving still preserves unknown settings belonging to another build."
	)
	_values.erase(Settings.ROUND_MODE_KEY)
	_settings.call("load_settings", path)
	_check(
		int(_settings.call("round_mode")) == Settings.RoundMode.LIVES,
		"The game-specific default survives a settings reload."
	)
	_settings.call("set_value", Settings.ROUND_MODE_KEY, Settings.RoundMode.LIVES)
	_settings.call("save", path)
	config.clear()
	_check(
		config.load(path) == OK and config.has_section_key("game", "round_mode"),
		"Explicitly choosing the current default still persists the player's choice."
	)
	_values.erase(Settings.ROUND_MODE_KEY)
	_settings.call("load_settings", path)
	_check(
		_values.get(Settings.ROUND_MODE_KEY) == Settings.RoundMode.LIVES,
		"An explicit Lives preference loads as an override."
	)
	_check(
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK,
		"The isolated settings fixture is removed."
	)
	_values.erase(Settings.ROUND_MODE_KEY)


func _test_menu_and_briefing() -> void:
	for manifest in GameCatalog.all():
		if manifest.id != GAME_ID:
			GameCatalog.select(manifest.id)
			break
	var menu_scene := load("res://scenes/menus/settings_menu.tscn") as PackedScene
	var menu := menu_scene.instantiate()
	menu.set("game_context_id", GAME_ID)
	get_root().add_child(menu)
	await process_frame
	var picker := menu.get_node("%RoundModeOption") as OptionButton
	_check(
		picker.get_selected_id() == Settings.RoundMode.LIVES
		and (menu.get_node("%StartingLivesSlider") as HSlider).editable,
		"The Settings menu uses the running game's context, not the catalog's prior selection."
	)
	menu.queue_free()
	await process_frame
	GameCatalog.select(GAME_ID)
	get_root().get_node("GameSession").call("configure_single_player")
	var briefing_scene := load("res://scenes/menus/instructions.tscn") as PackedScene
	var briefing := briefing_scene.instantiate()
	get_root().add_child(briefing)
	await process_frame
	_check(
		(briefing.get_node("%Rules") as Label).text.contains("3 lives per round"),
		"The briefing advertises the default lives pool."
	)
	briefing.queue_free()
	await process_frame


func _open_game() -> bool:
	var packed := load(GAME_SCENE) as PackedScene
	_check(packed != null, "The lives-enabled gameplay scene loads.")
	if packed == null:
		return false
	_values[DmjOptions.NOTE_SOURCE_KEY] = DmjOptions.SOURCE_KEYBOARD
	_values[DmjOptions.MODE_KEY] = DmjOptions.MODE_JAM
	_values[DmjOptions.TRACK_KEY] = DmjOptions.TRACK_PRACTICE
	_values[Settings.REDUCED_MOTION_KEY] = true
	_values[Settings.VISUAL_EFFECTS_KEY] = false
	_values[Settings.AUDIO_CAPTIONS_KEY] = false
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1920, 1080)
	get_root().add_child(_viewport)
	for manifest in GameCatalog.all():
		if manifest.id != GAME_ID:
			GameCatalog.select(manifest.id)
			break
	_game = packed.instantiate()
	_check(_game.has_method("_on_drone_fired"), "The gameplay script compiled.")
	if not _game.has_method("_on_drone_fired"):
		_game.free()
		_viewport.queue_free()
		return false
	_viewport.add_child(_game)
	await process_frame
	await process_frame
	_game.set_process(false)
	GameCatalog.select(GAME_ID)
	return true


func _test_lives_round() -> void:
	var rack := _rack()
	_check(
		bool(_game.get("_lives_mode")) and _remaining() == 3
		and (_game.get_node("%RoundTimer") as Timer).is_stopped(),
		"The default is three lives with no countdown running."
	)
	_check(
		rack.visible and rack.remaining_lives == 3 and rack.capacity == 3,
		"The rack starts from the shell's actual pool."
	)
	_check(
		not (_game.get_node("%TimeLabel") as Control).visible
		and not (_game.get_node("%TimeCaption") as Control).visible
		and not (_game.get_node("%TimeProgress") as Control).visible,
		"Lives replace the visible countdown instead of adding a duplicate gauge."
	)
	_check(
		rack.get_node("%LifeCount").text == "3 / 3 LIVES"
		and not rack.accessibility_description.is_empty(),
		"The rack provides a numeric count and an accessible explanation."
	)
	_check(
		str(_game.call("_play_instruction")).contains("firing robot"),
		"The HUD explains that fired shots, not wrong notes, cost lives."
	)
	var director: EncounterDirector = _game.get("_director")
	director.set_track([{"drones": [
		_plan(0.0), _plan(4.0), _plan(8.0),
	]}])
	director.begin()
	for _frame in range(240):
		_step()
		if not director.live_drones().is_empty():
			break
	var router: NoteRouter = _game.get("_router")
	router.note_started.emit(NoteEvent.make(47, NoteEvent.Source.KEYBOARD))
	_check(
		_remaining() == 3 and int(_game.get("_misses")) == 1,
		"A real wrong note costs no lives or tubes."
	)
	_run_to_lives(2)
	_check(
		_remaining() == 2 and rack.remaining_lives == 2
		and rack.get_node("%LifeStatus").text == "1 TUBE BLOWN",
		"A real firing drone burns exactly one tube."
	)
	_values[Settings.ROUND_MODE_KEY] = Settings.RoundMode.TIMER
	_settings.emit_signal("changed", Settings.ROUND_MODE_KEY, Settings.RoundMode.TIMER)
	_check(
		bool(_game.get("_lives_mode")) and rack.visible,
		"Changing the preference does not reshape the round already running."
	)
	_run_to_lives(1)
	_check(
		rack.is_critical() and rack.get_node("%LifeStatus").text.contains("LAST TUBE"),
		"The last life has a textual warning even with motion disabled."
	)
	_run_to_lives(0)
	for _frame in range(ceili(DmjShotFx.RESULT_SETTLE / STEP) + 2):
		if not bool(_game.get("_round_active")):
			break
		_step()
	_check(
		not bool(_game.get("_round_active")) and _remaining() == 0
		and (_game.get_node("%RoundOver") as Control).visible
		and rack.get_node("%LifeStatus").text == "POWER CUT",
		"Three actual firing drones exhaust the pool and settle the round."
	)
	_check(
		not bool(_game.get("_track_finished")),
		"The last hostile shot cannot turn a lethal ending into a track-clear victory."
	)
	var payload: Dictionary = _game.call("_share_payload")
	_check(str(payload.get("mode", "")).contains("3 Lives"), "Results keep the round's lives metadata.")
	var score: int = (_game.get("_scores") as Array)[0]
	router.note_started.emit(NoteEvent.make(40, NoteEvent.Source.KEYBOARD))
	_check(
		int((_game.get("_scores") as Array)[0]) == score,
		"An eliminated player cannot score."
	)


func _test_timer_and_replay() -> void:
	_game.call("_on_play_again_pressed")
	await process_frame
	_check(
		not bool(_game.get("_lives_mode")) and not _rack().visible
		and (_game.get_node("%TimeLabel") as Control).visible
		and (_game.get_node("%TimeProgress") as Control).visible
		and not (_game.get_node("%RoundTimer") as Timer).is_stopped(),
		"Replay applies the explicit Timer preference and restores the countdown HUD."
	)
	_values[Settings.ROUND_MODE_KEY] = Settings.RoundMode.LIVES
	_game.call("_on_play_again_pressed")
	await process_frame
	_check(
		_remaining() == 3 and _rack().remaining_lives == 3
		and _rack().visible and not _rack().is_critical(),
		"A lives replay refills every tube and clears the warning."
	)


func _test_layouts() -> void:
	for count in [1, 3, 9]:
		_values[Settings.STARTING_LIVES_KEY] = count
		_game.call("_start_round")
		_check(
			_rack().capacity == count and _remaining() == count,
			"The rack uses the configured %d-life pool." % count
		)
		for dimensions: Vector2i in [
			Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(960, 1700),
		]:
			_viewport.size = dimensions
			for _frame in range(4):
				await process_frame
			var screen := Rect2(Vector2.ZERO, Vector2(dimensions))
			var top: Control = _game.get_node("HUD/Overlay/Margins/Layout/TopBar")
			_check(
				screen.encloses(top.get_global_rect()),
				"The top bar fits %d lives at %s." % [count, dimensions]
			)
			var rack := _rack()
			var local := Rect2(Vector2.ZERO, rack.size)
			var heading: Control = rack.get_node("%LifeHeading")
			var status: Control = rack.get_node("%LifeStatus")
			_check(
				local.grow(0.5).encloses(heading.get_rect())
				and local.grow(0.5).encloses(status.get_rect()),
				"Both lives readouts fit the rack at %s." % dimensions
			)
			for index in range(count):
				var tube := rack.tube_rect(index)
				_check(
					local.encloses(tube) and tube.size.y > 0.0
					and not tube.intersects(heading.get_rect())
					and not tube.intersects(status.get_rect()),
					"Tube %d fits without covering either label." % index
				)
			var console: Control = _game.get_node("%DmjPrompt")
			var field: Rect2 = _game.call("_playfield_bounds")
			_check(
				field.position.y > top.get_global_rect().end.y
				and field.end.y <= console.get_global_rect().position.y
				and field.size.y > 1.0,
				"The lives HUD leaves a usable corridor at %s." % dimensions
			)


func _test_accessibility() -> void:
	_values[Settings.STARTING_LIVES_KEY] = 3
	_game.call("_start_round")
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", true)
	_game.call("_lose_life", 0, 2)
	var rack := _rack()
	_check(rack.is_processing() and rack.is_critical(), "The last tube can animate gently.")
	rack.set_protected(true)
	_check(
		not rack.is_processing() and float(rack.get("_burn_left")) == 0.0,
		"Protecting the circuit also clears a burnout already in progress."
	)
	rack.set_protected(false)
	_game.call("_set_reduced_motion_enabled", true)
	var held: float = rack.get("_pulse_time")
	rack._process(0.5)
	_check(
		not rack.is_processing() and float(rack.get("_burn_left")) == 0.0
		and float(rack.get("_pulse_time")) == held and rack.is_critical(),
		"Reduced motion freezes animation without removing the warning."
	)
	_game.call("_set_reduced_motion_enabled", false)
	_game.call("_set_intense_effects_enabled", false)
	_check(not rack.is_processing(), "Disabling visual effects also disables tube animation.")


func _test_demo() -> void:
	_values[DmjOptions.MODE_KEY] = DmjOptions.MODE_DEMO
	_values[Settings.STARTING_LIVES_KEY] = 1
	_game.call("_start_round")
	var rack := _rack()
	_game.call("_on_drone_fired", null)
	_check(
		_remaining() == 1 and rack.remaining_lives == 1 and rack.protected
		and not rack.is_critical() and not rack.is_processing()
		and rack.get_node("%LifeStatus").text.contains("PROTECTED"),
		"Demo protects a one-life pool and never presents it as a critical circuit."
	)


func _test_track_clear() -> void:
	_values[DmjOptions.MODE_KEY] = DmjOptions.MODE_JAM
	_values[Settings.STARTING_LIVES_KEY] = 3
	_game.call("_start_round")
	var director: EncounterDirector = _game.get("_director")
	director.set_track([{"drones": [_plan(0.0)]}])
	director.begin()
	var router: NoteRouter = _game.get("_router")
	for _frame in range(480):
		_step()
		for drone in director.live_drones():
			if absf(drone.time_to_beat()) < 0.01:
				router.note_started.emit(NoteEvent.make(40, NoteEvent.Source.KEYBOARD))
		if not bool(_game.get("_round_active")):
			break
	_check(
		bool(_game.get("_track_finished")) and _remaining() == 3
		and not bool(_game.get("_round_active")),
		"Clearing the actual track wins without spending the remaining lives."
	)


func _rack() -> DmjLifeRack:
	return _game.get_node("%DmjLifeRack")


func _remaining() -> int:
	return int((_game.get("_lives") as Array)[0])


func _plan(at: float) -> Dictionary:
	return {"lane": 1, "note": 40, "at": at, "approach": 1.0, "windup": 0.5}


func _step() -> void:
	_game.call("_update_round", STEP, 60.0)


func _run_to_lives(remaining: int) -> void:
	for _frame in range(900):
		if _remaining() <= remaining or not bool(_game.get("_round_active")):
			return
		_step()


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		printerr("ERROR: %s" % failure)
	if _failures.is_empty():
		print("Lives HUD tests passed. (%d checks)" % _checks)
	quit(0 if _failures.is_empty() else 1)
