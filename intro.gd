extends Control

## Dead Metal Jam's opening: an amp wakes up, the title lands on a power chord,
## and three Rusty Clankies take firing positions and are shot with musical notes.
##
## The drones are the game's own [RustyClanky] actors, not a picture of them, so
## this scene cannot drift away from what the game actually looks like — and
## the opening teaches the verb before the menu ever appears.
##
## Only a build that ships this game alone plays it: `studio_logo.gd` asks
## [method GameCatalog.intro_scene_path], which returns
## [member GameManifest.intro_scene_path] when the catalog holds one game. The
## contract is the framework intro's — stay skippable, and eventually call
## `Router.goto(next_scene)`.

## Identity comes from the manifest so the title on screen cannot disagree with
## the title in the menu.
const MANIFEST := preload("res://games/dead_metal_jam/game.gd")

@export_file("*.tscn") var next_scene := "res://scenes/menus/main_menu.tscn"

## Narration, shown in order. Each line replaces the one before it.
@export var cards: Array[String] = [
	"The amp is still warm.",
	"Something in the scrapyard is awake.",
	"It only answers to the note it asks for.",
	"Kill the robots by playing the right note.",
]

## The notes the opening's drones demand: three open strings, three different
## letters, so the glyphs never repeat.
const DRONE_NOTES: Array[int] = [40, 45, 50]

const DRONE_APPROACH := 6.4
const DRONE_WINDUP := 1.6

## The drones are drawn at the size the game uses; the opening is a title card,
## so it shows them a little larger. The playfield is divided by the same
## factor, which keeps them landing exactly where the lanes say they should.
const DRONE_ZOOM := 1.35

const TOTAL_SECONDS := 9.0
const SHAKE_DECAY := 42.0


@onready var _stage: Control = %Stage
@onready var _drones: Node2D = %Drones
@onready var _flash: ColorRect = %Flash
@onready var _frame: MarginContainer = %Frame
@onready var _title: Label = %Title
@onready var _card: Label = %Card
@onready var _hint: Label = %Hint
@onready var _progress: ColorRect = %ProgressFill

var _actors: Array[JamBot] = []
var _shots: DmjShotFx3D
var _cues: Array[Dictionary] = []
var _chord: AudioStreamWAV
var _hum: AudioStreamWAV
var _pings: Array[AudioStreamWAV] = []

var _card_tween: Tween
var _title_tween: Tween
var _flash_tween: Tween
var _progress_tween: Tween
var _hint_tween: Tween
var _rng := RandomNumberGenerator.new()

var _elapsed := 0.0
var _shake := 0.0
var _next_cue := 0
var _finished := false
var _reduced_motion := false
var _intense_effects := true
var _arena: DmjArena3D


func _ready() -> void:
	AudioManager.stop_music(0.0)
	_reduced_motion = Settings.reduced_motion_enabled()
	_intense_effects = Settings.visual_effects_enabled()
	_rng.randomize()

	var manifest := GameCatalog.get_manifest(MANIFEST.GAME_ID)
	_title.text = (manifest.title if manifest else "Dead Metal Jam").to_upper()
	_hint.text = (
		"Tap to skip"
		if DisplayServer.is_touchscreen_available()
		else "Press any key to skip"
	)

	_title.modulate.a = 0.0
	_card.modulate.a = 0.0
	_flash.color.a = 0.0
	_progress.anchor_right = 0.0
	_drones.scale = Vector2(DRONE_ZOOM, DRONE_ZOOM)
	_drones.hide()

	# Rendering the sounds up front keeps the synthesis out of the cue that
	# needs them, where a few milliseconds would land as a stutter.
	_chord = DmjIntroSound.power_chord()
	_hum = DmjIntroSound.amp_hum()
	for note in DRONE_NOTES:
		_pings.append(DmjIntroSound.note_ping(note + 12))

	_arena = DmjArena3D.new()
	_arena.name = "Opening3D"
	_stage.add_child(_arena)
	_arena.set_presentation_options(_reduced_motion, _intense_effects)
	_arena.set_weapon_visible(false)
	_shots = _arena.shots
	get_viewport().size_changed.connect(_refresh_layout)
	_title.resized.connect(_center_pivot)
	_refresh_layout()
	_center_pivot()

	_build_cues()
	_pulse_hint()
	_start_progress()


