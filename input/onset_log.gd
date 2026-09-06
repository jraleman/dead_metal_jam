class_name OnsetLog
extends RefCounted

## Writes one CSV row per analysed hop so the onset rule can be retuned against
## a real instrument instead of a synthesised one.
##
## `DESIGN.md` §13 carries a standing risk: [constant PitchDetector.ONSET_RMS_RATIO]
## and [constant PitchDetector.ONSET_STABLE_HOPS] were chosen against synthetic
## attacks, which decay exponentially and cleanly. A real string does not — it
## has a body resonance, a pick transient, sympathetic ringing from the strings
## you did not play, and a decay that flattens out into the room rather than
## reaching zero. The thresholds might be fine. Nobody has looked.
##
## This is the looking. It records the two quantities the rule actually gates
## on, next to what the detector concluded, so a real decay envelope can be
## plotted and the constants set from it.
##
## Deliberately not on by default and deliberately not in the round scene: it
## opens a file and writes at ~43 rows per second, which is not something a
## game should do while someone is playing it. Run the tuner with `-- --log`,
## play, quit, and read the file.
##
## [codeblock]
## godot --path godot-base res://games/dead_metal_jam/ui/tuner.tscn -- --log
## [/codeblock]

## Rows buffered before the file is flushed. A crash or a hard quit costs at
## most this many hops, which at a ~21 ms hop is well under a second.
const FLUSH_EVERY := 64

const COLUMNS := (
	"sample_index,seconds,rms,trailing_rms,rms_ratio,stable_hops,"
	+ "voiced,midi_note,note,cents_off,confidence,is_onset"
)

var _file: FileAccess
var _path := ""
var _rate := 48000.0
var _rows := 0
var _since_flush := 0


## Opens the log. Returns false and leaves the log inert if the file cannot be
## written, because a tuner that refuses to start is a worse outcome than a
## tuner with no log.
func start(rate: float, path := "user://dmj_onset_log.csv") -> bool:
	_rate = maxf(rate, 1.0)
	_path = path
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		push_warning(
			"Onset log could not open %s (%d)" % [path, FileAccess.get_open_error()]
		)
		return false
	_file.store_line(COLUMNS)
	return true


func is_open() -> bool:
	return _file != null


func rows() -> int:
	return _rows


## Where the file landed, in terms the shell you launched from understands.
## `user://` is somewhere different on every platform and nobody remembers
## where, so the caller prints this rather than the resource path.
func absolute_path() -> String:
	return ProjectSettings.globalize_path(_path)


## One hop. Everything the onset rule was judged on already travels on
## [param analysis], so a whole batch can be logged accurately after the fact.
func record(analysis: PitchAnalysis) -> void:
	if _file == null:
		return

	# The ratio is the interesting column and it divides by a running average
	# that is exactly zero until the first sound arrives.
	var ratio := 0.0
	if analysis.trailing_rms > 0.0:
		ratio = analysis.rms / analysis.trailing_rms

	var seconds := 0.0
	if analysis.sample_index >= 0:
		seconds = analysis.sample_index / _rate

	_file.store_line(
		(
			"%d,%.6f,%.8f,%.8f,%.4f,%d,%d,%d,%s,%.2f,%.4f,%d"
			% [
				analysis.sample_index,
				seconds,
				analysis.rms,
				analysis.trailing_rms,
				ratio,
				analysis.stable_hops,
				1 if analysis.voiced else 0,
				analysis.midi_note,
				PitchDetector.note_label(analysis.midi_note) if analysis.voiced else "",
				analysis.cents_off,
				analysis.confidence,
				1 if analysis.is_onset else 0,
			]
		)
	)
	_rows += 1
	_since_flush += 1
	if _since_flush >= FLUSH_EVERY:
		_file.flush()
		_since_flush = 0


func close() -> void:
	if _file == null:
		return
	_file.flush()
	_file.close()
	_file = null
