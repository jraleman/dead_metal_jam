extends SceneTree

## Headless tests for Dead Metal Jam's opening: [DmjIntroSound] and the
## timeline in `intro.gd`.
##
## The opening is the one place the game gets to explain its verb before the
## menu, so the things asserted here are the things that carry that meaning:
## three drones walk out, each one is answered by a note, and none of them ever
## gets to fire.
##
## The scene is loaded at runtime rather than preloaded — its script uses
## autoload instances, which do not exist while a `--script` run is compiling
## this file. [RustyClanky] and [DmjIntroSound] touch no autoload, so they can be
## named directly.
##
## The timeline is driven by hand with a fixed timestep instead of by the
## engine, so every assertion below is deterministic rather than frame-rate
## dependent.
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/intro_test.gd

const INTRO_SCENE := "res://games/dead_metal_jam/intro.tscn"
const GAME_ID := "dead_metal_jam"

## Fixed timestep, matching a 60 Hz frame.
const STEP := 1.0 / 60.0

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sounds_are_audible()
	_test_pitch_is_standard()
	_test_backing_track_is_a_bed()
	_test_manifest_declares_the_intro()
	await _test_timeline()
	await _test_music_starts_with_the_scene()
	await _test_reduced_motion_reaches_the_actors()
	_finish()


# --------------------------------------------------------------------------
# Sound
# --------------------------------------------------------------------------


## The opening renders its own audio, so silence would be a silent failure.
func _test_sounds_are_audible() -> void:
	var sounds := {
		"power chord": DmjIntroSound.power_chord(),
		"amp hum": DmjIntroSound.amp_hum(),
		"note ping": DmjIntroSound.note_ping(52),
	}
	for name: String in sounds:
		var stream: AudioStreamWAV = sounds[name]
		if stream == null:
			_failures.append("The %s must render to a stream." % name)
			continue
		_expect(
			stream.mix_rate == int(DmjIntroSound.RATE),
			"The %s must be rendered at the sound bank's rate." % name
		)
		_expect(stream.data.size() > 0, "The %s must contain samples." % name)
		_expect(_peak(stream) > 0.2, "The %s must be loud enough to hear." % name)


## Concert A is the anchor every other note is measured from; if this drifts,
## the opening and the game disagree about what a note is.
func _test_pitch_is_standard() -> void:
	_expect(
		absf(DmjIntroSound.frequency(69) - 440.0) < 0.01,
		"MIDI 69 must be 440 Hz."
	)
	_expect(
		absf(DmjIntroSound.frequency(81) - 880.0) < 0.01,
		"An octave up must double the frequency."
	)


## The opening's backing track is a bed, not a loop.
##
## The opening is nine seconds long and the track is minutes long, so nothing
## on screen would ever reveal a loop flag left on — it would only show up
## much later, in whatever scene inherited the still-playing stream. Checked
## here because looping is set by the `.import`, which no other test reads.
func _test_backing_track_is_a_bed() -> void:
	var script := load(INTRO_SCENE) as PackedScene
	var intro := script.instantiate() if script else null
	if intro == null:
		_failures.append("The opening must instantiate to be checked.")
		return

	var music: AudioStream = intro.get("music")
	_expect(music != null, "The opening must carry a backing track.")
	if music != null:
		_expect(
			not bool(music.get("loop")),
			"The opening's backing track must not loop."
		)
		_expect(
			music.get_length() >= 9.0,
			"It must outlast the opening it plays under."
		)
	intro.free()


