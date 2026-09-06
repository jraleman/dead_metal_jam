extends Control

## Input check — what is listening, and what it hears.
##
## Every source the game can build is attached to a real [NoteRouter], so this
## screen exercises the same code a round does rather than a parallel copy of
## it. It answers the three questions that actually go wrong before a set:
##
## 1. Is my gear detected at all?
## 2. Does playing it produce the note I played?
## 3. Is anything arriving twice, or not at all?
##
## It is also how the MIDI device picker gets validated. `DESIGN.md` §4.2
## flagged that [member InputEvent.device] might not be populated on every
## platform, in which case filtering by device would silently discard every
## note. The observed-device line here is that check.
##
## Runnable on its own:
## [codeblock]
## godot --path godot-base res://games/dead_metal_jam/ui/input_check.tscn
## [/codeblock]

## How many recent notes to keep on screen.
const HISTORY := 12

## Long enough to read, short enough not to hide the next note.
const LEVEL_DECAY := 2.5

var _router: NoteRouter
var _mic: MicNoteSource
var _midi: MidiNoteSource
var _keys: KeyboardNoteSource
var _history: Array[String] = []
var _level := 0.0

@onready var _sources_label: Label = %Sources
@onready var _midi_label: Label = %MidiDetail
@onready var _last_note: Label = %LastNote
@onready var _detail: Label = %NoteDetail
@onready var _history_label: Label = %History
@onready var _level_bar: ProgressBar = %Level
@onready var _stats: Label = %Stats


func _ready() -> void:
	_router = NoteRouter.new()
	_router.name = "NoteRouter"
	_router.note_started.connect(_on_note_started)
	_router.note_ended.connect(_on_note_ended)
	_router.input_level_changed.connect(_on_level)
	add_child(_router)

	_mic = MicNoteSource.new()
	_mic.name = "MicNoteSource"
	_mic.capture_failed.connect(func(_r: String) -> void: _refresh_sources())
	_mic.calibrated.connect(func(_f: float) -> void: _refresh_sources())
	_router.add_source(_mic)

	_midi = MidiNoteSource.new()
	_midi.name = "MidiNoteSource"
	_midi.device_seen.connect(func(_d: int) -> void: _refresh_midi())
	_router.add_source(_midi)

	_keys = KeyboardNoteSource.new()
	_keys.name = "KeyboardNoteSource"
	_keys.octave_changed.connect(func(_b: int) -> void: _refresh_sources())
	_router.add_source(_keys)

	_refresh_sources()
	_refresh_midi()


func _process(delta: float) -> void:
	_level = maxf(_level - delta * LEVEL_DECAY, 0.0)
	_level_bar.value = _level * 100.0
	_stats.text = "Merged duplicates: %d   ·   Sources listening: %d of %d" % [
		_router.merged_count(),
		_router.available_sources().size(),
		_router.sources().size(),
	]


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.keycode == KEY_ESCAPE:
		get_tree().quit()
	elif key.keycode == KEY_F2:
		_mic.toggle_test_tone()
		_refresh_sources()
	elif key.keycode == KEY_F5:
		_midi.refresh_devices()
		_refresh_midi()


func _on_note_started(event: NoteEvent) -> void:
	# Printed as well as shown, so a run can be captured to a file and read
	# back. This is the evidence the design asked for about MIDI device ids.
	print(
		"NOTE %-4s src=%-10s vel=%.2f cents=%+.1f conf=%.2f" % [
			PitchDetector.note_label(event.midi_note),
			NoteEvent.source_name(event.source),
			event.velocity,
			event.cents_off,
			event.confidence,
		]
	)
	_last_note.text = PitchDetector.note_label(event.midi_note)
	_detail.text = "%s   ·   velocity %.2f   ·   %s" % [
		NoteEvent.source_name(event.source),
		event.velocity,
		(
			"%+.0f cents, confidence %.2f" % [event.cents_off, event.confidence]
			if event.source == NoteEvent.Source.MIC
			else "exact"
		),
	]
	_history.push_front(
		"%s  %-10s  vel %.2f" % [
			PitchDetector.note_label(event.midi_note).rpad(4),
			NoteEvent.source_name(event.source),
			event.velocity,
		]
	)
	while _history.size() > HISTORY:
		_history.pop_back()
	_history_label.text = "\n".join(_history)


func _on_note_ended(midi_note: int) -> void:
	if midi_note >= 0 and _last_note.text == PitchDetector.note_label(midi_note):
		_detail.text += "   ·   released"


func _on_level(rms: float) -> void:
	_level = maxf(_level, clampf(rms * 4.0, 0.0, 1.0))


func _refresh_sources() -> void:
	_sources_label.text = _router.describe_sources()
	if _keys != null:
		_sources_label.text += "\nKeyboard octave: %s (Z / X to shift)" % _keys.octave_label()


## The line that settles whether the MIDI device picker can work at all: if
## notes arrive but no device index is ever observed, the field is not
## populated on this platform and the picker must degrade to "all devices".
func _refresh_midi() -> void:
	var devices := _midi.devices()
	if devices.is_empty():
		_midi_label.text = "MIDI: no device found. Plug one in and press F5."
		return
	var lines: PackedStringArray = []
	for i in devices.size():
		lines.append("  [%d] %s" % [i, devices[i]])
	var observed := _midi.observed_devices()
	lines.append(
		"  device field observed: %s" % (
			"not yet — play a note" if observed.is_empty() else str(observed)
		)
	)
	_midi_label.text = "MIDI devices:\n" + "\n".join(lines)
	print("MIDI ", devices, " observed device ids: ", observed)
