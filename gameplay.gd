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

## The chart the player asked for supplies the sections, the roster placement
## and the audio; a track it fails to compile falls back to the practice ramp,
## so a broken chart costs the song and not the round. Which charts exist is
## [constant DmjOptions.CHART_PATHS] — the same list the Settings row is built
## from, so the menu and the loader can never disagree about how many songs
## ship (§10).

## How long a heard note stays on screen, so a decaying string does not flicker
## away before it has been read.
const HEARD_HOLD := 0.8

## How long a judgement callout ("PERFECT") stays up.
const CALLOUT_HOLD := 0.5

## The rung of the combo ladder `jam_combo_eight` is named after (§6). Compared
## against the *multiplier* rather than against a streak length, so the badge
## keeps meaning what its title says if the ladder is ever re-spaced.
const SHREDDER_MULTIPLIER := 8

## Achievement ids, declared in `game.gd` (§9.6). Named here rather than typed
## into the calls so a rename is one edit and a typo is a parse error instead of
## a warning nobody reads at runtime.
const FIRST_TRACK_ACHIEVEMENT := "jam_first_track"
const PERFECT_SECTION_ACHIEVEMENT := "jam_perfect_section"
const NO_DAMAGE_ACHIEVEMENT := "jam_no_damage"
const MIC_RUN_ACHIEVEMENT := "jam_mic_run"
const SHREDDER_ACHIEVEMENT := "jam_combo_eight"

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
##
## The readout is laid out by the shell's own HUD column rather than pinned to
## the viewport, which is what keeps it from ever landing on the audio caption.
## That in turn fixes its top edge relative to the play area: the panel's own
## height plus the HUD's bottom margin, less the clearance the shell already
## applies, plus enough room for the front row of drones — a drone is drawn
## centred on its position, so the rail has to stop half a body short.
const READOUT_PANEL_HEIGHT := 208.0
const READOUT_PANEL_MARGIN := 30.0
const DRONE_FOOT_ROOM := JamBot.BODY_SIZE.y * 0.5 + 8.0
const READOUT_CLEARANCE := (
	READOUT_PANEL_HEIGHT + READOUT_PANEL_MARGIN + DRONE_FOOT_ROOM - BOTTOM_CLEARANCE
)

## Scores are floored here. A wrong note costs points and the combo, but a run
## of them must never leave the player digging out of a hole — the penalty is
## there to make experimenting cost something, not to make a round unwinnable.
const MIN_SCORE := 0

## What the banner flashes on a rail advance.
##
## This used to be the chart's own section name — CHORUS, BRIDGE. Those were
## cut because a section name is *authoring* vocabulary: it is how the person
## who wrote the chart talks about the song, and it tells a player holding an
## instrument nothing they can act on. The advance is the one stretch of a
## round where nobody can be hurt and there is nothing to read, so it is spent
## on encouragement instead. The names stay in the chart, where they are still
## worth having (§10) — they simply stop being player-facing.
##
## Keyed on how far through the track the player is rather than picked at
## random, so the line always suits the moment and two runs of the same track
## read the same way.
const ADVANCE_LINES: Array[String] = [
	"Keep on going!",
	"Nice! Keep it up!",
	"Still standing!",
	"You've got this!",
]

## Saved for the last advance of a track, because "keep going" is the wrong
## thing to say to somebody who is one wave from the end.
const LAST_ADVANCE_LINE := "Last stretch!"

## Open strings of a guitar in standard tuning. Notes are matched by pitch
## class, so the player may take any of these an octave up or down and still
## score — which is what makes the game playable on more than one instrument.
@export var note_pool: Array[int] = [40, 45, 50, 55, 59, 64]

