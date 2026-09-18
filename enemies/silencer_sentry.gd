class_name SilencerSentry
extends DmjPhraseBot

## Re-articulate the same note: first the shield, then the exposed core.
const ECHO_SECONDS := 0.5
const REQUIRED_HITS := 2


static func windup_for() -> float:
	return phrase_windup(REQUIRED_HITS, ECHO_SECONDS)


func configure_echo(drone_lane: int, note: int, approach: float, windup: float) -> void:
	configure_phrase(drone_lane, [note, note], approach, windup, ECHO_SECONDS)


func roster_key() -> String:
	return "silencer_sentry"


func display_name() -> String:
	return "SILENCER SENTRY"


func instruction() -> String:
	return (
		"Play the same note twice: shield, then core."
		if _cursor == 0 else "Shield broken! Repeat the note to finish it."
	)


func on_wrong_note() -> void:
	# Unlike armor plates, a shattered shield never regenerates.
	pass


func hit_label() -> String:
	return "SHIELD BROKEN"


func _create_art() -> DmjDroneArt:
	return DmjSilencerSentryArt.new()
