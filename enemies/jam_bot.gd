class_name JamBot
extends Node2D

## Everything every enemy in the roster does, minus the thing that makes it
## that enemy (§8.2).
##
## A bot snaps into a firing position, aims through its musical lead-in,
## winds up, then fires. It owns none of the judgement: it only reports
## where it is in its life and which note it is asking for right now, so
## [EncounterDirector] can rule on it.
##
## Subclasses supply three things and nothing else:
##
## - **what it is asking for** — [method accepts_pitch_class] and the
##   [member required_note] it keeps in step with its own state,
## - **what a correct note does to it** — [method strike], which may break one
##   plate rather than kill,
## - **what it looks like** — [method _create_art].
##
## The split exists because the roster's whole point is that each enemy asks
## for something different (§8.2). Approach, depth, wind-up and death are the
## same question for all of them, and duplicating them per enemy is how the
## timing rules drift apart between one bot and the next.
##
## This script must never touch an autoload instance. Headless `--script` runs
## compile it before autoloads exist, so `encounter_test.gd` could not name the
## type if it did. Settings arrive through [method set_reduced_motion] instead.

enum State {
	## Aiming from a firing position. The legacy name preserves chart contracts.
	APPROACH,
	## The bonus beat has passed. Still killable before the gun fires.
	WINDUP,
	## Fired at the player. No longer a target.
	FIRED,
	## Killed by the right note. Fading out.
	DEAD,
}

## Body size at full depth. Everything else is drawn relative to this so the
## whole actor scales with one `scale` assignment.
const BODY_SIZE := DmjDroneArt.SIZE

## Apparent size at the horizon, as a fraction of full size.
const HORIZON_SCALE := 0.34

## Lane separation at the horizon, as a fraction of separation at the front.
## Lanes converging with distance is the entire depth illusion (§8.1).
const HORIZON_LANE_SPREAD := 0.22

## Space above the firing floor for the room's back wall and ceiling.
## The scenery and actors share this inset so feet land on the same surface.
const HORIZON_HEADROOM := 0.26

## Dust hanging between the player and the far end. Multiplied into a bot, so
## this is what the furthest one is tinted *towards*, never past.
const DEPTH_FOG := Color("9c8871")

## How much of the way to [constant DEPTH_FOG] the furthest bot goes. Short of
## the whole way on purpose: the glyph on a distant bot is the note the player
## is being asked for, so distance may cost it contrast but never legibility.
const FOG_STRENGTH := 0.7

const DEATH_FADE := DmjDroneArt.DESTRUCTION_SECONDS
const QUIET_DEATH_FADE := 0.22

## How long the muzzle flash of a drone that fired stays up (§5.2).
const FIRED_FADE := 0.34
const ENTRY_SECONDS := 0.25

const CHASSIS := DmjDroneArt.RUST
const CHASSIS_DARK := DmjDroneArt.RUST_DARK
const GLYPH_INK := DmjDroneArt.NOTE_INK
const WINDUP_COLOR := DmjDroneArt.HOSTILE
const TARGET_OUTLINE := DmjDroneArt.ACCENT

## The note the player must play *right now*. Multi-note enemies move it as
## their sequence advances, so the readout, the glyph and the matching rule all
## keep reading one value rather than each asking a different question.
var required_note := -1
var lane := 1
var approach_seconds := 4.0
var windup_seconds := 1.6
var state: State = State.APPROACH
## Fits the larger character drawings into short playfields, without changing
## their position, approach duration or judgement clock.
var visual_scale := 1.0
var arena_index := 0
var firing_slot := 0
var presentation_speed := 1.0
var show_attack_bar := true

var _elapsed := 0.0
var _windup_elapsed := 0.0
var _dead_elapsed := 0.0
var _fired_elapsed := 0.0
var _targeted := false
var _reduced_motion := false
var _effects_enabled := true
var _feedback_age := -1.0
var _death_animated := false
var _art: DmjDroneArt
## Seconds added to this bot's beat by its own progress. Zero for anything that
## dies to one note; a plate broken by [PlatedKnuckle] pushes the next beat out
## by one plate interval.
var _beat_offset := 0.0


