extends GameShell

## Dead Metal Jam — the note-matching rail shooter round.
##
## The HUD, countdown, lives, pause overlay, results and share card all come
## from [GameShell]. This script owns only what is specific to playing an
## instrument at robots: the input sources, the encounter it feeds, and how a
## judgement becomes score, combo and damage.
##
## It talks to [NoteRouter] and never to a source directly, so it cannot tell
## whether a note arrived from a guitar, a MIDI keyboard or the computer
## keyboard — which is what makes adding an input a local change (§4.1). It
## talks to [EncounterDirector] and never to a drone directly, for the same
## reason: the rules live there, and they are tested there.
##
## The round cannot start until the room has been measured, so the countdown
## never burns seconds the player has no way to score in.

## Matches the folder name and `games/dead_metal_jam/game.gd`, so this scene can
## look up its own manifest without the framework naming it.
const GAME_ID := "dead_metal_jam"

## How long a heard note stays on screen, so a decaying string does not flicker
## away before it has been read.
const HEARD_HOLD := 0.8

## How long a judgement callout ("PERFECT") stays up.
const CALLOUT_HOLD := 0.5

const STREAK_ACHIEVEMENT_TARGET := 10

## Frozen time after taking damage (§5.2). Implemented by holding the encounter
## still for a moment rather than by touching `Engine.time_scale`, which would
## fight the shell's round timer, its tweens and the pause overlay.
const HIT_STOP := 0.12

## Waves in a practice track are the player's own option now; the chart's own
## section count replaces them once the chart format lands (§10).

## Slack added to the round timer on top of the track's own length, so the
## backstop never cuts off a drone that is still legitimately in play.
const TRACK_TIMER_MARGIN := 4.0

## `GameShell.round_duration` is an exported range; the track length is clamped
## into it rather than silently overflowing.
const MIN_ROUND_SECONDS := 5.0
const MAX_ROUND_SECONDS := 180.0

## Toggles the microphone self-test tone. A function key rather than a letter
## because every letter in the home rows is a piano key once the keyboard
## source is attached (§4.5). Rebindable from Settings → Controls, so the key
## itself is declared in [DmjOptions] and read from [Settings] at press time.

## Vertical strip reserved at the bottom of the screen for the note readout, so
## drones never walk underneath the most important widget in the game (§5.1).
const READOUT_CLEARANCE := 132.0

## Open strings of a guitar in standard tuning. Notes are matched by pitch
## class, so the player may take any of these an octave up or down and still
## score — which is what makes the game playable on more than one instrument.
@export var note_pool: Array[int] = [40, 45, 50, 55, 59, 64]

var _router: NoteRouter
var _mic: MicNoteSource
var _keys: KeyboardNoteSource
var _director: EncounterDirector
var _track: Array = []
var _heard_hold := 0.0
var _callout_hold := 0.0
var _hit_stop := 0.0
var _hits := 0
var _misses := 0
var _track_finished := false

@onready var _prompt_root: Control = %DmjPrompt
@onready var _prompt_caption: Label = %DmjPromptCaption
@onready var _target_label: Label = %DmjTarget
@onready var _heard_label: Label = %DmjHeard
@onready var _status_label: Label = %DmjStatus
@onready var _combo_label: Label = %DmjCombo
@onready var _section_label: Label = %DmjSection


func game_id() -> String:
	return GAME_ID


## Which inputs are attached is the player's choice (Settings → Game → Note
## input). Automatic attaches every source that can run on this machine and
## lets the router decide per note; pinning to one is how a player silences a
## noisy room or a MIDI controller that is echoing their guitar.
func _build_playfield() -> void:
	_router = NoteRouter.new()
	_router.name = "NoteRouter"
	_router.note_started.connect(_on_note_started)
	add_child(_router)

	var preference := Settings.tunable_choice(DmjOptions.NOTE_SOURCE_KEY)

	# A source with nothing to listen to reports itself unavailable rather
	# than being left out, so the reason can reach the player.
	if _source_enabled(preference, DmjOptions.SOURCE_MIC):
		_mic = MicNoteSource.new()
		_mic.name = "MicNoteSource"
		_mic.calibrated.connect(_on_calibrated)
		_mic.capture_failed.connect(_on_capture_failed)
		_router.add_source(_mic)

	if _source_enabled(preference, DmjOptions.SOURCE_MIDI):
		var midi := MidiNoteSource.new()
		midi.name = "MidiNoteSource"
		_router.add_source(midi)

	if _source_enabled(preference, DmjOptions.SOURCE_KEYBOARD):
		_keys = KeyboardNoteSource.new()
		_keys.name = "KeyboardNoteSource"
		_keys.octave_down_key = Settings.binding_keycode(
			DmjOptions.OCTAVE_DOWN_BINDING
		)
		_keys.octave_up_key = Settings.binding_keycode(
			DmjOptions.OCTAVE_UP_BINDING
		)
		_router.add_source(_keys)

	# Nothing scores until the round is actually running.
	_router.set_accepting(false)

	_director = EncounterDirector.new()
	_director.name = "EncounterDirector"
	_director.drone_fired.connect(_on_drone_fired)
	_director.wave_started.connect(_on_wave_started)
	_director.wave_cleared.connect(_on_wave_cleared)
	_director.track_cleared.connect(_on_track_cleared)
	_playfield.add_child(_director)


