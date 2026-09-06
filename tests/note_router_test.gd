extends SceneTree

## Headless tests for the note input stack: [NoteEvent], [KeyboardNoteSource],
## [MidiNoteSource] and [NoteRouter].
##
## Hardware-free on purpose. MIDI is exercised by pushing synthetic
## [InputEventMIDI]s through the source, which was verified to be faithful:
## `device`, `pitch`, `velocity` and `message` all survive the round trip
## through Godot's input pipeline. That means every branch here — including the
## velocity-0 note-off trap — is the same code a real controller drives.
##
## Run:
##   godot --headless --path godot-base \
##     --script res://games/dead_metal_jam/tests/note_router_test.gd

const DEDUPE_WINDOW_US := int(NoteRouter.DEDUPE_WINDOW_MS * 1000.0)

var _failures: Array[String] = []
var _checks := 0


func _initialize() -> void:
	_test_note_event_derives_pitch_class()
	_test_note_event_neutrals()
	_test_router_runs_with_no_sources()
	_test_router_forwards_a_note()
	_test_router_applies_latency_offset()
	_test_router_merges_two_sources()
	_test_router_keeps_same_source_repeats()
	_test_router_keeps_distant_notes()
	_test_router_separates_pitch_classes()
	_test_router_drops_while_not_accepting()
	_test_router_reports_availability()
	_test_keyboard_layout_is_a_piano()
	_test_keyboard_octave_shift()
	_test_keyboard_releases_before_shifting()
	_test_keyboard_ignores_unmapped_keys()
	_test_midi_note_on_and_off()
	_test_midi_velocity_zero_is_note_off()
	_test_midi_ignores_sustain_pedal()
	_test_midi_device_filter()
	_finish()


# --------------------------------------------------------------------------
# NoteEvent


func _test_note_event_derives_pitch_class() -> void:
	var event := NoteEvent.make(57, NoteEvent.Source.MIDI, 0.5)
	_check(event.pitch_class == 9, "A3 must be pitch class 9, got %d" % event.pitch_class)
	_check(not event.is_onset_only(), "A pitched note is not onset-only.")

	var onset := NoteEvent.make(-1, NoteEvent.Source.TOUCH)
	_check(onset.pitch_class == -1, "An onset with no pitch has no pitch class.")
	_check(onset.is_onset_only(), "An onset with no pitch is onset-only.")

	# Pitch class must never go negative, or the modulo comparison in scoring
	# silently stops matching.
	var low := NoteEvent.make(0, NoteEvent.Source.KEYBOARD)
	_check(low.pitch_class == 0, "MIDI 0 is pitch class 0, got %d" % low.pitch_class)


func _test_note_event_neutrals() -> void:
	var event := NoteEvent.make(60, NoteEvent.Source.MIDI, 2.0)
	_check(is_equal_approx(event.velocity, 1.0), "Velocity must be clamped to 1.0.")
	_check(event.timestamp_us > 0, "A note must be stamped when it is made.")


# --------------------------------------------------------------------------
# Router


func _test_router_runs_with_no_sources() -> void:
	# The framework's own suite drives a full headless round with no devices at
	# all. A router that assumed it had inputs would break game_shell_test.
	var router := NoteRouter.new()
	root.add_child(router)
	_check(router.sources().is_empty(), "A fresh router has no sources.")
	_check(not router.has_any_input(), "No sources means no input.")
	_check(
		router.describe_sources() == "No input sources.",
		"An empty router says so in words."
	)
	router.set_accepting(true)
	_check(router.merged_count() == 0, "Nothing merged when nothing arrived.")
	router.queue_free()


func _test_router_forwards_a_note() -> void:
	var rig := _rig()
	rig.source.play_note(57)
	_check(rig.notes.size() == 1, "One played note is one forwarded note.")
	if rig.notes.size() == 1:
		var event: NoteEvent = rig.notes[0]
		_check(event.midi_note == 57, "The note survives the router unchanged.")
		_check(
			event.source == NoteEvent.Source.KEYBOARD,
			"The source is recorded on the event."
		)
	rig.router.queue_free()


func _test_router_applies_latency_offset() -> void:
	var router := NoteRouter.new()
	root.add_child(router)
	var notes: Array[NoteEvent] = []
	router.note_started.connect(func(e: NoteEvent) -> void: notes.append(e))

	var source := LaggySource.new()
	source.lag_ms = 80.0
	router.add_source(source)

	var before := Time.get_ticks_usec()
	source.play(45)
	var after := Time.get_ticks_usec()

	_check(notes.size() == 1, "The laggy source produced one note.")
	if notes.size() == 1:
		var stamp: int = notes[0].timestamp_us
		# The note is dated 80 ms earlier than it arrived, because that is when
		# the player actually played it.
		var expected_low := before - 80_000
		var expected_high := after - 80_000
		_check(
			stamp >= expected_low - 2000 and stamp <= expected_high + 2000,
			"Latency must be subtracted: stamp %d outside [%d, %d]" % [
				stamp, expected_low, expected_high
			]
		)
	router.queue_free()


