extends SceneTree

## Headless tests for the round's song: who owns it, and what stops it.
##
## The song is the one thing in this game that used to outlive the round that
## started it. `AudioManager` plays music on `PROCESS_MODE_ALWAYS` players, so a
## paused game kept singing over its own pause menu, and the overlay's *Exit to
## main menu* hands the scene to `Router` without the round ever being told —
## so the track followed the player into a menu that has no music of its own to
## talk over it. [DmjTrackBed] answers both by owning the player, and this file
## is the check that it does: the class on its own first, then the shipping
## scene, paused and exited for real.
##
## `gameplay.gd` can never be *preloaded* headlessly — it extends `GameShell`,
## which uses autoload instances (§9.8) — so the scene is loaded at runtime,
## by which time the autoloads exist.
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/round_music_test.gd

const GAMEPLAY_SCENE := "res://games/dead_metal_jam/gameplay.tscn"
const GAME_ID := "dead_metal_jam"

## Long enough to hold a playback position that is obviously not zero.
const BED_SECONDS := 4.0

## Shorter than the frames this test spends waiting, so it can run out on
## purpose. A pause that lands after the song is over must not restart it.
const BRIEF_SECONDS := 0.08

## Positions are read from a real mixer, so they are compared with a window
## rather than for equality. A tenth of a second is far tighter than the
## restart this is here to catch, which would come back at zero.
const POSITION_TOLERANCE := 0.1

var _failures: Array[String] = []
var _checks := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_bed_plays_on_the_music_bus()
	await _test_bed_holds_its_place()
	await _test_bed_only_resumes_what_it_held()
	await _test_bed_finish_is_final()
	await _test_the_round_owns_its_song()
	_finish()


# --------------------------------------------------------------------------
# The bed on its own
# --------------------------------------------------------------------------


## Two properties carry the whole design, and neither is visible in a scene
## file, because the bed is built in code.
func _test_bed_plays_on_the_music_bus() -> void:
	var bed := DmjTrackBed.new()
	_expect(
		bed.bus == DmjTrackBed.MUSIC_BUS,
		"The song must play on the music bus, or the player's music volume "
		+ "stops reaching the one piece of music the game has."
	)
	_expect(
		bed.process_mode == Node.PROCESS_MODE_PAUSABLE,
		"The bed must be pausable: `AudioManager`'s always-on players are "
		+ "exactly what this class exists to avoid."
	)
	bed.free()


## The point of holding rather than stopping: the player comes back to the song
## they left, not to the top of the track.
func _test_bed_holds_its_place() -> void:
	var bed := await _open_bed(BED_SECONDS)
	_expect(bed.playing, "A started bed plays.")

	var left_at := bed.get_playback_position()
	_expect(
		left_at > POSITION_TOLERANCE,
		"And it advances, or nothing below means anything."
	)

	_expect(bed.hold(), "Holding a playing bed reports that it held something.")
	_expect(not bed.playing, "A held song stops — completely, not quietly.")

	_expect(bed.resume(), "Resuming reports that it had something to resume.")
	_expect(bed.playing, "And the song is running again.")
	_expect(
		absf(bed.get_playback_position() - left_at) < POSITION_TOLERANCE,
		"It must come back where it stopped, not at the top of the track: "
		+ "left at %.3fs, came back at %.3fs."
		% [left_at, bed.get_playback_position()]
	)

	bed.finish()
	bed.free()


## Resuming is only ever allowed to undo a hold. Everything else — a bed that
## was never held, one whose song has already run out, one resumed twice — has
## to stay silent, because starting a track under a player who is not in a
## round is the same bug as never stopping it.
func _test_bed_only_resumes_what_it_held() -> void:
	var fresh := await _open_bed(BED_SECONDS)
	_expect(not fresh.resume(), "A bed that was never held has nothing to resume.")
	_expect(fresh.playing, "And the song already running is left where it is.")

	_expect(fresh.hold(), "Holding it takes its place in the song,")
	_expect(fresh.resume(), "which resuming spends,")
	_expect(not fresh.resume(), "and cannot spend twice.")
	fresh.finish()
	fresh.free()

	var brief := await _open_bed(BRIEF_SECONDS)
	await _settle(400)
	_expect(not brief.playing, "A song shorter than the round runs out on its own.")
	_expect(
		not brief.hold(),
		"Pausing after the song has run out holds nothing, so the pause has "
		+ "no position to bring back."
	)
	_expect(not brief.resume(), "And resuming cannot restart a track that ended.")
	_expect(not brief.playing, "The round stays as quiet as the player left it.")
	brief.free()


## `finish()` is what the end of a round and the end of the scene both call, so
## it has to be the end of the song in every sense: no hold left behind for a
## later resume to find, and no fade left running when it is told not to fade.
func _test_bed_finish_is_final() -> void:
	var bed := await _open_bed(BED_SECONDS)
	bed.hold()
	bed.finish()
	_expect(not bed.resume(), "Finishing clears a pending hold.")
	_expect(not bed.playing, "And leaves nothing playing.")

	bed.start(DmjIntroSound.note_ping(52, BED_SECONDS))
	await _settle(120)
	bed.finish()
	_expect(
		not bed.playing and is_zero_approx(bed.get_playback_position()),
		"A finish with no fade is immediate: stopped and back at zero, which "
		+ "is what tells a stop apart from the engine's own pause."
	)

	bed.start(DmjIntroSound.note_ping(52, BED_SECONDS))
	await _settle(120)
	bed.finish(0.4)
	_expect(bed.playing, "A finish with a fade is still audible while it fades.")
	await _settle(700)
	_expect(not bed.playing, "And silent once the fade has run out.")
	bed.free()


