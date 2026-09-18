extends SceneTree

## No background music, including crossfades, replay, pause and legacy charts.
const SCENE := "res://games/dead_metal_jam/gameplay.tscn"
var _checks := 0
var _failures: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var settings := root.get_node("Settings")
	var values: Dictionary = settings.get("_values")
	var saved := values.duplicate(true)
	var save_timer: Timer = settings.get("_save_timer")
	var save_mode := save_timer.process_mode
	save_timer.process_mode = Node.PROCESS_MODE_DISABLED
	values[DmjOptions.NOTE_SOURCE_KEY] = DmjOptions.SOURCE_KEYBOARD
	GameCatalog.select("dead_metal_jam")
	root.get_node("GameSession").call("configure_single_player")
	var audio := root.get_node("AudioManager")
	var packed := load(SCENE) as PackedScene
	var chart := load(DmjOptions.chart_path(DmjOptions.TRACK_SONG)) as JamChart
	var previous_audio := chart.audio
	chart.audio = DmjIntroSound.note_ping(48, 4.0)

	for mode in [DmjOptions.MODE_JAM, DmjOptions.MODE_RHYTHM, DmjOptions.MODE_DEMO]:
		for track in [DmjOptions.TRACK_SONG, DmjOptions.TRACK_SONG_02, DmjOptions.TRACK_SONG_03, DmjOptions.TRACK_PRACTICE]:
			values[DmjOptions.MODE_KEY] = mode
			values[DmjOptions.TRACK_KEY] = track
			audio.call("play_music", chart.audio, 1.0)
			_check(bool(audio.call("is_music_playing")), "The handover starts with an actual pending music crossfade.")
			var game := packed.instantiate()
			root.add_child(game)
			await process_frame
			await process_frame
			game.set_process(false)
			_check(not bool(audio.call("is_music_playing")), "Every mode and track stops music before soundcheck.")
			_check(_music_players(game) == 0, "The game never creates a replacement backing-track player.")
			paused = true
			await process_frame
			_check(not bool(audio.call("is_music_playing")), "Pause stays free of background music.")
			paused = false
			game.call("_on_pause_closed")
			_check(not bool(audio.call("is_music_playing")), "Resume cannot restart old chart audio.")
			game.call("_on_play_again_pressed")
			await process_frame
			_check(not bool(audio.call("is_music_playing")), "Replay stays silent even with legacy chart audio metadata.")
			game.set("_round_active", false)
			game.call("_finish_round")
			game.queue_free()
			await process_frame
			await process_frame
			_check(not bool(audio.call("is_music_playing")), "Results and scene exit leave no music behind.")

	var before := int(audio.get("_sfx_index"))
	audio.call("play_game_hit", 1)
	_check(int(audio.get("_sfx_index")) != before, "Removing music does not mute note-hit feedback.")
	chart.audio = previous_audio
	values.clear()
	values.merge(saved, true)
	save_timer.stop()
	save_timer.process_mode = save_mode
	for voice: AudioStreamPlayer in audio.get("_sfx_pool"):
		voice.stop()
	await process_frame
	if _failures.is_empty():
		print("Dead Metal Jam focused-audio tests passed (%d checks)." % _checks)
	else:
		for failure in _failures:
			printerr(failure)
	quit(0 if _failures.is_empty() else 1)


func _music_players(node: Node) -> int:
	var count := 0
	if node is AudioStreamPlayer and (node as AudioStreamPlayer).bus == &"Music":
		count += 1
	for child in node.get_children():
		count += _music_players(child)
	return count


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)
