class_name DmjRoom3D
extends Node3D

var _machines: Array[Node3D] = []
var _accent := DmjPalette.AMBER
var _index := 0


func configure(index: int) -> void:
	_index = index
	name = "Room%d" % index
	position = DmjArenaLayout.world_origin(index)
	var style := posmod(index, DmjArenaLayout.ARENA_NAMES.size())
	_accent = [DmjPalette.AMBER, DmjPalette.SIGNAL, Color("b7a5ff")][style]
	_build_shell()
	match style:
		0: _build_loading_bay()
		1: _build_turbines()
		2: _build_reactor()
	var sign := DmjMeshKit.label(self, DmjArenaLayout.arena_name(index), Vector3(-6.8, 7.0, -16.9), 104, _accent)
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	DmjMeshKit.box(self, Vector3(8.0, 1.2, 0.2), Vector3(-6.8, 7.0, -17.1), DmjPalette.PANEL)


func _build_shell() -> void:
	DmjMeshKit.box(self, Vector3(23, 0.35, 34), Vector3(0, -0.23, -3), Color("263942"))
	for row in range(11):
		var z := 12.0 - float(row) * 3.0
		for column in range(5):
			DmjMeshKit.box(
				self, Vector3(4.32, 0.035, 2.88), Vector3(-8.8 + column * 4.4, -0.035, z),
				Color("304650") if (row + column) % 2 == 0 else Color("2a3c45")
			)
	for side in [-1.0, 1.0]:
		DmjMeshKit.box(self, Vector3(0.5, 9, 34), Vector3(side * 11.5, 4.4, -3), DmjPalette.STEEL)
		DmjMeshKit.box(self, Vector3(6.4, 8, 0.5), Vector3(side * 8.2, 4, -19.8), DmjPalette.PANEL)
		DmjMeshKit.box(self, Vector3(0.12, 0.045, 33), Vector3(side * 7.6, 0.005, -3), _accent, true)
		for segment in range(6):
			var z := 10.0 - segment * 5.4
			DmjMeshKit.box(self, Vector3(0.72, 8, 0.55), Vector3(side * 11.08, 3.9, z), Color("405964"))
			DmjMeshKit.box(self, Vector3(0.1, 1.6, 0.18), Vector3(side * 10.68, 3.6, z), _accent, true)
			DmjMeshKit.beam(self, Vector3(side * 10.9, 0.2, z), Vector3(side * 10.9, 5.8, z - 3.8), 0.12, DmjPalette.LINE, false)
		for height in [5.2, 5.7]:
			var pipe := DmjMeshKit.cylinder(self, 0.17, 32, Vector3(side * 10.6, height, -3), Color("68767a"))
			pipe.rotation.x = PI * 0.5
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(side * 6.0, 6.5, -6)
		lamp.light_color = _accent
		lamp.light_energy = 2.0
		lamp.omni_range = 14.0
		add_child(lamp)
	for z in [8.0, -3.0, -14.0]:
		DmjMeshKit.box(self, Vector3(23, 0.45, 0.5), Vector3(0, 8, z), DmjPalette.LINE)
		DmjMeshKit.box(self, Vector3(5.0, 0.1, 0.28), Vector3(0, 7.7, z), DmjPalette.TEXT, true)
	for lane in range(3):
		var anchor := DmjArenaLayout.world_position(lane, _index) - position
		var pad := DmjMeshKit.cylinder(self, 1.6, 0.08, anchor, DmjPalette.PANEL)
		pad.name = "FiringBay%d" % lane
		DmjMeshKit.ring(self, 1.5, 0.025, anchor + Vector3(0, 0.045, 0), _accent)
	# The open central gate is the camera's path into the next physical room.
	for x in [-4.6, 4.6]:
		DmjMeshKit.box(self, Vector3(0.32, 7.7, 0.8), Vector3(x, 3.8, -19.6), _accent)
	DmjMeshKit.box(self, Vector3(9.5, 0.35, 0.8), Vector3(0, 7.6, -19.6), _accent)


