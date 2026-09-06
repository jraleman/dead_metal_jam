class_name PlatedKnuckle
extends JamBot

## The roster's second demand: a short phrase, in order, one plate per note
## (§8.2). It teaches phrasing and reading ahead, which is the thing a
## one-note-one-kill enemy can never ask for.
##
## Each plate is its own beat. Breaking one pushes the next beat out by
## [member plate_seconds], so the player is playing a rhythm rather than
## racing — and every plate is judged by the same timing tiers as a Rusty
## Clanky, because the tier ladder is the game's only vocabulary for "how well
## was that timed".
##
## A wrong note resets the sequence (§8.3), but resetting a *cursor* alone
## would leave the bot's next beat already in the past and therefore unhittable,
## which quietly converts one wrong note into a guaranteed hit taken. So the
## reset re-bases the beat to one plate interval from now: the phrase starts
## again, and what it costs is the wind-up time it just burned.
##
## Like every enemy, this file touches no autoload — see [JamBot].

## Plates a chart may ask for. Two is a phrase, three is the most that fits
## inside a readable wind-up; beyond that it stops being a phrase and starts
## being a solo, which is [b]The Conductor[/b]'s job (§8.2, stretch).
const MIN_PLATES := 2
const MAX_PLATES := 3

## Default gap between plate beats. One beat at the practice tempo.
const PLATE_SECONDS := 0.8

## Wind-up time left after the last plate's beat, so arriving on the final note
## is never a coin flip against the fire frame.
const WINDUP_TAIL := 0.9

const PLATE_INTACT := Color("8b7565")
const PLATE_BROKEN := Color("2f2823")
const PLATE_EDGE := Color("c9b49a")

## The phrase, in order. Kept as plain ints so a chart is data, not code.
var notes: Array[int] = []

## Gap between one plate's beat and the next.
var plate_seconds := PLATE_SECONDS

var _cursor := 0


## Configures the bot from a phrase rather than a single note.
##
## The wind-up is widened to whatever the phrase needs if the chart asked for
## less, because a phrase that cannot physically be finished before the bot
## fires is not a difficulty setting, it is a broken beat.
func configure_sequence(
	drone_lane: int,
	sequence: Array,
	approach_time: float,
	windup_time: float,
	gap := PLATE_SECONDS
) -> void:
	notes = []
	for value: Variant in sequence:
		notes.append(int(value))
	if notes.is_empty():
		notes = [-1]

	plate_seconds = maxf(gap, 0.05)
	configure(
		drone_lane,
		notes[0],
		approach_time,
		maxf(windup_time, windup_for(notes.size(), plate_seconds))
	)
	_cursor = 0


## Shortest wind-up that lets a phrase of [param plate_count] be finished.
##
## Static so the chart compiler and [DmjTrackBuilder] can write the real number
## into the plan — the round length is derived from the plan (§2), so a
## wind-up silently widened at spawn time would make the round timer lie.
static func windup_for(plate_count: int, gap := PLATE_SECONDS) -> float:
	return float(maxi(plate_count, 1) - 1) * gap + WINDUP_TAIL


func roster_key() -> String:
	return "plated_knuckle"


func demand_size() -> int:
	return plates_left()


## How many plates are still on. Exposed for tests and for the HUD.
func plates_left() -> int:
	return maxi(notes.size() - _cursor, 0)


func plate_count() -> int:
	return notes.size()


## Index of the plate the phrase is currently on.
func cursor() -> int:
	return _cursor


## One correct, in-window note breaks one plate. Only the last one kills.
func strike() -> bool:
	if not is_targetable():
		return false
	_cursor += 1
	if _cursor >= notes.size():
		return kill()
	required_note = notes[_cursor]
	# The next plate is a beat later, not immediately: this is the phrase.
	_delay_beat(plate_seconds)
	queue_redraw()
	return true


## A note that named nothing on the field breaks the phrase (§8.3). Only a
## sequence actually in progress can be broken — a bot still on its first plate
## has nothing to lose, and charging it anyway would make every stray note on
## the field a penalty against enemies the player has not engaged.
func on_wrong_note() -> void:
	if _cursor <= 0 or not is_targetable():
		return
	_cursor = 0
	required_note = notes[0]
	_rebase_beat(plate_seconds)
	queue_redraw()


func _draw_chassis(body: Rect2, alpha: float) -> void:
	draw_rect(body, Color(CHASSIS_DARK, alpha))

	# Plates stack down the flanks, broken ones hollowed out. The count is
	# readable in greyscale and at horizon scale, which is what makes "two
	# notes left" something the player can see rather than remember.
	var total := maxi(notes.size(), 1)
	var plate_height := (BODY_SIZE.y - 20.0) / float(total)
	for index in range(total):
		var plate := Rect2(
			Vector2(body.position.x + 5.0, body.position.y + 10.0 + float(index) * plate_height),
			Vector2(BODY_SIZE.x - 10.0, plate_height - 5.0)
		)
		if index < _cursor:
			draw_rect(plate, Color(PLATE_BROKEN, alpha))
			draw_rect(plate, Color(PLATE_EDGE, alpha * 0.5), false, 2.0)
			continue
		draw_rect(plate, Color(PLATE_INTACT, alpha))
		draw_rect(plate, Color(PLATE_EDGE, alpha * 0.8), false, 2.0)


## The letter, plus how much of the phrase is left. The glyph is what the
## player plays; the pip row is what tells them a phrase is still running.
func _draw_glyph(alpha: float) -> void:
	super(alpha)

	var remaining := plates_left()
	if remaining <= 0:
		return
	var pip := Vector2(9.0, 9.0)
	var gap := 5.0
	var total_width := float(notes.size()) * pip.x + float(notes.size() - 1) * gap
	for index in range(notes.size()):
		var origin := Vector2(
			-total_width * 0.5 + float(index) * (pip.x + gap),
			BODY_SIZE.y * 0.5 - 15.0
		)
		var color := PLATE_INTACT if index >= _cursor else PLATE_BROKEN
		draw_rect(Rect2(origin, pip), Color(color, alpha))
