class_name RustyClanky
extends JamBot

## One Rusty Clanky — the game's core verb in a single actor (§8.2).
##
## One note, one hit. It is the enemy that teaches what the instrument is for,
## so it asks for nothing beyond what [JamBot] already does: walk in, show a
## letter, die to that letter.
##
## Its rattling limbs and note-bearing chest come from [DmjRustyClankyArt].
## The shared pose contract keeps its telegraphs identical to the other bots.


func roster_key() -> String:
	return "rusty_clanky"


func _create_art() -> DmjDroneArt:
	return DmjRustyClankyArt.new()