var _router: NoteRouter
var _mic: MicNoteSource
var _keys: KeyboardNoteSource
var _director: EncounterDirector
## Charts already read off disk, by path. See [method _chart_at].
var _charts: Dictionary = {}
var _track: Array = []
var _heard_hold := 0.0
var _callout_hold := 0.0
var _hit_stop := 0.0
var _hits := 0
var _misses := 0
## Robots actually destroyed. Not the same as [member _hits] since the roster
## grew a bot that takes more than one note (§8.2), and the results copy counts
## robots while the accuracy figure counts notes.
var _kills := 0
var _track_finished := false
## Set the first time a robot completes its wind-up and fires. What
## `jam_no_damage` is really asking about is the *encounter*, not the lives
## pool: a Jam round played with nine lives and one hit taken is not an
## untouched run, and the pool is the shell's business anyway (§7).
var _took_a_hit := false
## Whether every note that has scored this round arrived on the microphone.
## Starts true and is falsified, so a round nobody played is not a microphone
## run — [member _hits] is what proves anything was played at all.
var _mic_only := true
## Whether every robot dropped in the section on the field went down on a
## Perfect. Reset by [method _on_wave_started], so it describes one section
## rather than the run.
var _section_all_perfect := true
## Kills inside the section on the field, so an empty section cannot claim to
## have been cleared perfectly.
var _section_kills := 0
## Edge-detects Demo's stop-time so the caption fires once per freeze rather
## than once per frame.
var _time_stopped := false

## The encouragement being shown for the advance in progress, empty when a wave
## is on the field. Held rather than set once because `_update_target_readout()`
## rewrites the status line every frame (§5.3).
var _advance_line_now := ""

@onready var _prompt_root: Control = %DmjPrompt
@onready var _prompt_caption: Label = %DmjPromptCaption
@onready var _target_label: Label = %DmjTarget
@onready var _heard_label: Label = %DmjHeard
@onready var _status_label: Label = %DmjStatus
@onready var _combo_label: Label = %DmjCombo
@onready var _progress_label: Label = %DmjProgress
@onready var _bottom_row: HBoxContainer = $HUD/Overlay/Margins/Layout/BottomRow


func game_id() -> String:
	return GAME_ID


## Which inputs are attached is the player's choice (Settings → Game → Note
## input). Automatic attaches every source that can run on this machine and
## lets the router decide per note; pinning to one is how a player silences a
## noisy room or a MIDI controller that is echoing their guitar.
func _build_playfield() -> void:
	# The shell's hint panel is game-supplied copy that would sit directly on
	# top of this game's note readout and repeat the one instruction it already
	# carries. The readout owns the bottom of the screen here (§5.1), so the
	# panel is folded into it — see [method _play_instruction].
	_bottom_row.hide()

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
	_director.section_started.connect(_on_section_started)
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
	_set_readout_visible(true)
	if _mic == null:
		_prompt_caption.text = "INCOMING"
		_status_label.text = _play_instruction()
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
	_track = _build_track()
	# The speed handicap slows the whole encounter (§9.7), so the timer has to
	# stretch with it. Without this, asking for an easier game would quietly
	# mean "the same timer, less of the song" and put TRACK CLEARED further out
	# of reach — the exact opposite of a help.
	var speed := maxf(Settings.gameplay_speed_scale(), 0.1)
	round_duration = clampf(
		DmjTrackBuilder.duration(_track) / speed + TRACK_TIMER_MARGIN,
		MIN_ROUND_SECONDS,
		MAX_ROUND_SECONDS
	)

	super()

	if _director == null:
		return
	# The mode is applied before the handicaps, and the two do not overlap:
	# `apply_mode` sets what kind of game this is, and everything below it sets
	# how forgiving that game is being (§3, §9.4).
	_director.apply_mode(_round_mode())
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


## The player's mode choice, translated into the director's own vocabulary.
## This is the only place in the game that maps one to the other, so the
## settings key and the rules can be renamed independently of each other.
func _round_mode() -> EncounterDirector.Mode:
	match Settings.tunable_choice(DmjOptions.MODE_KEY):
		DmjOptions.MODE_RHYTHM:
			return EncounterDirector.Mode.RHYTHM
		DmjOptions.MODE_DEMO:
			return EncounterDirector.Mode.DEMO
		_:
			return EncounterDirector.Mode.JAM


## The song, or the practice ramp the player asked for instead. Both compile to
## the same plain data, which is the whole point of the chart being a compiler
## rather than a second staging system (§10).
func _build_track() -> Array:
	var chart := _load_chart()
	if chart != null:
		var compiled := chart.to_track(EncounterDirector.LANE_COUNT)
		if not compiled.is_empty():
			return compiled

	var rng := RandomNumberGenerator.new()
	rng.seed = _rng.randi()
	return DmjTrackBuilder.build(
		note_pool, roundi(Settings.tunable(DmjOptions.WAVES_KEY)), rng
	)