func _init() -> void:
	set_process(false)


func _process(delta: float) -> void:
	advance_feedback(delta)


## Reactions finish even when Demo holds its next beat; normal scene pause applies.
func advance_feedback(delta: float) -> void:
	if _feedback_age < 0.0:
		return
	_feedback_age += delta
	_sync_art()
	if _feedback_age >= (_death_duration() if state == State.DEAD else 0.28):
		set_process(false)


func react_to_hit() -> void:
	_feedback_age = 0.0
	set_process(true)
	_sync_art()


## Places the bot in a lane with the note it demands. Called once at spawn;
## every timing decision afterwards is driven from these numbers.
func configure(
	drone_lane: int,
	note: int,
	approach_time: float,
	windup_time: float
) -> void:
	lane = drone_lane
	required_note = note
	approach_seconds = maxf(approach_time, 0.05)
	windup_seconds = maxf(windup_time, 0.05)
	state = State.APPROACH
	_elapsed = 0.0
	_windup_elapsed = 0.0
	_dead_elapsed = 0.0
	_fired_elapsed = 0.0
	_beat_offset = 0.0
	_targeted = false
	_feedback_age = -1.0
	_death_animated = false
	set_process(false)
	_sync_art()


## Advances one frame and returns `true` on the single frame the bot fires, so
## the caller cannot miss the transition by polling at the wrong moment.
func advance(delta: float, field: Rect2, lane_count: int) -> bool:
	var fired_now := false

	match state:
		State.APPROACH, State.WINDUP:
			_elapsed += delta
			_windup_elapsed = maxf(_elapsed - approach_seconds, 0.0)
			if _windup_elapsed >= windup_seconds:
				state = State.FIRED
				fired_now = true
			elif _elapsed >= approach_seconds:
				state = State.WINDUP
		State.FIRED:
			_fired_elapsed += delta
		State.DEAD:
			_dead_elapsed += delta / maxf(presentation_speed, 0.1)

	_place(field, lane_count)
	_sync_art()
	return fired_now


## Kills the bot outright. Returns `false` if it was already gone, so two notes
## landing on the same frame cannot score it twice.
func kill() -> bool:
	if state == State.DEAD or state == State.FIRED:
		return false
	state = State.DEAD
	_dead_elapsed = 0.0
	_death_animated = _effects_enabled and not _reduced_motion
	react_to_hit()
	return true


## What a correct, in-window note does. Returns `false` if the note landed on
## something already gone.
##
## One note is one hit for most of the roster, so the default is [method kill].
## Multi-note enemies override this to consume one step of their sequence and
## only die on the last one — which is why the director asks *this* rather than
## calling [method kill] directly.
func strike() -> bool:
	return kill()


## Called when the player names a note that matches nothing on the field.
## Single-note bots do not care. A sequence in progress does (§8.3).
func on_wrong_note() -> void:
	pass


## True once the bot has finished its exit animation and can be freed.
func is_finished() -> bool:
	if state == State.DEAD:
		return _death_age() >= _death_duration()
	if state == State.FIRED:
		return _fired_elapsed >= FIRED_FADE
	return false


func occupies_firing_slot() -> bool:
	# A longer cosmetic breakup must not keep a newly arriving bot out of its bay.
	return _death_age() < QUIET_DEATH_FADE if state == State.DEAD else not is_finished()


func _death_age() -> float:
	return maxf(_dead_elapsed, maxf(_feedback_age, 0.0))


func _death_duration() -> float:
	return DEATH_FADE if _death_animated else QUIET_DEATH_FADE


## True while the bot can still be shot.
func is_targetable() -> bool:
	return state == State.APPROACH or state == State.WINDUP


## Signed error against the current bonus beat; each armor plate has its own.
func time_to_beat() -> float:
	return _elapsed - approach_seconds - _beat_offset


