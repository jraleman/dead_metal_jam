class_name DmjOptions
extends RefCounted

## Setting keys, ranges and bindings owned by Dead Metal Jam.
##
## The framework stores, clamps and renders these; only this file and the
## game's own scenes decide what they mean. Everything here reaches the player
## through the in-game Settings screen — the Game tab for the numbers and the
## input choice, the Controls tab for the keys.
##
## Microphone latency is deliberately absent: it is measured, not chosen, and
## it lives in [DmjProfile] beside the noise floor it was measured against.
##
## Constants only: this class is loaded by headless test scripts before
## autoloads exist, so it must not reference [Settings] or any other singleton.

## Matches the folder name and `games/dead_metal_jam/game.gd`.
const GAME_ID := "dead_metal_jam"

const WAVES_KEY := "game/dmj_waves"
const MODE_KEY := "game/dmj_mode"
const TRACK_KEY := "game/dmj_track"
const TIMING_WINDOW_KEY := "game/dmj_timing_window"
const WRONG_NOTE_PENALTY_KEY := "game/dmj_wrong_note_penalty"
const NOTE_SOURCE_KEY := "game/dmj_note_source"

const OCTAVE_DOWN_BINDING := "controls/dmj_octave_down"
const OCTAVE_UP_BINDING := "controls/dmj_octave_up"
const SELF_TEST_BINDING := "controls/dmj_self_test"

const OCTAVE_DOWN_ACTION := &"dmj_octave_down"
const OCTAVE_UP_ACTION := &"dmj_octave_up"
const SELF_TEST_ACTION := &"dmj_self_test"

## Which inputs are attached for the round. `AUTO` attaches every source that
## can run on this machine and lets [NoteRouter] pick per note; the rest pin
## the round to one, which is how a player silences a noisy room or a MIDI
## controller that is echoing their guitar.
const SOURCE_AUTO := 0
const SOURCE_MIC := 1
const SOURCE_MIDI := 2
const SOURCE_KEYBOARD := 3

## What a round is staged from. A song is a charted track — named sections, the
## rail advance between them, and the full roster (§10). The practice ramp is
## the generated one: the same rules, endlessly, with the wave count as its
## only dial, which is what a player wants when they are learning an instrument
## rather than playing a song.
##
## Both compile to the same plain data, so nothing downstream can tell them
## apart (§9.1).
##
## **The numbers are not in menu order, and they must not be renumbered.** A
## tunable's value is what gets written to `user://settings.cfg`, so shuffling
## these to read tidily would silently move every player who had chosen the
## practice ramp onto a song. The two values that shipped in milestone 6 keep
## the meanings they shipped with, and the tracks added in milestone 8 are
## appended. `TRACK_CHOICES` below decides the order the player sees.
const TRACK_SONG := 0
const TRACK_PRACTICE := 1
const TRACK_SONG_02 := 2
const TRACK_SONG_03 := 3

## Where each song's chart lives. A path constant is data, so it belongs with
## the choice it names rather than in `gameplay.gd`, which would otherwise hold
## a second list that could disagree with this one about how many songs there
## are. `jam_chart_test.gd` loads every entry.
const CHART_PATHS := {
	TRACK_SONG: "res://games/dead_metal_jam/chart/charts/track_01.tres",
	TRACK_SONG_02: "res://games/dead_metal_jam/chart/charts/track_02.tres",
	TRACK_SONG_03: "res://games/dead_metal_jam/chart/charts/track_03.tres",
}

## Menu order: the three songs by tempo, then the ramp. The titles are the
## songs' own, because a player picking a track is picking music.
const TRACK_CHOICES: Array[Dictionary] = [
	{"value": TRACK_SONG, "title": "Demo — 140 BPM"},
	{"value": TRACK_SONG_02, "title": "Scrapyard Stomp — 100 BPM"},
	{"value": TRACK_SONG_03, "title": "Overdrive — 168 BPM"},
	{"value": TRACK_PRACTICE, "title": "Practice ramp"},
]

## How a round is judged (§3). These mirror [enum EncounterDirector.Mode] and
## are repeated rather than imported so this file keeps its one real
## constraint — it is parsed by headless test scripts and must drag in nothing.
## `encounter_test.gd` asserts the two lists agree, so they cannot drift.
const MODE_JAM := 0
const MODE_RHYTHM := 1
const MODE_DEMO := 2

const MIN_WAVES := 1
const MAX_WAVES := 12
const MIN_TIMING_WINDOW := 0.6
const MAX_TIMING_WINDOW := 2.0
const MIN_WRONG_NOTE_PENALTY := 0
const MAX_WRONG_NOTE_PENALTY := 100

## The practice ramp's own dial. The shipped song brings its own sections, so
## this only decides how long the generated ramp runs.
const DEFAULT_WAVES := 4
const DEFAULT_TRACK := TRACK_SONG
const DEFAULT_MODE := MODE_JAM
const DEFAULT_TIMING_WINDOW := 1.0
const DEFAULT_WRONG_NOTE_PENALTY := 25
const DEFAULT_NOTE_SOURCE := SOURCE_AUTO

