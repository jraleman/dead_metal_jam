class_name NoteEvent
extends RefCounted

## One note, from whichever input the player is using.
##
## This is the only thing gameplay ever sees. A note played on a MIDI keyboard,
## a note picked out of the microphone and a note typed on the computer
## keyboard all arrive here identical in shape, which is what lets the game
## reach a new platform by adding a source rather than by touching scoring
## (`DESIGN.md` §4.1).
##
## Fields that a given source cannot know are filled with honest neutrals
## rather than plausible guesses: MIDI has no cents deviation because it is not
## measuring anything, so [member cents_off] is 0.0 and [member confidence] is
## 1.0. A caller must never have to ask which source it came from to know
## whether a field means anything.

enum Source {
	MIDI,
	MIC,
	KEYBOARD,
	## Tap-to-fire, mobile. Onset only — see `DESIGN.md` §4.5.
	TOUCH,
}

## 0-127, or -1 when only an *onset* is known and the pitch is not — which is
## what Rhythm mode and the touch source produce.
var midi_note := -1

## [member midi_note] modulo 12, or -1. What scoring actually matches on, so
## the player may play the called note in whichever octave suits their
## instrument.
var pitch_class := -1

## 0.0-1.0. Real data on the MIDI path, a constant elsewhere. Never a gate: a
## quietly played correct note is still a correct note.
var velocity := 0.0

## Signed deviation from equal temperament, -50.0 to +50.0. Always 0.0 from
## sources that are told the note rather than measuring it.
var cents_off := 0.0

## 0.0-1.0. Always 1.0 from sources that cannot be wrong about the pitch.
var confidence := 0.0

var source := Source.MIC

## [method Time.get_ticks_usec] at detection, **before** latency compensation.
## [NoteRouter] applies the offset, so a source never has to know how far
## behind the player it is.
var timestamp_us := 0


## The usual way to build one. [param midi_note] may be -1 for an onset with no
## pitch; [member pitch_class] is derived so it can never disagree.
static func make(
	midi_note: int,
	source: Source,
	velocity := 1.0,
	timestamp_us := 0,
	cents_off := 0.0,
	confidence := 1.0
) -> NoteEvent:
	var event := NoteEvent.new()
	event.midi_note = midi_note
	event.pitch_class = -1 if midi_note < 0 else ((midi_note % 12) + 12) % 12
	event.source = source
	event.velocity = clampf(velocity, 0.0, 1.0)
	event.timestamp_us = timestamp_us if timestamp_us > 0 else Time.get_ticks_usec()
	event.cents_off = cents_off
	event.confidence = clampf(confidence, 0.0, 1.0)
	return event


## True when the pitch is unknown and only the attack is. Rhythm mode scores
## these; note-matching mode cannot.
func is_onset_only() -> bool:
	return midi_note < 0


static func source_name(kind: Source) -> String:
	match kind:
		Source.MIDI:
			return "MIDI"
		Source.MIC:
			return "Microphone"
		Source.KEYBOARD:
			return "Keyboard"
		Source.TOUCH:
			return "Touch"
	return "Unknown"


func _to_string() -> String:
	if is_onset_only():
		return "<NoteEvent onset from %s>" % source_name(source)
	return "<NoteEvent %s from %s at %.2f velocity>" % [
		PitchDetector.note_label(midi_note), source_name(source), velocity
	]