## Musical lead-in progress, not distance. Kept for practice-mode ordering.
func approach_progress() -> float:
	return clampf(_elapsed / approach_seconds, 0.0, 1.0)


## How far through its wind-up, 0 to 1. Drives the telegraph bar.
func windup_progress() -> float:
	if state == State.APPROACH:
		return 0.0
	return clampf(_windup_elapsed / windup_seconds, 0.0, 1.0)


func time_until_fire() -> float:
	return maxf(approach_seconds + windup_seconds - _elapsed, 0.0) if is_targetable() else 0.0


func attack_progress() -> float:
	return 1.0 - time_until_fire() / (approach_seconds + windup_seconds) if is_targetable() else 0.0


func entry_progress() -> float:
	return clampf(_elapsed / minf(ENTRY_SECONDS, approach_seconds * 0.3), 0.0, 1.0)


## Director-local points, captured before a strike changes the active plate.
func aim_point() -> Vector2:
	return transform * (_art.transform * _art.target_offset())


func muzzle_point() -> Vector2:
	return transform * (_art.transform * _art.muzzle_offset())


## The pitch class the player must play. Matching by class, not by absolute
## note, is what lets one chart work on a bass, a guitar and a keyboard.
func pitch_class() -> int:
	if required_note < 0:
		return -1
	return ((required_note % 12) + 12) % 12


## Whether a played pitch class names this bot. Separate from
## [method pitch_class] because an enemy may accept something other than the
## single note it is currently displaying.
func accepts_pitch_class(played_pitch_class: int) -> bool:
	return pitch_class() == played_pitch_class


## Roster key, matching the chart's `JamBeat.enemy` (§10). Used for reporting
## and for tests; nothing in the rules branches on it.
func roster_key() -> String:
	return "jam_bot"


## How many more correct notes this bot needs before it goes down. One for most
## of the roster; a phrase counts what is left of itself.
##
## The HUD asks this rather than asking what kind of enemy it is looking at, so
## adding an enemy never means editing the readout.
func demand_size() -> int:
	return 1


## Marks this bot as the front-most valid target, drawn as a heavier outline.
func set_targeted(value: bool) -> void:
	if _targeted == value:
		return
	_targeted = value
	_sync_art()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		_death_animated = false
	_sync_art()


func set_effects_enabled(enabled: bool) -> void:
	_effects_enabled = enabled
	if not enabled:
		_death_animated = false
	_sync_art()


## Pushes this bot's beat out by [param seconds] from where it stands now.
## Sequence progress is the only caller.
func _delay_beat(seconds: float) -> void:
	_beat_offset += seconds


## Re-bases the beat so the next one lands [param seconds] from this instant,
## which keeps a broken phrase's next bonus beat reachable in practice modes.
func _rebase_beat(seconds: float) -> void:
	_beat_offset = _elapsed - approach_seconds + seconds


## Entry is a short lateral reveal, not a walk toward the player. The anchor
## stays put through aiming and firing; the chart's lead-in only sets the beat.
func _place(field: Rect2, lane_count: int) -> void:
	var depth := DmjArenaLayout.depth(lane, arena_index, firing_slot)
	position = DmjArenaLayout.position(
		field, lane, lane_count, arena_index, firing_slot
	)
	if not _reduced_motion:
		var entry := 1.0 - pow(1.0 - entry_progress(), 3.0)
		var side := -1.0 if lane % 2 == 0 else 1.0
		position.x += side * 30.0 * visual_scale * (1.0 - entry)
	var depth_scale := lerpf(0.80, 1.0, depth)
	scale = Vector2.ONE * depth_scale * visual_scale
	if _art != null:
		var margin := BODY_SIZE.x * 0.5 + 12.0
		_art.destruction_x_limits = Vector2(
			minf((field.position.x - position.x) / maxf(scale.x, 0.1) + margin, 0.0),
			maxf((field.end.x - position.x) / maxf(scale.x, 0.1) - margin, 0.0)
		)
	# Back-row bays are slightly hazier without sacrificing note contrast.
	modulate = Color.WHITE.lerp(DEPTH_FOG, (1.0 - depth) * FOG_STRENGTH * 0.5)
	# Nearer bots draw over further ones, which is the whole depth cue.
	z_index = int(depth * 100.0)


