extends SceneTree

## Run with the existing headless runner, with or without --game=dead_metal_jam.
## Settings are changed only in memory and restored before exit.

const GAME_ID := "dead_metal_jam"
const MAIN_MENU := "res://scenes/menus/main_menu.tscn"

var _failures := PackedStringArray()
var _settings: Node
var _audio: Node
var _saved_settings: Dictionary
var _saved_theme: Theme
var _original_pin := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_settings = root.get_node("Settings")
	_audio = root.get_node("AudioManager")
	_saved_settings = (_settings.get("_values") as Dictionary).duplicate(true)
	_saved_theme = root.theme
	_original_pin = GameCatalog.single_game_id()
	_set_setting("audio/muted", true)
	_set_setting("accessibility/reduced_motion", false)
	if not GameCatalog.restrict_to(GAME_ID):
		_failures.append("Dead Metal Jam must be available.")
		await _finish()
		return
	root.theme = GameCatalog.theme().restyle(ThemeDB.get_project_theme())
	_test_skin()
	_test_sound_resources()
	await _test_focus_and_motion()
	await _test_menu_surfaces()
	await _test_pause_audio()
	_test_sound_fallbacks_and_volume()
	await _test_collection_isolation()
	await _finish()


func _test_skin() -> void:
	var presentation := GameCatalog.theme()
	var skin := presentation.ui_theme
	_expect(skin != null, "Standalone Dead Metal Jam must declare a UI skin.")
	_expect(
		presentation.menu_motion == GameTheme.MenuMotion.FIRM,
		"The standalone menu must opt into firm, non-bouncy motion."
	)
	_expect(
		presentation.background_material != null and presentation.plaque_material != null,
		"The game must own its backdrop and plaque material."
	)
	if skin == null:
		return
	for type_name in ["Button", "OptionButton", "MenuButton", "PrimaryButton"]:
		for state in ["normal", "hover", "pressed", "disabled"]:
			var box := skin.get_stylebox(state, type_name) as StyleBoxTexture
			_expect(
				box != null and box.texture != null and box.texture.get_width() > 0,
				"%s/%s must use a loadable steel plate." % [type_name, state]
			)
	var heading := skin.get_font("font", "MenuHeading") as FontVariation
	_expect(
		heading != null and heading.base_font != null
		and heading.variation_embolden > 0.0 and heading.variation_transform.x.x < 1.0,
		"Headings must use a portable bold, condensed font."
	)
	_expect(
		not skin.has_font("font", "Label") and not skin.has_font("normal_font", "RichTextLabel"),
		"Body and instruction text must retain the normal readable font."
	)
	var focus := skin.get_stylebox("focus", "Button") as StyleBoxFlat
	_expect(
		focus != null and focus.border_width_left >= 2
		and focus.border_color == DmjPalette.AMBER,
		"Focus must retain an explicit amber outline without relying on animation."
	)
	var contrast := (
		(DmjPalette.TEXT.srgb_to_linear().get_luminance() + 0.05)
		/ (DmjPalette.STEEL.srgb_to_linear().get_luminance() + 0.05)
	)
	_expect(contrast >= 4.5, "Menu text must contrast clearly against steel.")
	_expect(
		root.theme.get_stylebox("normal", "Button").get_content_margin(SIDE_LEFT) == 32,
		"The skin must preserve shared button padding."
	)