func _source_enabled(preference: int, source: int) -> bool:
	return preference == DmjOptions.SOURCE_AUTO or preference == source


## The round starts on the framework's schedule so the shell's round bookkeeping
## stays intact, but the countdown is held in [method _update_round] until the
## room has been measured. Otherwise the soundcheck would quietly eat the first
## couple of seconds of every round.
func _begin_first_round() -> void:
	_prompt_root.show()
	if _mic == null:
		_prompt_caption.text = "INCOMING"
		_status_label.text = "Play the note printed on each robot."
	else:
		_prompt_caption.text = "SOUNDCHECK"
		_status_label.text = "Measuring the room. Stay quiet for a moment."
	super()


## The track is built here rather than in [method _reset_round_state] because
## the shell reads `round_duration` immediately after this returns, and "a round
## is one track" (§2) — the chart's length sets the round length, not the other
## way round. The timer is only a backstop; a played-out track ends the round
## early through TRACK CLEARED (§7.4).
func _load_round_settings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	_track = DmjTrackBuilder.build(
		note_pool, roundi(Settings.tunable(DmjOptions.WAVES_KEY)), rng
	)
	round_duration = clampf(
		DmjTrackBuilder.duration(_track) + TRACK_TIMER_MARGIN,
		MIN_ROUND_SECONDS,
		MAX_ROUND_SECONDS
	)

	super()

	if _director == null:
		return
	# Reuses the shared "make it easier" handicap rather than adding a second
	# difficulty dial (§6); the game's own leniency option multiplies into it
	# so the two agree instead of competing.
	_director.window_scale = (
		_round_target_size * Settings.tunable(DmjOptions.TIMING_WINDOW_KEY)
	)
	_director.wrong_note_penalty = roundi(
		Settings.tunable(DmjOptions.WRONG_NOTE_PENALTY_KEY)
	)
	_director.set_reduced_motion(_reduced_motion_enabled)


func _reset_round_state() -> void:
	_hits = 0
	_misses = 0
	_heard_hold = 0.0
	_callout_hold = 0.0
	_hit_stop = 0.0
	_track_finished = false
	_heard_label.text = ""
	_target_label.text = "—"
	_section_label.text = ""
	_prompt_caption.text = "INCOMING"
	_update_combo_label()
	_director.set_track(_track)


func _activate_round() -> void:
	super()
	_prompt_root.show()
	_hint.text = "Play the note on each robot before it fires. %s" % (
		_lives_rule_note()
	)
	_director.begin()


func _finish_round() -> void:
	_prompt_root.hide()
	if _router != null:
		_router.set_accepting(false)
	if _director != null:
		_director.halt()


func _update_round(delta: float, _time_left: float) -> void:
	if _router == null:
		return

	# Nothing the player does can score while the room is still being measured,
	# so the countdown waits for them rather than the other way round. This
	# gates every source, not just the microphone: a MIDI note played during
	# the soundcheck is no more scoreable than a strummed one. With the
	# microphone switched off there is no room to measure, so play starts at
	# once.
	var calibrating := _mic != null and _mic.is_calibrating()
	_round_timer.paused = calibrating
	_router.set_accepting(not calibrating and not _player_is_out(PLAYER_ONE))
	if calibrating:
		_prompt_caption.text = "SOUNDCHECK"
		_status_label.text = "Measuring the room… %d%%" % int(
			_mic.calibration_progress() * 100.0
		)
		return

	if _hit_stop > 0.0:
		_hit_stop = maxf(_hit_stop - delta, 0.0)
	else:
		_director.advance(delta, _playfield_bounds())

	_update_target_readout()

	_heard_hold = maxf(_heard_hold - delta, 0.0)
	if is_zero_approx(_heard_hold) and not _heard_label.text.is_empty():
		_heard_label.text = ""

	_callout_hold = maxf(_callout_hold - delta, 0.0)
	if is_zero_approx(_callout_hold) and not _callout.text.is_empty():
		_callout.text = ""