func _test_router_merges_two_sources() -> void:
	# One guitar, heard by a pickup and a microphone at once, is one note.
	var router := NoteRouter.new()
	root.add_child(router)
	var notes: Array[NoteEvent] = []
	router.note_started.connect(func(e: NoteEvent) -> void: notes.append(e))

	var midi := StubSource.new()
	midi.kind = NoteEvent.Source.MIDI
	var mic := StubSource.new()
	mic.kind = NoteEvent.Source.MIC
	router.add_source(midi)
	router.add_source(mic)

	var now := Time.get_ticks_usec()
	midi.play_at(57, now)
	mic.play_at(57, now + 40_000)

	_check(notes.size() == 1, "Two sources hearing one note emit one note, got %d" % notes.size())
	_check(router.merged_count() == 1, "The merge is counted.")
	if notes.size() >= 1:
		_check(
			notes[0].source == NoteEvent.Source.MIDI,
			"The first source to report wins, not the last."
		)
	router.queue_free()


func _test_router_keeps_same_source_repeats() -> void:
	# A player re-striking a string is exactly what the game is listening for.
	var rig := _rig()
	var now := Time.get_ticks_usec()
	rig.source.play_note(57)
	rig.source.play_note(57)
	_check(
		rig.notes.size() == 2,
		"Two notes from one source are two notes, got %d" % rig.notes.size()
	)
	rig.router.queue_free()


func _test_router_keeps_distant_notes() -> void:
	var router := NoteRouter.new()
	root.add_child(router)
	var notes: Array[NoteEvent] = []
	router.note_started.connect(func(e: NoteEvent) -> void: notes.append(e))

	var midi := StubSource.new()
	midi.kind = NoteEvent.Source.MIDI
	var mic := StubSource.new()
	mic.kind = NoteEvent.Source.MIC
	router.add_source(midi)
	router.add_source(mic)

	var now := Time.get_ticks_usec()
	midi.play_at(57, now)
	mic.play_at(57, now + DEDUPE_WINDOW_US + 50_000)

	_check(
		notes.size() == 2,
		"The same note played again later is a new note, got %d" % notes.size()
	)
	router.queue_free()


func _test_router_separates_pitch_classes() -> void:
	var router := NoteRouter.new()
	root.add_child(router)
	var notes: Array[NoteEvent] = []
	router.note_started.connect(func(e: NoteEvent) -> void: notes.append(e))

	var midi := StubSource.new()
	midi.kind = NoteEvent.Source.MIDI
	var mic := StubSource.new()
	mic.kind = NoteEvent.Source.MIC
	router.add_source(midi)
	router.add_source(mic)

	var now := Time.get_ticks_usec()
	midi.play_at(57, now)
	mic.play_at(59, now + 10_000)

	_check(notes.size() == 2, "Different notes at the same moment are two notes.")

	# An octave apart is the *same* pitch class, which is what scoring matches
	# on, so it must still merge.
	notes.clear()
	router.set_accepting(false)
	router.set_accepting(true)
	var later := Time.get_ticks_usec()
	midi.play_at(45, later)
	mic.play_at(57, later + 10_000)
	_check(
		notes.size() == 1,
		"A3 and A2 from two sources are one note, got %d" % notes.size()
	)
	router.queue_free()


func _test_router_drops_while_not_accepting() -> void:
	var rig := _rig()
	rig.router.set_accepting(false)
	rig.source.play_note(57)
	_check(rig.notes.is_empty(), "Nothing scores while the router is closed.")
	rig.router.set_accepting(true)
	rig.source.play_note(57)
	_check(rig.notes.size() == 1, "Reopening the router lets notes through again.")
	rig.router.queue_free()


func _test_router_reports_availability() -> void:
	var router := NoteRouter.new()
	root.add_child(router)
	var broken := StubSource.new()
	broken.available = false
	broken.reason = "No MIDI device is connected."
	router.add_source(broken)

	_check(router.sources().size() == 1, "An unavailable source stays attached.")
	_check(not router.has_any_input(), "An unavailable source is not input.")
	_check(
		router.describe_sources().contains("No MIDI device"),
		"The reason reaches the player."
	)
	_check(
		router.find_source(broken.source_kind()) == broken,
		"A source can be found by kind."
	)
	router.queue_free()


# --------------------------------------------------------------------------
# Keyboard


