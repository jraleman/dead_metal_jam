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
	game.default_lives_mode = true
	# The player acts by playing a note rather than by pressing a bound key, so
	# the target-key control cards would describe controls that do not exist.
	# This style is the one that renders manifest copy instead.
	game.control_style = GameManifest.CONTROL_STYLE_DIRECT_MOVEMENT
	game.tunables = DmjOptions.TUNABLES
	game.control_bindings = DmjOptions.CONTROL_BINDINGS
	game.copy = {
		# Kept for a build that re-enables two players: this game declares
		# `supports_multiplayer = false`, so mode select is skipped entirely and
		# Play goes straight to the instructions.
		"mode_select_intro": "Tune up and pick your round.",
		"mode_select_hint": "Bring an instrument — the game listens to your microphone.",
		"single_player_description": (
			"Match the robot's note and color before its attack bar fills. "
			+ "Shots near the beat earn bigger bonuses."
		),
		"player_one_control_description": "Play the called note on your instrument.",
		"solo_confirm_title": "Ready to play?",
		"solo_confirm_description": (
			"The game listens for two seconds to learn the room, then starts "
			+ "calling notes. Play them on your instrument to score."
		),
		"instructions_headline": "Play the note the robot calls",
		"instructions_rules": (
			"Right note fires  ·  Beat timing earns bonuses  ·  "
			+ "Wrong note -25  ·  Shoot before the attack bar fills  ·  Esc pauses"
		),
		"instructions_demo_prompt": "PLAY THE NOTE SHOWN ON SCREEN",
		"instructions_solo_summary": (
			"A note appears; play it on your instrument and the microphone does "
			+ "the rest. Any octave counts, so play it where it sits best. No "
			+ "instrument handy? A MIDI keyboard or the computer keyboard works. "
			+ "Plated Knuckles take three notes in order; a wrong note resets their armor."
			+ " Silencer Sentries need the same note twice. The Conductor needs "
			+ "four notes, saving progress after each pair. No background music: "
			+ "listen to your instrument and follow the visual beat rings."
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
	# The card's artwork is this game's own scene, not one of the framework's
	# two built-in styles (§9.5). A corridor of robots calling notes is the
	# whole pitch of the game, and it is not something the base project should
	# be asked to know how to draw.
	game.share_art_scene_path = "res://games/dead_metal_jam/ui/share_art.tscn"
	# Recorded against Scrapyard Stomp rather than the practice ramp: the ramp
	# is seeded from the clock, so its captions would describe a take nobody
	# else will ever get. Re-record with
	# `tools/record_tutorials.ps1 -Games dead_metal_jam`.
	game.tutorial_video_path = "res://games/dead_metal_jam/assets/video/tutorial.ogv"
	game.tutorial_poster_path = (
		"res://games/dead_metal_jam/assets/video/tutorial_poster.webp"
	)
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
			"lines": ["Amp hum, power chords, note pings and mechanical menu cues synthesised in-engine"],
		},
		{
			"heading": "Instrument",
			"lines": ["Whatever you plugged in, played into your microphone"],
		},
	]
	game.achievements = {
		# The ladder is deliberately shallow at the bottom and steep at the
		# top: finishing a track at all is the first one, and the other four
		# each ask for one specific thing to be done well rather than for the
		# same run to be done again with a bigger number attached (§9.6).
		"jam_first_track": {
			"title": "Soundcheck",
			"description": "Finish a track in any mode.",
			"badge": "SET",
		},
		"jam_perfect_section": {
			"title": "Tight",
			"description": "Clear a whole section with every robot dropped on a Perfect.",
			"badge": "100",
		},
		"jam_no_damage": {
			"title": "Untouched",
			"description": "Finish a Jam track without letting a single robot fire.",
			"badge": "0",
		},
		"jam_mic_run": {
			"title": "Unplugged",
			"description": "Finish a Jam track played entirely into the microphone.",
			"badge": "MIC",
		},
		"jam_combo_eight": {
			"title": "Shredder",
			"description": "Reach a x8 combo.",
			"badge": "x8",
		},
	}
	return game


## Warm stage lighting over cold steel, shared with the corridor and console.
##
## Only a build that ships this game alone wears it — see [GameCatalog.theme].
static func _theme() -> GameTheme:
	var theme := GameTheme.new()
	theme.logo_texture_path = "res://games/dead_metal_jam/assets/game-icon.svg"
	theme.logo_color = DmjPalette.AMBER
	theme.plaque_color = DmjPalette.STEEL
	theme.accent = DmjPalette.AMBER
	theme.light = Color("fff0c2")
	theme.background_top = Color("15252d")
	theme.background_bottom = DmjPalette.INK
	theme.ui_theme = DmjMenuSkin.create()
	theme.ui_sounds = DmjMenuSound.create()
	theme.background_material = preload("res://games/dead_metal_jam/ui/menu_background.tres")
	theme.plaque_material = preload("res://games/dead_metal_jam/ui/menu_plaque.tres")
	theme.menu_motion = GameTheme.MenuMotion.FIRM
	return theme
