@tool
class_name DmjConductorArt
extends DmjDroneArt

const HAT := Color("302c36")
const CABINET := Color("51424a")


func visual_bounds() -> Rect2:
	return Rect2(-100.0, -109.0, 210.0, 218.0)


func _draw_character() -> void:
	var beat := _wave(2.1) if not defeated else 0.0
	var free_beat := _wave(2.1, 0.7) if not defeated else 0.0
	var left_elbow := Vector2(-72.0, -15.0 + free_beat * 1.8)
	var left_hand := Vector2(-87.0, 25.0 + free_beat * 2.0)
	var right_elbow := Vector2(65.0, -17.0 + beat * 2.0)
	var right_hand := Vector2(76.0, 20.0 + beat * 3.5)

	_limb(Vector2(-25.0, 71.0), Vector2(-30.0, 91.0), 9.0, RUST_DARK, 1)
	_limb(Vector2(29.0, 71.0), Vector2(32.0, 93.0), 9.0, RUST_DARK, 1)
	_limb(Vector2(-30.0, 90.0), Vector2(32.0, 90.0), 5.0, METAL_DARK)
	_draw_wheel(Vector2(-30.0, 91.0), 15.0, -0.19)
	_draw_wheel(Vector2(32.0, 93.0), 13.0, 0.14)

	_limb(Vector2(-40.0, 1.0), left_elbow, 8.0, METAL, 3)
	_limb(left_elbow, left_hand, 9.0, METAL_LIGHT, 5)
	_joint(Vector2(-41.0, 1.0), 6.0, RUST)
	_joint(left_elbow, 4.5, RUST_LIGHT)
	_joint(left_hand, 6.5, METAL_LIGHT)
	draw_line(left_hand + Vector2(-4.0, 1.0), left_hand + Vector2(4.0, -1.0), INK, 1.7, true)
	_limb(Vector2(41.0, 2.0), right_elbow, 7.0, RUST_LIGHT, 3)
	_limb(right_elbow, right_hand, 8.0, METAL_LIGHT, 5)
	_joint(Vector2(41.0, 2.0), 6.0, RUST)
	_joint(right_elbow, 4.5, METAL)

	var baton_vector := Vector2(26.0, -35.0).rotated(beat * 0.12)
	var baton_tip := right_hand + baton_vector
	_limb(right_hand, baton_tip, 2.0, PAPER)
	_limb(right_hand, right_hand + baton_vector.normalized() * 11.0, 4.5, RUST, 1)
	draw_circle(baton_tip, 2.1, INK)
	draw_circle(baton_tip, 1.0, PAPER)
	_joint(right_hand, 6.0, METAL_LIGHT)
	draw_line(right_hand + Vector2(-3.0, -2.0), right_hand + Vector2(3.0, 1.0), INK, 2.0, true)

	_limb(Vector2(-1.0, -35.0), Vector2(1.0, -19.0), 10.0, METAL, 2)
	_panel(PackedVector2Array([
		Vector2(-37.0, -22.0), Vector2(-48.0, -7.0),
		Vector2(-47.0, 70.0), Vector2(-35.0, 80.0),
	]), CABINET)
	for vent: int in range(6):
		var y := -1.0 + float(vent) * 12.0
		draw_line(Vector2(-45.0, y + 6.0), Vector2(-38.0, y), METAL_LIGHT, 1.6, true)
	_panel(PackedVector2Array([
		Vector2(-37.0, -22.0), Vector2(35.0, -24.0), Vector2(43.0, -16.0),
		Vector2(42.0, 74.0), Vector2(34.0, 80.0), Vector2(-35.0, 80.0),
		Vector2(-39.0, 69.0),
	]), METAL_DARK)
	_panel(PackedVector2Array([
		Vector2(-34.0, -17.0), Vector2(33.0, -19.0), Vector2(38.0, -13.0),
		Vector2(37.0, 9.0), Vector2(-35.0, 10.0),
	]), METAL)
	draw_line(Vector2(-30.0, -20.0), Vector2(30.0, -22.0), RUST_LIGHT, 2.0, true)
	_eye(Rect2(-24.0, -5.0, 8.0, 9.0))
	_eye(Rect2(14.0, -5.0, 8.0, 9.0))
	draw_line(Vector2(-29.0, -13.0), Vector2(-11.0, -2.0), INK, 4.0, true)
	draw_line(Vector2(28.0, -13.0), Vector2(10.0, -2.0), INK, 4.0, true)

	_box(Rect2(-32.0, 10.0, 70.0, 61.0), CABINET, 4.0)
	_note_plate(Rect2(-27.0, 12.0, 61.0, 55.0), current_note(), true, defeated)
	_box(Rect2(-28.0, 71.0, 59.0, 7.0), RUST_DARK, 1.5)
	for knob: int in range(3):
		var center := Vector2(-16.0 + float(knob) * 13.0, 74.5)
		_joint(center, 1.8, RUST_LIGHT)
	draw_line(Vector2(23.0, 73.0), Vector2(23.0, 76.0), PAPER, 2.0, true)
	for screw: Vector2 in [
		Vector2(-32.0, -12.0), Vector2(34.0, -13.0),
		Vector2(-33.0, 74.0), Vector2(36.0, 73.0),
	]:
		_rivet(screw, 1.5)

	_panel(PackedVector2Array([
		Vector2(-13.0, -29.0), Vector2(-2.0, -25.0), Vector2(-13.0, -21.0),
	]), RUST)
	_panel(PackedVector2Array([
		Vector2(2.0, -25.0), Vector2(13.0, -31.0), Vector2(14.0, -21.0),
	]), RUST)
	_joint(Vector2(0.0, -25.0), 2.5, RUST_LIGHT)
	_draw_head()
	draw_set_transform(Vector2.ZERO)