func _test_keyboard_layout_is_a_piano() -> void:
	var rig := _rig()
	# A S D F G H J K over W E T Y U is C D E F G A B C over the black keys.
	var expected := {
		KEY_A: 0, KEY_W: 1, KEY_S: 2, KEY_E: 3, KEY_D: 4, KEY_F: 5,
		KEY_T: 6, KEY_G: 7, KEY_Y: 8, KEY_H: 9, KEY_U: 10, KEY_J: 11, KEY_K: 12,
	}
	var base := rig.source.base_midi()
	for keycode: int in expected.keys():
		rig.notes.clear()
		rig.source.press_key(keycode)
		rig.source.release_key(keycode)
		if rig.notes.size() != 1:
			_check(false, "Key %d produced %d notes." % [keycode, rig.notes.size()])
			continue
		var got: int = rig.notes[0].midi_note
		var want: int = base + int(expected[keycode])
		_check(got == want, "Key %d should be MIDI %d, got %d" % [keycode, want, got])

	# The whole point of the source: notes with no instrument.
	_check(
		rig.source.base_midi() == KeyboardNoteSource.DEFAULT_BASE_MIDI,
		"The base octave is unchanged by playing."
	)
	rig.router.queue_free()


func _test_keyboard_octave_shift() -> void:
	var rig := _rig()
	var base := rig.source.base_midi()
	rig.source._shift_octave(12)
	_check(rig.source.base_midi() == base + 12, "X shifts up an octave.")
	rig.source.press_key(KEY_A)
	_check(
		rig.notes.size() == 1 and rig.notes[0].midi_note == base + 12,
		"A plays the shifted C."
	)
	rig.source.release_key(KEY_A)

	# Clamped, so a player leaning on the key cannot leave the MIDI range.
	for i in 20:
		rig.source._shift_octave(12)
	_check(
		rig.source.base_midi() <= KeyboardNoteSource.MAX_BASE_MIDI,
		"The octave is clamped at the top."
	)
	for i in 40:
		rig.source._shift_octave(-12)
	_check(
		rig.source.base_midi() >= KeyboardNoteSource.MIN_BASE_MIDI,
		"The octave is clamped at the bottom."
	)
	rig.router.queue_free()


func _test_keyboard_releases_before_shifting() -> void:
	# A note held across an octave shift would otherwise be ended with a
	# different MIDI number than it started with, leaving it stuck on.
	var rig := _rig()
	var ended: Array[int] = []
	rig.router.note_ended.connect(func(n: int) -> void: ended.append(n))

	var base := rig.source.base_midi()
	rig.source.press_key(KEY_A)
	rig.source._shift_octave(12)
	_check(ended.size() == 1, "Shifting ends held notes, got %d" % ended.size())
	if ended.size() == 1:
		_check(
			ended[0] == base,
			"The note ends with the number it started with, got %d" % ended[0]
		)
	rig.router.queue_free()


func _test_keyboard_ignores_unmapped_keys() -> void:
	var rig := _rig()
	rig.source.press_key(KEY_ESCAPE)
	rig.source.press_key(KEY_SPACE)
	rig.source.press_key(KEY_F2)
	_check(rig.notes.is_empty(), "Unmapped keys are not notes.")

	# A key already down does not fire twice, whatever the OS repeat does.
	rig.source.press_key(KEY_A)
	rig.source.press_key(KEY_A)
	_check(rig.notes.size() == 1, "A held key fires once, got %d" % rig.notes.size())
	rig.router.queue_free()


# --------------------------------------------------------------------------
# MIDI


func _test_midi_note_on_and_off() -> void:
	var rig := _midi_rig()
	var ended: Array[int] = []
	rig.router.note_ended.connect(func(n: int) -> void: ended.append(n))

	rig.source._input(_midi_event(MIDI_MESSAGE_NOTE_ON, 57, 100))
	_check(rig.notes.size() == 1, "A note-on is a note.")
	if rig.notes.size() == 1:
		var event: NoteEvent = rig.notes[0]
		_check(event.midi_note == 57, "The pitch survives.")
		_check(
			is_equal_approx(event.velocity, 100.0 / 127.0),
			"Velocity is real data on this path, got %f" % event.velocity
		)
		_check(is_equal_approx(event.confidence, 1.0), "MIDI is never unsure.")
		_check(is_zero_approx(event.cents_off), "MIDI measures nothing, so no cents.")

	rig.source._input(_midi_event(MIDI_MESSAGE_NOTE_OFF, 57, 0))
	_check(ended.size() == 1, "A note-off ends the note.")
	rig.router.queue_free()