func _process(delta: float) -> void:
	_elapsed += delta
	_run_due_cues()
	_advance_drones(delta)
	_advance_shake(delta)
	var field := _drone_field()
	_arena.set_field(Rect2(field.position * DRONE_ZOOM + _drones.position, field.size * DRONE_ZOOM))
	_arena.present(_actors, 0, 1.0, _elapsed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("skip") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_finish()


# --------------------------------------------------------------------------
# Timeline
# --------------------------------------------------------------------------


## The whole opening in one place, in seconds. Reading it top to bottom is
## meant to read like the shot list it is.
func _build_cues() -> void:
	_cues = [
		{"at": 0.15, "run": _cue_power_on},
		{"at": 1.20, "run": _cue_title},
		{"at": 2.10, "run": _cue_march},
		{"at": 3.90, "run": _cue_call},
		{"at": 4.70, "run": _cue_answer.bind(0)},
		{"at": 5.80, "run": _cue_answer.bind(1)},
		{"at": 7.20, "run": _cue_tagline},
		{"at": TOTAL_SECONDS, "run": _finish},
	]


func _run_due_cues() -> void:
	while _next_cue < _cues.size() and _elapsed >= float(_cues[_next_cue]["at"]):
		var run: Callable = _cues[_next_cue]["run"]
		_next_cue += 1
		run.call()


func _cue_power_on() -> void:
	AudioManager.play_sfx(_hum, -14.0)
	AudioManager.request_caption("Amp hum")
	_show_card(0)


## The title lands with the chord, which is the one moment the opening is
## allowed to be loud.
func _cue_title() -> void:
	AudioManager.play_sfx(_chord, -7.0)
	AudioManager.request_caption("Power chord")
	_add_shake(9.0)
	_flash_screen(0.22)
	if _title_tween and _title_tween.is_valid():
		_title_tween.kill()
	_title_tween = create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _reduced_motion:
		_title.scale = Vector2.ONE
		_title_tween.tween_property(_title, "modulate:a", 1.0, 0.45)
		return
	_title.scale = Vector2(1.16, 1.16)
	_title_tween.tween_property(_title, "scale", Vector2.ONE, 0.5)
	_title_tween.parallel().tween_property(_title, "modulate:a", 1.0, 0.22)


func _cue_march() -> void:
	_spawn_drones()
	_show_card(1)


func _cue_call() -> void:
	_show_card(2)


## One drone is answered: its note is played, and it goes down.
func _cue_answer(index: int) -> void:
	if index < 0 or index >= _actors.size():
		return
	var drone := _actors[index]
	if not is_instance_valid(drone) or not drone.kill():
		return

	if index < _pings.size():
		AudioManager.play_sfx(_pings[index], -8.0)
	AudioManager.request_caption(
		"%s lands — drone down" % PitchDetector.note_name(DRONE_NOTES[index])
	)
	_shots.player_shot(
		_arena.aim_point(drone), true, DRONE_NOTES[index], _arena.ground_point(drone)
	)
	_add_shake(5.0)
	_flash_screen(0.1)
	_target_next(index + 1)


## The last drone falls on the tagline, so the line and the verb land together.
func _cue_tagline() -> void:
	_cue_answer(2)
	_show_card(3)


# --------------------------------------------------------------------------
# Drones
# --------------------------------------------------------------------------


func _spawn_drones() -> void:
	for lane in DRONE_NOTES.size():
		var drone := RustyClanky.new()
		drone.set_reduced_motion(_reduced_motion)
		drone.set_effects_enabled(_intense_effects)
		drone.configure(lane, DRONE_NOTES[lane], DRONE_APPROACH, DRONE_WINDUP)
		_drones.add_child(drone)
		_actors.append(drone)
	_target_next(0)


## Marks who the next note is for, with the same outline the game uses.
func _target_next(index: int) -> void:
	for i in _actors.size():
		var drone := _actors[i]
		if is_instance_valid(drone):
			drone.set_targeted(i == index)


func _advance_drones(delta: float) -> void:
	var field := _drone_field()
	var floor_rect := JamBot.corridor_rect(field)
	for drone in _actors:
		if not is_instance_valid(drone):
			continue
		drone.visual_scale = DmjDroneArt.fit_scale(field.size.y)
		# The return value says the drone fired; nothing here lives long
		# enough to, and the opening must never show the player losing.
		drone.advance(delta, floor_rect, DRONE_NOTES.size())


## The lanes, in the drones' own space — the container is scaled, so the rect
## is divided by the same factor.
func _drone_field() -> Rect2:
	var size := get_viewport_rect().size
	var portrait := Responsive.is_portrait(size)
	var width := minf(size.x * (0.86 if portrait else 0.72), 1180.0)
	var top := size.y * (0.50 if portrait else 0.46)
	top = maxf(
		top, _card.get_global_rect().end.y + DmjRail.BACKDROP_PADDING * DRONE_ZOOM + 16.0
	)
	var bottom := size.y * 0.88
	var rect := Rect2(
		Vector2((size.x - width) * 0.5, top), Vector2(width, bottom - top)
	)
	return Rect2(rect.position / DRONE_ZOOM, rect.size / DRONE_ZOOM)


# --------------------------------------------------------------------------
# Stage, effects and layout
# --------------------------------------------------------------------------


func _add_shake(amount: float) -> void:
	if not _intense_effects or _reduced_motion:
		return
	_shake = maxf(_shake, amount)


## Only the drone container is displaced. The text is anchored, and moving an
## anchored control bakes the offset in.
func _advance_shake(delta: float) -> void:
	if _shake <= 0.05:
		_shake = 0.0
		_drones.position = Vector2.ZERO
		return
	_drones.position = Vector2(
		_rng.randf_range(-_shake, _shake), _rng.randf_range(-_shake, _shake)
	)
	_shake = move_toward(_shake, 0.0, delta * SHAKE_DECAY)


func _flash_screen(alpha: float) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	if not _intense_effects or _reduced_motion:
		_flash_tween = null
		_flash.color.a = 0.0
		return
	_flash.color.a = alpha
	_flash_tween = create_tween()
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.34).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)