func _peak(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var loudest := 0.0
	# 16-bit little-endian, the format `DmjIntroSound` writes.
	for i in range(0, data.size() - 1, 2):
		var value := data.decode_s16(i) / 32768.0
		loudest = maxf(loudest, absf(value))
	return loudest


# --------------------------------------------------------------------------
# Timeline
# --------------------------------------------------------------------------


## The opening must be reachable the way the framework reaches it: as a path on
## the manifest, not as a name the boot sequence knows.
func _test_manifest_declares_the_intro() -> void:
	var manifest := GameCatalog.get_manifest(GAME_ID)
	if manifest == null:
		_failures.append("Dead Metal Jam must be in the catalog.")
		return
	_expect(
		manifest.intro_scene_path == INTRO_SCENE,
		"Dead Metal Jam must declare its own intro on the manifest."
	)
	_expect(
		ResourceLoader.exists(manifest.intro_scene_path),
		"The declared intro scene must exist."
	)


func _test_timeline() -> void:
	var intro := await _open_intro()
	if intro == null:
		return
	var drones: Node2D = intro.get_node_or_null("%Drones")
	if drones == null:
		_failures.append("The opening must have a stage to walk the drones onto.")
		intro.queue_free()
		return

	_expect(drones.get_child_count() == 0, "The opening must start on an empty stage.")
	var rail := intro.get("_rail") as DmjRail
	_expect(rail != null, "The opening shares the playable corridor.")
	if rail != null:
		var field: Rect2 = intro.call("_drone_field")
		var card: Control = intro.get_node("%Card")
		_expect(
			(field.position.y - DmjRail.BACKDROP_PADDING) * rail.scale.y
			>= card.get_global_rect().end.y,
			"The corridor backdrop must not crowd the narration."
		)

	_advance(intro, 2.0)
	_expect(
		drones.get_child_count() == 0,
		"No drone may appear before the title has landed."
	)

	_advance(intro, 0.6)
	_expect(
		drones.get_child_count() == 3,
		"The march cue must send out one drone per note."
	)
	_expect(
		_targetable(drones) == 3, "Every drone must still be alive when it walks out."
	)
	_expect(
		_distinct_notes(drones) == 3,
		"Each drone must ask for a different note, so the glyphs never repeat."
	)

	_advance(intro, 2.3)
	_expect(_targetable(drones) == 2, "The first note must answer exactly one drone.")

	_advance(intro, 1.2)
	_expect(_targetable(drones) == 1, "The second note must answer exactly one drone.")

	_advance(intro, 1.5)
	_expect(_targetable(drones) == 0, "The last note must clear the stage.")
	_expect(
		_in_state(drones, RustyClanky.State.DEAD) == 3,
		"Every drone must be answered — the opening must never show a drone firing."
	)

	# Stops short of the closing cue, which would hand the scene to `Router`.
	_advance(intro, 1.2)
	_expect(
		not bool(intro.get("_finished")),
		"The opening must still be running before its last second."
	)

	await _settle()
	_expect(
		str(intro.get("_card").text) == str(intro.get("cards")[3]),
		"The closing line must be the one left on screen."
	)
	_expect(
		_skip_is_wired(intro), "The opening must be skippable from the Skip button."
	)

	intro.queue_free()
	await process_frame


## The bed starts with the scene, not on a cue part-way through it.
##
## `_start_music()` is one line and looks impossible to get wrong, but it is
## the only thing standing between the opening and silence: it is reached
## through `_ready`, and the two lines above it read Settings and can throw the
## whole method away on a machine where they fail. Playing is checked, not
## called.
func _test_music_starts_with_the_scene() -> void:
	var audio := get_root().get_node_or_null("AudioManager")
	if audio == null:
		_failures.append("AudioManager must be available to the intro test.")
		return

	var intro := await _open_intro()
	if intro == null:
		return
	await _settle()

	var playing: Array[AudioStream] = []
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.playing and player.stream != null:
			playing.append(player.stream)

	# Membership, not "something is playing": the manager's SFX pool lives in
	# the same list, and a stray ping from the cue before this one would
	# otherwise answer for the music.
	_expect(not playing.is_empty(), "The opening must leave audio running.")
	_expect(
		playing.has(intro.get("music")),
		"And the opening's own backing track must be one of the streams playing."
	)

	audio.call("stop_music", 0.05)
	intro.queue_free()
	await process_frame


## Accessibility is not the opening's to decide: it reads the setting once and
## hands it to the actors, which is what this checks.
func _test_reduced_motion_reaches_the_actors() -> void:
	var settings := get_root().get_node_or_null("Settings")
	if settings == null:
		_failures.append("Settings must be available to the intro test.")
		return
	var key := _constant(settings, "REDUCED_MOTION_KEY", "accessibility/reduced_motion")
	var original: bool = settings.call("get_value", key, false)
	settings.call("set_value", key, true)

	var intro := await _open_intro()
	if intro != null:
		_expect(
			bool(intro.get("_reduced_motion")),
			"The opening must read the reduced-motion setting."
		)
		_advance(intro, 2.6)
		var drones: Node2D = intro.get_node_or_null("%Drones")
		var calmed := 0
		if drones:
			for drone in drones.get_children():
				if bool(drone.get("_reduced_motion")):
					calmed += 1
		_expect(calmed == 3, "Reduced motion must reach every drone the opening spawns.")
		_expect(
			is_zero_approx(float(intro.get("_shake"))),
			"Reduced motion must leave the stage still."
		)
		intro.queue_free()
		await process_frame

	settings.call("set_value", key, original)


# --------------------------------------------------------------------------
# Harness
# --------------------------------------------------------------------------


## Opens the opening and takes the timeline off the engine's hands, so the
## tests below step it themselves.
func _open_intro() -> Node:
	var packed := load(INTRO_SCENE) as PackedScene
	if packed == null:
		_failures.append("The opening must load.")
		return null
	var intro := packed.instantiate()
	get_root().add_child(intro)
	await process_frame
	intro.set_process(false)
	return intro


func _advance(intro: Node, seconds: float) -> void:
	var steps := int(round(seconds / STEP))
	for i in steps:
		intro.call("_process", STEP)


## Lets the tweens — which run on real time, not on the stepped timeline —
## catch up before their results are read.
func _settle() -> void:
	var deadline := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _targetable(drones: Node2D) -> int:
	var alive := 0
	for drone in drones.get_children():
		if bool(drone.call("is_targetable")):
			alive += 1
	return alive


func _in_state(drones: Node2D, state: RustyClanky.State) -> int:
	var matching := 0
	for drone in drones.get_children():
		if int(drone.get("state")) == int(state):
			matching += 1
	return matching


func _distinct_notes(drones: Node2D) -> int:
	var notes := {}
	for drone in drones.get_children():
		notes[int(drone.get("required_note")) % 12] = true
	return notes.size()


func _skip_is_wired(intro: Node) -> bool:
	var button: Button = intro.get_node_or_null("%SkipButton")
	if button == null:
		return false
	return button.pressed.is_connected(Callable(intro, "_on_skip_pressed"))


## Reads a constant off an autoload without naming the autoload's script, which
## a headless run cannot compile.
func _constant(node: Node, name: String, fallback: String) -> String:
	var map: Dictionary = node.get_script().get_script_constant_map()
	return str(map.get(name, fallback))


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Dead Metal Jam intro tests passed (%d checks)." % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr(failure)
	quit(1)
