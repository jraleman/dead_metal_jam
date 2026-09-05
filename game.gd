extends RefCounted

## Dead Metal Jam manifest — the rhythm game you play with a real instrument.
##
## [GameCatalog] discovers this file automatically; nothing in the framework
## refers to Dead Metal Jam by name.

const GAME_ID := "dead_metal_jam"


static func manifest() -> GameManifest:
	var game := GameManifest.new()
	game.id = GAME_ID
	game.title = "Dead Metal Jam"
	game.tagline = "Kill the robots by playing the right note."
	game.gameplay_scene_path = "res://games/dead_metal_jam/gameplay.tscn"
	game.menu_order = 2
	# One microphone hears one room, so there is no way to tell two players
	# apart and no way for a CPU to hold an instrument.
	game.supports_multiplayer = false
	game.supports_cpu_opponent = false
	# The player acts by playing a note rather than by pressing a bound key, so
	# the target-key control cards would describe controls that do not exist.
	# This style is the one that renders manifest copy instead.
	game.control_style = GameManifest.CONTROL_STYLE_DIRECT_MOVEMENT
	game.copy = {
		"mode_select_intro": "Tune up and pick your round.",
		"mode_select_hint": "Bring an instrument — the game listens to your microphone.",
		"single_player_description": (
			"Play the note each robot calls out. Hit it and the robot goes down; "
			+ "miss it and it keeps coming."
		),
		"player_one_control_description": "Play the called note on your instrument.",
		"solo_confirm_title": "Ready to play?",
		"solo_confirm_description": (
			"The game listens for two seconds to learn the room, then starts "
			+ "calling notes. Play them on your instrument to score."
		),
		"instructions_headline": "Play the note the robot calls",
		"instructions_rules": (
			"Right note +1  ·  Wrong note -1  ·  Play louder than the room  ·  "
			+ "Esc pauses"
		),
		"instructions_demo_prompt": "PLAY THE NOTE SHOWN ON SCREEN",
		"instructions_solo_summary": (
			"A note appears; play it on your instrument and the microphone does "
			+ "the rest. Any octave counts, so play it where it sits best."
		),
	}
	game.stats_url = "https://deskcansaw.com/stats/dmj"
	game.achievements = {
		"first_note": {
			"title": "First Blood",
			"description": "Play your first correct note.",
			"badge": "NOTE",
		},
		"clean_streak": {
			"title": "In The Pocket",
			"description": "Hit ten notes in a row without a miss.",
			"badge": "x10",
		},
	}
	return game
