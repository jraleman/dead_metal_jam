class_name PitchAnalysis
extends RefCounted

## One analysed window of audio from [PitchDetector].
##
## Its own file rather than an inner class so callers can type arrays of it
## (`Array[PitchAnalysis]`) and so a hop can be handed around the note pipeline
## without dragging the detector along with it.
##
## [member voiced] is the only field worth branching on. Everything else is
## neutral — -1 or 0.0 — when nothing was heard, so a caller that forgets the
## check reads "no note" rather than the last note that happened to be played.

var voiced := false
var frequency := 0.0

## Fractional MIDI number, so intonation survives rounding.
var midi := 0.0

var midi_note := -1

## What gameplay actually matches on (see `DESIGN.md` §4.4), 0-11, or -1 when
## unvoiced.
var pitch_class := -1

## Signed deviation from equal temperament, -50.0 to +50.0.
var cents_off := 0.0

## NSDF clarity at the chosen peak, 0.0-1.0. The note readout shows this so an
## unsure guess never looks like a confident answer.
var confidence := 0.0

var rms := 0.0

## True on the hop where a note *starts*, which is the hop the game turns into
## a shot. Only the streaming path sets this; a single analysed window has no
## history to compare against, so [method PitchDetector.analyse_window] always
## leaves it false.
var is_onset := false


func _to_string() -> String:
	if not voiced:
		return "<PitchAnalysis unvoiced>"
	return "<PitchAnalysis %s %+.1f cents at %.2f confidence>" % [
		PitchDetector.note_label(midi_note), cents_off, confidence
	]
