class_name RustyClanky
extends JamBot

## One Rusty Clanky — the game's core verb in a single actor (§8.2).
##
## One note, one hit. It is the enemy that teaches what the instrument is for,
## so it asks for nothing beyond what [JamBot] already does: walk in, show a
## letter, die to that letter.
##
## Everything that distinguishes it from the rest of the roster is below, and
## it is all art (§8.4). The approach, the wind-up telegraph, the target
## outline and the timing rules live in [JamBot], because those must look and
## behave identically on every enemy or the player cannot learn them once.

## Rivets down the flank, so a Clanky is still a Clanky in a greyscale
## screenshot next to a [PlatedKnuckle].
const RIVET_COLOR := Color("574636")


func roster_key() -> String:
	return "rusty_clanky"


func _draw_chassis(body: Rect2, alpha: float) -> void:
	super(body, alpha)
	var rivet := Vector2(6.0, 6.0)
	for step in range(3):
		var y := body.position.y + 30.0 + float(step) * 20.0
		draw_rect(
			Rect2(Vector2(body.position.x + 6.0, y), rivet),
			Color(RIVET_COLOR, alpha)
		)
		draw_rect(
			Rect2(Vector2(body.end.x - 12.0, y), rivet),
			Color(RIVET_COLOR, alpha)
		)