## Drones walk down the play area, so its bottom is raised to clear the note
## readout. Everything else stays on the shell's own clearances.
func _playfield_bounds() -> Rect2:
	var bounds := super()
	bounds.size.y = maxf(bounds.size.y - READOUT_CLEARANCE, 80.0)
	return bounds


## The self-test tone is reachable during a round because a silent microphone
## and a broken analyser look identical from the player's side of the screen.
## The key is the player's own binding, not a fixed one.
func _handle_gameplay_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.keycode != Settings.binding_keycode(DmjOptions.SELF_TEST_BINDING):
		return
	if _mic == null:
		_status_label.text = "The microphone is switched off in Settings."
		return
	if _mic.toggle_test_tone():
		_status_label.text = "Self-test: playing %s for you." % MicCapture.test_tone_label()
	else:
		_status_label.text = "Back on the microphone."


## The practice keyboard's octave keys are rebindable, so a change made from
## the pause menu reaches the live source rather than waiting for a new round.
func _on_controls_changed() -> void:
	super()
	if _keys == null:
		return
	_keys.octave_down_key = Settings.binding_keycode(
		DmjOptions.OCTAVE_DOWN_BINDING
	)
	_keys.octave_up_key = Settings.binding_keycode(
		DmjOptions.OCTAVE_UP_BINDING
	)


## One note, from whichever input produced it. By the time it arrives the
## router has already applied that source's latency compensation and dropped it
## if another source reported the same note a moment earlier.
func _on_note_started(event: NoteEvent) -> void:
	if _player_is_out(PLAYER_ONE):
		return

	_heard_hold = HEARD_HOLD
	_heard_label.text = "heard %s · %s" % [
		PitchDetector.note_label(event.midi_note),
		(
			"%+.0f cents" % event.cents_off
			if event.source == NoteEvent.Source.MIC
			else NoteEvent.source_name(event.source).to_lower()
		),
	]

	# MIDI and the computer keyboard are exact by construction, so they always
	# earn the intonation bonus; the microphone has to play in tune for it.
	var exact := event.source != NoteEvent.Source.MIC
	var judgement := _director.resolve_note(
		event.pitch_class, _streaks[PLAYER_ONE], event.cents_off, exact
	)

	match int(judgement.get("kind", EncounterDirector.Judgement.NOISE)):
		EncounterDirector.Judgement.HIT:
			_score_hit(event, judgement)
		EncounterDirector.Judgement.WRONG_NOTE:
			_score_wrong_note(event, judgement)
		_:
			_score_noise()

	_update_scores()
	_update_streaks()
	_update_combo_label()


func _score_hit(event: NoteEvent, judgement: Dictionary) -> void:
	_hits += 1
	_scores[PLAYER_ONE] += int(judgement.get("points", 0))
	_streaks[PLAYER_ONE] += 1
	_best_streaks[PLAYER_ONE] = maxi(
		_best_streaks[PLAYER_ONE], _streaks[PLAYER_ONE]
	)

	var tier := int(judgement.get("tier", EncounterDirector.Tier.EDGE))
	_show_callout(EncounterDirector.tier_name(tier))

	AudioManager.play_game_hit(_streaks[PLAYER_ONE])
	AudioManager.request_caption(
		"%s: %s" % [
			EncounterDirector.tier_name(tier),
			PitchDetector.note_name(event.midi_note),
		]
	)
	_flash_screen(_player_color(PLAYER_ONE), 0.12)
	# A harder-played note hits harder. Velocity colours the reaction; it never
	# decides whether the note counted.
	_add_screen_shake(3.0 + event.velocity * 3.0)

	_unlock_round_achievement("first_note")
	if _streaks[PLAYER_ONE] >= STREAK_ACHIEVEMENT_TARGET:
		_unlock_round_achievement("clean_streak")
	if _streaks[PLAYER_ONE] >= 3 and (
		_streaks[PLAYER_ONE] == 3 or _streaks[PLAYER_ONE] % 5 == 0
	):
		_show_announcement(
			"%d NOTE STREAK!" % _streaks[PLAYER_ONE], _player_color(PLAYER_ONE)
		)


## A note played at drones that are on the field but naming none of them. It
## costs points and the combo, and never a life in any round mode (§7.3) —
## otherwise experimenting is punished, in a game whose whole subject is
## playing an instrument.
func _score_wrong_note(event: NoteEvent, judgement: Dictionary) -> void:
	_misses += 1
	_scores[PLAYER_ONE] += int(judgement.get("points", 0))
	_streaks[PLAYER_ONE] = 0

	AudioManager.play_game_miss()
	AudioManager.request_caption(
		"Wrong note: %s" % PitchDetector.note_name(event.midi_note)
	)
	# Deliberately inert rather than punishing-loud: a wrong note changes
	# nothing in the world, or players stop experimenting (§5.2).
	_flash_screen(DANGER_COLOR, 0.06)


