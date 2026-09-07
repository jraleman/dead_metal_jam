@tool
class_name DmjRustyClankyArt
extends DmjDroneArt


func visual_bounds() -> Rect2:
	if combat_pose:
		return Rect2(-84.0, -105.0, 168.0, 208.0)
	return Rect2(-70.0, -105.0, 140.0, 208.0)


func _draw_character() -> void:
	_draw_leg(-1.0, 0.0)
	_draw_leg(1.0, PI)
	_draw_arm(-1.0, 0.0)
	_draw_arm(1.0, PI)
	for x in [-11.0, 0.0, 12.0]:
		_limb(Vector2(x, -48.0), Vector2(x, -27.0), 5.0, METAL)

	_panel(PackedVector2Array([
		Vector2(-39.0, -30.0), Vector2(37.0, -32.0),
		Vector2(40.0, 45.0), Vector2(-36.0, 48.0),
	]), RUST)
	_panel(PackedVector2Array([
		Vector2(-39.0, -30.0), Vector2(-30.0, -23.0),
		Vector2(-28.0, 43.0), Vector2(-36.0, 48.0),
	]), RUST_DARK)
	draw_line(Vector2(-27.0, -26.0), Vector2(32.0, -28.0), RUST_LIGHT, 2.0, true)
	_box(Rect2(-28.0, 42.0, 58.0, 10.0), METAL_DARK)
	_note_plate(Rect2(-29.0, -22.0, 60.0, 64.0), current_note())
	for corner: Vector2 in [
		Vector2(-34.0, -23.0), Vector2(34.0, -24.0),
		Vector2(-32.0, 39.0), Vector2(35.0, 38.0),
	]:
		_rivet(corner, 1.7)
	_draw_head()


func _draw_head() -> void:
	var aim_tilt := _wave(2.4) * 0.015 if combat_pose and not defeated else 0.0
	draw_set_transform(Vector2(0.0, -66.0), _stride(0.018) + aim_tilt)
	_panel(PackedVector2Array([
		Vector2(-25.0, -20.0), Vector2(-25.0, -35.0),
		Vector2(-14.0, -32.0), Vector2(-15.0, -19.0),
	]), METAL_LIGHT)
	_panel(PackedVector2Array([
		Vector2(15.0, -21.0), Vector2(17.0, -34.0),
		Vector2(28.0, -32.0), Vector2(25.0, -19.0),
	]), METAL)
	_panel(PackedVector2Array([
		Vector2(-35.0, -20.0), Vector2(34.0, -22.0),
		Vector2(33.0, 20.0), Vector2(-32.0, 22.0),
	]), RUST_LIGHT)
	draw_line(Vector2(-30.0, -17.0), Vector2(29.0, -19.0), PAPER, 1.6, true)
	_box(Rect2(-35.0, -5.0, 7.0, 8.0), RUST_DARK, 1.0)
	_eye(Rect2(-18.0, -10.0, 9.0, 12.0))
	_eye(Rect2(10.0, -11.0, 9.0, 12.0))
	draw_polyline(PackedVector2Array([
		Vector2(-18.0, 13.0), Vector2(-10.0, 7.0),
		Vector2(-1.0, 14.0), Vector2(7.0, 8.0), Vector2(17.0, 13.0),
	]), INK, 3.0, true)
	draw_set_transform(Vector2.ZERO)


func _draw_arm(side: float, phase: float) -> void:
	var swing := _stride(3.5, phase)
	if combat_pose and not defeated:
		swing += _wave(3.0, phase) * 1.5
	var shoulder := Vector2(side * 39.0, -20.0)
	var elbow := Vector2(side * 49.0 + swing * 0.4, 8.0)
	var wrist := Vector2(side * 55.0 + swing, 40.0)
	if combat_pose and side > 0.0:
		wrist = muzzle_offset()
	_limb(shoulder, elbow, 7.0, RUST_DARK)
	_limb(elbow, wrist, 6.0, METAL, 2)
	_joint(shoulder, 5.0, METAL)
	_joint(elbow, 3.4, RUST_LIGHT)
	_box(Rect2(wrist - Vector2(7.0, 1.0), Vector2(14.0, 14.0)), RUST, 2.0)
	draw_line(wrist + Vector2(-4.0, 2.0), wrist + Vector2(4.0, 10.0), INK, 1.6, true)
	draw_line(wrist + Vector2(4.0, 2.0), wrist + Vector2(-4.0, 10.0), INK, 1.6, true)
	if combat_pose and side > 0.0:
		_emitter(wrist)


func _draw_leg(side: float, phase: float) -> void:
	var step := _stride(3.0, phase)
	var lift := maxf(_stride(4.0, phase), 0.0)
	var hip := Vector2(side * 17.0, 45.0)
	var knee := Vector2(side * 20.0 + step * 0.4, 66.0 - lift * 0.5)
	var ankle := Vector2(side * 23.0 + step, 84.0 - lift)
	_limb(hip, knee, 7.0, METAL_LIGHT)
	_limb(knee, ankle, 6.0, METAL)
	_joint(knee, 3.0, RUST)
	var foot := Rect2(ankle - Vector2(15.0, 0.0), Vector2(31.0, 11.0))
	_box(foot, RUST_DARK, 2.0)
	draw_line(foot.position + Vector2(4.0, 2.0), foot.end - Vector2(4.0, 2.0), METAL_LIGHT, 1.6, true)
	draw_line(
		Vector2(foot.end.x - 4.0, foot.position.y + 2.0),
		Vector2(foot.position.x + 4.0, foot.end.y - 2.0), METAL_LIGHT, 1.6, true
	)