func _test_sound_resources() -> void:
	var bank := GameCatalog.theme().ui_sounds
	_expect(bank != null, "Standalone Dead Metal Jam must declare menu sounds.")
	if bank == null:
		return
	var focus := bank.focus as AudioStreamRandomizer
	_expect(
		focus != null
		and focus.playback_mode == AudioStreamRandomizer.PLAYBACK_RANDOM_NO_REPEATS
		and focus.streams_count == 4,
		"Hover must use four matched variations without consecutive repeats."
	)
	var fingerprints := {}
	if focus != null:
		for index in focus.streams_count:
			var stream := focus.get_stream(index) as AudioStreamWAV
			_check_wave(stream, 0.04, 0.09, "hover %d" % index)
			if stream != null:
				fingerprints[hash(stream.data)] = true
		_expect(fingerprints.size() == 4, "The hover variations must actually differ.")
	_check_wave(bank.click as AudioStreamWAV, 0.12, 0.20, "confirm")
	_check_wave(bank.back as AudioStreamWAV, 0.08, 0.15, "back")
	_expect(
		bank.focus_volume_db < bank.click_volume_db and bank.focus_cooldown_ms == 60,
		"Hover must be quieter than confirmation and rate-limited."
	)
	_expect(DmjMenuSound.create() == bank, "The generated sound bank must be cached.")


func _check_wave(stream: AudioStreamWAV, minimum: float, maximum: float, label: String) -> void:
	_expect(stream != null, "%s must contain a rendered wave." % label)
	if stream == null:
		return
	_expect(
		stream.get_length() >= minimum and stream.get_length() <= maximum
		and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED,
		"%s must be a short one-shot, not a ringing or looping cue." % label
	)
	var bytes := stream.data
	var peak := 0.0
	for offset in range(0, bytes.size(), 2):
		peak = maxf(peak, absf(float(bytes.decode_s16(offset)) / 32768.0))
	_expect(peak > 0.2 and peak < 0.9, "%s must be audible without clipping." % label)
	_expect(
		bytes.decode_s16(0) == 0 and bytes.decode_s16(bytes.size() - 2) == 0,
		"%s must start and finish at zero to avoid discontinuities." % label
	)


func _test_focus_and_motion() -> void:
	var before := _voice_index()
	var menu := await _open(MAIN_MENU)
	_expect(_voice_index() == before, "Opening the menu must not play a focus sound.")
	var play := menu.get_node("%PlayButton") as Button
	var credits := menu.get_node("Margins/Layout/ButtonRow/Buttons/CreditsButton") as Button
	var settings_button := menu.get_node("Margins/Layout/ButtonRow/Buttons/SettingsButton") as Button
	var quit_button := menu.get_node("%QuitButton") as Button
	_expect(play.has_focus(), "Play must receive initial keyboard/controller focus.")
	_expect(
		(menu.get_node("%Title") as Label).get_theme_font("font") is FontVariation,
		"The actual title must inherit the heading font."
	)
	_audio.set("_last_focus_msec", -1)
	credits.mouse_entered.emit()
	_expect(
		credits.has_focus() and _voice_index() == _next_voice(before),
		"Mouse hover must move focus and play exactly one cue."
	)
	_expect(
		_last_voice().stream == GameCatalog.theme().ui_sounds.focus
		and _last_voice().bus == &"SFX",
		"Hover must use the game bank through the existing SFX bus."
	)
	before = _voice_index()
	credits.mouse_entered.emit()
	_expect(_voice_index() == before, "Hovering an already focused button must stay silent.")
	play.grab_focus()
	_expect(_voice_index() == before, "Rapid focus movement must obey the cooldown.")
	_audio.set("_last_focus_msec", -1)
	var down := InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = true
	root.push_input(down)
	down = InputEventAction.new()
	down.action = &"ui_down"
	down.pressed = false
	root.push_input(down)
	await process_frame
	_expect(
		settings_button.has_focus() and _voice_index() == _next_voice(before),
		"Keyboard/controller navigation must use the same single focus cue as the mouse."
	)
	before = _voice_index()
	quit_button.disabled = true
	quit_button.mouse_entered.emit()
	_expect(
		settings_button.has_focus() and _voice_index() == before,
		"Disabled buttons must not steal focus or make hover sounds."
	)
	quit_button.disabled = false
	_audio.set("_last_focus_msec", Time.get_ticks_msec() - 61)
	_audio.call("play_focus")
	_expect(_voice_index() == _next_voice(before), "Focus audio must resume after its cooldown.")

	var backdrop := menu.get_node("Background") as ColorRect
	var material := backdrop.material as ShaderMaterial
	var theme := GameCatalog.theme()
	_expect(
		material != theme.background_material
		and material.shader == theme.background_material.shader,
		"Each menu must have its own instance of the game backdrop material."
	)
	var body := menu.get_node("%Body") as MeshInstance3D
	var plaque := (body.mesh as PrimitiveMesh).material as StandardMaterial3D
	_expect(
		plaque != theme.plaque_material and plaque.albedo_texture != null
		and is_equal_approx(plaque.metallic, 0.82) and plaque.uv1_scale == Vector3(3, 2, 1),
		"The plaque must use a cloned metal material with its 3-by-2 face UVs corrected."
	)
	await create_timer(0.25).timeout
	_expect(settings_button.scale == Vector2.ONE, "Firm hover must not swell or bounce the button.")
	_set_setting("accessibility/reduced_motion", true)
	await process_frame
	var rig := menu.get_node("%LogoRig") as Node3D
	var rotation := rig.rotation
	await process_frame
	_expect(
		not menu.is_processing() and rig.rotation == rotation and rig.scale == Vector3.ONE
		and material.get_shader_parameter("speed") == 0.0,
		"Live reduced motion must stop the logo and background."
	)
	_expect(
		(menu.get_node("%FocusAccent") as ColorRect).modulate.a == 1.0
		and settings_button.scale == Vector2.ONE,
		"Reduced motion must keep focus visible without spatial animation."
	)
	_expect(
		is_equal_approx(float(theme.background_material.get_shader_parameter("speed")), 0.12),
		"Reduced motion must not modify the game's shared material resource."
	)
	_set_setting("accessibility/reduced_motion", false)
	_expect(
		menu.is_processing() and float(material.get_shader_parameter("speed")) > 0.0,
		"Turning reduced motion off must restore the authored motion."
	)
	menu.queue_free()
	await process_frame