## A note played with nothing valid to hit — between waves, or at a drone that
## has not reached its window yet. Costs the combo, never the score (§6).
func _score_noise() -> void:
	_streaks[PLAYER_ONE] = 0


## A drone completed its wind-up and fired. This is the game's one mistake, so
## it is the one thing reported to the shell's lives pool. The call is
## unconditional: it no-ops under the countdown, so the game never branches on
## the round mode (§7.1).
func _on_drone_fired(_drone: RustDrone) -> void:
	_streaks[PLAYER_ONE] = 0
	_hit_stop = HIT_STOP
	_update_streaks()
	_update_combo_label()
	_lose_life(PLAYER_ONE)


func _on_wave_started(index: int, total: int) -> void:
	_prompt_caption.text = "INCOMING"
	_section_label.text = "WAVE %d / %d" % [index + 1, total]
	_status_label.text = "Play the note printed on each robot."


func _on_wave_cleared(_index: int, clean: bool) -> void:
	if not clean:
		return
	_scores[PLAYER_ONE] += EncounterDirector.SECTION_CLEAR_BONUS
	_update_scores()
	_show_announcement(
		"WAVE CLEAR +%d" % EncounterDirector.SECTION_CLEAR_BONUS,
		StudioInfo.CREAM
	)
	AudioManager.request_caption("Wave cleared with no damage.")


## The chart ran out before the round did. The shell has no public verb for
## winning early, so this calls the inherited settle path directly (§7.4) —
## the same one the countdown and an empty lives pool both use.
func _on_track_cleared() -> void:
	if _track_finished or not _round_active:
		return
	_track_finished = true
	_section_label.text = "TRACK CLEARED"
	_show_announcement("TRACK CLEARED", StudioInfo.CREAM)
	_spawn_round_confetti(_player_color(PLAYER_ONE))
	_end_round()


## The big letter is whatever a note would hit right now, so the readout and
## the outlined drone on the field always agree.
func _update_target_readout() -> void:
	var live := _director.live_drones()
	if live.is_empty():
		_target_label.text = "—"
		if _director.phase() == EncounterDirector.Phase.ADVANCING:
			_prompt_caption.text = "RAIL ADVANCING"
			_status_label.text = "Breathe. The next wave is coming."
		return
	_prompt_caption.text = "PLAY THIS NOTE"
	_target_label.text = PitchDetector.note_name(live[0].required_note)


func _update_combo_label() -> void:
	var multiplier := EncounterDirector.combo_multiplier(_streaks[PLAYER_ONE])
	_combo_label.text = "COMBO x%d" % multiplier


func _show_callout(text: String) -> void:
	_callout.text = text
	_callout_hold = CALLOUT_HOLD


func _round_totals() -> Dictionary:
	return {"hits": _hits, "attempts": _hits + _misses}


func _player_stats(player_index: int) -> Dictionary:
	if player_index != PLAYER_ONE:
		return super(player_index)
	return {
		"score": _scores[PLAYER_ONE],
		"hits": _hits,
		"misses": _misses,
		"accuracy": _accuracy_percent(_hits, _hits + _misses),
		"streak": _best_streaks[PLAYER_ONE],
	}


func _round_highlight_summary() -> String:
	if _hits <= 0:
		return "No robots down this track."
	return "%d robots down, best combo x%d." % [
		_hits, EncounterDirector.combo_multiplier(_best_streaks[PLAYER_ONE])
	]


func _on_calibrated(_noise_floor: float) -> void:
	_prompt_caption.text = "INCOMING"
	_status_label.text = "Play the note printed on each robot."


## A dead microphone does not stall the round, and no longer even stops play:
## the MIDI and keyboard sources are attached independently, so the message
## says what is still possible rather than only what broke.
func _on_capture_failed(reason: String) -> void:
	var alternatives := _router.available_sources().size()
	if alternatives > 0:
		_prompt_caption.text = "INCOMING"
		_status_label.text = "%s Playing on: %s." % [
			reason, _router.describe_sources().replace("\n", ", ")
		]
		return
	_prompt_caption.text = "NO INPUT"
	_status_label.text = "%s Press %s to play a test tone instead." % [
		reason, Settings.binding_key_label(DmjOptions.SELF_TEST_BINDING)
	]
