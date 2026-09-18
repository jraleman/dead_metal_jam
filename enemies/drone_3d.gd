class_name DmjDrone3D
extends Node3D

## A real mesh chassis. Combat remains in JamBot, including Demo's held clock.
const STEEL := Color("526976")
const DARK := Color("162832")
const EDGE := Color("8fa5a9")
const RUST := Color("b16b46")

var source: JamBot
var _body: Node3D
var _pieces: Array[Node3D] = []
var _rest: Array[Transform3D] = []
var _fade_surfaces: Array[StandardMaterial3D] = []
var _plates: Array[MeshInstance3D] = []
var _plate_labels: Array[Label3D] = []
var _core: MeshInstance3D
var _note: Label3D
var _nameplate: Label3D
var _attack_back: MeshInstance3D
var _attack_fill: MeshInstance3D
var _target: MeshInstance3D
var _beat_ring: MeshInstance3D
var _shield: MeshInstance3D
var _muzzle: Node3D
var _height := 3.45


func configure(drone: JamBot) -> void:
	source = drone
	name = drone.display_name().to_pascal_case()
	_body = Node3D.new()
	add_child(_body)
	if drone is SilencerSentry:
		_build_sentry()
	else:
		_build_walker(drone is PlatedKnuckle, drone is DmjConductor)
	_build_readouts()
	for part in _pieces:
		_rest.append(part.transform)
	sync(true, false, true)


func _part(at: Vector3) -> Node3D:
	var part := Node3D.new()
	part.position = at
	_body.add_child(part)
	_pieces.append(part)
	return part


func _build_walker(plated: bool, conductor: bool) -> void:
	var width := 1.75 if plated or conductor else 1.35
	var armor := STEEL if plated else (DARK if conductor else RUST)
	var torso := _part(Vector3(0, 1.95, 0))
	DmjMeshKit.box(torso, Vector3(width, 1.45, 0.95), Vector3.ZERO, armor)
	DmjMeshKit.box(torso, Vector3(width + 0.12, 0.16, 1.03), Vector3(0, 0.62, 0), EDGE)
	DmjMeshKit.box(torso, Vector3(width - 0.15, 0.16, 1.02), Vector3(0, -0.58, 0), DARK)
	for side in [-1.0, 1.0]:
		var leg := _part(Vector3(side * 0.43, 0.68, 0))
		DmjMeshKit.cylinder(leg, 0.22, 0.9, Vector3.ZERO, DARK)
		DmjMeshKit.box(leg, Vector3(0.5, 0.5, 0.55), Vector3(0, -0.12, 0.02), armor)
		DmjMeshKit.box(leg, Vector3(0.6, 0.25, 0.92), Vector3(0, -0.52, 0.17), DARK)
		var arm := _part(Vector3(side * (width * 0.5 + 0.3), 2.25, 0))
		DmjMeshKit.sphere(arm, 0.3, Vector3.ZERO, EDGE)
		DmjMeshKit.box(arm, Vector3(0.6, 0.65, 0.8), Vector3(0, -0.08, 0), armor)
		DmjMeshKit.box(arm, Vector3(0.42, 0.7, 0.55), Vector3(0, -0.63, 0.08), DARK)
		var barrel := DmjMeshKit.cylinder(
			arm, 0.23, 0.85, Vector3(0, -0.48, 0.6), DARK
		)
		barrel.rotation.x = PI * 0.5
		var tip := DmjMeshKit.ring(arm, 0.17, 0.035, Vector3(0, -0.48, 1.05), DmjPalette.DANGER)
		tip.rotation.x = PI * 0.5
		if side > 0.0:
			_muzzle = Node3D.new()
			_muzzle.position = Vector3(0, -0.48, 1.12)
			arm.add_child(_muzzle)
		if plated:
			var shoulder := DmjMeshKit.box(
				arm, Vector3(0.9, 0.36, 1.0), Vector3(side * 0.12, 0.36, 0), DmjPalette.AMBER
			)
			shoulder.rotation.z = side * -0.18
		if conductor:
			DmjMeshKit.beam(arm, Vector3(0, -0.5, 0.4), Vector3(side * 0.2, 0.95, 0.8), 0.055, DmjPalette.AMBER)
			DmjMeshKit.sphere(arm, 0.14, Vector3(side * 0.2, 0.95, 0.8), DmjPalette.TEXT, true)
	var head := _part(Vector3(0, 3.0, 0))
	DmjMeshKit.cylinder(head, 0.18, 0.3, Vector3(0, -0.38, 0), EDGE)
	DmjMeshKit.box(head, Vector3(0.9, 0.68, 0.75), Vector3.ZERO, armor)
	DmjMeshKit.box(head, Vector3(0.71, 0.12, 0.05), Vector3(0, 0.08, 0.405), DmjPalette.DANGER, true)
	for tooth in range(4):
		DmjMeshKit.box(head, Vector3(0.08, 0.1, 0.06), Vector3(-0.24 + tooth * 0.16, -0.18, 0.41), EDGE)
	if conductor:
		_height = 4.05
		DmjMeshKit.cylinder(head, 0.72, 0.12, Vector3(0, 0.45, 0), DARK)
		DmjMeshKit.cylinder(head, 0.45, 0.65, Vector3(0, 0.78, 0), DARK)
		DmjMeshKit.cylinder(head, 0.465, 0.13, Vector3(0, 0.54, 0), DmjPalette.AMBER, true)
		for index in range(3):
			DmjMeshKit.box(torso, Vector3(0.1, 0.78, 0.07), Vector3(-0.4 + index * 0.4, 0, 0.51), EDGE)


