class_name RustDrone
extends Node2D

## One Rust Drone — the game's core verb in a single actor (§8.2).
##
## It walks down a lane from the horizon to the strike line over its approach
## time, winds up, then fires. Killing it means playing its note while it is in
## the timing window around its arrival; the drone itself owns none of that
## judgement, it only reports where it is in its life so [EncounterDirector] can
## rule on it.
##
## Art is deliberately flat placeholder rectangles. Nothing below encodes
## meaning in colour alone: the note is a letter, the wind-up is a filling bar,
## and the front-most target is a heavier outline — all readable in greyscale.
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

## How long a killed drone stays on screen fading out.
const DEATH_FADE := 0.22

## How long the muzzle flash of a drone that fired stays up (§5.2).
const FIRED_FADE := 0.34

const CHASSIS := Color("6d5a4a")
const CHASSIS_DARK := Color("3c322a")
const GLYPH_INK := Color("f2f6f7")
const WINDUP_COLOR := Color("ff4964")
const TARGET_OUTLINE := Color("ffd34e")

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


## Places the drone in a lane with the note it demands. Called once at spawn;
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
	_targeted = false
	queue_redraw()


## Advances one frame and returns `true` on the single frame the drone fires,
## so the caller cannot miss the transition by polling at the wrong moment.
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


## Kills the drone. Returns `false` if it was already gone, so two notes landing
## on the same frame cannot score it twice.
func kill() -> bool:
	if state == State.DEAD or state == State.FIRED:
		return false
	state = State.DEAD
	_dead_elapsed = 0.0
	return true


## True once the drone has finished its exit animation and can be freed.
func is_finished() -> bool:
	if state == State.DEAD:
		return _dead_elapsed >= DEATH_FADE
	if state == State.FIRED:
		return _fired_elapsed >= FIRED_FADE
	return false


## True while the drone can still be shot.
func is_targetable() -> bool:
	return state == State.APPROACH or state == State.WINDUP


## Seconds until this drone reaches the strike line: negative while it is still
## approaching, positive once it is winding up. This is the value the timing
## tiers in §6 are measured against, so the drone's arrival *is* its beat.
func time_to_beat() -> float:
	return _elapsed - approach_seconds


## How far along the approach the drone is, 0 at the horizon and 1 at the front.
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


## Marks this drone as the front-most valid target, drawn as a heavier outline.
func set_targeted(value: bool) -> void:
	if _targeted == value:
		return
	_targeted = value
	queue_redraw()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


## Depth is faked with position, scale and draw order — no 3D and no
## perspective camera (§8.1). The vertical walk stays linear on purpose: a
## drone that accelerates as it nears is impossible to play to the beat.
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
	# Nearer drones draw over further ones, which is the whole depth cue.
	z_index = int(progress * 100.0)


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
	draw_rect(body, Color(CHASSIS, alpha))
	draw_rect(
		Rect2(body.position, Vector2(BODY_SIZE.x, 16.0)),
		Color(CHASSIS_DARK, alpha)
	)

	_draw_glyph(alpha)

	if state == State.WINDUP:
		_draw_windup(body, alpha)
	if state == State.FIRED and _fired_elapsed < FIRED_FADE * 0.5:
		draw_rect(body.grow(10.0), Color(WINDUP_COLOR, alpha))
	if _targeted and is_targetable():
		draw_rect(body.grow(6.0), Color(TARGET_OUTLINE, alpha), false, 4.0)


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


## The wind-up telegraph: a bar that fills over the drone's charge time (§5.2).
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
