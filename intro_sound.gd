class_name DmjIntroSound
extends RefCounted

## The opening's sounds, rendered as streams instead of shipped as files.
##
## Dead Metal Jam is a game about an instrument, so its intro has to sound like
## one — but the base project ships no music and this game must not push its
## own sounds into `AudioManager`, which already carries another game's SFX as
## a known coupling. Rendering here keeps the noise inside `games/<id>/` where
## it belongs, and costs a few milliseconds once at load.
##
## Nothing in this file touches an autoload, so a headless `--script` run may
## reference it directly.

## Low enough to keep the buffers small, high enough for a distorted chord:
## the top voice here is a few hundred hertz, nowhere near this Nyquist.
const RATE := 22050.0

## Standard tuning's low E — the note the opening's chord is built on, and one
## the player can answer on a guitar or a bass without thinking.
const ROOT_NOTE := 40

const CHORD_SECONDS := 1.9
const HUM_SECONDS := 1.5
const PING_SECONDS := 0.55


## The title sting: root, fifth and octave driven hard enough to distort.
##
## A power chord rather than a full triad on purpose — it is the sound the
## game is named after, and it stays readable through the soft clipping that a
## major third does not.
static func power_chord(root_note := ROOT_NOTE, seconds := CHORD_SECONDS) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var voices := [
		frequency(root_note),
		frequency(root_note + 7),
		frequency(root_note + 12),
	]
	var noise := 991123

	for i in count:
		var t := float(i) / RATE
		var value := 0.0
		for voice: float in voices:
			# Naive saw: rich enough to hear the distortion working on it.
			value += fposmod(t * voice, 1.0) * 2.0 - 1.0
		value /= float(voices.size())

		# The pick: a few milliseconds of noise so the chord starts with a
		# transient instead of swelling out of nothing.
		if t < 0.012:
			noise = (1103515245 * noise + 12345) % 2147483648
			var hit := (float(noise) / 2147483648.0) * 2.0 - 1.0
			value += hit * 0.6 * (1.0 - t / 0.012)

		samples[i] = _saturate(value * 4.2) * _pluck_envelope(t, seconds, 0.006, 1.5)

	return render_samples(samples, 0.86)


## The amp waking up: mains hum with a little hiss, fading in from nothing.
## It is the first thing the player hears, so it stays quiet and never resolves
## into a pitch the game would later ask for.
static func amp_hum(seconds := HUM_SECONDS) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var noise := 5150

	for i in count:
		var t := float(i) / RATE
		var progress := t / seconds
		noise = (1103515245 * noise + 12345) % 2147483648
		var hiss := (float(noise) / 2147483648.0) * 2.0 - 1.0
		var value := (
			sin(TAU * 60.0 * t)
			+ sin(TAU * 120.0 * t) * 0.42
			+ hiss * 0.06
		)
		# Swell in, then duck away under whatever plays next.
		var envelope := minf(progress * 3.0, 1.0) * (1.0 - pow(progress, 4.0))
		samples[i] = value * envelope

	return render_samples(samples, 0.34)


## One note landing on a drone: a clean pluck, so it reads as the player's
## answer rather than as more machinery.
static func note_ping(note: int, seconds := PING_SECONDS) -> AudioStreamWAV:
	var count := int(RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)

	var root := frequency(note)
	for i in count:
		var t := float(i) / RATE
		var value := (
			sin(TAU * root * t)
			+ sin(TAU * root * 2.0 * t) * 0.34
			+ sin(TAU * root * 3.0 * t) * 0.12
		)
		samples[i] = value * _pluck_envelope(t, seconds, 0.003, 6.5)

	return render_samples(samples, 0.7)


## Equal-tempered frequency of a MIDI note, A4 = 440 Hz.
static func frequency(note: int) -> float:
	return 440.0 * pow(2.0, (float(note) - 69.0) / 12.0)


## Shared PCM rendering for the intro and the game's short menu cues.
static func render_samples(samples: PackedFloat32Array, peak: float) -> AudioStreamWAV:
	return _stream(_normalized(samples, peak))


## Fast attack, exponential decay, and a short fade at the very end so the
## stream cannot click when it stops.
static func _pluck_envelope(t: float, seconds: float, attack: float, decay: float) -> float:
	var envelope := exp(-t * decay)
	if t < attack:
		envelope *= t / attack
	var remaining := seconds - t
	if remaining < 0.02:
		envelope *= maxf(remaining, 0.0) / 0.02
	return envelope


## Smooth saturation. Distortion by clipping alone would buzz; this rounds the
## corners, which is what makes it sound like an amp rather than an error.
static func _saturate(value: float) -> float:
	return value / (1.0 + absf(value))


static func _normalized(samples: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var loudest := 0.0
	for sample in samples:
		loudest = maxf(loudest, absf(sample))
	if loudest <= 0.0001:
		return samples
	var gain := peak / loudest
	for i in samples.size():
		samples[i] *= gain
	return samples


static func _stream(samples: PackedFloat32Array) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(RATE)
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
