@tool
class_name DmjPlatedKnuckleArt
extends DmjDroneArt


func visual_bounds() -> Rect2:
	if combat_pose:
		return Rect2(-109.0, -108.0, 218.0, 215.0)
	return Rect2(-97.0, -108.0, 194.0, 215.0)


func target_offset() -> Vector2:
	if notes.size() > 1 and active_index < 2:
		return Vector2(-48.0 if active_index == 0 else 48.0, -30.0)
	return Vector2(0.0, 20.0)


func muzzle_offset() -> Vector2:
	return Vector2(80.0, 14.0 - firing * 5.0 + _wave(2.5) * 1.0)


func _draw_character() -> void:
	for side in [-1.0, 1.0]:
		draw_set_transform_matrix(fragment_transform(
			Vector2(side * 29.0, 76.0), Vector2(side * 80.0, -80.0), -side * 2.8, 32.0
		))
		_draw_leg(side, 0.0 if side < 0.0 else PI)
	for side in [-1.0, 1.0]:
		draw_set_transform_matrix(fragment_transform(
			Vector2(side * 77.0, 21.0), Vector2(side * 125.0, -85.0), side * 4.2, 44.0
		))
		_draw_arm(side, 0.0 if side < 0.0 else PI)
	draw_set_transform_matrix(fragment_transform(
		Vector2(0.0, 15.0), Vector2(-12.0, -25.0), -2.5, 68.0
	))
	_panel(PackedVector2Array([
		Vector2(-47.0, -29.0), Vector2(46.0, -28.0),
		Vector2(50.0, 60.0), Vector2(-49.0, 59.0),
	]), METAL_DARK)
	_box(Rect2(-30.0, -45.0, 60.0, 17.0), INK)
	draw_set_transform_matrix(fragment_transform(
		Vector2(0.0, -62.0), Vector2(25.0, -190.0), 3.5, 46.0
	))
	_draw_head()

	var shoulders := notes.size() > 1
	draw_set_transform_matrix(fragment_transform(
		Vector2(-48.0, -30.0), Vector2(-135.0, -145.0), -4.5, 42.0
	))
	_draw_plate(Vector2(-48.0, -30.0), 40.0, 0 if shoulders else -1)
	draw_set_transform_matrix(fragment_transform(
		Vector2(48.0, -30.0), Vector2(135.0, -125.0), 5.2, 42.0
	))
	_draw_plate(Vector2(48.0, -30.0), 40.0, 1 if shoulders else -1)
	var chest_index := 2 if notes.size() >= 3 else (0 if not shoulders else -1)
	draw_set_transform_matrix(fragment_transform(
		Vector2(0.0, 20.0), Vector2(30.0, -90.0), 3.0, 44.0
	))
	_draw_plate(Vector2(0.0, 20.0), 43.0, chest_index)
	draw_set_transform(Vector2.ZERO)


func _draw_head() -> void:
	_panel(PackedVector2Array([
		Vector2(-10.0, -79.0), Vector2(0.0, -104.0), Vector2(12.0, -78.0),
	]), METAL_LIGHT)
	_panel(PackedVector2Array([
		Vector2(0.0, -104.0), Vector2(12.0, -78.0), Vector2(2.0, -79.0),
	]), RUST_DARK)
	_box(Rect2(-25.0, -82.0, 50.0, 40.0), METAL_LIGHT, 4.0)
	_eye(Rect2(-14.0, -67.0, 7.0, 9.0))
	_eye(Rect2(7.0, -67.0, 7.0, 9.0))
	draw_line(Vector2(-20.0, -72.0), Vector2(-5.0, -64.0), INK, 4.0, true)
	draw_line(Vector2(5.0, -64.0), Vector2(20.0, -72.0), INK, 4.0, true)
	draw_polyline(PackedVector2Array([
		Vector2(-13.0, -49.0), Vector2(0.0, -57.0), Vector2(13.0, -49.0),
	]), INK, 3.5, true)


func _draw_plate(center: Vector2, radius: float, index: int) -> void:
	var diamond := PackedVector2Array([
		center - Vector2(radius, 0.0), center - Vector2(0.0, radius),
		center + Vector2(radius, 0.0), center + Vector2(0.0, radius),
	])
	if index < 0 or index >= notes.size():
		_panel(diamond, METAL)
		for offset in [-8.0, 0.0, 8.0]:
			draw_line(
				center + Vector2(-12.0, offset), center + Vector2(12.0, offset - 7.0),
				METAL_DARK, 3.0, true
			)
		return
	var active := index == active_index
	var broken := index < active_index
	_plate_face(
		diamond, Rect2(center - Vector2(25.0, 30.0), Vector2(50.0, 60.0)),
		notes[index], active, broken
	)
	if not broken:
		_text(
			str(index + 1), Rect2(center - Vector2(5.0, 33.0), Vector2(10.0, 10.0)),
			9, NOTE_INK if active else METAL_LIGHT
		)


func _draw_arm(side: float, phase: float) -> void:
	var sway := _stride(2.0, phase)
	if combat_pose and not defeated:
		sway += _wave(2.5, phase) * 1.2
	var shoulder := Vector2(side * 64.0, -26.0)
	var elbow := Vector2(side * 77.0, 21.0)
	var wrist := Vector2(side * 80.0 + sway, 51.0)
	if combat_pose and side > 0.0:
		wrist = muzzle_offset()
	_limb(shoulder, elbow, 13.0, METAL_LIGHT, 5)
	_limb(elbow, wrist, 12.0, METAL, 4)
	_joint(elbow, 6.0, RUST_DARK)
	_box(Rect2(wrist - Vector2(10.0, 0.0), Vector2(20.0, 19.0)), METAL_LIGHT, 3.0)
	draw_line(wrist + Vector2(-6.0, 4.0), wrist + Vector2(6.0, 15.0), INK, 2.0, true)
	draw_line(wrist + Vector2(6.0, 4.0), wrist + Vector2(-6.0, 15.0), INK, 2.0, true)
	if combat_pose and side > 0.0:
		_emitter(wrist, 12.0)


func _draw_leg(side: float, phase: float) -> void:
	var lift := maxf(_stride(2.5, phase), 0.0)
	var hip := Vector2(side * 26.0, 53.0)
	var knee := Vector2(side * 27.0, 75.0 - lift)
	var ankle := Vector2(side * 29.0, 89.0 - lift)
	_limb(hip, knee, 12.0, METAL_LIGHT, 3)
	_limb(knee, ankle, 12.0, METAL, 2)
	_joint(knee, 4.0, RUST_DARK)
	var foot := Rect2(ankle - Vector2(19.0, 0.0), Vector2(38.0, 13.0))
	_box(foot, METAL_DARK, 3.0)
	draw_line(
		foot.position + Vector2(5.0, 3.0),
		Vector2(foot.end.x - 4.0, foot.position.y + 3.0), METAL_LIGHT, 2.0, true
	)