func _show_card(index: int) -> void:
	if index < 0 or index >= cards.size():
		return
	if _card_tween and _card_tween.is_valid():
		_card_tween.kill()
	_card_tween = create_tween().set_trans(Tween.TRANS_SINE)
	_card_tween.tween_property(_card, "modulate:a", 0.0, 0.18)
	_card_tween.tween_callback(func() -> void: _card.text = cards[index])
	_card_tween.tween_property(_card, "modulate:a", 1.0, 0.32)


func _start_progress() -> void:
	_progress_tween = create_tween()
	_progress_tween.tween_property(_progress, "anchor_right", 1.0, TOTAL_SECONDS)


func _pulse_hint() -> void:
	if _reduced_motion:
		_hint.modulate.a = 1.0
		return
	_hint_tween = create_tween().set_loops()
	_hint_tween.tween_property(_hint, "modulate:a", 0.35, 1.1).set_trans(Tween.TRANS_SINE)
	_hint_tween.tween_property(_hint, "modulate:a", 1.0, 1.1).set_trans(Tween.TRANS_SINE)


func _refresh_layout() -> void:
	var size := get_viewport_rect().size
	Responsive.apply_margins(
		_frame, size, Vector2(0.08, 0.06), Vector2(28, 22), Vector2(280, 130)
	)
	var portrait := Responsive.is_portrait(size)
	_title.add_theme_font_size_override("font_size", 58 if portrait else 96)
	_card.add_theme_font_size_override("font_size", 26 if portrait else 34)


## The title is anchored, so it is animated with scale around its own centre.
func _center_pivot() -> void:
	_title.pivot_offset = _title.size * 0.5


func _on_skip_pressed() -> void:
	_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	set_process(false)
	for tween in [_card_tween, _title_tween, _flash_tween, _progress_tween, _hint_tween]:
		if tween and tween.is_valid():
			tween.kill()
	AudioManager.stop_music(0.0)
	Router.goto(next_scene)
