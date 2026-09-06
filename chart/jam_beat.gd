class_name JamBeat
extends Resource

## One demand in a chart: what to play, when it arrives, and who is carrying it.
##
## Field-for-field this mirrors the `.jam` JSON in `README.md` (§10), so the
## stretch importer is a translation and not a redesign. Nothing here is a
## Godot-ism the JSON could not express.

## Seconds from the start of the track, and it is the **arrival** — the moment
## the player is asked to play, not the moment the bot appears. A chart is a
## promise about when things reach the strike line (§8.5), and the walk-in is
## derived from it by the section's archetype.
@export var time := 0.0

## MIDI note number. Matched by pitch class, so any octave counts (§8.3).
@export var note := 60

## The phrase, for enemies that ask for more than one note. Ignored by
## single-note enemies; when it is empty a multi-note enemy falls back to
## [member note].
@export var notes: Array[int] = []

## Hit-window width in seconds, centred on [member time] — the `beats[].duration`
## of the README JSON.
##
## The early half is already the approach, which the timing tiers judge, so
## what this actually buys the player is the *late* half: the wind-up the bot
## charges through before it fires. Zero means "use the section archetype",
## which is how nearly every beat should be written.
@export var duration := 0.0

## Lane 0-2. `-1` means auto, and the compiler spreads those across the lanes
## in beat order so a hand-written chart never has to think about staging.
@export var lane := -1

## Roster key (§8.2): `rusty_clanky` or `plated_knuckle`.
@export var enemy := "rusty_clanky"


## The phrase this beat asks for, however it was written. A chart may give a
## multi-note enemy a bare [member note] and mean a one-note phrase.
func phrase() -> Array[int]:
	var sequence: Array[int] = []
	if notes.is_empty():
		sequence.append(note)
		return sequence
	for value: int in notes:
		sequence.append(value)
	return sequence
