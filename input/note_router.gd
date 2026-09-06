class_name NoteRouter
extends Node

## The one input surface gameplay talks to.
##
## Sources are attached to it; it merges what they produce, drops duplicates of
## the same physical note heard by two sources at once, applies each source's
## latency compensation, and emits the result. Gameplay never learns which
## source a note came from — that is what lets a new platform be reached by
## adding a source rather than by touching scoring (`DESIGN.md` §4.1).
##
## **It must construct and run with zero sources attached.** The framework's own
## suite drives every registered game through a full headless round with no
## MIDI device and no microphone, so a router that assumed it had inputs would
## break `tests/game_shell_test.gd` (§4.1).

signal note_started(event: NoteEvent)
signal note_ended(midi_note: int)
signal input_level_changed(rms: float)

## A source was attached or removed; the input readout re-reads the list.
signal sources_changed

## How close two notes of the same pitch from *different* sources have to be
## before the second is treated as an echo of the first rather than a second
## note.
##
## Sized by the worst realistic disagreement between two sources watching one
## instrument: an uncalibrated microphone runs roughly 100 ms behind a MIDI
## pickup on the same guitar. Same-source repeats are never merged, so this
## cannot swallow a fast re-strike.
const DEDUPE_WINDOW_MS := 150.0

## Key used for notes whose pitch is unknown, so onset-only events from two
## sources still merge with each other but never with a pitched note.
const ONSET_KEY := -1

var _sources: Array[NoteSource] = []
var _accepting := true
var _merged_count := 0

## Dedupe key to the corrected microsecond timestamp and source kind of the
## last event accepted for it.
var _recent_starts: Dictionary[int, Array] = {}
var _recent_ends: Dictionary[int, Array] = {}


## Attaches a source and starts listening to it. The router takes ownership:
## the source becomes a child so it is freed with the router and stops
## listening when the round does.
func add_source(source: NoteSource) -> void:
	if source == null or _sources.has(source):
		return
	_sources.append(source)
	source.note_started.connect(_on_note_started.bind(source))
	source.note_ended.connect(_on_note_ended.bind(source))
	source.input_level_changed.connect(_on_input_level_changed)
	if source.get_parent() == null:
		add_child(source)
	sources_changed.emit()


func remove_source(source: NoteSource) -> void:
	if source == null or not _sources.has(source):
		return
	source.note_started.disconnect(_on_note_started)
	source.note_ended.disconnect(_on_note_ended)
	source.input_level_changed.disconnect(_on_input_level_changed)
	_sources.erase(source)
	if source.get_parent() == self:
		remove_child(source)
	sources_changed.emit()


func sources() -> Array[NoteSource]:
	return _sources.duplicate()


## Sources that actually have something to listen to. A source that failed to
## open stays attached so the reason can be shown, but it is not counted here.
func available_sources() -> Array[NoteSource]:
	return _sources.filter(func(s: NoteSource) -> bool: return s.is_available())


func has_any_input() -> bool:
	return not available_sources().is_empty()


## Finds an attached source by kind, or null. Used by screens that need to talk
## to one specific source — the soundcheck asking the microphone how loud the
## room is, for instance.
func find_source(kind: NoteEvent.Source) -> NoteSource:
	for source in _sources:
		if source.source_kind() == kind:
			return source
	return null


## While false, notes are dropped rather than forwarded. This is how the round
## ignores playing during the soundcheck, between rounds and on the results
## screen without every source having to know whether a round is running.
func set_accepting(accepting: bool) -> void:
	_accepting = accepting
	if not accepting:
		_recent_starts.clear()
		_recent_ends.clear()


func is_accepting() -> bool:
	return _accepting


## How many events have been dropped as duplicates. Diagnostic — a number that
## climbs during ordinary play means the dedupe window is too wide.
func merged_count() -> int:
	return _merged_count


## Human-readable summary of what is listening, for the soundcheck screen.
func describe_sources() -> String:
	if _sources.is_empty():
		return "No input sources."
	var parts: PackedStringArray = []
	for source in _sources:
		if source.is_available():
			parts.append(source.display_name())
		else:
			parts.append("%s — %s" % [source.display_name(), source.unavailable_reason()])
	return "\n".join(parts)


func _on_note_started(event: NoteEvent, source: NoteSource) -> void:
	if not _accepting:
		return

	event.timestamp_us -= int(source.latency_ms() * 1000.0)

	var key := ONSET_KEY if event.is_onset_only() else event.pitch_class
	if _is_echo(_recent_starts, key, event.timestamp_us, event.source):
		_merged_count += 1
		return

	_recent_starts[key] = [event.timestamp_us, event.source]
	note_started.emit(event)


func _on_note_ended(midi_note: int, source: NoteSource) -> void:
	if not _accepting:
		return

	var stamp := Time.get_ticks_usec() - int(source.latency_ms() * 1000.0)
	var key := ONSET_KEY if midi_note < 0 else ((midi_note % 12) + 12) % 12
	if _is_echo(_recent_ends, key, stamp, source.source_kind()):
		return

	_recent_ends[key] = [stamp, source.source_kind()]
	note_ended.emit(midi_note)


func _on_input_level_changed(rms: float) -> void:
	input_level_changed.emit(rms)


## True when this looks like the same physical note a *different* source
## already reported. Two notes from the same source are always two notes: a
## player re-striking a string is exactly what the game is trying to hear, and
## each source already has its own repeat guard.
func _is_echo(
	table: Dictionary[int, Array], key: int, stamp_us: int, kind: NoteEvent.Source
) -> bool:
	_prune(table, stamp_us)
	if not table.has(key):
		return false
	var previous: Array = table[key]
	var previous_kind: NoteEvent.Source = previous[1]
	if previous_kind == kind:
		return false
	return absi(stamp_us - int(previous[0])) <= int(DEDUPE_WINDOW_MS * 1000.0)


## Drops entries that can no longer match, so a long round does not accumulate
## one row per pitch class forever.
func _prune(table: Dictionary[int, Array], now_us: int) -> void:
	var window := int(DEDUPE_WINDOW_MS * 1000.0)
	for key: int in table.keys():
		var entry: Array = table[key]
		if absi(now_us - int(entry[0])) > window:
			table.erase(key)