## The chart for the track the player has chosen, or `null` for the practice
## ramp — which is also what an unloadable chart returns, so a bad file and a
## deliberate ramp reach [method _build_track] the same way.
func _load_chart() -> JamChart:
	return _chart_at(
		DmjOptions.chart_path(Settings.tunable_choice(DmjOptions.TRACK_KEY))
	)


## Charts are kept between rounds because one carries the round's audio as well
## as its sections, and re-reading a megabyte of song off disk to start the same
## track again would be a stutter on Play Again.
##
## **Keyed by path**, because the track is a setting the player can change
## between rounds: caching one chart in a bare `_chart` was correct when one
## song shipped and would have pinned every later round to track one the moment
## a second appeared.
func _chart_at(path: String) -> JamChart:
	if path.is_empty():
		return null
	if _charts.has(path):
		return _charts[path]
	if not ResourceLoader.exists(path):
		push_warning("Dead Metal Jam: chart '%s' is missing." % path)
		return null
	var loaded := load(path)
	if not (loaded is JamChart):
		push_warning("Dead Metal Jam: '%s' is not a JamChart." % path)
		return null
	_charts[path] = loaded
	return loaded


func _reset_round_state() -> void:
	_hits = 0
	_misses = 0
	_kills = 0
	_took_a_hit = false
	_mic_only = true
	_section_all_perfect = true
	_section_kills = 0
	_heard_hold = 0.0
	_callout_hold = 0.0
	_hit_stop = 0.0
	_track_finished = false
	_time_stopped = false
	_advance_line_now = ""
	_heard_label.text = ""
	_target_label.text = "—"
	_progress_label.text = ""
	_prompt_caption.text = "INCOMING"
	_update_combo_label()
	_director.set_track(_track)


func _activate_round() -> void:
	super()
	_set_readout_visible(true)
	_status_label.text = _play_instruction()
	_start_track_music()
	_director.begin()


## Starts the song from the top, every round.
##
## Not the shell's `music` export: that plays once, on scene ready, and a
## rhythm game whose second round opens in silence is a bug the player reads
## as the game having broken.
##
## It plays a *duplicate* of the stream, which looks redundant and is not.
## `AudioManager.play_music()` no-ops when the same stream object is already
## playing, and `stop_music()` fades out and only calls `stop()` from a tween
## callback at the *end* of that fade. Pressing Play Again inside the fade
## would hit that no-op and then be silenced by the callback already in
## flight — the silent round this is here to prevent. A fresh instance fails
## the identity check instead, so playback restarts and the pending fade is
## killed. The MP3 bytes are copy-on-write, so the copy is a handle rather
## than a second megabyte.
##
## It runs through the soundcheck on purpose — the noise floor has to be
## measured against the room the player will actually be playing in, and that
## room has this song in it (§4.3).
func _start_track_music() -> void:
	var stream := _round_music()
	if stream == null:
		return
	AudioManager.play_music(stream.duplicate(), 0.4)


## The bed for this round.
##
## A song brings its own. The practice ramp does not have one — it is generated
## from a note pool and a wave count, and it has no tempo to agree with — so it
## borrows the first track's, which is what it has played under since milestone
## 6. An arbitrary bed is a better answer than silence for the mode a player
## uses to warm up in.
func _round_music() -> AudioStream:
	var chart := _load_chart()
	if chart == null:
		chart = _chart_at(DmjOptions.chart_path(DmjOptions.TRACK_SONG))
	return chart.audio if chart != null else null


func _finish_round() -> void:
	_set_readout_visible(false)
	AudioManager.stop_music(0.6)
	# Demo may have left it paused mid-beat, and a paused timer would survive
	# into the next round.
	_round_timer.paused = false
	_time_stopped = false
	if _router != null:
		_router.set_accepting(false)
	if _director != null:
		_director.halt()


## The readout and the combo chip only mean anything while a round is running,
## so they appear and disappear together.
func _set_readout_visible(shown: bool) -> void:
	_prompt_root.visible = shown
	_combo_label.visible = shown


