extends Control

## Share cards render the same mesh arena and enemies as the playable scene.
const ARENA := 1

var _arena: DmjArena3D
var _actors: Array[JamBot] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var rules := Node2D.new()
	rules.hide()
	add_child(rules)
	var clanky := RustyClanky.new()
	clanky.configure(1, 40, 4.0, 2.0)
	clanky.set_targeted(true)
	var knuckle := PlatedKnuckle.new()
	knuckle.configure_sequence(0, [45, 48, 52], 4.0, 3.0)
	var sentry := SilencerSentry.new()
	sentry.configure_echo(2, 43, 4.0, 2.0)
	_actors.assign([knuckle, clanky, sentry])
	for actor in _actors:
		actor.arena_index = ARENA
		actor.show_attack_bar = false
		actor.set_reduced_motion(true)
		rules.add_child(actor)
		actor.set_process(false)
	_arena = DmjArena3D.new()
	add_child(_arena)
	_arena.set_process(false)
	_arena.set_presentation_options(true, false)
	_arena.set_weapon_visible(false)
	_refresh_corridor()


func configure(_data: Dictionary) -> void:
	_refresh_corridor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_corridor()


func _refresh_corridor() -> void:
	if _arena == null or size.x <= 0.0 or size.y <= 0.0:
		return
	_arena.set_field(Rect2(Vector2.ZERO, size))
	_arena.present(_actors, ARENA, 1.0, 0.0)
