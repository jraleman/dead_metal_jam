class_name DmjMenuSkin
extends RefCounted

const PLATE := preload("res://games/dead_metal_jam/assets/ui/plate.svg")
const HOVER := preload("res://games/dead_metal_jam/assets/ui/plate_hover.svg")
const PRESSED := preload("res://games/dead_metal_jam/assets/ui/plate_pressed.svg")
const TOGGLE_ON := preload("res://games/dead_metal_jam/assets/ui/toggle_on.svg")
const TOGGLE_OFF := preload("res://games/dead_metal_jam/assets/ui/toggle_off.svg")

static var _skin: Theme


static func create() -> Theme:
	if _skin != null:
		return _skin
	_skin = Theme.new()
	var heading := FontVariation.new()
	heading.base_font = ThemeDB.fallback_font
	heading.variation_embolden = 0.8
	heading.variation_transform = Transform2D(
		Vector2(0.82, 0.0), Vector2(0.0, 1.0), Vector2.ZERO
	)
	heading.spacing_glyph = 1
	_skin.set_type_variation("MenuHeading", "Label")
	_skin.set_font("font", "MenuHeading", heading)
	_skin.set_color("font_color", "MenuHeading", DmjPalette.TEXT)
	_skin.set_type_variation("MenuSectionHeading", "Label")
	_skin.set_color("font_color", "MenuSectionHeading", DmjPalette.AMBER)

	var normal := _plate(PLATE)
	var hover := _plate(HOVER)
	var pressed := _plate(PRESSED)
	var disabled := _plate(PLATE)
	disabled.modulate_color = Color(0.65, 0.65, 0.65, 0.65)
	var focus := _flat(Color.TRANSPARENT, DmjPalette.AMBER, 2)
	for type_name in ["Button", "OptionButton", "MenuButton", "PrimaryButton"]:
		if type_name == "PrimaryButton":
			_skin.set_type_variation(type_name, "Button")
		_skin.set_font("font", type_name, heading)
		_skin.set_stylebox("normal", type_name, normal)
		_skin.set_stylebox("hover", type_name, hover)
		_skin.set_stylebox("pressed", type_name, pressed)
		_skin.set_stylebox("hover_pressed", type_name, pressed)
		_skin.set_stylebox("disabled", type_name, disabled)
		_skin.set_stylebox("focus", type_name, focus)
		_skin.set_color("font_color", type_name, DmjPalette.TEXT)
		_skin.set_color("font_hover_color", type_name, DmjPalette.AMBER)
		_skin.set_color("font_focus_color", type_name, DmjPalette.AMBER)
		_skin.set_color("font_pressed_color", type_name, DmjPalette.TEXT)
		_skin.set_color("font_disabled_color", type_name, DmjPalette.MUTED.darkened(0.3))

	var panel := _plate(PLATE, Vector2(32, 28))
	for type_name in ["Panel", "PanelContainer", "PopupMenu", "TabContainer"]:
		_skin.set_stylebox("panel", type_name, panel)
	for type_name in ["Label", "LineEdit", "CheckButton", "CheckBox", "PopupMenu"]:
		_skin.set_color("font_color", type_name, DmjPalette.TEXT)
	_skin.set_color("default_color", "RichTextLabel", DmjPalette.TEXT)
	_skin.set_color("font_hover_color", "PopupMenu", DmjPalette.AMBER)
	_skin.set_stylebox("hover", "PopupMenu", _flat(DmjPalette.STEEL))

	var field := _flat(DmjPalette.INK, DmjPalette.LINE, 1, Vector2(16, 10))
	_skin.set_stylebox("normal", "LineEdit", field)
	_skin.set_stylebox(
		"focus", "LineEdit", _flat(Color.TRANSPARENT, DmjPalette.AMBER, 2, Vector2(16, 10))
	)
	_skin.set_color("caret_color", "LineEdit", DmjPalette.AMBER)
	_skin.set_color("selection_color", "LineEdit", Color(DmjPalette.AMBER, 0.25))

	for type_name in ["HSlider", "VSlider"]:
		_skin.set_stylebox(
			"slider", type_name, _flat(DmjPalette.LINE, Color.TRANSPARENT, 0, Vector2(0, 6))
		)
		_skin.set_stylebox(
			"grabber_area", type_name,
			_flat(DmjPalette.AMBER, Color.TRANSPARENT, 0, Vector2(0, 6))
		)
		_skin.set_stylebox(
			"grabber_area_highlight", type_name,
			_flat(DmjPalette.TEXT, Color.TRANSPARENT, 0, Vector2(0, 6))
		)

	for type_name in ["TabContainer", "TabBar"]:
		_skin.set_font("font", type_name, heading)
		_skin.set_color("font_selected_color", type_name, DmjPalette.AMBER)
		_skin.set_color("font_unselected_color", type_name, DmjPalette.MUTED)
		_skin.set_color("font_hovered_color", type_name, DmjPalette.TEXT)
		var selected := _flat(DmjPalette.STEEL, DmjPalette.AMBER, 0, Vector2(28, 14))
		selected.border_width_bottom = 3
		_skin.set_stylebox("tab_selected", type_name, selected)
		_skin.set_stylebox(
			"tab_unselected", type_name,
			_flat(DmjPalette.PANEL, Color.TRANSPARENT, 0, Vector2(28, 14))
		)
		_skin.set_stylebox(
			"tab_hovered", type_name,
			_flat(DmjPalette.STEEL, DmjPalette.LINE, 1, Vector2(28, 14))
		)
		_skin.set_stylebox(
			"tab_focus", type_name,
			_flat(Color.TRANSPARENT, DmjPalette.AMBER, 2, Vector2(28, 14))
		)

	for type_name in ["CheckButton", "CheckBox"]:
		var toggle_focus := _flat(
			Color.TRANSPARENT, DmjPalette.AMBER, 2, Vector2(10, 8)
		)
		var toggle_hover := _flat(
			Color(DmjPalette.AMBER, 0.08), DmjPalette.LINE, 1, Vector2(10, 8)
		)
		_skin.set_stylebox("focus", type_name, toggle_focus)
		_skin.set_stylebox("hover", type_name, toggle_hover)
		_skin.set_stylebox("hover_pressed", type_name, toggle_hover)
	for suffix in ["", "_disabled"]:
		_skin.set_icon("checked" + suffix, "CheckButton", TOGGLE_ON)
		_skin.set_icon("unchecked" + suffix, "CheckButton", TOGGLE_OFF)
	return _skin


static func _plate(texture: Texture2D, padding := Vector2(32, 16)) -> StyleBoxTexture:
	var box := StyleBoxTexture.new()
	box.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_texture_margin(side, 16.0)
		box.set_content_margin(side, padding.x if side in [SIDE_LEFT, SIDE_RIGHT] else padding.y)
	return box


static func _flat(
	fill: Color, border := Color.TRANSPARENT, width := 0, padding := Vector2(32, 16)
) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(2)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		box.set_content_margin(side, padding.x if side in [SIDE_LEFT, SIDE_RIGHT] else padding.y)
	return box
