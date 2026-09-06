class_name NoteSource
extends Node

## Base class for anything that can tell the game a note was played.
##
## Subclasses are added as children of [NoteRouter], which connects these
## signals and forwards them to gameplay. A source knows how to listen to one
## kind of input and nothing else: it does not know what the target note is,
## whether the round is running, or that any other source exists.
##
## **A source that cannot run on this machine is simply not constructed.** That
## is the same code path as "nothing plugged in", and the framework's own
## headless suite already exercises it — `tests/game_shell_test.gd` drives a
## full round with no MIDI device and no microphone, so nothing here may block,
## poll a null device, or throw when a driver is missing (`DESIGN.md` §4.1).

signal note_started(event: NoteEvent)

## [param midi_note] is -1 when the source only knows that *something* stopped.
signal note_ended(midi_note: int)

## Drives the input meter on the note readout. Sources with no meaningful level
## never emit it, and the meter stays where it was rather than showing a
## confident zero.
signal input_level_changed(rms: float)


## Which [enum NoteEvent.Source] this produces. Subclasses must override.
func source_kind() -> NoteEvent.Source:
	return NoteEvent.Source.KEYBOARD


## Shown in Soundcheck. Subclasses override to name the actual device.
func display_name() -> String:
	return NoteEvent.source_name(source_kind())


## False when the source was constructed but has nothing to listen to — no
## device, no permission, a failed driver. It stays attached so the reason can
## be shown, rather than vanishing and leaving the player guessing.
func is_available() -> bool:
	return true


## Why this source is not available, in words a player can act on. Empty when
## it is working.
func unavailable_reason() -> String:
	return ""


## How far behind the player this source runs, in milliseconds. [NoteRouter]
## subtracts it from every timestamp, so the compensation lives with the source
## that knows about it instead of being applied uniformly to sources that do
## not need it.
func latency_ms() -> float:
	return 0.0


## Convenience for subclasses: build and emit a note in one call.
func emit_note(
	midi_note: int, velocity := 1.0, cents_off := 0.0, confidence := 1.0
) -> NoteEvent:
	var event := NoteEvent.make(
		midi_note, source_kind(), velocity, 0, cents_off, confidence
	)
	note_started.emit(event)
	return event
