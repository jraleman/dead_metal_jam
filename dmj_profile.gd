class_name DmjProfile
extends RefCounted

## Where Dead Metal Jam keeps the few things it measures about the player's
## hardware, separate from the framework's own settings.
##
## Deliberately **not** a row in the base `Settings` autoload. Latency is not a
## preference — nobody chooses it, and nobody should be shown a slider for it.
## It is a property of one machine, measured once by the calibration screen
## (§4.6), and it would be wrong for it to travel with a settings profile or to
## sit in a menu of things the player is invited to change. Keeping it here
## also means the base gains nothing to carry for one game.

const PATH := "user://dead_metal_jam.cfg"

const SECTION := "audio"
const LATENCY_KEY := "input_latency_ms"

## Returned when nothing has been measured yet. Zero rather than a guess: an
## uncalibrated game should judge notes exactly as they arrive and say the
## calibration is missing, not silently apply someone else's hardware.
const UNMEASURED := 0.0


static func input_latency_ms() -> float:
	return float(_load().get_value(SECTION, LATENCY_KEY, UNMEASURED))


static func has_latency() -> bool:
	return _load().has_section_key(SECTION, LATENCY_KEY)


static func set_input_latency_ms(value: float) -> void:
	var config := _load()
	config.set_value(SECTION, LATENCY_KEY, value)
	var error := config.save(PATH)
	if error != OK:
		push_warning("DmjProfile: could not save %s (error %d)." % [PATH, error])


static func clear_latency() -> void:
	var config := _load()
	if not config.has_section_key(SECTION, LATENCY_KEY):
		return
	config.erase_section_key(SECTION, LATENCY_KEY)
	config.save(PATH)


## A missing or corrupt file is not an error worth reporting: it means the game
## has never been calibrated, which is the normal state on a first run.
static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(PATH)
	return config