const TRACK_HEADING := "The track · next round"
const INPUT_HEADING := "Instrument input"

const TUNABLES: Array[Dictionary] = [
	{
		"key": MODE_KEY,
		"type": GameManifest.OPTION_CHOICE,
		"default": DEFAULT_MODE,
		"title": "Mode",
		"description": (
			"Jam is the game. Rhythm ignores which note you play and scores "
			+ "only your timing. Demo waits at every beat until you play it, "
			+ "and nothing can hurt you."
		),
		"heading": TRACK_HEADING,
		"choices": [
			{"value": MODE_JAM, "title": "Jam"},
			{"value": MODE_RHYTHM, "title": "Rhythm — any note"},
			{"value": MODE_DEMO, "title": "Demo — time waits for you"},
		],
	},
	{
		"key": TRACK_KEY,
		"type": GameManifest.OPTION_CHOICE,
		"default": DEFAULT_TRACK,
		"title": "Track",
		"description": (
			"Each song is charted: named sections, a rail advance between "
			+ "them, and armoured robots that ask for a phrase. The practice "
			+ "ramp just keeps sending waves."
		),
		"heading": TRACK_HEADING,
		"choices": TRACK_CHOICES,
	},
	{
		"key": WAVES_KEY,
		"default": float(DEFAULT_WAVES),
		"min": float(MIN_WAVES),
		"max": float(MAX_WAVES),
		"step": 1.0,
		"title": "Practice waves",
		"description": (
			"How long the practice ramp runs. The round timer follows the "
			+ "track; the song brings its own sections."
		),
		"format": GameManifest.FORMAT_COUNT,
		"heading": TRACK_HEADING,
	},
	{
		"key": TIMING_WINDOW_KEY,
		"default": DEFAULT_TIMING_WINDOW,
		"min": MIN_TIMING_WINDOW,
		"max": MAX_TIMING_WINDOW,
		"step": 0.05,
		"title": "Timing leniency",
		"description": (
			"Widens or tightens every timing window. Stacks with the "
			+ "Gameplay tab's handicap."
		),
		"format": GameManifest.FORMAT_PERCENT,
		"heading": TRACK_HEADING,
	},
	{
		"key": WRONG_NOTE_PENALTY_KEY,
		"default": float(DEFAULT_WRONG_NOTE_PENALTY),
		"min": float(MIN_WRONG_NOTE_PENALTY),
		"max": float(MAX_WRONG_NOTE_PENALTY),
		"step": 5.0,
		"title": "Wrong-note penalty",
		"description": (
			"Points lost for naming a robot that is not on the field. Set it "
			+ "to zero to experiment freely."
		),
		"format": GameManifest.FORMAT_COUNT,
		"heading": TRACK_HEADING,
	},
	{
		"key": NOTE_SOURCE_KEY,
		"type": GameManifest.OPTION_CHOICE,
		"default": DEFAULT_NOTE_SOURCE,
		"title": "Note input",
		"description": (
			"Chooses what the game listens to. Automatic uses whichever input "
			+ "answers first."
		),
		"heading": INPUT_HEADING,
		"choices": [
			{"value": SOURCE_AUTO, "title": "Automatic"},
			{"value": SOURCE_MIC, "title": "Microphone only"},
			{"value": SOURCE_MIDI, "title": "MIDI only"},
			{"value": SOURCE_KEYBOARD, "title": "Computer keyboard only"},
		],
	},
]

## No note key is rebindable: the practice keyboard is a picture of a piano
## (§4.5) and rebinding one key of it would leave a piano with a hole in it.
## The keys around it are another matter — they are ordinary shortcuts.
const CONTROL_BINDINGS: Array[Dictionary] = [
	{
		"key": OCTAVE_DOWN_BINDING,
		"action": OCTAVE_DOWN_ACTION,
		"default": KEY_Z,
		"title": "Practice keyboard: octave down",
		"heading": "Practice keyboard",
	},
	{
		"key": OCTAVE_UP_BINDING,
		"action": OCTAVE_UP_ACTION,
		"default": KEY_X,
		"title": "Practice keyboard: octave up",
		"heading": "Practice keyboard",
	},
	{
		"key": SELF_TEST_BINDING,
		"action": SELF_TEST_ACTION,
		"default": KEY_F2,
		"title": "Microphone self-test",
		"description": (
			"Plays a known tone through the analyser so a silent microphone "
			+ "and a broken one can be told apart."
		),
		"heading": "Practice keyboard",
	},
]


## True when [param choice] names a charted song rather than the generated ramp.
static func is_song(choice: int) -> bool:
	return CHART_PATHS.has(choice)


## The chart behind [param choice], or empty for the practice ramp.
##
## Empty is also what an *unrecognised* value gets, and that is deliberate: a
## `user://settings.cfg` written by a build with more tracks in it must still
## open a round on this one. Falling back to the ramp costs the player their
## chosen song; refusing to resolve would cost them the round.
static func chart_path(choice: int) -> String:
	return str(CHART_PATHS.get(choice, ""))
