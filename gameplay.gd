extends GameShell

## Dead Metal Jam — the note-matching round.
##
## The HUD, countdown, lives, pause overlay, results and share card all come
## from [GameShell]. This script owns only what is specific to playing an
## instrument: the microphone, the pitch analysis and the scoring rules.
##
## The round cannot start until the room has been measured, so the countdown
## never burns seconds the player has no way to score in.

## Matches the folder name and `games/dead_metal_jam/game.gd`, so this scene can
## look up its own manifest without the framework naming it.
const GAME_ID := "dead_metal_jam"

## How long a heard note stays on screen, so a decaying string does not flicker
## away before it has been read.
const HEARD_HOLD := 0.8

const STREAK_ACHIEVEMENT_TARGET := 10

## Open strings of a guitar in standard tuning. Notes are matched by pitch
## class, so the player may take any of these an octave up or down and still
## score — which is what makes the game playable on more than one instrument.
@export var note_pool: Array[int] = [40, 45, 50, 55, 59, 64]
@export_range(1, 10, 1) var points_per_note := 1
@export_range(1, 10, 1) var miss_penalty := 1

var _detector := PitchDetector.new()
var _mic: MicCapture
var _target_note := -1
var _heard_hold := 0.0
var _hits := 0
var _misses := 0

@onready var _prompt_root: Control = %DmjPrompt
@onready var _prompt_caption: Label = %DmjPromptCaption
@onready var _target_label: Label = %DmjTarget
@onready var _heard_label: Label = %DmjHeard
@onready var _status_label: Label = %DmjStatus


func game_id() -> String:
	return GAME_ID


func _build_playfield() -> void:
	_detector.configure(AudioServer.get_mix_rate())
	_mic = MicCapture.new()
	_mic.name = "MicCapture"
	_mic.calibrated.connect(_on_calibrated)
	_mic.capture_failed.connect(_on_capture_failed)
	add_child(_mic)


## The round starts on the framework's schedule so the shell's round bookkeeping
## stays intact, but the countdown is held in [method _update_round] until the
## room has been measured. Otherwise the soundcheck would quietly eat the first
## couple of seconds of every round.
func _begin_first_round() -> void:
	_prompt_root.show()
	_prompt_caption.text = "SOUNDCHECK"
	_status_label.text = "Measuring the room. Stay quiet for a moment."
	super()


func _reset_round_state() -> void:
	_hits = 0
	_misses = 0
	_heard_hold = 0.0
	_heard_label.text = ""
	_prompt_caption.text = "PLAY THIS NOTE"
	_pick_target()


func _activate_round() -> void:
	super()
	_prompt_root.show()


func _finish_round() -> void:
	_prompt_root.hide()


func _update_round(delta: float, _time_left: float) -> void:
	if _mic == null:
		return

	# Nothing the player does can score while the room is still being measured,
	# so the countdown waits for them rather than the other way round.
	_round_timer.paused = _mic.is_calibrating()
	if _mic.is_calibrating():
		_prompt_caption.text = "SOUNDCHECK"
		_status_label.text = "Measuring the room… %d%%" % int(
			_mic.calibration_progress() * 100.0
		)
		return

	for analysis: PitchAnalysis in _detector.push_frames(_mic.poll()):
		_observe(analysis)

	_heard_hold = maxf(_heard_hold - delta, 0.0)
	if is_zero_approx(_heard_hold) and not _heard_label.text.is_empty():
		_heard_label.text = ""


## The self-test tone is reachable during a round because a silent microphone
## and a broken analyser look identical from the player's side of the screen.
func _handle_gameplay_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_T:
		return
	if _mic.toggle_test_tone():
		_status_label.text = "Self-test: playing %s for you." % MicCapture.test_tone_label()
	else:
		_status_label.text = "Back on the microphone."


func _observe(analysis: PitchAnalysis) -> void:
	if not analysis.voiced:
		return

	_heard_hold = HEARD_HOLD
	_heard_label.text = "heard %s · %+.0f cents" % [
		PitchDetector.note_label(analysis.midi_note),
		analysis.cents_off,
	]

	# Only the attack is judged. Without this a single sustained string would
	# be scored again on every hop for as long as it rang.
	if not analysis.is_onset or _target_note < 0:
		return
	if analysis.pitch_class == _target_pitch_class():
		_score_hit(analysis)
	else:
		_score_miss(analysis)

	_update_scores()
	_update_streaks()


func _score_hit(analysis: PitchAnalysis) -> void:
	_hits += 1
	_scores[PLAYER_ONE] += points_per_note
	_streaks[PLAYER_ONE] += 1
	_best_streaks[PLAYER_ONE] = maxi(
		_best_streaks[PLAYER_ONE], _streaks[PLAYER_ONE]
	)

	AudioManager.play_game_hit(_streaks[PLAYER_ONE])
	AudioManager.request_caption(
		"Correct note: %s" % PitchDetector.note_name(analysis.midi_note)
	)
	_flash_screen(_player_color(PLAYER_ONE), 0.12)
	_add_screen_shake(4.0)

	_unlock_round_achievement("first_note")
	if _streaks[PLAYER_ONE] >= STREAK_ACHIEVEMENT_TARGET:
		_unlock_round_achievement("clean_streak")
	if _streaks[PLAYER_ONE] >= 3 and (
		_streaks[PLAYER_ONE] == 3 or _streaks[PLAYER_ONE] % 5 == 0
	):
		_show_announcement(
			"%d NOTE STREAK!" % _streaks[PLAYER_ONE], _player_color(PLAYER_ONE)
		)

	_pick_target()


func _score_miss(analysis: PitchAnalysis) -> void:
	_misses += 1
	_scores[PLAYER_ONE] -= miss_penalty
	_streaks[PLAYER_ONE] = 0

	AudioManager.play_game_miss()
	AudioManager.request_caption(
		"Wrong note: %s, wanted %s" % [
			PitchDetector.note_name(analysis.midi_note),
			PitchDetector.note_name(_target_note),
		]
	)
	_flash_screen(DANGER_COLOR, 0.09)
	_add_screen_shake(8.5)

	# A wrong note is this game's mistake, so it is what the shared lives round
	# mode charges for. A no-op under the countdown.
	_lose_life(PLAYER_ONE)


## Never repeats the note just played, so a hit always visibly changes the
## prompt and the player is never left unsure whether it registered.
func _pick_target() -> void:
	if note_pool.is_empty():
		push_error("Dead Metal Jam: note_pool is empty, so there is nothing to call.")
		return
	var next := note_pool[randi() % note_pool.size()]
	if note_pool.size() > 1:
		while next == _target_note:
			next = note_pool[randi() % note_pool.size()]
	_target_note = next
	_target_label.text = PitchDetector.note_name(_target_note)
	_status_label.text = "Play %s in any octave." % PitchDetector.note_name(_target_note)


func _target_pitch_class() -> int:
	return ((_target_note % 12) + 12) % 12


func _on_calibrated(noise_floor: float) -> void:
	_detector.set_noise_floor(noise_floor)
	_detector.reset()
	_prompt_caption.text = "PLAY THIS NOTE"
	if _target_note >= 0:
		_status_label.text = "Play %s in any octave." % PitchDetector.note_name(_target_note)


## A dead microphone does not stall the round: the player can still read what
## went wrong, reach the pause menu and try the self-test, none of which is
## possible from a screen frozen on the soundcheck.
func _on_capture_failed(reason: String) -> void:
	_prompt_caption.text = "NO INPUT"
	_status_label.text = "%s Press T to play a test tone instead." % reason
