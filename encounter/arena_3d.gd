class_name DmjArena3D
extends SubViewportContainer

## Isolated 3D world inside GameShell's 2D HUD; no shared renderer changes.
var viewport: SubViewport
var world: Node3D
var camera: Camera3D
var shots: DmjShotFx3D
var director: EncounterDirector
var _rooms: Dictionary[int, DmjRoom3D] = {}
var _models: Dictionary[int, DmjDrone3D] = {}
var _actors: Array[JamBot] = []
var _weapon: Node3D
var _muzzle: Node3D
var _weapon_light: MeshInstance3D
var _muzzle_light: OmniLight3D
var _reduced_motion := false
var _effects_enabled := true
var _pitch_matters := true
var _arena_index := 0
var _travel := 1.0
var _time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stretch = true
	viewport = SubViewport.new()
	viewport.name = "WorldViewport"
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	world = Node3D.new()
	world.name = "Arena"
	viewport.add_child(world)
	_build_lighting()
	camera = Camera3D.new()
	camera.name = "RailCamera"
	camera.fov = 34.0
	camera.near = 0.1
	camera.far = 120.0
	world.add_child(camera)
	camera.make_current()
	shots = DmjShotFx3D.new()
	shots.name = "Shots"
	world.add_child(shots)
	shots.set_presentation_options(_reduced_motion, _effects_enabled)
	_build_weapon()
	present([], 0, 1.0, 0.0)


func _build_lighting() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = DmjPalette.INK
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("afc8d6")
	settings.ambient_light_energy = 0.45
	settings.fog_enabled = true
	settings.fog_light_color = Color("233743")
	settings.fog_density = 0.008
	environment.environment = settings
	world.add_child(environment)
	var key := DirectionalLight3D.new()
	key.name = "StageKey"
	key.rotation_degrees = Vector3(-48, -28, 0)
	key.light_color = Color("ffebc8")
	key.light_energy = 1.3
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 65.0
	world.add_child(key)


func _build_weapon() -> void:
	_weapon = Node3D.new()
	_weapon.name = "InstrumentAmplifier"
	_weapon.scale = Vector3.ONE * 0.68
	camera.add_child(_weapon)
	DmjMeshKit.box(_weapon, Vector3(1.15, 0.7, 0.65), Vector3.ZERO, DmjPalette.PANEL)
	DmjMeshKit.box(_weapon, Vector3(1.2, 0.1, 0.72), Vector3(0, 0.38, 0), DmjDrone3D.EDGE)
	for index in range(7):
		DmjMeshKit.box(_weapon, Vector3(0.055, 0.44, 0.035), Vector3(-0.39 + index * 0.13, -0.02, 0.34), DmjPalette.LINE)
	for side in [-1.0, 1.0]:
		var barrel := DmjMeshKit.cylinder(_weapon, 0.13, 0.65, Vector3(side * 0.36, 0.35, -0.48), DmjDrone3D.EDGE)
		barrel.rotation.x = PI * 0.5
	_weapon_light = DmjMeshKit.box(_weapon, Vector3(0.65, 0.055, 0.04), Vector3(0, 0.24, 0.34), DmjPalette.SIGNAL, true)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.35, -0.83)
	_weapon.add_child(_muzzle)
	_muzzle_light = OmniLight3D.new()
	_muzzle_light.name = "NoteFlash"
	_muzzle_light.omni_range = 22.0
	_muzzle_light.light_energy = 0.0
	world.add_child(_muzzle_light)


func set_field(field: Rect2) -> void:
	position = field.position
	size = field.size.max(Vector2.ONE)
	if camera != null:
		_place_camera()


func set_presentation_options(reduced_motion: bool, effects_enabled: bool) -> void:
	_reduced_motion = reduced_motion
	_effects_enabled = effects_enabled
	if shots == null:
		return
	shots.set_presentation_options(reduced_motion, effects_enabled)
	present(_actors, _arena_index, _travel, _time, _pitch_matters)


