extends SceneTree

## Uses the existing SceneTree test runner; no microphone or MIDI is needed.
## godot --headless --path ..\.. --script res://games/dead_metal_jam/tests/drone_art_test.gd
const FIELD := Rect2(Vector2(40.0, 200.0), Vector2(900.0, 460.0))
const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_art_bounds()
	_test_live_clanky_pose()
	_test_plate_cursor()
	_test_scale_does_not_change_the_beat()
	_test_demo_freezes_the_drawing()
	await _test_gallery()
	await _test_share_art()
	_finish.call_deferred()


func _test_art_bounds() -> void:
	var artists: Array[DmjDroneArt] = [
		DmjRustyClankyArt.new(), DmjPlatedKnuckleArt.new(),
		DmjSilencerSentryArt.new(), DmjConductorArt.new(),
	]
	for art in artists:
		var name: String = art.get_script().get_global_name()
		_check(
			Rect2(-DmjDroneArt.SIZE * 0.5, DmjDroneArt.SIZE).encloses(art.visual_bounds()),
			"%s fits the shared character envelope." % name
		)
		_check(art.framed_bounds().encloses(art.visual_bounds()), "%s reserves room for telegraphs." % name)
		_check(not art.has_method("strike"), "%s is artwork, not a combat actor." % name)
		art.set_pose(1.25, true, 0.5, true, false, 0.0, true)
		_check(is_zero_approx(art._wave(4.0)), "%s suppresses decorative motion." % name)
		_check(is_zero_approx(art._stride(4.0)), "%s also suppresses its gait." % name)
		art.free()


func _test_live_clanky_pose() -> void:
	var drone := RustyClanky.new()
	drone.configure(1, 47, 1.0, 1.0)
	var art := drone.get_node("Art") as DmjRustyClankyArt
	_check(art != null, "Rusty Clanky uses the concept-based artist.")
	if art == null:
		drone.free()
		return
	_check(art.current_note() == 47, "The chest reads the actual required note.")
	_check(
		(art.position + art.ground_offset()).is_zero_approx(),
		"The feet and ground shadow stand on the actor's rail position."
	)
	drone.set_targeted(true)
	_check(art.targeted, "The target outline reaches the drawing immediately.")
	drone.advance(0.4, FIELD, 3)
	_check(is_equal_approx(art.motion_time, 0.4), "The gait uses the actor's clock.")
	drone.set_reduced_motion(true)
	_check(art.reduced_motion and is_zero_approx(art._stride(3.0)), "Reduced motion reaches live limbs.")
	drone.advance(0.6, FIELD, 3)
	drone.advance(0.4, FIELD, 3)
	_check(is_equal_approx(art.charge, 0.7), "The charge bar tracks the complete attack deadline.")
	_check(is_equal_approx(drone.attack_progress(), art.charge), "Attack timing is shown by the bar alone.")
	_check(not art.walking, "A winding-up bot stops walking.")
	drone.kill()
	_check(art.defeated and not art.targeted, "A killed bot changes its pose and drops its target brackets.")
	drone.advance(JamBot.DEATH_FADE * 0.5, FIELD, 3)
	_check(is_equal_approx(art.self_modulate.a, 0.5), "The whole character shares the existing death fade.")
	drone.free()


func _test_plate_cursor() -> void:
	var drone := PlatedKnuckle.new()
	drone.configure_sequence(1, [48, 52, 55], 2.0, 3.0)
	var art := drone.get_node("Art") as DmjPlatedKnuckleArt
	_check(art != null, "Plated Knuckle uses the armored concept.")
	if art == null:
		drone.free()
		return
	_check(art.notes == [48, 52, 55] and art.active_index == 0, "A phrase starts on its first plate.")
	drone.strike()
	_check(
		art.active_index == 1 and art.current_note() == drone.required_note,
		"Breaking a plate moves the highlight and called note together."
	)
	drone.strike()
	_check(art.active_index == 2 and art.current_note() == 55, "The third note reaches the chest plate.")
	drone.on_wrong_note()
	_check(art.active_index == 0 and art.current_note() == 48, "A wrong note restores the visual phrase.")
	art.notes[0] = 35
	_check(drone.notes[0] == 48, "Changing preview data cannot alter an actor's scoring sequence.")
	drone.advance(0.0, FIELD, 3)
	_check(art.current_note() == 48, "The next pose restores the authoritative note.")
	drone.strike()
	drone.strike()
	drone.strike()
	_check(art.defeated and art.active_index == 3, "The final hit leaves all plates visibly broken.")
	drone.configure_sequence(0, [46, 49], 2.0, 3.0)
	_check(
		not art.defeated and art.notes == [46, 49, 46] and art.active_index == 0,
		"Reconfiguring restores all three plates, cycling shorter phrases without losing accidentals."
	)
	drone.free()


func _test_scale_does_not_change_the_beat() -> void:
	var full := RustyClanky.new()
	var small := RustyClanky.new()
	full.configure(0, 40, 4.0, 1.0)
	small.configure(0, 40, 4.0, 1.0)
	small.visual_scale = 0.25
	full.advance(1.0, FIELD, 3)
	small.advance(1.0, FIELD, 3)
	_check(full.position.is_equal_approx(small.position), "Visual fitting never changes the lane position.")
	_check(is_equal_approx(full.time_to_beat(), small.time_to_beat()), "Visual fitting never changes timing.")
	_check(is_equal_approx(small.scale.x, full.scale.x * 0.25), "Only the drawing becomes smaller.")
	_check(DmjDroneArt.fit_scale(600.0) == 1.0, "A normal field shows the full design.")
	_check(DmjDroneArt.fit_scale(120.0) < 1.0, "A short field fits the larger silhouette.")
	full.free()
	small.free()


