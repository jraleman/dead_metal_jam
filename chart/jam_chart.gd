class_name JamChart
extends Resource

## A track: the song, and the sections the game is staged from (§10).
##
## MVP charts are Godot resources whose shape mirrors the `.jam` JSON one for
## one, so importing real `.jam` files later is a field translation rather than
## a rewrite (§11, *Cut*).
##
## The chart is also the seam between *music* and *rules*. [method to_track]
## compiles it down to the plain-data waves [EncounterDirector] consumes —
## exactly the shape [DmjTrackBuilder] already produces — so nothing downstream
## knows whether it is playing a song or a practice ramp.
##
## No autoload is touched here, so `jam_chart_test.gd` can drive the real
## compiler headlessly (§9.8).

## Staging profiles a section may name (§8.5). An archetype is *pacing*: how
## long the walk-in is, how long the bot charges before it fires, and how much
## rail sits in front of the section.
##
## This is the whole of what a chart controls about difficulty, and it is
## deliberately a small closed set — per-beat tuning is how a chart format
## turns into a scripting language.
const ARCHETYPES := {
	## The opener. The longest read in the game, because the player has not
	## found their hands yet.
	"walk_in": {"approach": 3.6, "windup": 1.6, "advance": 2.2},
	## The default. Steady, sight-readable, no tricks.
	"march": {"approach": 3.2, "windup": 1.5, "advance": 2.2},
	## Late-track pressure: a shorter read and a shorter fuse, arrived at
	## through a shorter rail so it lands as a step up in tempo.
	"press": {"approach": 2.6, "windup": 1.2, "advance": 1.6},
	## The bridge. Slow, heavy, and preceded by real rail — this is where the
	## player gets their breath back before the last push (§8.1).
	"hold": {"approach": 4.2, "windup": 2.2, "advance": 3.4},
}

const DEFAULT_ARCHETYPE := "march"

@export var title := ""
@export var artist := ""
@export var bpm := 120.0

## The track itself. Played under the round as a bed; the chart's own beat
## times are what the game is judged against, not the audio clock.
@export var audio: AudioStream

@export var sections: Array[JamSection] = []


## Staging profile for [param key], falling back to the default rather than
## failing. A chart with a typo in one section name should still be playable —
## the alternative is a track that refuses to load on jam night.
static func archetype(key: String) -> Dictionary:
	if ARCHETYPES.has(key):
		return ARCHETYPES[key]
	return ARCHETYPES[DEFAULT_ARCHETYPE]


static func has_archetype(key: String) -> bool:
	return ARCHETYPES.has(key)


## Compiles the chart into the waves [EncounterDirector] plays.
##
## Two things are worth knowing about the timing.
##
## **Arrivals are preserved; the grid is offset.** A beat's `time` is when the
## player must play, so the bot has to spawn one approach earlier. Rather than
## clamping the first beat's spawn to zero — which would drag its arrival late
## and shear the section's rhythm — the whole section is shifted by one
## approach. Every interval inside the section survives exactly, which is what
## a chart actually promises.
##
## **Sections are not glued to the audio clock.** A wave ends when it is
## cleared, and the rail advance in front of the next one is a fixed length, so
## real time drifts from track time as the player plays well. The audio is a
## bed, not a conductor; syncing to it needs the chart cursor to drive the
## spawner from the audio position, and that is a bigger change than pacing
## needs (§13).
func to_track(lane_count := EncounterDirector.LANE_COUNT) -> Array:
	var waves: Array = []
	var lanes := maxi(lane_count, 1)

	for section in sections:
		if section == null:
			continue
		var beats := section.ordered_beats()
		if beats.is_empty():
			# A section with no beats would compile to a wave that is over on
			# the frame it starts, which reads on screen as a skipped section.
			continue

		var profile := archetype(section.wave_archetype)
		var approach := float(profile.get("approach", 3.2))
		var origin := beats[0].time
		var drones: Array = []

		for index in range(beats.size()):
			drones.append(
				_compile_beat(beats[index], index, origin, approach, profile, lanes)
			)

		waves.append({
			"section": section.name,
			"archetype": section.wave_archetype,
			"advance": float(profile.get("advance", EncounterDirector.RAIL_ADVANCE_SECONDS)),
			"drones": drones,
		})

	return waves


## Worst-case length of the compiled track, in seconds — what the round timer
## is set from (§2).
func duration(lane_count := EncounterDirector.LANE_COUNT) -> float:
	return DmjTrackBuilder.duration(to_track(lane_count))


## Section names in playing order, for the HUD and for tests.
func section_names() -> PackedStringArray:
	var names := PackedStringArray()
	for section in sections:
		if section != null and not section.ordered_beats().is_empty():
			names.append(section.name)
	return names


func _compile_beat(
	beat: JamBeat,
	index: int,
	origin: float,
	approach: float,
	profile: Dictionary,
	lane_count: int
) -> Dictionary:
	# `duration` is a window centred on the beat, so half of it is the late
	# side — and the late side is the wind-up the bot charges through.
	var windup := float(profile.get("windup", 1.5))
	if beat.duration > 0.0:
		windup = beat.duration * 0.5

	var plan := {
		"lane": _lane_for(beat, index, lane_count),
		"at": maxf(beat.time - origin, 0.0),
		"approach": approach,
		"windup": windup,
		"enemy": beat.enemy,
		"note": beat.note,
	}

	if beat.enemy == "plated_knuckle":
		var phrase := PlatedKnuckle.normalize_sequence(beat.phrase(), beat.note)
		plan["notes"] = phrase
		plan["note"] = phrase[0]
		# Written into the plan, not left to the bot to widen at spawn: the
		# round length is derived from the plan, so a wind-up that only exists
		# at runtime would make the round timer lie (§2).
		plan["windup"] = maxf(windup, PlatedKnuckle.windup_for(phrase.size()))

	return plan


## Auto lanes spread across the field in beat order, so a chart that never
## names a lane still stages across all three (§8.1).
func _lane_for(beat: JamBeat, index: int, lane_count: int) -> int:
	if beat.lane >= 0:
		return clampi(beat.lane, 0, lane_count - 1)
	return index % lane_count
