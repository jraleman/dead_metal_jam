extends Control

## The promotional artwork on Dead Metal Jam's share card (§9.5).
##
## The framework's [ShareCardArt] draws one of two hardcoded styles, and adding
## a third would put this game's corridor inside a framework file — the exact
## thing [member GameManifest.share_art_scene_path] exists to prevent. So the
## card is handed this scene instead, and it draws the corridor the same way
## the game does: same colours, same lane spread, same depth curve, read off
## [DmjRail] and [JamBot] rather than copied. Repaint the game and the card
## follows.
##
## It draws a *still frame*, not a live encounter. No gameplay node is
## instantiated, nothing ticks, and nothing here can fail a render — the card
## is produced on a headless render target with no encounter running (§9.5).
##
## The contract is [ShareCardArt]'s: a `Control` with `configure(data)` reading
## `accent_color` and `secondary_color`, so either art can sit in the same slot.

## Bots in the still, near to far: lane index, walk progress, and the note each
## is calling. Three, because that is the widest a wave gets in the shipped
## charts (§10) and a card showing more would be advertising a game nobody is
## playing.
const POSED_BOTS := [
	{"lane": 1, "progress": 0.78, "note": 40, "targeted": true, "plated": false},
	{"lane": 0, "progress": 0.5, "note": 45, "targeted": false, "plated": true},
	{"lane": 2, "progress": 0.27, "note": 43, "targeted": false, "plated": false},
]

const LANE_COUNT := 3

## Cross-ties on the floor. Fewer than the rail's fourteen: at card size the
## far ones would land inside a pixel of each other and read as a smear.
const RUNG_COUNT := 9

## Where the corridor's vanishing point sits horizontally. Dead centre, unlike
## the framework art's off-centre marks, because the lanes have to converge on
## the same point the bots walk towards or the depth reads as a lean.
const VANISH_X := 0.5

var _accent := Color("ffd34e")
var _secondary := Color("ff4964")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func configure(data: Dictionary) -> void:
	_accent = data.get("accent_color", _accent)
	_secondary = data.get("secondary_color", _secondary)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var field := Rect2(Vector2.ZERO, size)
	var floor_rect := JamBot.corridor_rect(field)

	_draw_corridor(field, floor_rect)
	_draw_lanes(floor_rect)
	_draw_light(floor_rect)
	# Far to near, so a nearer bot occludes the one behind it — the same draw
	# order the encounter gets from `z_index` (§8.1).
	var posed := POSED_BOTS.duplicate()
	posed.reverse()
	for bot: Dictionary in posed:
		_draw_bot(floor_rect, bot)
	_draw_strike_line(floor_rect)


## Ceiling, haze and floor. The horizon is where [method JamBot.corridor_rect]
## puts it, so the card's floor starts exactly where the game's does.
func _draw_corridor(field: Rect2, floor_rect: Rect2) -> void:
	draw_rect(
		Rect2(field.position, Vector2(field.size.x, floor_rect.position.y)),
		DmjRail.CEILING_FAR
	)
	_draw_vertical_fade(
		Rect2(field.position, Vector2(field.size.x, floor_rect.position.y)),
		DmjRail.CEILING_NEAR,
		DmjRail.CEILING_FAR
	)
	_draw_vertical_fade(floor_rect, DmjRail.FLOOR_FAR, DmjRail.FLOOR_NEAR)
	draw_line(
		Vector2(field.position.x, floor_rect.position.y),
		Vector2(field.end.x, floor_rect.position.y),
		DmjRail.HORIZON_COLOR,
		2.0
	)
	draw_rect(
		Rect2(
			Vector2(field.position.x, floor_rect.position.y - field.size.y * 0.06),
			Vector2(field.size.x, field.size.y * 0.12)
		),
		Color(DmjRail.HAZE, 0.55)
	)


## The lanes and their cross-ties, converging on the vanishing point by the
## same [constant JamBot.HORIZON_LANE_SPREAD] the bots use, so a lane edge on
## the card always passes under the bot standing in that lane.
func _draw_lanes(floor_rect: Rect2) -> void:
	for edge in range(LANE_COUNT + 1):
		var slot := float(edge) - float(LANE_COUNT) * 0.5
		var near := _lane_point(floor_rect, slot, 1.0)
		var far := _lane_point(floor_rect, slot, 0.0)
		draw_line(far, near, DmjRail.LANE_EDGE, 1.0, true)

	for rung in range(1, RUNG_COUNT + 1):
		# Cubed, so the ties bunch towards the horizon. Evenly spaced ties read
		# as a ladder lying flat rather than as a floor going away.
		var progress := pow(float(rung) / float(RUNG_COUNT + 1), 3.0)
		var half := float(LANE_COUNT) * 0.5
		draw_line(
			_lane_point(floor_rect, -half, progress),
			_lane_point(floor_rect, half, progress),
			Color(DmjRail.RUNG_COLOR, 0.35 + progress * 0.65),
			1.0
		)


## The player's own light, pooled at the strike line. It is the reason the near
## end of the corridor is readable at all (§8.1), so leaving it out would make
## the card darker than the game ever looks.
func _draw_light(floor_rect: Rect2) -> void:
	var origin := Vector2(floor_rect.get_center().x, floor_rect.end.y)
	var reach := floor_rect.size.y * DmjRail.LIGHT_REACH
	for ring in range(6, 0, -1):
		var radius := reach * float(ring) / 3.0
		draw_circle(
			origin,
			radius,
			Color(DmjRail.LIGHT_COLOR, DmjRail.LIGHT_REST * 0.5 / float(ring))
		)


