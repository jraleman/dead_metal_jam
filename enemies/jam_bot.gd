class_name JamBot
extends Node2D

## Everything every enemy in the roster does, minus the thing that makes it
## that enemy (§8.2).
##
## A bot walks down a lane from the horizon to the strike line over its approach
## time, winds up, then fires. It owns none of the judgement: it only reports
## where it is in its life and which note it is asking for right now, so
## [EncounterDirector] can rule on it.
##
## Subclasses supply three things and nothing else:
##
## - **what it is asking for** — [method accepts_pitch_class] and the
##   [member required_note] it keeps in step with its own state,
## - **what a correct note does to it** — [method strike], which may break one
##   plate rather than kill,
## - **what it looks like** — [method _draw_chassis].
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
	## Walking toward the strike line; killable inside the timing window.
	APPROACH,
	## Arrived and charging. Still killable, and the last chance to act.
	WINDUP,
	## Fired at the player. No longer a target.
	FIRED,
	## Killed by the right note. Fading out.
	DEAD,
}

## Body size at full depth. Everything else is drawn relative to this so the
## whole actor scales with one `scale` assignment.
const BODY_SIZE := Vector2(74.0, 92.0)

## Apparent size at the horizon, as a fraction of full size.
const HORIZON_SCALE := 0.34

## Lane separation at the horizon, as a fraction of separation at the front.
## Lanes converging with distance is the entire depth illusion (§8.1).
const HORIZON_LANE_SPREAD := 0.22

## The share of the play area kept above the horizon, for the ceiling and the
## far end of the corridor to live in.
##
## Before this, the horizon *was* the top edge of the play area, which left a
## corridor no room to have a ceiling: a wall rising from a floor that starts
## at the top of the frame has nowhere to rise into. Bots walk the shortened
## floor rather than the whole frame, and because [DmjRail] insets by the same
## constant, the lanes it draws stay exactly under the bots that walk them.
const HORIZON_HEADROOM := 0.26

## Dust hanging between the player and the far end. Multiplied into a bot, so
## this is what the furthest one is tinted *towards*, never past.
const DEPTH_FOG := Color("9c8871")

## How much of the way to [constant DEPTH_FOG] the furthest bot goes. Short of
## the whole way on purpose: the glyph on a distant bot is the note the player
## is being asked for, so distance may cost it contrast but never legibility.
const FOG_STRENGTH := 0.7

## How long a killed drone stays on screen fading out.
const DEATH_FADE := 0.22

## How long the muzzle flash of a drone that fired stays up (§5.2).
const FIRED_FADE := 0.34

const CHASSIS := Color("6d5a4a")
const CHASSIS_DARK := Color("3c322a")
const GLYPH_INK := Color("f2f6f7")
const WINDUP_COLOR := Color("ff4964")
const TARGET_OUTLINE := Color("ffd34e")

## The note the player must play *right now*. Multi-note enemies move it as
## their sequence advances, so the readout, the glyph and the matching rule all
## keep reading one value rather than each asking a different question.
var required_note := -1
var lane := 1
var approach_seconds := 4.0
var windup_seconds := 1.6
var state: State = State.APPROACH

var _elapsed := 0.0
var _windup_elapsed := 0.0
var _dead_elapsed := 0.0
var _fired_elapsed := 0.0
var _targeted := false
var _reduced_motion := false
## Seconds added to this bot's beat by its own progress. Zero for anything that
## dies to one note; a plate broken by [PlatedKnuckle] pushes the next beat out
## by one plate interval.
var _beat_offset := 0.0


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
	queue_redraw()


## Advances one frame and returns `true` on the single frame the bot fires, so
## the caller cannot miss the transition by polling at the wrong moment.
func advance(delta: float, field: Rect2, lane_count: int) -> bool:
	var fired_now := false

	match state:
		State.APPROACH:
			_elapsed += delta
			if _elapsed >= approach_seconds:
				state = State.WINDUP
		State.WINDUP:
			_elapsed += delta
			_windup_elapsed += delta
			if _windup_elapsed >= windup_seconds:
				state = State.FIRED
				fired_now = true
		State.FIRED:
			_fired_elapsed += delta
		State.DEAD:
			_dead_elapsed += delta

	_place(field, lane_count)
	queue_redraw()
	return fired_now


## Kills the bot outright. Returns `false` if it was already gone, so two notes
## landing on the same frame cannot score it twice.
func kill() -> bool:
	if state == State.DEAD or state == State.FIRED:
		return false
	state = State.DEAD
	_dead_elapsed = 0.0
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
		return _dead_elapsed >= DEATH_FADE
	if state == State.FIRED:
		return _fired_elapsed >= FIRED_FADE
	return false


## True while the bot can still be shot.
func is_targetable() -> bool:
	return state == State.APPROACH or state == State.WINDUP


## Seconds until this bot's current beat: negative while it is still
## approaching, positive once it is late. This is the value the timing tiers in
## §6 are measured against, so arrival *is* the beat — and for a sequence, each
## step gets its own.
func time_to_beat() -> float:
	return _elapsed - approach_seconds - _beat_offset


## How far along the approach the bot is, 0 at the horizon and 1 at the front.
func approach_progress() -> float:
	return clampf(_elapsed / approach_seconds, 0.0, 1.0)


## How far through its wind-up, 0 to 1. Drives the telegraph bar.
func windup_progress() -> float:
	if state == State.APPROACH:
		return 0.0
	return clampf(_windup_elapsed / windup_seconds, 0.0, 1.0)


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
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


