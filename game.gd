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
	# Played instead of the framework's placeholder cards, but only in a build
	# that ships this game on its own — see `GameCatalog.intro_scene_path`.
	game.intro_scene_path = "res://games/dead_metal_jam/intro.tscn"
	game.menu_order = 2
	# One microphone hears one room, so there is no way to tell two players
	# apart and no way for a CPU to hold an instrument.
	game.supports_multiplayer = false
	game.supports_cpu_opponent = false
	# The player acts by playing a note rather than by pressing a bound key, so
	# the target-key control cards would describe controls that do not exist.
	# This style is the one that renders manifest copy instead.
	game.control_style = GameManifest.CONTROL_STYLE_DIRECT_MOVEMENT
	game.tunables = DmjOptions.TUNABLES
	game.control_bindings = DmjOptions.CONTROL_BINDINGS
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
			+ "the rest. Any octave counts, so play it where it sits best. No "
			+ "instrument handy? A MIDI keyboard or the computer keyboard works."
		),
		# Overrides the framework's mouse-and-keyboard line, which would be
		# nonsense here: nothing in this game is played with a control the base
		# knows about.
		"instructions_player_one_controls": (
			"Your instrument, into your microphone\n"
			+ "Or a MIDI keyboard, or A S D F G H J to practise\n"
			+ "Self-test and octave keys: Settings → Controls"
		),
	}
	game.stats_url = "https://deskcansaw.com/stats/dmj"
	game.theme = _theme()
	game.credits = [
		{
			"heading": "Game Design & Code",
			"lines": ["DeskCanSaw"],
		},
		{
			"heading": "Pitch Detection",
			"lines": [
				"McLeod Pitch Method over the NSDF",
				"Philip McLeod & Geoff Wyvill, \"A Smarter Way to Find Pitch\"",
				"Implemented in GDScript for this game",
			],
		},
		{
			"heading": "Sound",
			"lines": ["Amp hum, power chords and note pings synthesised in-engine"],
		},
		{
			"heading": "Instrument",
			"lines": ["Whatever you plugged in, played into your microphone"],
		},
	]
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


## Rusted metal under a warm stage lamp: the amber the drones outline their
## called note with is the accent, and the chassis brown they are built from is
## the plaque. The screens read the same colours the playfield does.
##
## Only a build that ships this game alone wears it — see [GameCatalog.theme].
static func _theme() -> GameTheme:
	var theme := GameTheme.new()
	theme.logo_texture_path = "res://games/dead_metal_jam/assets/game-icon.svg"
	theme.logo_color = Color("ffd34e")
	theme.plaque_color = Color("2a2019")
	theme.accent = Color("ffd34e")
	theme.light = Color("ffe3a8")
	theme.background_top = Color("241a12")
	theme.background_bottom = Color("0b0806")
	return theme
