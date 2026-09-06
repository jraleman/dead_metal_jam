class_name DmjTrackBuilder

## Builds a practice track: the plain-data waves [EncounterDirector] consumes.
##
## This is a stand-in for the chart format (§10), and deliberately produces the
## exact same shape a compiled chart will, so swapping a real song in later
## changes nothing downstream. Until then it ramps a few waves out of the
## game's note pool so there is something to play.
##
## Drones are placed by *arrival*, not by spawn time. A rhythm game is a
## promise about when things reach the strike line, so the beat grid is applied
## to arrivals and the spawn time is derived from it.
##
## Static only, and free of autoload instances, so `encounter_test.gd` can name
## it in a headless run.

## Seconds per beat at the practice tempo — 75 BPM, slow enough to sight-read.
const BEAT_SECONDS := 0.8

## How long a drone spends walking in. Long enough to read its note at the
## horizon and still have time to find it on the instrument.
const APPROACH_SECONDS := 3.6

## Shortest approach the ramp is allowed to reach, so late waves stay playable.
const MIN_APPROACH_SECONDS := 2.4

## Seconds a drone charges before firing once it has arrived.
const WINDUP_SECONDS := 1.5

## Drones in the first wave, and how many are added every wave after it.
const OPENING_DRONES := 2
const DRONES_PER_WAVE := 1

## Never ask for more than this many drones in one wave during MVP.
const MAX_WAVE_DRONES := 6


## Builds `wave_count` waves from `note_pool`.
##
## `rng` is passed in rather than created so a test can seed it and get the
## same track twice.
static func build(
	note_pool: Array,
	wave_count: int,
	rng: RandomNumberGenerator,
	lane_count := EncounterDirector.LANE_COUNT
) -> Array:
	var waves: Array = []
	if note_pool.is_empty() or wave_count <= 0:
		return waves

	for wave_index in range(wave_count):
		waves.append(
			_build_wave(note_pool, wave_index, rng, maxi(lane_count, 1))
		)
	return waves


static func _build_wave(
	note_pool: Array,
	wave_index: int,
	rng: RandomNumberGenerator,
	lane_count: int
) -> Dictionary:
	var count := mini(
		OPENING_DRONES + wave_index * DRONES_PER_WAVE, MAX_WAVE_DRONES
	)
	var approach := maxf(
		APPROACH_SECONDS - float(wave_index) * 0.2, MIN_APPROACH_SECONDS
	)

	var drones: Array = []
	var previous_note := -1
	for slot in range(count):
		var note := _pick_note(note_pool, previous_note, rng)
		previous_note = note
		# Every drone in a wave shares one approach time, so spacing the spawns
		# on the beat grid spaces the *arrivals* on it too — which is the thing
		# the player is actually playing to. Two beats apart leaves room to
		# hear the note and find it on the instrument.
		drones.append({
			"lane": rng.randi_range(0, lane_count - 1),
			"note": note,
			"at": float(slot) * BEAT_SECONDS * 2.0,
			"approach": approach,
			"windup": WINDUP_SECONDS,
		})

	return {"drones": drones}


## Avoids repeating the previous note, so a hit always visibly changes what the
## player is being asked for.
static func _pick_note(
	note_pool: Array,
	previous_note: int,
	rng: RandomNumberGenerator
) -> int:
	if note_pool.size() == 1:
		return int(note_pool[0])
	var note := int(note_pool[rng.randi_range(0, note_pool.size() - 1)])
	while note == previous_note:
		note = int(note_pool[rng.randi_range(0, note_pool.size() - 1)])
	return note


## How long the track runs if the player never kills anything: every rail
## advance, plus each wave's slowest drone all the way through its wind-up.
##
## "A round is one track" (§2), so this is what sets the round duration rather
## than a hardcoded number of seconds. It is a worst case on purpose — killing
## drones ends waves early, so the round timer stays a backstop and TRACK
## CLEARED is the normal way to finish.
static func duration(track: Array) -> float:
	var total := 0.0
	for wave: Dictionary in track:
		total += EncounterDirector.RAIL_ADVANCE_SECONDS
		var longest := 0.0
		var drones: Variant = wave.get("drones", [])
		if not (drones is Array):
			continue
		for plan: Dictionary in drones:
			longest = maxf(
				longest,
				float(plan.get("at", 0.0))
				+ float(plan.get("approach", 0.0))
				+ float(plan.get("windup", 0.0))
			)
		total += longest
	return total