func _test_demo_freezes_the_drawing() -> void:
	var director := EncounterDirector.new()
	get_root().add_child(director)
	director.apply_mode(EncounterDirector.Mode.DEMO)
	director.visual_scale = 0.6
	director.set_track([{"drones": [
		{"lane": 1, "note": 40, "at": 0.0, "approach": 0.5, "windup": 1.0},
	]}])
	director.begin()
	for _index in range(200):
		director.advance(STEP, FIELD)
	var live := director.live_drones()
	_check(director.is_time_stopped() and live.size() == 1, "Demo reaches a held note for the pose test.")
	if live.size() == 1:
		var art: DmjDroneArt = live[0].get_node("Art")
		var held := art.motion_time
		_check(is_equal_approx(live[0].visual_scale, 0.6), "The director passes the presentation scale to actors.")
		for _index in range(60):
			director.advance(STEP, FIELD)
		_check(is_equal_approx(art.motion_time, held), "A held beat also holds limbs and facial animation.")
	director.free()


func _test_gallery() -> void:
	var settings := get_root().get_node("Settings")
	var values: Dictionary = settings.get("_values")
	var saved := values.duplicate(true)
	values["accessibility/reduced_motion"] = false
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1920, 1080)
	get_root().add_child(viewport)
	var packed := load("res://games/dead_metal_jam/ui/drone_gallery.tscn") as PackedScene
	_check(packed != null, "The standalone gallery loads.")
	if packed == null:
		viewport.free()
		values.clear()
		values.merge(saved, true)
		return
	var gallery := packed.instantiate()
	viewport.add_child(gallery)
	await process_frame
	await process_frame
	gallery.set_process(false)
	var artists: Array = gallery.get("_artists")
	_check(artists.size() == 4, "The gallery includes all four supplied concepts.")
	_check(not _contains_combat(gallery), "The preview never constructs combat enemies or an encounter.")
	var sentry_card: Node = gallery.get_node("%SentryCard")
	var boss_card: Node = gallery.get_node("%ConductorCard")
	_check(
		sentry_card.get_node("%DroneStatus").text == "ART PREVIEW"
		and boss_card.get_node("%DroneStatus").text == "ART PREVIEW",
		"The two future enemies are explicitly labeled as previews."
	)
	gallery.call("_on_cycle_notes_pressed")
	_check(artists[1].current_note() == 52, "The gallery can preview the next armor plate.")
	_check(artists[2].current_note() == -1, "The silencer never invents a required note.")
	var pause: CheckButton = gallery.get_node("%PauseMotion")
	pause.button_pressed = true
	var held: float = gallery.get("_time")
	gallery.call("_process", 0.5)
	_check(is_equal_approx(float(gallery.get("_time")), held), "The gallery can pause its animation.")
	var charge: CheckButton = gallery.get_node("%ChargePose")
	charge.button_pressed = true
	gallery.call("_update_poses")
	_check(artists[0].charge > 0.0 and not artists[0].walking, "The gallery uses a real charge pose.")
	values["accessibility/reduced_motion"] = true
	settings.emit_signal("changed", "accessibility/reduced_motion", true)
	_check(pause.disabled, "The gallery respects the global reduced-motion preference.")
	for art: DmjDroneArt in artists:
		_check(art.reduced_motion, "Reduced motion reaches every gallery drawing.")

	for dimensions: Vector2i in [
		Vector2i(1920, 1080), Vector2i(960, 1700), Vector2i(600, 900),
	]:
		viewport.size = dimensions
		for _frame in range(4):
			await process_frame
		var expected := 4 if dimensions.x == 1920 else (2 if dimensions.x == 960 else 1)
		_check(
			(gallery.get_node("%Roster") as GridContainer).columns == expected,
			"Gallery columns adapt to %s." % dimensions
		)
		for art: DmjDroneArt in artists:
			var stage := art.get_parent() as Control
			var bounds := art.framed_bounds()
			var drawn := Rect2(art.position + bounds.position * art.scale, bounds.size * art.scale)
			_check(
				Rect2(Vector2.ZERO, stage.size).grow(0.5).encloses(drawn),
				"Every full silhouette and telegraph fits its preview at %s." % dimensions
			)
	viewport.queue_free()
	await process_frame
	values.clear()
	values.merge(saved, true)


func _test_share_art() -> void:
	var packed := load("res://games/dead_metal_jam/ui/share_art.tscn") as PackedScene
	_check(packed != null, "The share artwork scene loads.")
	if packed == null:
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(250, 300)
	get_root().add_child(viewport)
	var art := packed.instantiate() as Control
	viewport.add_child(art)
	await process_frame
	await process_frame
	_check(art.size == Vector2(viewport.size), "The share portraits are exercised at card size.")
	var portraits: Array = art.get("_portraits")
	_check(portraits.size() == 3, "The share card still shows its three posed drones.")
	var plated := 0
	for portrait: DmjDroneArt in portraits:
		if portrait is DmjPlatedKnuckleArt:
			plated += 1
		_check(portrait.reduced_motion, "Share portraits are still frames.")
	_check(plated == 1, "The share card reuses the live armored drawing instead of a placeholder.")
	_check(not _contains_combat(art), "Sharing never starts an encounter.")
	viewport.queue_free()
	await process_frame


func _contains_combat(node: Node) -> bool:
	if node is JamBot or node is EncounterDirector:
		return true
	for child in node.get_children():
		if _contains_combat(child):
			return true
	return false


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	for failure in _failures:
		printerr("ERROR: %s" % failure)
	if _failures.is_empty():
		print("Drone art tests passed. (%d checks)" % _checks)
	quit(0 if _failures.is_empty() else 1)
