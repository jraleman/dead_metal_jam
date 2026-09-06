class_name JamSection
extends Resource

## A named stretch of the song — "intro", "chorus", "bridge" — and the beats
## inside it (§10).
##
## A section is the game's pacing unit, not just a label. One section compiles
## to one wave, and the rail advance between them is the breathing room a music
## game needs, because nobody can sight-read continuously for four minutes
## (§8.1). That is why an advance is banner-worthy at all: it is the player's
## cue that the pressure just stopped. The banner says so in its own words
## rather than repeating the section's name (§5.3).
##
## No musical semantics are attached (§11, *Simplified*): the name is free text
## and the archetype is a staging profile, not a key or a mode.

## Free text, for whoever is writing the chart. **Not shown to the player**:
## CHORUS and BRIDGE are how an author talks about a song, not something
## somebody holding a guitar can act on, so the HUD shows progress and
## encouragement instead (§5.3).
@export var name := "section"

## Which staging profile places these beats — see [constant JamChart.ARCHETYPES].
## An unknown key falls back to the default rather than failing the chart.
@export var wave_archetype := "march"

@export var beats: Array[JamBeat] = []


## Beats in playing order. Charts are hand-written, so this sorts rather than
## trusting the file: a beat typed out of order should stage late, not scramble
## the wave it is in.
func ordered_beats() -> Array[JamBeat]:
	var sorted: Array[JamBeat] = []
	for beat in beats:
		if beat != null:
			sorted.append(beat)
	sorted.sort_custom(
		func(a: JamBeat, b: JamBeat) -> bool: return a.time < b.time
	)
	return sorted


## When this section starts, in track seconds: its first arrival.
func start_time() -> float:
	var ordered := ordered_beats()
	if ordered.is_empty():
		return 0.0
	return ordered[0].time