func _test_menu_surfaces() -> void:
	for name in ["settings_menu", "instructions", "credits"]:
		var menu := await _open("res://scenes/menus/%s.tscn" % name)
		var heading := menu.get_node("Margins/Layout/Header/Title") as Label
		var back := menu.get_node("Margins/Layout/Header/BackButton") as Button
		_expect(
			heading.get_theme_font("font") is FontVariation
			and back.get_theme_stylebox("normal") is StyleBoxTexture,
			"%s must inherit the same heading and button skin." % name
		)
		if name == "settings_menu":
			var section := menu.get_node("Margins/Layout/Tabs/Audio/Pad/List/VolumeHeading") as Label
			_expect(
				section.get_theme_color("font_color") == DmjPalette.AMBER,
				"Non-player settings headings must use the game's amber UI role."
			)
		elif name == "instructions":
			var frame := menu.get_node("%VideoOverlay").get_node("Frame") as Panel
			var border := frame.get_theme_stylebox("panel") as StyleBoxTexture
			_expect(
				border != null and not border.draw_center,
				"The steel video frame must not cover the tutorial or its poster."
			)
		var before := _voice_index()
		back.pressed.emit()
		_expect(
			_voice_index() == _next_voice(before)
			and _last_voice().stream == GameCatalog.theme().ui_sounds.back,
			"%s Back must play only the back cue, not an extra confirm." % name
		)
		await process_frame


func _test_pause_audio() -> void:
	var menu := await _open("res://scenes/menus/pause_menu.tscn")
	var resume := menu.get_node("Center/Panel/Layout/ResumeButton") as Button
	var before := _voice_index()
	resume.pressed.emit()
	_expect(
		not paused and _voice_index() == _next_voice(before)
		and _last_voice().stream == GameCatalog.theme().ui_sounds.back,
		"Resume must unpause and play a single back cue."
	)
	await process_frame