## Pushes this bot's beat out by [param seconds] from where it stands now.
## Sequence progress is the only caller.
func _delay_beat(seconds: float) -> void:
	_beat_offset += seconds


## Re-bases the beat so the next one lands [param seconds] from this instant,
## which is how a broken phrase gets another go rather than becoming unhittable.
func _rebase_beat(seconds: float) -> void:
	_beat_offset = _elapsed - approach_seconds + seconds


## Depth is faked with position, scale, tint and draw order — no 3D and no
## perspective camera (§8.1). The vertical walk stays linear on purpose: a bot
## that accelerates as it nears is impossible to play to the beat.
func _place(field: Rect2, lane_count: int) -> void:
	var progress := approach_progress()
	var spread := lerpf(HORIZON_LANE_SPREAD, 1.0, progress)
	var slot := float(lane) - float(maxi(lane_count, 1) - 1) * 0.5
	var lane_width := field.size.x / float(maxi(lane_count, 1))

	position = Vector2(
		field.get_center().x + slot * lane_width * spread,
		lerpf(field.position.y, field.end.y, progress)
	)
	var depth_scale := lerpf(HORIZON_SCALE, 1.0, pow(progress, 1.5))
	scale = Vector2(depth_scale, depth_scale)
	# Size and draw order alone made every bot equally bright, which reads as a
	# row of cut-outs at different sizes rather than as distance. Tinting the
	# far ones towards the dust puts them *behind* something.
	#
	# The curve is deliberately shallow (`pow` under 1) so the fog is spent
	# early in the walk: a bot loses its contrast while it is still a shape in
	# the distance, and is back to full colour well before it is close enough
	# to be worth aiming at.
	modulate = Color.WHITE.lerp(DEPTH_FOG, (1.0 - pow(progress, 0.6)) * FOG_STRENGTH)
	# Nearer bots draw over further ones, which is the whole depth cue.
	z_index = int(progress * 100.0)


## The floor the bots actually walk, which is the play area minus the strip
## [constant HORIZON_HEADROOM] reserves above the horizon.
##
## Static, and the single definition of it: [DmjRail] and [EncounterDirector]
## both call this rather than insetting themselves, because two copies of the
## inset would put the lanes and the bots on different floors the moment either
## was tuned.
static func corridor_rect(field: Rect2) -> Rect2:
	var headroom := field.size.y * HORIZON_HEADROOM
	return Rect2(
		Vector2(field.position.x, field.position.y + headroom),
		Vector2(field.size.x, maxf(field.size.y - headroom, 1.0))
	)


## The parts every bot shares. The chassis itself is the subclass's, so an
## artist replacing one enemy never touches the wind-up telegraph or the target
## outline — the two things that must look the same on all of them.
func _draw() -> void:
	var alpha := 1.0
	if state == State.DEAD:
		alpha = 1.0 - clampf(_dead_elapsed / DEATH_FADE, 0.0, 1.0)
	elif state == State.FIRED:
		alpha = 1.0 - clampf(_fired_elapsed / FIRED_FADE, 0.0, 1.0) * 0.7
	if alpha <= 0.0:
		return

	var half := BODY_SIZE * 0.5
	var body := Rect2(-half, BODY_SIZE)

	draw_rect(
		Rect2(body.position + Vector2(4.0, 6.0), body.size),
		Color(0.0, 0.0, 0.0, 0.3 * alpha)
	)
	_draw_chassis(body, alpha)
	_draw_glyph(alpha)

	if state == State.WINDUP:
		_draw_windup(body, alpha)
	if state == State.FIRED and _fired_elapsed < FIRED_FADE * 0.5:
		draw_rect(body.grow(10.0), Color(WINDUP_COLOR, alpha))
	if _targeted and is_targetable():
		draw_rect(body.grow(6.0), Color(TARGET_OUTLINE, alpha), false, 4.0)


## The enemy's own art. Flat placeholder rectangles for the jam (§8.4);
## everything an artist would replace is confined to overrides of this.
func _draw_chassis(body: Rect2, alpha: float) -> void:
	draw_rect(body, Color(CHASSIS, alpha))
	draw_rect(
		Rect2(body.position, Vector2(BODY_SIZE.x, 16.0)),
		Color(CHASSIS_DARK, alpha)
	)


## The required note as a letter. Text, never colour: the base project forbids
## encoding meaning in colour alone, and this is the most important thing on
## the actor.
func _draw_glyph(alpha: float) -> void:
	if required_note < 0:
		return
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var glyph := PitchDetector.note_name(required_note)
	var glyph_size := 44
	var width := font.get_string_size(
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, glyph_size
	).x
	draw_string(
		font,
		Vector2(-width * 0.5, 18.0),
		glyph,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		glyph_size,
		Color(GLYPH_INK, alpha)
	)


## The wind-up telegraph: a bar that fills over the bot's charge time (§5.2).
## A bar rather than only a colour pulse, so it survives reduced motion — the
## pulse is dropped there and the bar is not.
func _draw_windup(body: Rect2, alpha: float) -> void:
	var track := Rect2(
		Vector2(body.position.x, body.position.y - 18.0),
		Vector2(BODY_SIZE.x, 9.0)
	)
	draw_rect(track, Color(CHASSIS_DARK, alpha))
	var filled := track
	filled.size.x = track.size.x * windup_progress()
	draw_rect(filled, Color(WINDUP_COLOR, alpha))

	if _reduced_motion:
		return
	var pulse := 0.35 + 0.35 * sin(_windup_elapsed * 18.0)
	draw_rect(body.grow(3.0), Color(WINDUP_COLOR, pulse * alpha), false, 3.0)
