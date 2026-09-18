class_name DmjPhraseBot
extends JamBot

## Shared note-by-note progression; each chassis defines its phrase and reset rule.
const DEFAULT_NOTE_SECONDS := 0.8
const PHRASE_TAIL := 0.9

var notes: Array[int] = []
var plate_seconds := DEFAULT_NOTE_SECONDS
var _cursor := 0


static func normalize_phrase(sequence: Array, count: int, fallback_note := -1) -> Array[int]:
	var authored: Array[int] = []
	for value: Variant in sequence:
		authored.append(int(value))
	if authored.is_empty():
		authored.append(fallback_note)
	var result: Array[int] = []
	for index in range(count):
		result.append(authored[index % authored.size()])
	return result


static func phrase_windup(count: int, gap: float) -> float:
	return float(maxi(count - 1, 0)) * gap + PHRASE_TAIL


func configure_phrase(
	drone_lane: int, sequence: Array[int], approach_time: float,
	windup_time: float, gap := DEFAULT_NOTE_SECONDS
) -> void:
	assert(not sequence.is_empty(), "A phrase enemy needs at least one note.")
	notes = sequence.duplicate()
	plate_seconds = maxf(gap, 0.05)
	_cursor = 0
	configure(
		drone_lane, notes[0], approach_time,
		maxf(windup_time, phrase_windup(notes.size(), plate_seconds))
	)


func demand_size() -> int:
	return plates_left()


func plates_left() -> int:
	return maxi(notes.size() - _cursor, 0)


func plate_count() -> int:
	return notes.size()


func cursor() -> int:
	return _cursor


func strike() -> bool:
	if not is_targetable():
		return false
	_cursor += 1
	if _cursor >= notes.size():
		return kill()
	required_note = notes[_cursor]
	_delay_beat(plate_seconds)
	_sync_art()
	return true


func on_wrong_note() -> void:
	if _cursor <= 0 or not is_targetable():
		return
	_cursor = _reset_step()
	required_note = notes[_cursor]
	_rebase_beat(plate_seconds)
	_sync_art()


func _reset_step() -> int:
	return 0


func _art_notes() -> Array[int]:
	return notes.duplicate() if not notes.is_empty() else [required_note]


func _art_cursor() -> int:
	return _cursor
