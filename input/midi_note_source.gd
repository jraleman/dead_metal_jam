class_name MidiNoteSource
extends NoteSource

## Notes from a MIDI instrument — the primary input when the player has one.
##
## Godot exposes MIDI natively, so there is no addon and no shim on desktop or
## on Android and iOS, where a USB-OTG or Bluetooth controller shows up as an
## ordinary device. Web is the exception and needs a `JavaScriptBridge` shim
## behind this same interface (`DESIGN.md` §4.2, §4.7).
##
## This path is exact: the instrument states the note rather than the game
## guessing it, so [member NoteEvent.confidence] is always 1.0 and
## [member NoteEvent.cents_off] is always 0.0. Velocity is real data here and
## feeds hit reactions, but it is never a gate — a quietly played correct note
## is still a correct note.

signal device_seen(device: int)

## Controller number for the sustain pedal. Ignored **on purpose**: without
## this being explicit, a held pedal would make every note look sustained to
## anything that watches note-off.
const SUSTAIN_PEDAL_CONTROLLER := 64

## Accept notes from every device.
const ANY_DEVICE := -1

## Ports are opened process-wide by [method OS.open_midi_inputs] and there is no
## per-device open, so a second source opening them would make the first one's
## close pull the ports out from under it.
static var _ports_open := false

var _device_filter := ANY_DEVICE
var _devices: PackedStringArray = []
var _observed_devices: Array[int] = []
var _opened_here := false


func _ready() -> void:
	_open_ports()


func _exit_tree() -> void:
	# Leaving ports open across scene changes has caused stuck handles on some
	# ALSA setups, so this is not merely tidy.
	if _opened_here:
		OS.close_midi_inputs()
		_ports_open = false
		_opened_here = false


func source_kind() -> NoteEvent.Source:
	return NoteEvent.Source.MIDI


func display_name() -> String:
	if _devices.is_empty():
		return "MIDI (no device)"
	if _device_filter == ANY_DEVICE:
		return "MIDI: %s" % ", ".join(_devices)
	if _device_filter < _devices.size():
		return "MIDI: %s" % _devices[_device_filter]
	return "MIDI: device %d" % _device_filter


func is_available() -> bool:
	return not _devices.is_empty()


func unavailable_reason() -> String:
	if is_available():
		return ""
	return "No MIDI device is connected."


## Names of every connected device, in the order their index refers to.
func devices() -> PackedStringArray:
	return _devices


## Re-reads the device list. MIDI devices are enumerated once at open, so a
## controller plugged in later is invisible until this runs.
func refresh_devices() -> PackedStringArray:
	if not _ports_open:
		_open_ports()
	else:
		_devices = OS.get_connected_midi_inputs()
	return _devices


## Restrict to one device index, or [constant ANY_DEVICE] for all of them.
##
## The design flagged a real risk here: `InputEvent.device` might not be
## populated on every platform, in which case filtering would silently discard
## every note. [method observed_devices] is how that gets checked against real
## hardware before anyone relies on it.
func set_device_filter(index: int) -> void:
	_device_filter = index


func device_filter() -> int:
	return _device_filter


## Every distinct `device` value actually seen on an incoming event. Empty
## after real playing means the field is not populated on this platform and the
## picker must degrade to "all devices".
func observed_devices() -> Array[int]:
	return _observed_devices


func _input(event: InputEvent) -> void:
	var midi := event as InputEventMIDI
	if midi == null:
		return

	if not _observed_devices.has(midi.device):
		_observed_devices.append(midi.device)
		device_seen.emit(midi.device)

	if _device_filter != ANY_DEVICE and midi.device != _device_filter:
		return

	match midi.message:
		MIDI_MESSAGE_NOTE_ON:
			# Velocity 0 is a Note Off in disguise. Many controllers never send
			# a real Note Off at all, so missing this means notes never end.
			if midi.velocity == 0:
				note_ended.emit(midi.pitch)
			else:
				emit_note(midi.pitch, midi.velocity / 127.0)
		MIDI_MESSAGE_NOTE_OFF:
			note_ended.emit(midi.pitch)
		MIDI_MESSAGE_CONTROL_CHANGE:
			# Explicitly nothing, including for the sustain pedal.
			pass


func _open_ports() -> void:
	if not _ports_open:
		OS.open_midi_inputs()
		_ports_open = true
		_opened_here = true
	_devices = OS.get_connected_midi_inputs()