# --------------------------------------------------------------------------
# The shipping scene
# --------------------------------------------------------------------------


## The whole claim, against the real scene: pausing the game stops the song,
## resuming brings it back where it was, leaving the round on the way to the
## menu does not, and nothing the round played is ever left in `AudioManager`
## to follow the player out of the game.
func _test_the_round_owns_its_song() -> void:
	var packed := load(GAMEPLAY_SCENE) as PackedScene
	if packed == null:
		_expect(false, "The gameplay scene must load.")
		return

	var settings := get_root().get_node("Settings")
	var values: Dictionary = settings.get("_values")
	var saved := values.duplicate(true)
	values[DmjOptions.NOTE_SOURCE_KEY] = DmjOptions.SOURCE_KEYBOARD
	values[DmjOptions.MODE_KEY] = DmjOptions.MODE_JAM
	values[DmjOptions.TRACK_KEY] = DmjOptions.TRACK_SONG_02
	values["accessibility/audio_captions"] = false
	GameCatalog.select(GAME_ID)
	get_root().get_node("GameSession").call("configure_single_player")

	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	get_root().add_child(viewport)
	var game := packed.instantiate()
	viewport.add_child(game)
	for _frame in range(4):
		await process_frame

	var bed: DmjTrackBed = game.get("_bed")
	if bed == null:
		_expect(false, "The round must build a bed to play its song on.")
		viewport.queue_free()
		return

	_expect(bed.playing, "A round opens with its song playing.")
	_expect(
		bed.stream != null and not _manager_is_playing(bed.stream),
		"And the round's own player is the one playing it — a song left with "
		+ "`AudioManager` outlives the scene that started it."
	)

	# Let the song get somewhere first. A round paused on its first millisecond
	# cannot tell "came back where it was" apart from "started the track over".
	await _settle(400)
	var left_at := bed.get_playback_position()
	_expect(
		left_at > POSITION_TOLERANCE,
		"The song has to have played for long enough to have a place to come "
		+ "back to, and it has only reached %.3fs." % left_at
	)

	paused = true
	var parked := bed.get_playback_position()
	_expect(
		not bed.playing and is_zero_approx(parked),
		(
			"Pausing the game stops the song outright. Back at zero rather "
			+ "than parked at %.3fs, which is the difference between the round "
			+ "having stopped it and the engine having merely muted a pausable "
			+ "player."
		) % parked
	)
	_expect(
		not _manager_is_playing(bed.stream),
		"With nothing carrying on in the manager behind the overlay either."
	)

	paused = false
	game.call("_on_pause_closed")
	_expect(bed.playing, "Resuming starts it again,")
	_expect(
		absf(bed.get_playback_position() - left_at) < POSITION_TOLERANCE,
		"from where the pause stopped it: left at %.3fs, came back at %.3fs."
		% [left_at, bed.get_playback_position()]
	)

	# Exit to main menu, as the pause overlay does it: the tree is unpaused and
	# the scene is handed to `Router`, and the round is never told. Nothing
	# emits `closed`, so nothing may bring the song back.
	paused = true
	paused = false
	for _frame in range(2):
		await process_frame
	_expect(
		not bed.playing,
		"Leaving from the pause menu must not start the song up again on the "
		+ "way out — only resuming does that."
	)

	# And the scene itself leaving is the backstop, for every exit that never
	# passes through a pause at all.
	game.call("_start_track_music")
	await process_frame
	_expect(bed.playing, "A song can be running when the scene is torn down,")
	viewport.remove_child(game)
	_expect(
		not bed.playing and is_zero_approx(bed.get_playback_position()),
		"and leaving the game stops it outright rather than parking it."
	)
	_expect(
		not _manager_is_playing(bed.stream),
		"Nothing of the round is left playing for the main menu to inherit."
	)

	game.queue_free()
	viewport.queue_free()
	await process_frame
	await process_frame
	values.clear()
	values.merge(saved, true)


# --------------------------------------------------------------------------
# Harness
# --------------------------------------------------------------------------


## A bed in the tree, playing one of the game's own rendered sounds. Rendered
## rather than loaded so the length is the test's to choose.
func _open_bed(seconds: float) -> DmjTrackBed:
	var bed := DmjTrackBed.new()
	get_root().add_child(bed)
	bed.start(DmjIntroSound.note_ping(52, seconds))
	await _settle(400)
	return bed


## Whether [param stream] is playing anywhere in `AudioManager`. Membership
## rather than "something is playing": the manager's SFX voices sit in the same
## list, and a UI click would otherwise answer for the song.
func _manager_is_playing(stream: AudioStream) -> bool:
	var audio := get_root().get_node_or_null("AudioManager")
	if audio == null:
		_failures.append("AudioManager must be available to this test.")
		return false
	for child in audio.get_children():
		var player := child as AudioStreamPlayer
		if player != null and player.playing and player.stream == stream:
			return true
	return false


## Real frames, because playback positions and fades run on real time rather
## than on anything this file can step.
func _settle(milliseconds: int) -> void:
	var deadline := Time.get_ticks_msec() + milliseconds
	while Time.get_ticks_msec() < deadline:
		await process_frame


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Dead Metal Jam round music tests passed (%d checks)." % _checks)
		quit(0)
		return
	for failure in _failures:
		printerr(failure)
	quit(1)
