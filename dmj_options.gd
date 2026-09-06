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

const MIN_WAVES := 1
const MAX_WAVES := 12
const MIN_TIMING_WINDOW := 0.6
const MAX_TIMING_WINDOW := 2.0
const MIN_WRONG_NOTE_PENALTY := 0
const MAX_WRONG_NOTE_PENALTY := 100

## The shipped chart: four waves judged on the windows the tiers were tuned
## against, with a wrong note costing a quarter of an edge hit.
const DEFAULT_WAVES := 4
const DEFAULT_TIMING_WINDOW := 1.0
const DEFAULT_WRONG_NOTE_PENALTY := 25
const DEFAULT_NOTE_SOURCE := SOURCE_AUTO

const TRACK_HEADING := "The track · next round"
const INPUT_HEADING := "Instrument input"

const TUNABLES: Array[Dictionary] = [
	{
		"key": WAVES_KEY,
		"default": float(DEFAULT_WAVES),
		"min": float(MIN_WAVES),
		"max": float(MAX_WAVES),
		"step": 1.0,
		"title": "Waves per track",
		"description": (
			"Sets how long a track runs. The round timer follows the track."
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