func _build_sentry() -> void:
	_height = 3.35
	var hull := _part(Vector3(0, 1.8, 0))
	DmjMeshKit.sphere(hull, 0.82, Vector3.ZERO, STEEL)
	DmjMeshKit.box(hull, Vector3(1.2, 0.65, 0.85), Vector3(0, 0.6, 0), DARK)
	DmjMeshKit.box(hull, Vector3(0.84, 0.12, 0.08), Vector3(0, 0.66, 0.46), DmjPalette.DANGER, true)
	for side in [-1.0, 1.0]:
		var wing := _part(Vector3(side * 1.05, 1.8, 0))
		var shell := DmjMeshKit.box(wing, Vector3(0.55, 1.45, 0.7), Vector3.ZERO, STEEL)
		shell.rotation.z = side * -0.45
		DmjMeshKit.cylinder(wing, 0.25, 0.32, Vector3(0, -0.75, 0), DARK)
		DmjMeshKit.ring(wing, 0.21, 0.05, Vector3(0, -0.94, 0), DmjPalette.SIGNAL)
		var gun := DmjMeshKit.cylinder(wing, 0.16, 1.4, Vector3(side * 0.2, 0.05, 0.65), DARK)
		gun.rotation.x = PI * 0.5
		if side > 0.0:
			_muzzle = Node3D.new()
			_muzzle.position = Vector3(side * 0.2, 0.05, 1.4)
			wing.add_child(_muzzle)
	var rotor := _part(Vector3(0, 0.72, 0))
	DmjMeshKit.cylinder(rotor, 0.65, 0.22, Vector3.ZERO, DARK)
	DmjMeshKit.ring(rotor, 0.65, 0.07, Vector3(0, -0.12, 0), DmjPalette.SIGNAL)
	_shield = DmjMeshKit.ring(_body, 1.37, 0.065, Vector3(0, 1.85, 0.7), DmjPalette.SIGNAL)
	_shield.rotation.x = PI * 0.5


func _build_readouts() -> void:
	_core = DmjMeshKit.box(_body, Vector3(0.91, 0.92, 0.12), Vector3(0, 2.0, 0.72), DmjPalette.AMBER, true)
	_note = DmjMeshKit.label(_body, "", Vector3(0, 2.0, 0.98), 96, DARK)
	_note.outline_size = 0
	_nameplate = DmjMeshKit.label(self, source.display_name(), Vector3(0, _height + 0.65, 0), 40, DmjPalette.TEXT)
	_nameplate.pixel_size = 0.01
	_nameplate.outline_size = 4
	_attack_back = DmjMeshKit.box(self, Vector3(2.15, 0.13, 0.08), Vector3(0, _height + 0.23, 0), DARK, true)
	_attack_fill = DmjMeshKit.box(self, Vector3(2.0, 0.075, 0.06), Vector3(0, _height + 0.23, 0.055), DmjPalette.AMBER, true)
	_target = DmjMeshKit.ring(_body, 0.77, 0.035, Vector3(0, 2.0, 0.84), DmjPalette.TEXT)
	_target.rotation.x = PI * 0.5
	_beat_ring = DmjMeshKit.ring(_body, 0.92, 0.018, Vector3(0, 2.0, 0.83), DmjPalette.AMBER)
	_beat_ring.rotation.x = PI * 0.5
	var phrase: Array = source.presentation_state()["notes"]
	if phrase.size() <= 1:
		return
	for index in range(phrase.size()):
		var at := Vector3((index - float(phrase.size() - 1) * 0.5) * 0.43, 1.27, 0.72)
		_plates.append(DmjMeshKit.box(_body, Vector3(0.38, 0.32, 0.1), at, DARK, true))
		_plate_labels.append(DmjMeshKit.label(_body, "", at + Vector3(0, 0, 0.18), 30, DARK))
		_plate_labels.back().outline_size = 0