## The floor containing the firing bays, which is the play area minus the strip
## [constant HORIZON_HEADROOM] reserves above the horizon.
##
## Static, and the single definition of it: [DmjRail] and [EncounterDirector]
## both call this rather than insetting themselves, because two copies of the
## inset would put the bays and the bots on different floors the moment either
## was tuned.
static func corridor_rect(field: Rect2) -> Rect2:
	var headroom := field.size.y * HORIZON_HEADROOM
	return Rect2(
		Vector2(field.position.x, field.position.y + headroom),
		Vector2(field.size.x, maxf(field.size.y - headroom, 1.0))
	)


## The same drawing is used in gameplay, the opening, and static previews.
## Its animation is fed from this actor's clock, so Demo and hit-stop freeze it.
func _sync_art() -> void:
	if _art == null:
		_art = _create_art()
		_art.name = "Art"
		add_child(_art)
	_art.combat_pose = true
	_art.effects_enabled = _effects_enabled
	_art.target_color = DmjPalette.note_color(required_note)
	_art.rotation = 0.0
	_art.scale = Vector2.ONE
	var death_age := _death_age()
	_art.destruction_age = death_age if state == State.DEAD and _death_animated else 0.0
	var reaction := maxf(1.0 - _feedback_age / 0.24, 0.0) if _feedback_age >= 0.0 else 0.0
	_art.hit_flash = (
		maxf(1.0 - _feedback_age / 0.09, 0.0)
		if _feedback_age >= 0.0 and _effects_enabled and not _reduced_motion
		and (state != State.DEAD or _death_animated) else 0.0
	)
	if _effects_enabled and not _reduced_motion:
		if state == State.DEAD:
			var kick := sin(clampf(death_age / 0.12, 0.0, 1.0) * PI) if _death_animated else 0.0
			_art.rotation = kick * (-0.08 if lane % 2 == 0 else 0.08)
			_art.scale = Vector2(1.0 + kick * 0.12, 1.0 - kick * 0.16)
		elif reaction > 0.0:
			_art.rotation = sin(_feedback_age * 42.0) * reaction * 0.055
			_art.scale = Vector2(1.0 + reaction * 0.05, 1.0 - reaction * 0.06)
	# Rotate/squash about planted feet, not the center of the sprite.
	_art.position = -(_art.ground_offset() * _art.scale).rotated(_art.rotation)
	var phrase := _art_notes()
	var cursor := _art_cursor()
	if _art.notes != phrase or _art.active_index != cursor:
		_art.set_phrase(phrase, cursor)
	var alpha := 1.0
	if state == State.DEAD:
		alpha = (
			1.0 - smoothstep(DmjDroneArt.DESTRUCTION_FADE_START, DEATH_FADE, death_age)
			if _death_animated else 1.0 - clampf(death_age / QUIET_DEATH_FADE, 0.0, 1.0)
		)
	elif state == State.FIRED:
		alpha = 1.0 - clampf(_fired_elapsed / FIRED_FADE, 0.0, 1.0) * 0.7
	_art.self_modulate.a = alpha
	_art.beat_in = -time_to_beat() / maxf(presentation_speed, 0.1)
	_art.set_pose(
		_elapsed, state == State.APPROACH and entry_progress() < 1.0,
		attack_progress() if is_targetable() and show_attack_bar else -1.0,
		_targeted and is_targetable(), state == State.DEAD,
		maxf(1.0 - _fired_elapsed / (FIRED_FADE * 0.5), 0.0) if state == State.FIRED else 0.0,
		_reduced_motion
	)


func _create_art() -> DmjDroneArt:
	return DmjDroneArt.new()


func _art_notes() -> Array[int]:
	return [required_note]


func _art_cursor() -> int:
	return 0