func _draw_wheel(center: Vector2, radius: float, lean: float) -> void:
	draw_set_transform(center, lean, Vector2(1.0, 0.86))
	draw_circle(Vector2.ZERO, radius + 2.0, INK)
	draw_circle(Vector2.ZERO, radius, METAL_DARK)
	draw_arc(Vector2.ZERO, radius - 1.0, PI * 1.1, PI * 1.85, 16, METAL, 1.7, true)
	draw_circle(Vector2.ZERO, radius * 0.72, RUST_LIGHT)
	draw_circle(Vector2.ZERO, radius * 0.54, METAL_DARK)
	var roll := _wave(0.65) * 0.75 if walking and not defeated else 0.0
	for spoke: int in range(5):
		var direction := Vector2.from_angle(float(spoke) * TAU / 5.0 + roll + lean)
		draw_line(direction * radius * 0.18, direction * radius * 0.58, METAL_LIGHT, 1.5, true)
	_joint(Vector2.ZERO, radius * 0.19, METAL_LIGHT)
	draw_set_transform(Vector2.ZERO)


func _draw_head() -> void:
	draw_line(Vector2(-21.0, -50.0), Vector2(-29.0, -43.0), INK, 3.2, true)
	draw_line(Vector2(17.0, -48.0), Vector2(27.0, -42.0), INK, 3.2, true)
	_panel(PackedVector2Array([
		Vector2(-22.0, -65.0), Vector2(-27.0, -58.0),
		Vector2(-24.0, -40.0), Vector2(-19.0, -34.0),
	]), RUST_DARK)
	_panel(PackedVector2Array([
		Vector2(-22.0, -65.0), Vector2(13.0, -68.0), Vector2(20.0, -63.0),
		Vector2(17.0, -35.0), Vector2(-20.0, -33.0), Vector2(-24.0, -40.0),
	]), METAL_LIGHT)
	_eye(Rect2(-15.0, -59.0, 5.0, 9.0))
	_eye(Rect2(5.0, -60.0, 5.0, 9.0))
	draw_line(Vector2(-18.0, -65.0), Vector2(-6.0, -61.0), INK, 2.8, true)
	draw_line(Vector2(3.0, -61.0), Vector2(14.0, -66.0), INK, 2.8, true)
	draw_polyline(PackedVector2Array([
		Vector2(-17.0, -40.0), Vector2(-10.0, -44.0), Vector2(-4.0, -40.0),
		Vector2(3.0, -44.0), Vector2(12.0, -40.0),
	]), INK, 2.5, true)
	_rivet(Vector2(15.0, -48.0), 1.2)

	_panel(PackedVector2Array([
		Vector2(-21.0, -104.0), Vector2(12.0, -106.0), Vector2(15.0, -101.0),
		Vector2(12.0, -77.0), Vector2(-17.0, -75.0),
	]), HAT)
	draw_line(Vector2(-16.0, -100.0), Vector2(9.0, -102.0), METAL, 1.5, true)
	draw_line(Vector2(-17.0, -98.0), Vector2(-14.0, -85.0), CABINET.lightened(0.2), 2.0, true)
	_panel(PackedVector2Array([
		Vector2(-18.0, -84.0), Vector2(13.0, -86.0),
		Vector2(12.0, -77.0), Vector2(-17.0, -75.0),
	]), RUST, INK, 1.6)
	_box(Rect2(3.0, -84.0, 8.0, 7.0), RUST_LIGHT, 1.0)
	draw_line(Vector2(7.0, -83.0), Vector2(7.0, -79.0), INK, 1.4, true)
	_panel(PackedVector2Array([
		Vector2(-32.0, -76.0), Vector2(28.0, -78.0), Vector2(31.0, -73.0),
		Vector2(0.0, -68.0), Vector2(-34.0, -70.0),
	]), HAT)
	draw_line(Vector2(-28.0, -73.0), Vector2(22.0, -75.0), RUST_LIGHT, 1.5, true)