func _crate(at: Vector3, height: float) -> void:
	DmjMeshKit.box(self, Vector3(2.4, height, 2.0), at + Vector3(0, height * 0.5, 0), Color("5e5141"))
	for y in [0.12, height - 0.12]:
		DmjMeshKit.box(self, Vector3(2.5, 0.15, 2.1), at + Vector3(0, y, 0), DmjPalette.LINE)
	for x in [-0.85, 0.85]:
		DmjMeshKit.box(self, Vector3(0.16, height, 2.1), at + Vector3(x, height * 0.5, 0), DmjDrone3D.EDGE)
	var tag := DmjMeshKit.label(self, "DMJ", at + Vector3(0, height * 0.5, 1.06), 50, DmjPalette.AMBER)
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED


func _build_loading_bay() -> void:
	for side in [-1.0, 1.0]:
		_crate(Vector3(side * 8.7, 0, -8), 2.0)
		_crate(Vector3(side * 8.7, 0, -14), 3.3)
		_crate(Vector3(side * 8.7, 3.35, -14), 1.7)
		DmjMeshKit.box(self, Vector3(0.8, 0.15, 11), Vector3(side * 8.7, 7, -7), DmjPalette.AMBER)
		DmjMeshKit.beam(self, Vector3(side * 8.7, 7, -8), Vector3(side * 8.7, 4.4, -8), 0.045, DmjDrone3D.EDGE, false)


func _build_turbines() -> void:
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 7.8, 3.7, -14)
		var casing := DmjMeshKit.cylinder(self, 2.65, 1.4, at, DmjPalette.LINE)
		casing.rotation.x = PI * 0.5
		var rim := DmjMeshKit.ring(self, 2.45, 0.12, at + Vector3(0, 0, 0.75), _accent)
		rim.rotation.x = PI * 0.5
		var rotor := Node3D.new()
		rotor.position = at + Vector3(0, 0, 0.85)
		rotor.set_meta("axis", Vector3.FORWARD)
		rotor.set_meta("speed", side * 0.8)
		add_child(rotor)
		_machines.append(rotor)
		DmjMeshKit.sphere(rotor, 0.5, Vector3.ZERO, DmjDrone3D.EDGE)
		for index in range(8):
			var angle := float(index) * TAU / 8.0
			var blade := DmjMeshKit.box(
				rotor, Vector3(0.5, 1.65, 0.17),
				Vector3(sin(angle), cos(angle), 0) * 1.35, DmjDrone3D.STEEL
			)
			blade.rotation.z = -angle + 0.25
		DmjMeshKit.box(self, Vector3(4.3, 1.0, 3.2), Vector3(side * 7.8, 0.5, -14), DmjPalette.PANEL)


func _build_reactor() -> void:
	for side in [-1.0, 1.0]:
		var at := Vector3(side * 7.8, 0, -12.5)
		DmjMeshKit.cylinder(self, 2.0, 0.6, at + Vector3(0, 0.3, 0), DmjPalette.LINE)
		DmjMeshKit.cylinder(self, 1.35, 0.35, at + Vector3(0, 5.85, 0), Color("526074"))
		DmjMeshKit.cylinder(self, 0.75, 5.8, at + Vector3(0, 3.1, 0), _accent, true)
		for level in range(3):
			var axis := Node3D.new()
			axis.position = at + Vector3(0, 1.4 + level * 1.5, 0)
			axis.set_meta("axis", Vector3(0.35, 1.0, 0.2).normalized())
			axis.set_meta("speed", (0.35 + level * 0.16) * side)
			add_child(axis)
			_machines.append(axis)
			var ring := DmjMeshKit.ring(axis, 1.6, 0.09, Vector3.ZERO, _accent)
			ring.rotation.z = 0.35 + level * 0.2
		for column in range(4):
			var angle := column * TAU / 4.0
			DmjMeshKit.box(self, Vector3(0.24, 5.8, 0.24), at + Vector3(sin(angle) * 1.75, 3.1, cos(angle) * 1.75), DmjPalette.LINE)


func set_time(time: float) -> void:
	for machine in _machines:
		var axis: Vector3 = machine.get_meta("axis")
		machine.quaternion = Quaternion(axis, time * float(machine.get_meta("speed")))