func _test_midi_velocity_zero_is_note_off() -> void:
	# The classic MIDI trap: many controllers never send a real Note Off.
	var rig := _midi_rig()
	var ended: Array[int] = []
	rig.router.note_ended.connect(func(n: int) -> void: ended.append(n))

	rig.source._input(_midi_event(MIDI_MESSAGE_NOTE_ON, 60, 0))
	_check(rig.notes.is_empty(), "A note-on at velocity 0 is not a note.")
	_check(ended.size() == 1, "A note-on at velocity 0 ends the note.")
	if ended.size() == 1:
		_check(ended[0] == 60, "It ends the right note.")
	rig.router.queue_free()


func _test_midi_ignores_sustain_pedal() -> void:
	# Without this being explicit, a held pedal makes every note look sustained.
	var rig := _midi_rig()
	var ended: Array[int] = []
	rig.router.note_ended.connect(func(n: int) -> void: ended.append(n))

	var pedal := InputEventMIDI.new()
	pedal.message = MIDI_MESSAGE_CONTROL_CHANGE
	pedal.controller_number = MidiNoteSource.SUSTAIN_PEDAL_CONTROLLER
	pedal.controller_value = 127
	rig.source._input(pedal)

	_check(rig.notes.is_empty(), "The sustain pedal is not a note.")
	_check(ended.is_empty(), "The sustain pedal does not end notes.")
	rig.router.queue_free()


func _test_midi_device_filter() -> void:
	var rig := _midi_rig()
	rig.source.set_device_filter(1)

	var wrong := _midi_event(MIDI_MESSAGE_NOTE_ON, 57, 90)
	wrong.device = 0
	rig.source._input(wrong)
	_check(rig.notes.is_empty(), "A note from another device is ignored.")

	var right := _midi_event(MIDI_MESSAGE_NOTE_ON, 57, 90)
	right.device = 1
	rig.source._input(right)
	_check(rig.notes.size() == 1, "A note from the chosen device is accepted.")

	# Every device seen is recorded even when filtered out, which is how the
	# picker finds out whether `device` is populated at all on this platform.
	var seen := rig.source.observed_devices()
	_check(seen.has(0) and seen.has(1), "Both devices were observed, got %s" % str(seen))

	rig.source.set_device_filter(MidiNoteSource.ANY_DEVICE)
	rig.notes.clear()
	rig.source._input(wrong)
	_check(rig.notes.size() == 1, "ANY_DEVICE accepts everything.")
	rig.router.queue_free()


# --------------------------------------------------------------------------
# Helpers


func _midi_event(message: int, pitch: int, velocity: int) -> InputEventMIDI:
	var event := InputEventMIDI.new()
	event.message = message
	event.pitch = pitch
	event.velocity = velocity
	event.channel = 0
	return event


## A router with a keyboard source attached and a list collecting what comes
## out the other side.
func _rig() -> Rig:
	var rig := Rig.new()
	rig.router = NoteRouter.new()
	root.add_child(rig.router)
	rig.router.note_started.connect(func(e: NoteEvent) -> void: rig.notes.append(e))
	rig.source = KeyboardNoteSource.new()
	rig.router.add_source(rig.source)
	return rig


func _midi_rig() -> MidiRig:
	var rig := MidiRig.new()
	rig.router = NoteRouter.new()
	root.add_child(rig.router)
	rig.router.note_started.connect(func(e: NoteEvent) -> void: rig.notes.append(e))
	rig.source = MidiNoteSource.new()
	rig.router.add_source(rig.source)
	return rig


func _check(passed: bool, message: String) -> void:
	_checks += 1
	if not passed:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Note router tests passed. (%d checks)" % _checks)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("Note router tests FAILED: %d of %d checks." % [_failures.size(), _checks])
	quit(1)


class Rig:
	extends RefCounted
	var router: NoteRouter
	var source: KeyboardNoteSource
	var notes: Array[NoteEvent] = []


class MidiRig:
	extends RefCounted
	var router: NoteRouter
	var source: MidiNoteSource
	var notes: Array[NoteEvent] = []


## A source with no hardware behind it, so timestamps and availability can be
## driven exactly.
class StubSource:
	extends NoteSource

	var kind := NoteEvent.Source.MIDI
	var available := true
	var reason := ""

	func source_kind() -> NoteEvent.Source:
		return kind

	func is_available() -> bool:
		return available

	func unavailable_reason() -> String:
		return reason

	func play_at(midi_note: int, stamp_us: int) -> void:
		var event := NoteEvent.make(midi_note, kind, 1.0, stamp_us)
		note_started.emit(event)


## A source that reports a fixed latency, for checking the router's offset.
class LaggySource:
	extends NoteSource

	var lag_ms := 0.0

	func source_kind() -> NoteEvent.Source:
		return NoteEvent.Source.MIC

	func latency_ms() -> float:
		return lag_ms

	func play(midi_note: int) -> void:
		emit_note(midi_note)
