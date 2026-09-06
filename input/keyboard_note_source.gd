class_name KeyboardNoteSource
extends NoteSource

## A piano laid out on the computer keyboard, for when there is no instrument.
##
## `DESIGN.md` §4.5 lists three reasons this exists, none of which is
## convenience:
##
## 1. `tests/game_shell_test.gd` has to drive a full round headlessly.
## 2. The tutorial capture records the instructions video with a scripted demo
##    player, and a scripted player cannot hold a guitar.
## 3. A player whose gear is not working can still finish the round.
##
## It is a listed input option marked "practice", not a hidden debug key. The
## layout is the one every tracker and DAW uses, so anyone who has typed notes
## before already knows it:
##
## [codeblock]
##     W E   T Y U        C# D#   F# G# A#
##    A S D F G H J K     C  D  E F  G  A  B  C
## [/codeblock]
##
## `Z` and `X` shift the octave. Notes are matched by pitch class anyway, so the
## octave is very nearly cosmetic — it exists so the readout shows something
## sensible rather than always claiming C3.

signal octave_changed(base_midi: int)

## Keycode to semitones above the base note. The two rows together are one
## octave plus the C on top, which is what makes the shape recognisable.
const LAYOUT := {
	KEY_A: 0,
	KEY_W: 1,
	KEY_S: 2,
	KEY_E: 3,
	KEY_D: 4,
	KEY_F: 5,
	KEY_T: 6,
	KEY_G: 7,
	KEY_Y: 8,
	KEY_H: 9,
	KEY_U: 10,
	KEY_J: 11,
	KEY_K: 12,
}

## C3. Guitar open strings run E2-E4, so this sits in the middle of the range
## the game calls notes from.
const DEFAULT_BASE_MIDI := 48

const OCTAVE_DOWN_KEY := KEY_Z
const OCTAVE_UP_KEY := KEY_X

## The octave keys are rebindable, so they are variables seeded with the
## defaults above rather than the constants themselves. The game sets them
## from [Settings]; the tests and the tutorial capture leave them alone.
var octave_down_key := OCTAVE_DOWN_KEY
var octave_up_key := OCTAVE_UP_KEY

## Keyboards have no velocity. A constant is the honest answer; inventing one
## from key-repeat timing would be a guess dressed up as data.
const FIXED_VELOCITY := 0.8

const MIN_BASE_MIDI := 12
const MAX_BASE_MIDI := 108

var _base_midi := DEFAULT_BASE_MIDI

## Which MIDI note each held key produced, so the note-off matches the note-on
## even if the octave was shifted while the key was down.
var _held: Dictionary[int, int] = {}


func source_kind() -> NoteEvent.Source:
	return NoteEvent.Source.KEYBOARD


func display_name() -> String:
	return "Computer keyboard (practice)"


func base_midi() -> int:
	return _base_midi


func octave_label() -> String:
	return PitchDetector.note_label(_base_midi)


## Handles the keys it knows and lets everything else through untouched, so
## pause, the self-test and any framework shortcut still work while this source
## is live.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or key.echo:
		return

	if not key.pressed:
		_release(key.keycode)
		return

	if key.keycode == octave_down_key:
		_shift_octave(-12)
		get_viewport().set_input_as_handled()
		return
	if key.keycode == octave_up_key:
		_shift_octave(12)
		get_viewport().set_input_as_handled()
		return

	if not LAYOUT.has(key.keycode):
		return
	_press(key.keycode)
	get_viewport().set_input_as_handled()


## Plays the note a key maps to. Public so the tutorial capture and the tests
## can drive this source without synthesising [InputEventKey]s.
func press_key(keycode: int) -> void:
	if LAYOUT.has(keycode):
		_press(keycode)


func release_key(keycode: int) -> void:
	_release(keycode)


## Plays a note directly, bypassing the layout. This is what a scripted demo
## player uses: it knows the note it wants, not which key happens to produce it.
func play_note(midi_note: int, velocity := FIXED_VELOCITY) -> NoteEvent:
	return emit_note(midi_note, velocity)


func _press(keycode: int) -> void:
	# A key already down cannot be pressed again; without this, an OS that
	# repeats through a different path would machine-gun the note.
	if _held.has(keycode):
		return
	var note: int = _base_midi + int(LAYOUT[keycode])
	_held[keycode] = note
	emit_note(note, FIXED_VELOCITY)


func _release(keycode: int) -> void:
	if not _held.has(keycode):
		return
	var note: int = _held[keycode]
	_held.erase(keycode)
	note_ended.emit(note)


## Held keys are released first: shifting the octave with a key down would
## otherwise leave a note that can never be ended, because the note-off would
## be computed from the new base.
func _shift_octave(semitones: int) -> void:
	var next := clampi(_base_midi + semitones, MIN_BASE_MIDI, MAX_BASE_MIDI)
	if next == _base_midi:
		return
	for keycode: int in _held.keys():
		_release(keycode)
	_base_midi = next
	octave_changed.emit(_base_midi)