## One bot, posed. Chassis, cap, plates and glyph are [JamBot]'s own colours at
## [JamBot]'s own depth scale and fog, so the card cannot drift from the game
## without someone editing the game.
func _draw_bot(floor_rect: Rect2, bot: Dictionary) -> void:
	var progress := float(bot["progress"])
	var slot := float(bot["lane"]) - float(LANE_COUNT - 1) * 0.5
	var center := _lane_point(floor_rect, slot, progress)
	var depth := lerpf(JamBot.HORIZON_SCALE, 1.0, pow(progress, 1.5))
	var body_size := JamBot.BODY_SIZE * depth * _art_scale(floor_rect)
	var body := Rect2(center - body_size * 0.5, body_size)
	var fog := Color.WHITE.lerp(
		JamBot.DEPTH_FOG, (1.0 - pow(progress, 0.6)) * JamBot.FOG_STRENGTH
	)

	draw_rect(
		Rect2(body.position + body_size * 0.06, body_size), Color(0.0, 0.0, 0.0, 0.3)
	)
	draw_rect(body, JamBot.CHASSIS * fog)
	draw_rect(
		Rect2(body.position, Vector2(body_size.x, body_size.y * 0.17)),
		JamBot.CHASSIS_DARK * fog
	)
	if bool(bot.get("plated", false)):
		_draw_plates(body, fog)
	_draw_glyph(body, int(bot["note"]), fog)
	if bool(bot.get("targeted", false)):
		draw_rect(body.grow(body_size.x * 0.08), _accent, false, 3.0)


## The plated knuckle's armour: the enemy that takes more than one note (§8.2).
## [PlatedKnuckle]'s own plate colours, so the card shows the enemy the player
## will actually meet rather than a yellow bar that happens to be in the theme.
func _draw_plates(body: Rect2, fog: Color) -> void:
	for index in range(2):
		var plate := Rect2(
			Vector2(
				body.position.x + body.size.x * 0.12,
				body.position.y + body.size.y * (0.3 + float(index) * 0.26)
			),
			Vector2(body.size.x * 0.76, body.size.y * 0.15)
		)
		draw_rect(plate, PlatedKnuckle.PLATE_INTACT * fog)
		draw_rect(plate, PlatedKnuckle.PLATE_EDGE * fog, false, 1.0)


## The called note, as a letter. The one thing on the card that says this game
## is played on an instrument, and text rather than colour for the same reason
## the bot itself uses text (§9.7).
func _draw_glyph(body: Rect2, note: int, fog: Color) -> void:
	var font := ThemeDB.fallback_font
	if font == null or note < 0:
		return
	var glyph := PitchDetector.note_name(note)
	var glyph_size := maxi(int(body.size.y * 0.42), 8)
	var extent := font.get_string_size(
		glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, glyph_size
	)
	draw_string(
		font,
		Vector2(
			body.get_center().x - extent.x * 0.5,
			body.get_center().y + extent.y * 0.32
		),
		glyph,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		glyph_size,
		JamBot.GLYPH_INK * fog
	)


## The strike line: where a bot that has not been answered gets its shot away.
## Drawn last so nothing stands in front of it, and inset from the bottom of
## the frame so it reads as a line on the floor rather than as the frame's own
## edge.
func _draw_strike_line(floor_rect: Rect2) -> void:
	var y := floor_rect.end.y - floor_rect.size.y * 0.09
	draw_rect(
		Rect2(
			Vector2(floor_rect.position.x, y),
			Vector2(floor_rect.size.x, floor_rect.end.y - y)
		),
		Color(_accent, 0.1)
	)
	draw_line(
		Vector2(floor_rect.position.x, y), Vector2(floor_rect.end.x, y), _accent, 3.0
	)


## A point on the corridor floor. `slot` is lane offsets from the centre line
## and `progress` is [JamBot]'s: 0 at the horizon, 1 at the strike line.
func _lane_point(floor_rect: Rect2, slot: float, progress: float) -> Vector2:
	var spread := lerpf(JamBot.HORIZON_LANE_SPREAD, 1.0, progress)
	var lane_width := floor_rect.size.x / float(LANE_COUNT)
	var vanish := floor_rect.position.x + floor_rect.size.x * VANISH_X
	return Vector2(
		lerpf(vanish, floor_rect.get_center().x, progress) + slot * lane_width * spread,
		lerpf(floor_rect.position.y, floor_rect.end.y, progress)
	)


## Bots are authored at gameplay resolution, and the card's art frame is a few
## hundred pixels wide. Scaling by the frame keeps the corridor's proportions
## instead of filling it with one enormous chassis.
func _art_scale(floor_rect: Rect2) -> float:
	return minf(floor_rect.size.x / 640.0, floor_rect.size.y / 360.0) * 1.6


## A flat gradient, in bands. `draw_rect` has no gradient and a shader would
## drag a material into a scene that has to render on a headless target, so the
## fade is stepped — at card size the bands are under a pixel of each other.
func _draw_vertical_fade(area: Rect2, top: Color, bottom: Color) -> void:
	var bands := 24
	var band_height := area.size.y / float(bands)
	for index in range(bands):
		draw_rect(
			Rect2(
				Vector2(area.position.x, area.position.y + float(index) * band_height),
				Vector2(area.size.x, band_height + 1.0)
			),
			top.lerp(bottom, float(index) / float(bands - 1))
		)
