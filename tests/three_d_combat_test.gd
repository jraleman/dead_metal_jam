extends SceneTree

## Add --capture-dir=<absolute directory> after -- to save real rendered frames.
const FIELD := Rect2(0, 0, 1280, 560)
var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	await _test_world()
	await _test_gameplay()
	if _failures.is_empty():
		print("3D combat tests passed (%d checks)." % _checks)
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _actors() -> Array[JamBot]:
	var clanky := RustyClanky.new()
	clanky.configure(0, 60, 4.0, 3.0)
	clanky.set_targeted(true)
	var plated := PlatedKnuckle.new()
	plated.configure_sequence(1, [62, 64, 65], 4.0, 3.0)
	var sentry := SilencerSentry.new()
	sentry.configure_echo(2, 67, 4.0, 3.0)
	var boss := DmjConductor.new()
	boss.configure_motif(1, [69, 67, 64, 60], 4.0, 4.0)
	boss.firing_slot = 1
	return [clanky, plated, sentry, boss]


func _test_world() -> void:
	var rules := Node2D.new()
	rules.hide()
	root.add_child(rules)
	var actors := _actors()
	for actor in actors:
		rules.add_child(actor)
		actor.advance(0.5, FIELD, 3)
	var arena := DmjArena3D.new()
	root.add_child(arena)
	arena.set_field(FIELD)
	arena.present(actors, 0, 1.0, 0.5)
	await process_frame
	await process_frame
	_check(arena.viewport.own_world_3d, "The game owns a real isolated 3D world.")
	_check(arena.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "Depth is projected by a perspective Camera3D.")
	_check(_mesh_count(arena.world) > 150, "Rooms and enemies are lit mesh geometry, not a sprite backdrop.")
	for actor in actors:
		var model := arena.model_for(actor)
		_check(_mesh_count(model) > 15, "Every enemy has an articulated mesh chassis.")
		_check(model.position.is_equal_approx(DmjArenaLayout.world_position(actor.lane, 0, actor.firing_slot)), "Meshes occupy physical firing bays.")
		var label: Label3D = model.get("_note")
		_check(label.text == PitchDetector.note_name(actor.required_note), "Every 3D core displays the note used for judgement.")
	var original := arena.model_for(actors[0]).position
	actors[0].position = Vector2(10000, -10000)
	actors[0].scale = Vector2(12, 12)
	arena.present(actors, 0, 1.0, 0.5)
	_check(arena.model_for(actors[0]).position.is_equal_approx(original), "Legacy 2D scale and fake depth cannot move the 3D actors.")
	for pitch in range(12):
		actors[0].required_note = 60 + pitch
		arena.present(actors, 0, 1.0, 0.5)
		await process_frame
		var model := arena.model_for(actors[0])
		var label: Label3D = model.get("_note")
		var plate: MeshInstance3D = model.get("_core")
		var font := label.font if label.font != null else ThemeDB.fallback_font
		var glyph_width := font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size
		).x * label.pixel_size
		_check(label.text == PitchDetector.note_name(60 + pitch), "All chromatic notes retain their letters.")
		# Measure shaped text, not the billboard's conservative AABB.
		_check(
			glyph_width <= plate.get_aabb().size.x,
			"%s fits its core (text %.3f, plate %.3f)." % [
				label.text, glyph_width, plate.get_aabb().size.x,
			]
		)
		_check(
			(plate.material_override as StandardMaterial3D).albedo_color == DmjPalette.note_color(60 + pitch),
			"The physical note core uses the same pitch color as the HUD."
		)
	actors[0].required_note = 60
	actors[0].advance(3.4, FIELD, 3)
	actors[0].presentation_speed = 0.5
	arena.present(actors, 0, 1.0, 0.5)
	var beat_ring: MeshInstance3D = arena.model_for(actors[0]).get("_beat_ring")
	_check(
		(beat_ring.material_override as StandardMaterial3D).albedo_color == DmjPalette.note_color(60),
		"The 3D beat cue uses the HUD's speed-adjusted bonus window."
	)
	actors[0].presentation_speed = 1.0
	arena.present(actors, 0, 1.0, 0.5)
	_check(
		(beat_ring.material_override as StandardMaterial3D).albedo_color == DmjPalette.TEXT,
		"The closing ring highlights the same on-beat window as the HUD."
	)
	for dimensions: Vector2 in [Vector2(1280, 560), Vector2(640, 360), Vector2(1600, 400), Vector2(360, 640)]:
		arena.set_field(Rect2(Vector2.ZERO, dimensions))
		await process_frame
		arena.present(actors, 0, 1.0, 0.5)
		for actor in actors:
			var target := arena.aim_point(actor)
			_check(not arena.camera.is_position_behind(target), "Every called note is in front of the camera.")
			_check(Rect2(Vector2.ZERO, dimensions).has_point(arena.camera.unproject_position(target)), "Called notes remain in frame after resizing.")
	arena.present(actors, 0, 1.0, 0.5, false)
	for actor in actors:
		var label: Label3D = arena.model_for(actor).get("_note")
		_check(label.text == "ANY", "Rhythm's 3D cores do not misleadingly require a specific pitch.")
	arena.set_field(FIELD)
	arena.present(actors, 0, 1.0, 0.5)
	var aim := arena.aim_point(actors[0])
	arena.shots.player_shot(aim, true, 60, arena.ground_point(actors[0]))
	arena.present(actors, 0, 1.0, 0.5)
	var muzzle_light: OmniLight3D = arena.get("_muzzle_light")
	_check(muzzle_light.light_energy > 0.0, "A played note lights the real 3D foreground.")
	var shots: Array = arena.shots.get("_shots")
	_check((shots[0]["destination"] as Vector3).is_equal_approx(aim), "The tracer hits the actual 3D core.")
	for value: Variant in shots[0].values():
		_check(not value is Node, "Shot metadata never retains a combat actor.")
	paused = true
	var age: float = shots[0]["age"]
	for frame in range(3):
		await process_frame
	_check(is_equal_approx(float(shots[0]["age"]), age), "Pause holds 3D effects as well as combat.")
	paused = false
	arena.set_presentation_options(true, false)
	_check(is_zero_approx(muzzle_light.light_energy), "Reduced effects immediately suppress the 3D muzzle flash.")
	_check((arena.shots.get("_particles") as Array).is_empty(), "Reduced effects immediately clear decorative particles.")
	_check(not bool(shots[0]["animated"]), "An in-flight effect becomes quiet immediately.")
	arena.set_presentation_options(false, true)
	_check(not bool(shots[0]["animated"]), "Re-enabling effects cannot replay an old explosion.")
	for index in range(DmjShotFx3D.MAX_SHOTS * 3):
		arena.shots.player_shot(aim, true, 60, Vector3.ZERO)
	_check(arena.shots.active_count() == DmjShotFx3D.MAX_SHOTS, "Dense MIDI input respects the 3D shot budget.")
	_check((arena.shots.get("_particles") as Array).size() <= DmjShotFx3D.MAX_PARTICLES, "Debris has a separate fixed budget.")
	_check(arena.shots.get_child_count() <= DmjShotFx3D.MAX_SHOTS + DmjShotFx3D.MAX_PARTICLES, "Discarded visuals are freed immediately, not accumulated until frame end.")
	arena.shots.advance(DmjShotFx3D.DESTRUCTION_LIFETIME + 0.01)
	_check(arena.shots.active_count() == 0 and arena.shots.get_child_count() == 0, "Expired 3D effects release every visual.")
	arena.set_presentation_options(true, false)
	actors[0].set_reduced_motion(true)
	actors[0].kill()
	actors[0].advance_feedback(JamBot.QUIET_DEATH_FADE * 0.5)
	arena.present(actors, 0, 1.0, 0.5)
	var surfaces: Array = arena.model_for(actors[0]).get("_fade_surfaces")
	_check(not surfaces.is_empty(), "Quiet destruction fades the actual mesh materials.")
	for surface: StandardMaterial3D in surfaces:
		_check(is_equal_approx(surface.albedo_color.a, 0.5), "Reduced-motion deaths fade without moving body parts.")
	arena.set_presentation_options(false, true)
	arena.present([], 1, 0.0, 1.0)
	var before := arena.camera.position
	arena.present([], 1, 0.5, 1.0)
	_check(arena.camera.position.distance_to(before) > 10.0, "Room transitions really translate the 3D camera.")
	for index in range(1, 9):
		arena.present([], index, 0.5, 1.0)
		_check((arena.get("_rooms") as Dictionary).size() <= 2, "A long round keeps at most two physical rooms.")
	arena.set_presentation_options(true, true)
	arena.present([], 8, 0.1, 1.0)
	before = arena.camera.position
	arena.present([], 8, 0.9, 12.0)
	_check(arena.camera.position.is_equal_approx(before), "Reduced motion removes camera travel and breathing.")
	_check((arena.get("_models") as Dictionary).is_empty(), "Leaving a wave releases every old mesh actor.")
	arena.queue_free()
	rules.queue_free()
	await process_frame
	await process_frame


