class_name DmjConductor
extends DmjPhraseBot

## A four-note miniboss with a checkpoint after each pair of notes.
const MOTIF_NOTES := 4
const NOTE_SECONDS := 0.7


static func normalize_sequence(sequence: Array, fallback_note := -1) -> Array[int]:
	return normalize_phrase(sequence, MOTIF_NOTES, fallback_note)


static func windup_for() -> float:
	return phrase_windup(MOTIF_NOTES, NOTE_SECONDS)


func configure_motif(
	drone_lane: int, sequence: Array, approach: float, windup: float, fallback_note := -1
) -> void:
	configure_phrase(
		drone_lane, normalize_sequence(sequence, fallback_note), approach, windup, NOTE_SECONDS
	)


func roster_key() -> String:
	return "conductor"


func display_name() -> String:
	return "THE CONDUCTOR"


func instruction() -> String:
	return (
		"Play its four-note phrase. Each completed pair stays broken."
		if _cursor < 2 else "Checkpoint saved! Finish the last two notes."
	)


func _reset_step() -> int:
	return 2 if _cursor >= 2 else 0


func hit_label() -> String:
	return "CHECKPOINT" if _cursor == 2 else "PHRASE HIT"


func _create_art() -> DmjDroneArt:
	return DmjConductorArt.new()
