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

## The plated phrase is fixed: every successful sequence is exactly three hits.
## Shorter authored phrases are repeated to fill the armor, and longer ones are
## trimmed to the first three notes so the requirement never drifts.
const REQUIRED_PLATES := 3
const MIN_PLATES := REQUIRED_PLATES
const MAX_PLATES := REQUIRED_PLATES

## Default gap between plate beats. One beat at the practice tempo.
const PLATE_SECONDS := 0.8

## Wind-up time left after the last plate's beat, so arriving on the final note
## is never a coin flip against the fire frame.
const WINDUP_TAIL := 0.9

const PLATE_INTACT := DmjDroneArt.PAPER
const PLATE_BROKEN := DmjDroneArt.METAL_DARK
const PLATE_EDGE := DmjDroneArt.METAL_LIGHT

## The phrase, in order. Kept as plain ints so a chart is data, not code.
var notes: Array[int] = []

## Gap between one plate's beat and the next.
var plate_seconds := PLATE_SECONDS

var _cursor := 0


## Normalizes any authored phrase to the fixed three-hit requirement.
##
## - Longer phrases keep their first three notes.
## - Shorter non-empty phrases repeat in order until all three plates are set.
## - An empty phrase keeps the existing "missing note" sentinel unless a caller
##   supplies the note it meant through [param fallback_note].
static func normalize_sequence(
	sequence: Array,
	fallback_note := -1
) -> Array[int]:
	var authored: Array[int] = []
	for value: Variant in sequence:
		authored.append(int(value))
	if authored.is_empty():
		authored.append(int(fallback_note))

	var normalized: Array[int] = []
	for index in range(REQUIRED_PLATES):
		normalized.append(authored[index % authored.size()])
	return normalized


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
	gap := PLATE_SECONDS,
	fallback_note := -1
) -> void:
	notes = normalize_sequence(sequence, fallback_note)
	plate_seconds = maxf(gap, 0.05)
	_cursor = 0
	configure(
		drone_lane,
		notes[0],
		approach_time,
		maxf(windup_time, windup_for(notes.size(), plate_seconds))
	)


## Shortest wind-up that lets the fixed three-plate phrase be finished.
##
## Static so the chart compiler and [DmjTrackBuilder] can write the real number
## into the plan — the round length is derived from the plan (§2), so a
## wind-up silently widened at spawn time would make the round timer lie.
static func windup_for(_plate_count: int, gap := PLATE_SECONDS) -> float:
	return float(REQUIRED_PLATES - 1) * gap + WINDUP_TAIL


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
	_sync_art()
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
	_sync_art()


func _create_art() -> DmjDroneArt:
	return DmjPlatedKnuckleArt.new()


func _art_notes() -> Array[int]:
	return notes.duplicate() if not notes.is_empty() else [required_note]


func _art_cursor() -> int:
	return _cursor
