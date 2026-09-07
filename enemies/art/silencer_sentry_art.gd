@tool
class_name DmjSilencerSentryArt
extends DmjDroneArt


func visual_bounds() -> Rect2:
	return Rect2(-93.0, -78.0, 186.0, 156.0)


func _draw_character() -> void:
	var bob := _wave(2.2) * 3.0 if not defeated else 0.0
	draw_set_transform(Vector2(0.0, bob))

	_limb(Vector2(0.0, -38.0), Vector2(0.0, -62.0), 8.0, METAL, 2)
	_box(Rect2(-11.0, -62.0, 22.0, 8.0), METAL_DARK, 2.0)
	_panel(PackedVector2Array([
		Vector2(-8.0, 17.0), Vector2(8.0, 18.0),
		Vector2(7.0, 40.0), Vector2(-9.0, 42.0),
	]), METAL)
	draw_line(Vector2(-7.0, 28.0), Vector2(7.0, 28.0), RUST_DARK, 3.0, true)
	_box(Rect2(-13.0, 35.0, 25.0, 8.0), METAL_DARK, 2.0)

	for end_cap: Vector2 in [Vector2(-46.0, 51.0), Vector2(46.0, 48.0)]:
		_joint(end_cap, 11.0, METAL_LIGHT)
		draw_circle(end_cap, 7.0, METAL_DARK)
		draw_circle(end_cap + Vector2(-1.0, -1.0), 3.5, RUST_LIGHT)
		draw_arc(end_cap, 8.5, PI * 0.9, PI * 1.8, 12, METAL, 1.5, true)
	_panel(PackedVector2Array([
		Vector2(-39.0, 40.0), Vector2(34.0, 37.0), Vector2(41.0, 42.0),
		Vector2(39.0, 59.0), Vector2(-39.0, 62.0), Vector2(-44.0, 55.0),
	]), RUST_DARK)
	_panel(PackedVector2Array([
		Vector2(-34.0, 43.0), Vector2(33.0, 41.0),
		Vector2(33.0, 55.0), Vector2(-35.0, 58.0),
	]), METAL)
	draw_line(Vector2(-28.0, 45.0), Vector2(27.0, 43.0), METAL_LIGHT, 1.4, true)
	for vent: int in range(3):
		var x := -8.0 + float(vent) * 8.0
		draw_line(Vector2(x, 49.0), Vector2(x - 1.0, 54.0), INK, 2.0, true)
	_rivet(Vector2(-28.0, 52.0), 1.5)
	_rivet(Vector2(26.0, 49.0), 1.5)

	_panel(PackedVector2Array([
		Vector2(-53.0, -38.0), Vector2(-73.0, -20.0),
		Vector2(-77.0, 15.0), Vector2(-57.0, 22.0),
	]), RUST_DARK)
	draw_line(Vector2(-68.0, -17.0), Vector2(-72.0, 9.0), RUST_LIGHT, 1.5, true)
	_panel(PackedVector2Array([
		Vector2(-53.0, -38.0), Vector2(57.0, -35.0), Vector2(64.0, -28.0),
		Vector2(59.0, 18.0), Vector2(-57.0, 22.0), Vector2(-64.0, 13.0),
		Vector2(-61.0, -30.0),
	]), METAL)
	_panel(PackedVector2Array([
		Vector2(-52.0, -35.0), Vector2(55.0, -32.0), Vector2(60.0, -27.0),
		Vector2(59.0, -13.0), Vector2(-57.0, -12.0), Vector2(-58.0, -28.0),
	]), METAL_LIGHT, INK, 1.8)
	draw_line(Vector2(-47.0, -33.0), Vector2(48.0, -30.0), PAPER, 1.1, true)
	for eye_position: Vector2 in [Vector2(-18.0, -24.0), Vector2(21.0, -23.0)]:
		if defeated:
			draw_line(eye_position - Vector2(4.0, 4.0), eye_position + Vector2(4.0, 4.0), INK, 2.2, true)
			draw_line(eye_position - Vector2(4.0, -4.0), eye_position + Vector2(4.0, -4.0), INK, 2.2, true)
		else:
			draw_circle(eye_position, 4.8, INK)
			draw_circle(eye_position - Vector2(1.3, 1.5), 1.1, METAL)
	_rivet(Vector2(-48.0, -25.0), 1.6)
	_rivet(Vector2(52.0, -24.0), 1.6)

	_panel(PackedVector2Array([
		Vector2(-53.0, -5.0), Vector2(55.0, -7.0),
		Vector2(52.0, 13.0), Vector2(-54.0, 17.0),
	]), METAL_LIGHT.darkened(0.1), INK, 1.6)
	draw_line(Vector2(-43.0, 5.0), Vector2(43.0, 3.0), INK, 2.7, true)
	for stitch: int in range(8):
		var center := Vector2(-35.0 + float(stitch) * 10.0, 4.8 - float(stitch) * 0.23)
		draw_line(center + Vector2(-2.6, 4.0), center + Vector2(2.6, -4.0), INK, 2.5, true)
	draw_line(Vector2(43.0, 3.0), Vector2(48.0, 9.0), RUST_DARK, 2.4, true)
	_joint(Vector2(49.0, 10.0), 2.0, RUST_LIGHT)
	_rivet(Vector2(-56.0, 13.0), 1.4)

	if not defeated:
		draw_line(Vector2(-24.0, 67.0), Vector2(-30.0, 72.0), METAL, 1.4, true)
		draw_line(Vector2(23.0, 66.0), Vector2(29.0, 71.0), METAL, 1.4, true)

	var rotor_tilt := _wave(8.0) * 0.024 if not defeated else 0.0
	draw_set_transform(Vector2(0.0, -64.0 + bob), rotor_tilt)
	_panel(PackedVector2Array([
		Vector2(-88.0, -1.0), Vector2(-19.0, -7.0), Vector2(87.0, -4.0),
		Vector2(89.0, -0.5), Vector2(20.0, 5.0), Vector2(-84.0, 4.0),
	]), METAL_DARK)
	draw_line(Vector2(-78.0, 0.0), Vector2(-21.0, -4.0), METAL_LIGHT, 1.3, true)
	_panel(PackedVector2Array([
		Vector2(64.0, -4.0), Vector2(83.0, -3.4),
		Vector2(84.0, -0.4), Vector2(64.0, 1.0),
	]), RUST_LIGHT, INK, 1.3)
	_joint(Vector2(1.0, -1.0), 4.0, RUST)
	draw_set_transform(Vector2.ZERO)