func _process(_delta: float) -> void:
	if director != null:
		sync_from_director()


func sync_from_director() -> void:
	if director == null:
		return
	present(
		director.staged_drones(), director.arena_index(), director.travel_progress(),
		director.world_time(), director.pitch_matters
	)


func present(
	actors: Array[JamBot], arena_index: int, travel: float, time: float, pitch_matters := true
) -> void:
	if world == null:
		return
	_actors = actors.duplicate()
	_arena_index = maxi(arena_index, 0)
	_travel = travel
	_time = time
	_pitch_matters = pitch_matters
	if not _rooms.has(_arena_index):
		var room := DmjRoom3D.new()
		world.add_child(room)
		room.configure(_arena_index)
		_rooms[_arena_index] = room
	for index: int in _rooms.keys():
		if index != _arena_index and (index != _arena_index - 1 or travel >= 1.0):
			_rooms[index].free()
			_rooms.erase(index)
		else:
			_rooms[index].set_time(time if _effects_enabled and not _reduced_motion else 0.0)
	_place_camera()
	var alive: Array[int] = []
	for actor in _actors:
		if not is_instance_valid(actor) or actor.is_queued_for_deletion():
			continue
		var model := model_for(actor)
		alive.append(actor.get_instance_id())
		_place_model(model, actor)
		model.sync(_reduced_motion, _effects_enabled, pitch_matters)
	for id: int in _models.keys():
		if not alive.has(id):
			_models[id].free()
			_models.erase(id)


func _place_camera() -> void:
	var motion := _effects_enabled and not _reduced_motion
	var progress := smoothstep(0.0, 1.0, _travel) if motion else 1.0
	var destination := DmjArenaLayout.world_origin(_arena_index)
	var origin := DmjArenaLayout.world_origin(_arena_index - 1) if _arena_index > 0 else Vector3(0, 0, 4)
	var offset := origin.lerp(destination, progress)
	var aspect := size.x / maxf(size.y, 1.0)
	var extra_distance := maxf(0.0, 20.0 / maxf(aspect, 0.25) - 11.8) * 1.65
	var bob := sin(_time * 1.8) * 0.045 if motion else 0.0
	camera.position = offset + Vector3(bob, 5.0, 15.0 + extra_distance)
	camera.look_at(offset + Vector3(0, 1.75, -4.0), Vector3.UP)
	_weapon.position = Vector3(0, -0.86, -3.1 + shots.recoil())
	_weapon_light.material_override = DmjMeshKit.material(shots.last_color, true)
	shots.muzzle = _muzzle.global_position
	_muzzle_light.position = shots.muzzle
	_muzzle_light.light_color = shots.last_color
	_muzzle_light.light_energy = shots.muzzle_flash() * 2.5


func model_for(actor: JamBot) -> DmjDrone3D:
	var id := actor.get_instance_id()
	if not _models.has(id):
		var model := DmjDrone3D.new()
		world.add_child(model)
		model.configure(actor)
		_models[id] = model
		_place_model(model, actor)
	return _models[id]


func _place_model(model: DmjDrone3D, actor: JamBot) -> void:
	model.scale = Vector3.ONE * 1.3
	model.position = DmjArenaLayout.world_position(actor.lane, actor.arena_index, actor.firing_slot)
	if _effects_enabled and not _reduced_motion:
		var entry := pow(1.0 - actor.entry_progress(), 3.0)
		model.position.x += (-1.0 if actor.lane % 2 == 0 else 1.0) * entry * 1.1
	model.rotation.y = atan2(camera.position.x - model.position.x, camera.position.z - model.position.z) * 0.5


func aim_point(actor: JamBot) -> Vector3:
	return model_for(actor).aim_point()


func muzzle_point(actor: JamBot) -> Vector3:
	return model_for(actor).muzzle_point()


func ground_point(actor: JamBot) -> Vector3:
	return model_for(actor).global_position


func set_weapon_visible(shown: bool) -> void:
	_weapon.visible = shown
