class_name DmjMenuSound
extends RefCounted

enum Cue { FOCUS, CONFIRM, BACK }

static var _bank: GameUISoundBank


static func create() -> GameUISoundBank:
	if _bank != null:
		return _bank
	_bank = GameUISoundBank.new()
	var variations := AudioStreamRandomizer.new()
	variations.playback_mode = AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
	variations.random_pitch = 1.025
	variations.random_volume_offset_db = 0.6
	for index in 4:
		variations.add_stream(-1, _render(Cue.FOCUS, index))
	_bank.focus = variations
	_bank.click = _render(Cue.CONFIRM)
	_bank.back = _render(Cue.BACK)
	_bank.focus_volume_db = -10.0
	_bank.click_volume_db = -5.0
	_bank.back_volume_db = -8.0
	_bank.focus_cooldown_ms = 60
	return _bank


## Damped, inharmonic transients keep navigation distinct from the pitched
## notes the microphone is meant to hear. Only confirm gets a brief low chug.
static func _render(cue: Cue, variation := 0) -> AudioStreamWAV:
	var seconds := 0.054 + variation * 0.006
	var body_hz := 580.0 + variation * 37.0
	var ring_hz := 1620.0 + variation * 89.0
	var decay := 82.0
	var peak := 0.38
	if cue == Cue.CONFIRM:
		seconds = 0.17
		body_hz = 140.0
		ring_hz = 690.0
		decay = 35.0
		peak = 0.65
	elif cue == Cue.BACK:
		seconds = 0.105
		body_hz = 210.0
		ring_hz = 930.0
		decay = 58.0
		peak = 0.44

	var random := RandomNumberGenerator.new()
	random.seed = 8191 + int(cue) * 997 + variation * 131
	var count := int(DmjIntroSound.RATE * seconds)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var filtered_noise := 0.0
	var guitar_hz := DmjIntroSound.frequency(40)
	for index in count:
		var time := float(index) / DmjIntroSound.RATE
		filtered_noise = lerpf(filtered_noise, random.randf_range(-1.0, 1.0), 0.58)
		var phase := body_hz * time
		if cue == Cue.BACK:
			phase -= 250.0 * time * time
		var value := (
			sin(TAU * phase) * 0.46
			+ sin(TAU * ring_hz * time) * exp(-time * 65.0) * 0.18
			+ filtered_noise * exp(-time * 100.0) * 0.64
		)
		if cue == Cue.CONFIRM:
			var chug := (
				sin(TAU * guitar_hz * time)
				+ sin(TAU * guitar_hz * 1.5 * time) * 0.5
				+ sin(TAU * guitar_hz * 2.0 * time) * 0.3
			) * 2.2
			value += chug / (1.0 + absf(chug)) * exp(-time * 22.0) * 0.4
		var envelope := minf(time / 0.0015, 1.0) * exp(-time * decay)
		envelope *= clampf((seconds - time) / 0.006, 0.0, 1.0)
		samples[index] = value * envelope
	samples[count - 1] = 0.0
	return DmjIntroSound.render_samples(samples, peak)
