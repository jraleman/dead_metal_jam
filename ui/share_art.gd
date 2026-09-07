extends Control

## The promotional artwork on Dead Metal Jam's share card (§9.5).
##
## The framework's [ShareCardArt] draws one of two hardcoded styles, and adding
## a third would put this game's corridor inside a framework file — the exact
## thing [member GameManifest.share_art_scene_path] exists to prevent. So the
## card is handed this scene instead, and it draws the combat room the same way
## the game does: shared colours, firing anchors and depth, read off
## [DmjRail] and [DmjArenaLayout] rather than copied. Repaint the game and the card
## follows.
##
## The rail draws a still frame, not a live encounter. No actors are instantiated
## and nothing ticks; the card uses the same environment as the playable scene.
##
## The contract is [ShareCardArt]'s: a `Control` with `configure(data)` reading
## `accent_color` and `secondary_color`, so either art can sit in the same slot.

## Bots in the still: firing bay and the note each
## is calling. Three, because that is the widest a wave gets in the shipped
## charts (§10) and a card showing more would be advertising a game nobody is
## playing.
const POSED_BOTS := [
	{"lane": 1, "note": 40, "targeted": true, "plated": false},
	{"lane": 0, "note": 45, "notes": [45, 48, 52], "targeted": false, "plated": true},
	{"lane": 2, "note": 43, "targeted": false, "plated": false},
]

const LANE_COUNT := 3
const ARENA := 1

var _accent := DmjPalette.AMBER
var _secondary := Color("ff4964")
var _rail: DmjRail
var _portraits: Array[DmjDroneArt] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_rail = DmjRail.new()
	_rail.name = "Rail"
	_rail.z_index = 0
	_rail.show_behind_parent = true
	_rail.set_reduced_motion(true)
	add_child(_rail)
	for index in range(POSED_BOTS.size() - 1, -1, -1):
		var pose: Dictionary = POSED_BOTS[index]
		var art: DmjDroneArt = (
			DmjPlatedKnuckleArt.new() if bool(pose["plated"]) else DmjRustyClankyArt.new()
		)
		var phrase: Array[int] = []
		for note: int in pose.get("notes", [pose["note"]]):
			phrase.append(note)
		art.set_phrase(phrase)
		art.combat_pose = true
		art.set_pose(0.0, false, -1.0, bool(pose["targeted"]), false, 0.0, true)
		_portraits.append(art)
		add_child(art)
	_refresh_corridor()


func configure(data: Dictionary) -> void:
	_accent = data.get("accent_color", _accent)
	_secondary = data.get("secondary_color", _secondary)
	_refresh_corridor()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_corridor()


func _refresh_corridor() -> void:
	if _rail == null or size.x <= 0.0 or size.y <= 0.0:
		return
	var field := Rect2(Vector2.ZERO, size)
	var floor_rect := JamBot.corridor_rect(field)
	_rail.set_arena(ARENA)
	_rail.update_rail(0.0, field, LANE_COUNT, false)
	for index in range(_portraits.size()):
		var pose: Dictionary = POSED_BOTS[POSED_BOTS.size() - 1 - index]
		var art := _portraits[index]
		var lane := int(pose["lane"])
		var depth := DmjArenaLayout.depth(lane, ARENA)
		var anchor := DmjArenaLayout.position(floor_rect, lane, LANE_COUNT, ARENA)
		var framed := art.framed_bounds()
		var edge_padding := minf(4.0, size.x * 0.02)
		var edge_scale := minf(
			(anchor.x - edge_padding) / maxf(-framed.position.x, 1.0),
			(size.x - anchor.x - edge_padding) / maxf(framed.end.x, 1.0)
		)
		art.z_index = int(depth * 100.0)
		art.scale = Vector2.ONE * minf(
			lerpf(0.80, 1.0, depth) * _art_scale(floor_rect), edge_scale
		)
		art.position = anchor - art.ground_offset() * art.scale
		art.modulate = Color.WHITE.lerp(
			JamBot.DEPTH_FOG, (1.0 - depth) * JamBot.FOG_STRENGTH * 0.5
		)
		art.target_color = _accent
		art.queue_redraw()


## Bots are authored at gameplay resolution, and the card's art frame is a few
## hundred pixels wide. Scaling by the frame keeps the corridor's proportions
## instead of filling it with one enormous chassis.
func _art_scale(floor_rect: Rect2) -> float:
	return minf(floor_rect.size.x / 640.0, floor_rect.size.y / 360.0) * 1.4