func sync(reduced_motion: bool, effects_enabled: bool, pitch_matters: bool) -> void:
	if not is_instance_valid(source):
		return
	var pose := source.presentation_state()
	var animated := effects_enabled and not reduced_motion
	var time := float(pose["time"]) if animated else 0.0
	var dead := source.state == JamBot.State.DEAD
	var live := source.is_targetable()
	var hit_age := float(pose["hit_age"])
	_body.position.y = sin(time * 2.4 + source.lane) * 0.12 if source is SilencerSentry else 0.0
	_body.rotation.z = (
		sin(hit_age * 38.0) * 0.09 * maxf(1.0 - hit_age / 0.24, 0.0)
		if animated and hit_age >= 0.0 and not dead else 0.0
	)
	var color := DmjPalette.note_color(source.required_note) if pitch_matters else DmjPalette.AMBER
	_core.material_override = DmjMeshKit.material(color, true)
	_note.text = PitchDetector.note_name(source.required_note) if pitch_matters else "ANY"
	_note.font_size = (64 if _note.text.length() > 1 else 96) if pitch_matters else 54
	var cursor := int(pose["cursor"])
	var phrase: Array = pose["notes"]
	for index in range(_plates.size()):
		var spent := index < cursor
		_plates[index].material_override = DmjMeshKit.material(
			DARK if spent else (DmjPalette.note_color(int(phrase[index])) if pitch_matters else DmjPalette.AMBER), true
		)
		_plate_labels[index].text = "-" if spent else (
			PitchDetector.note_name(int(phrase[index])) if pitch_matters else "*"
		)
		_plate_labels[index].modulate = EDGE if spent else DARK
	_nameplate.text = source.display_name()
	if phrase.size() > 1 and live:
		_nameplate.text += "  %d/%d" % [mini(cursor + 1, phrase.size()), phrase.size()]
	_nameplate.visible = live
	_attack_back.visible = live and source.show_attack_bar
	_attack_fill.visible = _attack_back.visible
	var charge := source.attack_progress()
	_attack_fill.scale.x = maxf(charge, 0.001)
	_attack_fill.position.x = -1.0 + charge
	_attack_fill.material_override = DmjMeshKit.material(
		DmjPalette.DANGER if charge > 0.78 else DmjPalette.AMBER, true
	)
	_target.visible = live and bool(pose["targeted"])
	_beat_ring.visible = _target.visible
	var beat_in := -source.time_to_beat() / maxf(source.presentation_speed, 0.1)
	_beat_ring.scale = Vector3.ONE * (0.85 + clampf(beat_in, 0.0, 1.2) * 0.45)
	_beat_ring.material_override = DmjMeshKit.material(
		DmjPalette.TEXT if absf(beat_in) <= 0.14 else color, true
	)
	if _shield != null:
		_shield.visible = live and cursor == 0
	_core.visible = not dead
	_note.visible = not dead
	for index in range(_plates.size()):
		_plates[index].visible = not dead
		_plate_labels[index].visible = not dead
	for index in range(_pieces.size()):
		var part := _pieces[index]
		part.transform = _rest[index]
		part.visible = true
		if not dead:
			continue
		var age := float(pose["death_age"])
		if animated and bool(pose["death_animated"]):
			var side := -1.0 if index % 2 == 0 else 1.0
			part.position += Vector3(side * (1.3 + index * 0.16), 2.0 + index * 0.15, 0.8) * age
			part.position.y = maxf(0.18, part.position.y - 5.0 * age * age)
			part.rotation += Vector3(1.5, side * 2.0, side * 3.5) * age
			part.scale *= maxf(0.001, 1.0 - smoothstep(0.55, JamBot.DEATH_FADE, age))
		else:
			part.visible = age < float(pose["death_duration"])
	if dead and _fade_surfaces.is_empty():
		for part in _pieces:
			_collect_fade_surfaces(part)
	var death_age := float(pose["death_age"])
	var opacity := 1.0
	if dead:
		opacity = (
			1.0 - smoothstep(0.55, JamBot.DEATH_FADE, death_age)
			if animated and bool(pose["death_animated"])
			else 1.0 - clampf(death_age / JamBot.QUIET_DEATH_FADE, 0.0, 1.0)
		)
	for surface in _fade_surfaces:
		surface.albedo_color.a = opacity


func _collect_fade_surfaces(node: Node3D) -> void:
	if node is MeshInstance3D:
		var piece := node as MeshInstance3D
		var surface := piece.material_override.duplicate() as StandardMaterial3D
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		piece.material_override = surface
		_fade_surfaces.append(surface)
	for child in node.get_children():
		if child is Node3D:
			_collect_fade_surfaces(child)


func aim_point() -> Vector3:
	return _core.global_position


func muzzle_point() -> Vector3:
	return _muzzle.global_position