## The one standing instruction, plus whatever the round mode charges for a
## mistake. This is the copy the shell's hint panel used to carry; the readout
## says it once, in the place the player is already looking.
## The instruction strip. It has to describe the mode being played, because the
## three ask for different things and the readout above it is only one word.
func _play_instruction() -> String:
	var verb := "Play the note printed on each robot."
	match _round_mode():
		EncounterDirector.Mode.RHYTHM:
			verb = "Play any note as each robot arrives — timing is all that counts."
		EncounterDirector.Mode.DEMO:
			return "Play the note printed on each robot. Time waits for you, and nothing can hurt you."
	var rule := _lives_rule_note()
	if rule.is_empty():
		return verb
	return "%s %s." % [verb, rule]


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
		# The one place the speed handicap is applied. Every moving thing in the
		# encounter — the rail, the walk, the wind-up fuse and the beat itself —
		# is derived from this clock, so slowing it here slows all of them
		# together and none of them can drift out of agreement.
		_director.advance(delta * _round_gameplay_speed, _playfield_bounds())

	# Demo holds the world at each beat, so the backstop has to hold with it.
	# Otherwise "the run always finishes" (§3) would be false for exactly the
	# player Demo is for: the one who stops to find the note on the fretboard
	# and comes back to a round that ran out while they were looking.
	var stopped := _director.is_time_stopped()
	_round_timer.paused = stopped
	# Stopping time is a change in the rules with no sound and no motion to
	# announce it, which is precisely the kind of event §9.7 says must be
	# captioned. Announced on the edge, not every frame.
	if stopped != _time_stopped:
		_time_stopped = stopped
		if stopped:
			AudioManager.request_caption("Time stopped. Waiting for your note.")

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

	# Every note played lights the corridor, whether or not it counted: the
	# player struck a string either way, and a light at the camera that only
	# answers correct notes is scoring feedback wearing a light's clothes.
	# How *much* it lights is where the difference shows.
	var landed := int(judgement.get("kind", EncounterDirector.Judgement.NOISE))
	_director.flash_rail(
		(0.75 if landed == EncounterDirector.Judgement.HIT else 0.3)
		+ event.velocity * 0.25
	)

	_update_scores()
	_update_streaks()
	_update_combo_label()


func _score_hit(event: NoteEvent, judgement: Dictionary) -> void:
	_hits += 1
	_add_score(int(judgement.get("points", 0)))
	_streaks[PLAYER_ONE] += 1
	_best_streaks[PLAYER_ONE] = maxi(
		_best_streaks[PLAYER_ONE], _streaks[PLAYER_ONE]
	)

	var tier := int(judgement.get("tier", EncounterDirector.Tier.EDGE))
	_show_callout(EncounterDirector.tier_name(tier))

	# A correct note does not always end a robot: a [PlatedKnuckle] sheds one
	# plate and keeps walking (§8.2). It scores and it feeds the combo either
	# way — the difference is only how hard the world reacts, so the player can
	# tell "that one is down" from "keep going".
	var killed := bool(judgement.get("killed", true))
	var drone: JamBot = judgement.get("drone")
	if killed:
		_kills += 1
		_section_kills += 1

	# A section is "clear with every kill at Perfect", so it is the tier of the
	# note that *drops* a robot that counts. Shedding a plate at Good and then
	# finishing the phrase on a Perfect is a Perfect kill: the plate was not
	# the robot.
	if killed and tier != EncounterDirector.Tier.PERFECT:
		_section_all_perfect = false
	if event.source != NoteEvent.Source.MIC:
		_mic_only = false

	AudioManager.play_game_hit(_streaks[PLAYER_ONE])
	AudioManager.request_caption(
		"%s: %s%s" % [
			EncounterDirector.tier_name(tier),
			PitchDetector.note_name(event.midi_note),
			_remaining_phrase_note(drone, killed),
		]
	)
	_flash_screen(_player_color(PLAYER_ONE), 0.12 if killed else 0.07)
	# A harder-played note hits harder. Velocity colours the reaction; it never
	# decides whether the note counted.
	var punch := 3.0 if killed else 1.6
	_add_screen_shake(punch + event.velocity * punch)

	_unlock_skill_achievement(
		SHREDDER_ACHIEVEMENT,
		EncounterDirector.combo_multiplier(_streaks[PLAYER_ONE]) >= SHREDDER_MULTIPLIER
	)
	if _streaks[PLAYER_ONE] >= 3 and (
		_streaks[PLAYER_ONE] == 3 or _streaks[PLAYER_ONE] % 5 == 0
	):
		_show_announcement(
			"%d NOTE STREAK!" % _streaks[PLAYER_ONE], _player_color(PLAYER_ONE)
		)


