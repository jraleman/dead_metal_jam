extends Control

## Standalone art workshop. Only drawing nodes live here, never combat actors.
const PROFILES := [
	["Rusty Clanky", "IN GAME", "Rattling scrap, a crooked grin, and one called note. One note, one hit."],
	["Plated Knuckle", "IN GAME", "Three note-colored plates, three hits in order. A wrong note resets all three."],
	[
		"Silencer Sentry", "ART PREVIEW",
		"A hovering rotor and a stitched-shut grille. Its silence mechanic is not enabled.",
	],
	["The Conductor", "ART PREVIEW", "A wheeled amplifier, top hat, and conducting baton. Boss phases are not enabled."],
]
const PHRASES := [[47], [48, 52, 55], [], [69, 72, 76, 74]]
const CLANKY_NOTES := [47, 48, 50, 52, 55]

@onready var _margins: MarginContainer = %Margins
@onready var _grid: GridContainer = %Roster
@onready var _pause_motion: CheckButton = %PauseMotion
@onready var _charge_pose: CheckButton = %ChargePose
@onready var _controls: BoxContainer = %Controls
@onready var _cards: Array[DmjDronePreviewCard] = [
	%RustyCard, %PlatedCard, %SentryCard, %ConductorCard,
]

var _artists: Array[DmjDroneArt] = []
var _time := 0.0
var _note_step := 0


func _ready() -> void:
	_artists = [
		DmjRustyClankyArt.new(), DmjPlatedKnuckleArt.new(),
		DmjSilencerSentryArt.new(), DmjConductorArt.new(),
	]
	for index in range(_artists.size()):
		var phrase: Array[int] = []
		phrase.assign(PHRASES[index])
		_artists[index].set_phrase(phrase)
		_cards[index].configure(
			PROFILES[index][0], PROFILES[index][1], PROFILES[index][2], _artists[index]
		)
	get_viewport().size_changed.connect(_refresh_layout)
	Settings.changed.connect(_on_setting_changed)
	AudioManager.attach_ui_sounds(self)
	_refresh_layout()
	_update_motion_control()
	_update_poses()


func _process(delta: float) -> void:
	if not _pause_motion.button_pressed and not Settings.reduced_motion_enabled():
		_time += delta
	_update_poses()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_close_pressed()


func _update_poses() -> void:
	var reduced := Settings.reduced_motion_enabled()
	for art in _artists:
		art.effects_enabled = Settings.visual_effects_enabled()
		art.set_pose(
			_time, not _charge_pose.button_pressed, 0.7 if _charge_pose.button_pressed else -1.0,
			_charge_pose.button_pressed, false, 0.0, reduced
		)


func _on_cycle_notes_pressed() -> void:
	_note_step += 1
	_artists[0].set_phrase([CLANKY_NOTES[_note_step % CLANKY_NOTES.size()]])
	for index in [1, 3]:
		var art := _artists[index]
		art.active_index = (art.active_index + 1) % art.notes.size()


func _on_setting_changed(key: String, _value: Variant) -> void:
	if key == Settings.REDUCED_MOTION_KEY:
		_update_motion_control()
		_update_poses()


func _update_motion_control() -> void:
	var reduced := Settings.reduced_motion_enabled()
	_pause_motion.disabled = reduced
	_pause_motion.text = "Reduced motion enabled" if reduced else "Pause motion"


func _refresh_layout() -> void:
	var viewport_size := get_viewport_rect().size
	Responsive.apply_margins(
		_margins, viewport_size, Vector2(0.035, 0.035),
		Vector2(20.0, 18.0), Vector2(60.0, 46.0)
	)
	var width := viewport_size.x - float(
		_margins.get_theme_constant("margin_left") + _margins.get_theme_constant("margin_right")
	)
	_grid.columns = 4 if width >= 1600.0 else (2 if width >= 760.0 else 1)
	_controls.vertical = width < 700.0


func _on_close_pressed() -> void:
	get_tree().quit()