func _test_gameplay() -> void:
	var settings := root.get_node("Settings")
	var values: Dictionary = settings.get("_values")
	var saved := values.duplicate(true)
	var timer: Timer = settings.get("_save_timer")
	var saved_mode := timer.process_mode
	timer.process_mode = Node.PROCESS_MODE_DISABLED
	values.merge({
		DmjOptions.NOTE_SOURCE_KEY: DmjOptions.SOURCE_KEYBOARD,
		DmjOptions.MODE_KEY: DmjOptions.MODE_JAM,
		DmjOptions.TRACK_KEY: DmjOptions.TRACK_SONG_02,
		Settings.REDUCED_MOTION_KEY: false,
		Settings.VISUAL_EFFECTS_KEY: true,
		Settings.ROUND_MODE_KEY: Settings.RoundMode.LIVES,
		Settings.STARTING_LIVES_KEY: 3,
	}, true)
	GameCatalog.select("dead_metal_jam")
	root.get_node("GameSession").call("configure_single_player")
	var packed := load("res://games/dead_metal_jam/gameplay.tscn") as PackedScene
	var game := packed.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	game.set_process(false)
	game.set_process_unhandled_input(false)
	(game.get("_router") as NoteRouter).set_accepting(false)
	(game.get_node("%RoundTimer") as Timer).stop()
	var arena: DmjArena3D = game.get("_arena")
	var director: EncounterDirector = game.get("_director")
	_check(arena != null and arena.is_visible_in_tree(), "Shipping gameplay actually displays the 3D viewport.")
	_check(not director.visible, "Legacy 2D combat art never draws over the 3D scene.")
	var plans: Array = [
		{"enemy": "rusty_clanky", "lane": 0, "note": 60, "approach": 12.0, "windup": 4.0},
		{"enemy": "plated_knuckle", "lane": 1, "notes": [62, 64, 65], "approach": 12.0, "windup": 4.0},
		{"enemy": "silencer_sentry", "lane": 2, "note": 67, "approach": 12.0, "windup": 4.0},
		{"enemy": "conductor", "lane": 1, "notes": [69, 67, 64, 60], "approach": 12.0, "windup": 4.0},
	]
	director.set_track([
		{"section": "INTRO", "advance": 0.0, "drones": plans},
		{"section": "VERSE", "advance": 0.0, "drones": plans},
		{"section": "OUTRO", "advance": 0.0, "drones": plans},
	])
	director.begin()
	var capture_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir="):
			capture_dir = arg.trim_prefix("--capture-dir=")
	for room in range(3):
		var field: Rect2 = game.call("_playfield_bounds")
		director.advance(0.4, field)
		arena.set_field(field)
		arena.sync_from_director()
		game.call("_update_target_readout")
		_check(director.live_drones().size() == 4, "Each 3D room can stage all four playable enemies.")
		if not capture_dir.is_empty():
			_check(DisplayServer.get_name() != "headless", "Captures require a real rendering driver.")
			if DisplayServer.get_name() != "headless":
				await create_timer(1.2).timeout
				for frame in range(4):
					await process_frame
				await RenderingServer.frame_post_draw
				var image := root.get_texture().get_image()
				_check(image.save_png("%s\\dmj-3d-room-%d.png" % [capture_dir, room]) == OK, "The actual game frame is saved.")
		for actor in director.live_drones():
			while actor.is_targetable():
				actor.strike()
		if room < 2:
			director.advance(0.01, field)
	game.set("_round_active", false)
	game.call("_finish_round")
	game.queue_free()
	await process_frame
	await process_frame
	values.clear()
	values.merge(saved, true)
	timer.stop()
	timer.process_mode = saved_mode


func _mesh_count(node: Node) -> int:
	var count := 1 if node is MeshInstance3D else 0
	for child in node.get_children():
		count += _mesh_count(child)
	return count


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)