## Spoken half of the plate feedback. The caption is the accessible channel for
## everything the screen says (§9.7), so "two to go" has to reach it too.
func _remaining_phrase_note(drone: JamBot, killed: bool) -> String:
	if killed or drone == null or not is_instance_valid(drone):
		return ""
	var left := drone.demand_size()
	if left <= 0:
		return ""
	return ". %d note%s to go" % [left, "" if left == 1 else "s"]


## A note played at drones that are on the field but naming none of them. It
## costs points and the combo, and never a life in any round mode (§7.3) —
## otherwise experimenting is punished, in a game whose whole subject is
## playing an instrument.
func _score_wrong_note(event: NoteEvent, judgement: Dictionary) -> void:
	_misses += 1
	_add_score(int(judgement.get("points", 0)))
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
## unconditional in every mode that reports damage: it no-ops under the
## countdown, so the game never branches on the round mode (§7.1).
##
## Demo is the exception, and it is the director that says so rather than a
## mode test here — nobody can die in Demo under either round mode (§3).
func _on_drone_fired(_drone: JamBot) -> void:
	_streaks[PLAYER_ONE] = 0
	_hit_stop = HIT_STOP
	_took_a_hit = true
	_update_streaks()
	_update_combo_label()
	if _director.reports_damage:
		_lose_life(PLAYER_ONE)


## Every change to the score goes through here, so the floor at
## [constant MIN_SCORE] cannot be sidestepped by a new scoring event.
func _add_score(points: int) -> void:
	_scores[PLAYER_ONE] = maxi(_scores[PLAYER_ONE] + points, MIN_SCORE)


## The rail has started travelling toward the next wave. This is the only
## moment in a round when nobody can be hurt, so it is the moment the banner
## gets to say something (§5.3, §8.1).
##
## The section's own name arrives here and is deliberately dropped — see
## [constant ADVANCE_LINES].
func _on_section_started(_name: String, index: int, total: int) -> void:
	_prompt_caption.text = "RAIL ADVANCING"
	_progress_label.text = _progress_caption(index, total)
	_advance_line_now = _advance_line(index, total)
	AudioManager.request_caption(
		"Rail advancing. Wave %d of %d. %s" % [index + 1, total, _advance_line_now]
	)
	# Not on the opening advance: the shell has just announced GO! and two
	# banners in the same frame read as a glitch rather than as a cue.
	if index > 0:
		_show_announcement(_advance_line_now.to_upper(), StudioInfo.CREAM)


func _on_wave_started(index: int, total: int) -> void:
	_prompt_caption.text = "INCOMING"
	_progress_label.text = _progress_caption(index, total)
	_advance_line_now = ""
	_section_all_perfect = true
	_section_kills = 0
	_status_label.text = _play_instruction()


## The banner text: how far through the track the player is, and nothing else.
##
## It reads the same whether the track is a charted song or the practice ramp,
## so the HUD does not change shape when the player switches tracks (§5.3).
##
## Static so a headless test can reach it: `gameplay.gd` can never be
## instantiated in one (§9.8), but a pure function on it can still be called.
static func _progress_caption(index: int, total: int) -> String:
	return "WAVE %d / %d" % [index + 1, total]


static func _advance_line(index: int, total: int) -> String:
	if total > 1 and index >= total - 1:
		return LAST_ADVANCE_LINE
	return ADVANCE_LINES[index % ADVANCE_LINES.size()]


