class_name MetronomeClick
extends RefCounted

## The calibration metronome (`DESIGN.md` §4.6), rendered ahead of time as one
## audio stream rather than played click by click.
##
## Two reasons it is pre-rendered. The player needs a *steady* beat to play
## against, and a click fired from `_process` inherits the frame rate's jitter.
## More importantly, the times have to be known exactly: with one stream, click
## `k` is audible at `start + k * beat` and the only unknown left in the
## measurement is the player.
##
## **The click is noise, not a tone, and that is the whole design.** Unless the
## player is wearing headphones the microphone hears the metronome, and a tonal
## click is a note — [PitchDetector] would lock onto it and the game would
## measure its own latency instead of the player's, confidently and wrongly.
## Broadband noise has no period to find, so it reads as unvoiced and fires no
## onset. `tests/latency_calibration_test.gd` holds that line.

## Short enough to be a tick rather than a hiss, long enough to hear over a
## room. Also keeps the burst well under the detector's window, so it can never
## fill one on its own.
const CLICK_SECONDS := 0.008

const ACCENT_LEVEL := 0.7
const BEAT_LEVEL := 0.45

## Loud beat every this many, so the player can hear where the bar starts and
## the count-in means something.
const ACCENT_EVERY := 4


## One bar's worth of clicks as raw mono samples, for tests and for the
## self-test path.
##
## Each sample is the difference of two noise values, which tilts the burst
## towards the top of the spectrum: it sounds like a tick rather than a thud,
## and it puts even less energy anywhere [PitchDetector] is looking.
static func click_samples(rate: float, accent := false) -> PackedFloat32Array:
	var count := int(rate * CLICK_SECONDS)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var level := ACCENT_LEVEL if accent else BEAT_LEVEL
	var state := 424242
	var previous := 0.0
	for i in count:
		state = (1103515245 * state + 12345) % 2147483648
		var value := (float(state) / 2147483648.0) * 2.0 - 1.0
		var envelope: float = pow(1.0 - float(i) / float(count), 2.0)
		samples[i] = (value - previous) * 0.5 * envelope * level
		previous = value

	return samples


## The whole metronome as one stream. Click `k` starts exactly
## `k * beat_seconds` into it, which is what makes the times trustworthy.
static func render(
	rate: float, beats: int, beat_seconds: float
) -> AudioStreamWAV:
	var total := int(rate * beat_seconds * float(beats))
	var samples := PackedFloat32Array()
	samples.resize(total)

	for beat in beats:
		var accent := beat % ACCENT_EVERY == 0
		var click := click_samples(rate, accent)
		var start := int(round(float(beat) * beat_seconds * rate))
		for i in click.size():
			var index := start + i
			if index >= total:
				break
			samples[index] = click[i]

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(rate)
	stream.stereo = false
	stream.data = _to_16_bit(samples)
	return stream


static func _to_16_bit(samples: PackedFloat32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var value := int(round(clampf(samples[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(i * 2, value)
	return bytes
