class_name DmjTrackBed
extends AudioStreamPlayer

## The round's song, owned by the round.
##
## The framework plays music through `AudioManager`, whose players run with
## `PROCESS_MODE_ALWAYS`. That is right for a menu bed, which has to survive the
## scene change it is playing under, and wrong for a song that belongs to one
## round: the pause overlay stops the world and the song plays straight through
## it, and the overlay's own *Exit to main menu* hands the scene to `Router`
## without the round ever being told, so the song follows the player into a menu
## that has no track of its own to talk over it.
##
## Both are fixed here by construction rather than by remembering to call
## something. The bed is a node in the gameplay scene, so it dies with the
## scene; it is `PROCESS_MODE_PAUSABLE`, so the world stopping arrives here as
## a notification and nothing has to notice the pause on its behalf; and
## [method hold] keeps the position it stopped at, so resuming picks the song
## up where the player left it instead of starting the track over on every
## pause.
##
## Nothing in this file touches an autoload, so a headless `--script` run may
## reference it directly (§9.8).

## Mirrors `AudioManager.BUS_MUSIC`. Spelled out rather than read from the
## autoload so this file stays compilable before the autoloads exist — the bus
## itself is the framework's, and playing on it is what keeps the song under the
## player's music volume rather than beside it.
const MUSIC_BUS := "Music"

## [member _held] when the bed is not holding a position. Negative rather than
## zero so a pause that lands *after* the song has run out cannot be mistaken
## for one that landed on its first sample and restart the track.
const NOT_HELD := -1.0

## Where a fade-out ends. `AudioManager` uses the same floor.
const SILENT_DB := -60.0

## How long the song takes to leave at the end of a round, and how long the
## menu's own bed takes to get out of the way at the start of one.
##
## A round end is the only stop that gets a fade — a hard cut under the results
## panel reads as the game having crashed, whereas a pause or an exit has to be
## silent by the time the next thing the player sees is on screen, which is why
## [method finish] takes no fade by default.
const ROUND_END_FADE := 0.6
const MENU_HANDOVER_FADE := 0.4

## Where the song was when the world stopped. See [method hold].
var _held := NOT_HELD
var _fade: Tween


func _init() -> void:
	name = "TrackBed"
	bus = MUSIC_BUS
	# Being pausable is what turns "the world stopped" into a notification this
	# node receives, which is the whole mechanism — see [method _notification].
	process_mode = Node.PROCESS_MODE_PAUSABLE


## The song stops when the world stops, and leaves when the scene leaves.
##
## Both arrive as notifications rather than as calls, which is the point. The
## pause overlay is opened from the pause button, from Escape and from a
## gamepad's Back button, and the scene is torn down by the shell's *Exit to
## main menu*, by the overlay's own copy of that button — which never tells the
## round it is over — and by anything else that hands `Router` a scene. A
## notification catches all of them, including routes this game has never heard
## of, and it catches them here rather than in `gameplay.gd`, so the song
## cannot be left playing by some future exit nobody remembered to wire up.
##
## A pause is the one stop that is meant to be undone, so it keeps its place;
## `gameplay.gd::_on_pause_closed()` is what gives it back.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PAUSED:
			hold()
		NOTIFICATION_EXIT_TREE:
			finish()


## Starts [param stream] from the top. A null stream leaves the bed silent,
## which is what a practice ramp with no song of its own gets.
func start(track: AudioStream) -> void:
	_kill_fade()
	_held = NOT_HELD
	volume_db = 0.0
	stream = track
	if track == null:
		return
	play()


## Stops the song and remembers where it was, so [method resume] can pick it up.
##
## Returns whether there was a song to hold. The position is read rather than
## `playing`, because by the time the pause notification arrives the engine may
## already have frozen this player — a paused `AudioStreamPlayer` reports
## `playing == false` with its position still intact, which is exactly the
## thing worth keeping.
func hold() -> bool:
	if _held >= 0.0 or stream == null:
		return false
	var position := get_playback_position()
	if not playing and is_zero_approx(position):
		return false
	_kill_fade()
	_held = position
	stop()
	return true


## Picks the song up exactly where [method hold] stopped it.
##
## Returns whether it did. A bed that is not holding anything stays silent: the
## song ran out, or the round ended while the overlay was up, and neither is a
## reason to start a track playing under a player who is no longer in a round.
func resume() -> bool:
	if _held < 0.0 or stream == null or playing:
		return false
	var from := _held
	_held = NOT_HELD
	_kill_fade()
	volume_db = 0.0
	play(from)
	return true


## Ends the song, optionally over [param fade] seconds.
##
## The fade is for the end of a round, where a hard cut under the results panel
## reads as the game having crashed. Everything else — leaving the scene, the
## world stopping — passes zero, because "stopped" has to mean stopped by the
## time the next thing happens.
func finish(fade := 0.0) -> void:
	_held = NOT_HELD
	_kill_fade()
	if fade <= 0.0 or not playing or not is_inside_tree():
		stop()
		return
	_fade = create_tween()
	_fade.tween_property(self, "volume_db", SILENT_DB, fade)
	_fade.tween_callback(stop)


func _kill_fade() -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	_fade = null