func _on_wave_cleared(_index: int, clean: bool) -> void:
	# Unlocked here rather than at the end of the round because a section is
	# the unit being claimed: a player who plays one section perfectly and then
	# falls apart has still done the thing.
	_unlock_skill_achievement(
		PERFECT_SECTION_ACHIEVEMENT, _section_kills > 0 and _section_all_perfect
	)
	if not clean:
		return
	_add_score(EncounterDirector.SECTION_CLEAR_BONUS)
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
	_progress_label.text = "TRACK CLEARED"
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
			# This runs every frame and would otherwise overwrite whatever
			# `_on_section_started()` wrote one frame earlier, so the advance's
			# line is held rather than set once and lost.
			_status_label.text = (
				"Breathe. %s" % _advance_line_now
				if not _advance_line_now.is_empty()
				else "Breathe. The next wave is coming."
			)
		return

	var front: JamBot = live[0]
	# Asks the bot how much it still wants rather than what kind of bot it is,
	# so a new enemy never means editing the readout (§5.1).
	var demand := front.demand_size()

	# Rhythm asks for an attack, not a pitch (§3), so printing a letter there
	# would be the game telling the player to do something it is not going to
	# check. The readout has to say what is actually being judged.
	if not _director.pitch_matters:
		_prompt_caption.text = (
			"PLAY ANY NOTE" if demand <= 1
			else "PLAY ANY %d NOTES" % demand
		)
		_target_label.text = "ANY"
		return

	if _director.is_time_stopped():
		_prompt_caption.text = "WAITING FOR YOU"
	else:
		_prompt_caption.text = (
			"PLAY THIS NOTE" if demand <= 1
			else "PLAY THIS PHRASE · %d LEFT" % demand
		)
	_target_label.text = PitchDetector.note_name(front.required_note)


func _update_combo_label() -> void:
	var multiplier := EncounterDirector.combo_multiplier(_streaks[PLAYER_ONE])
	_combo_label.text = "COMBO x%d" % multiplier


func _show_callout(text: String) -> void:
	_callout.text = text
	_callout_hold = CALLOUT_HOLD


func _round_totals() -> Dictionary:
	return {"hits": _hits, "attempts": _hits + _misses}


## The five achievements this game grants (§9.6). Three are settled here, at the
## end of a round; the two that describe a moment rather than a run are granted
## as they happen, from [method _score_hit] and [method _on_wave_cleared].
##
## Every one of them turns on the track being *finished* rather than on the
## round being over. A round can end because the backstop timer ran out or
## because the lives pool emptied, and neither of those is a track anybody
## played to the end.
func _award_round_achievements(_player_one_total: int, _player_two_total: int) -> void:
	if not _track_finished:
		return

	_unlock_round_achievement(FIRST_TRACK_ACHIEVEMENT)

	# The other two are Jam-only because that is what they claim on the tin:
	# nothing can fire at a player in Demo, and Rhythm is not being asked for
	# the notes it would have had to play to earn either of them. The mode is
	# read off the director rather than out of Settings, so a mode changed from
	# the pause menu cannot re-label the round that has just been played.
	if _director == null or _director.mode() != EncounterDirector.Mode.JAM:
		return
	if not _took_a_hit:
		_unlock_round_achievement(NO_DAMAGE_ACHIEVEMENT)
	if _mic_only and _hits > 0:
		_unlock_round_achievement(MIC_RUN_ACHIEVEMENT)


## Grants an achievement that is a claim about *skill*, which Demo mode is
## built to remove.
##
## Demo stops the world at every beat and resumes it the instant the right note
## lands (§3), so nobody in Demo can be late and nobody in Demo can drop a
## streak. A Perfect there is the mode's doing, not the player's, and an
## achievement handed out for something the game did on the player's behalf is
## worth nothing to the player who earned it properly. Rhythm still counts:
## timing is judged there, so the streak and the tier are both still real.
##
## This is the game's only branch on the round mode, and it is not a rule — the
## rules stay identical in all three modes (§7.1). It is a statement about what
## a badge means.
func _unlock_skill_achievement(id: String, earned: bool) -> void:
	if not earned or _director == null:
		return
	if _director.mode() == EncounterDirector.Mode.DEMO:
		return
	_unlock_round_achievement(id)


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
	# The mode is named because a Demo run and a Jam run are not the same
	# achievement, and the results panel is the only place the two can be told
	# apart after the fact.
	var mode := EncounterDirector.mode_name(_director.mode()).capitalize()
	if _kills <= 0:
		return "No robots down this track. (%s)" % mode
	return "%d robots down, best combo x%d. (%s)" % [
		_kills,
		EncounterDirector.combo_multiplier(_best_streaks[PLAYER_ONE]),
		mode,
	]


func _on_calibrated(_noise_floor: float) -> void:
	_prompt_caption.text = "INCOMING"
	_status_label.text = _play_instruction()


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