func _test_sound_fallbacks_and_volume() -> void:
	var theme := GameCatalog.theme()
	var bank := theme.ui_sounds
	_audio.call("play_click")
	_expect(
		_last_voice().stream == bank.click
		and is_equal_approx(_last_voice().volume_db, bank.click_volume_db),
		"Confirm must use the game's cue and gain."
	)
	_audio.call("play_game_hit")
	_expect(
		_last_voice().stream.resource_path == "res://assets/audio/ui_click.wav",
		"Custom UI cues must not replace shared gameplay hit audio."
	)
	_audio.call("play_game_miss")
	_expect(
		_last_voice().stream.resource_path == "res://assets/audio/ui_back.wav",
		"Custom UI cues must not replace shared gameplay miss audio."
	)
	theme.ui_sounds = GameUISoundBank.new()
	for pair in [["play_focus", "ui_focus.wav"], ["play_click", "ui_click.wav"], ["play_back", "ui_back.wav"]]:
		_audio.call(pair[0])
		_expect(
			_last_voice().stream.resource_path == "res://assets/audio/" + pair[1],
			"An omitted %s override must retain the default cue." % pair[0]
		)
	theme.ui_sounds = bank
	_set_setting("audio/muted", false)
	_set_setting("audio/sfx", 0.0)
	_audio.call("play_click")
	_expect(
		_last_voice().bus == &"SFX" and AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")),
		"Setting SFX volume to zero must mute the custom bank."
	)
	_set_setting("audio/muted", true)
	_expect(
		AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")),
		"Master mute must continue to cover every custom cue."
	)


func _test_collection_isolation() -> void:
	if not _original_pin.is_empty():
		return
	GameCatalog.clear_restriction()
	GameCatalog.select(GAME_ID)
	var studio := GameCatalog.theme()
	_expect(
		studio.ui_theme == null and studio.ui_sounds == null
		and studio.background_material == null and studio.plaque_material == null,
		"Selecting Dead Metal inside the collection must not theme the whole collection."
	)
	var base := ThemeDB.get_project_theme()
	root.theme = studio.restyle(base)
	_expect(root.theme == base, "The collection must inherit the untouched project theme.")
	var menu := await _open(MAIN_MENU)
	var play := menu.get_node("%PlayButton") as Button
	var box := play.get_theme_stylebox("normal") as StyleBoxFlat
	_expect(
		box != null and box.corner_radius_top_left == 12 and not bool(menu.get("_firm_menu_motion")),
		"Collection buttons must keep their original shape and motion."
	)
	_audio.call("play_focus")
	_expect(
		_last_voice().stream.resource_path == "res://assets/audio/ui_focus.wav",
		"Returning to the collection must restore its original hover cue."
	)
	menu.queue_free()
	await process_frame


func _open(path: String) -> Control:
	var menu := (load(path) as PackedScene).instantiate() as Control
	root.add_child(menu)
	await process_frame
	await process_frame
	return menu


func _set_setting(key: String, value: Variant) -> void:
	var values := (_settings.get("_values") as Dictionary).duplicate()
	values[key] = value
	_settings.set("_values", values)
	_settings.emit_signal("changed", key, value)


func _voice_index() -> int:
	return int(_audio.get("_sfx_index"))


func _next_voice(index: int) -> int:
	return (index + 1) % (_audio.get("_sfx_pool") as Array).size()


func _last_voice() -> AudioStreamPlayer:
	var voices: Array = _audio.get("_sfx_pool")
	return voices[posmod(_voice_index() - 1, voices.size())] as AudioStreamPlayer


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	paused = false
	GameCatalog.clear_restriction()
	root.theme = _saved_theme
	_settings.set("_values", _saved_settings)
	_audio.call("_apply_all_volumes")
	for voice: AudioStreamPlayer in _audio.get("_sfx_pool"):
		voice.stop()
		voice.stream = null
	# Let the audio mixer release stopped playbacks before engine teardown.
	await create_timer(0.25).timeout
	if _failures.is_empty():
		print("Dead Metal menu presentation tests passed.")
		quit(0)
		return
	for failure in _failures:
		printerr(failure)
	quit(1)
