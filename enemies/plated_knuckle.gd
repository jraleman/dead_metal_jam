class_name PlatedKnuckle
extends DmjPhraseBot

## Three plates, three notes in order. A wrong note restores the whole phrase.
const REQUIRED_PLATES := 3
const MIN_PLATES := REQUIRED_PLATES
const MAX_PLATES := REQUIRED_PLATES
const PLATE_SECONDS := 0.8
const WINDUP_TAIL := PHRASE_TAIL
const PLATE_INTACT := DmjDroneArt.PAPER
const PLATE_BROKEN := DmjDroneArt.METAL_DARK
const PLATE_EDGE := DmjDroneArt.METAL_LIGHT


static func normalize_sequence(sequence: Array, fallback_note := -1) -> Array[int]:
	return normalize_phrase(sequence, REQUIRED_PLATES, fallback_note)


func configure_sequence(
	drone_lane: int, sequence: Array, approach_time: float,
	windup_time: float, gap := PLATE_SECONDS, fallback_note := -1
) -> void:
	configure_phrase(
		drone_lane, normalize_sequence(sequence, fallback_note),
		approach_time, windup_time, gap
	)


static func windup_for(_plate_count: int, gap := PLATE_SECONDS) -> float:
	return phrase_windup(REQUIRED_PLATES, gap)


func roster_key() -> String:
	return "plated_knuckle"


func display_name() -> String:
	return "PLATED KNUCKLE"


func instruction() -> String:
	return "Three notes in order. A wrong note restores the armor."


func _create_art() -> DmjDroneArt:
	return DmjPlatedKnuckleArt.new()
