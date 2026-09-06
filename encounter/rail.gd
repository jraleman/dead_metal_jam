class_name DmjRail
extends Node2D

## The world the encounter happens in: the corridor the player rides down, and
## the three lanes on its floor (§8.1).
##
## This node draws and nothing else. It never spawns, never judges and never
## owns a bot — [EncounterDirector] tells it which phase the rail is in, how
## big the field is and where the camera's head is, and it answers with a
## picture.
##
## **Why it exists at all.** Milestone 6 is pacing, and pacing is the one thing
## that cannot be verified in a unit test. Before this, a rail advance was a
## 2.2-second pause in which the screen was empty and nothing moved, which
## reads as the game having stopped rather than as the camera travelling. The
## lanes were equally invisible: three bots walking down converging invisible
## lines is not the same picture as three lanes, and the depth illusion is the
## whole staging (§8.1).
##
## **Why it is a corridor.** A floor alone is a floor seen from above, however
## it is shaded — the eye has nothing at its own height to judge distance
## against. Walls and a ceiling put the player *inside* the scene, and panelled
## walls give the one cue a fixed camera can still deliver: features at known
## depths sweeping outwards and growing as they pass. That parallax is what
## the 2.5D read is made of; everything else here only supports it.
##
## Everything uses the same placement maths as [JamBot], including the
## headroom inset ([method JamBot.corridor_rect]), so a lane guide lands
## exactly under the bots that walk it. A separate copy of the projection
## would drift the moment either side was tuned.
##
## Like the rest of `encounter/`, this touches no autoload instance so the
## director stays drivable from a headless test.

## Cross-ties drawn between the horizon and the strike line.
const RUNG_COUNT := 14

## Wall panels down each side. Enough that a seam sweeps past often enough to
## read as travel, few enough that the far ones do not collapse into a smear.
const WALL_PANELS := 18

## Overhead beams. Fewer than the floor's rungs so the two do not beat against
## each other and turn the corridor into a moiré.
const BEAM_COUNT := 9

## Wall height at the strike line, in corridor heights.
##
## Tuned against [constant JamBot.HORIZON_HEADROOM] rather than picked: at this
## value the nearest wall reaches the top of the frame exactly, so the corridor
## encloses the player at the front and there is nothing left over to show
## behind it.
const WALL_HEIGHT := 1.35

## How tall the furthest wall is, as a fraction of the nearest.
##
## Deliberately *not* [constant JamBot.HORIZON_LANE_SPREAD]. The lanes stop
## converging at 0.22 because three bots at the far end still have to be three
## readable bots — that is a gameplay constraint, not a perspective one.
## Heights are under no such obligation, so they converge properly.
##
## That difference is the only reason there is a visible ceiling at all. Wall
## tops fall away much faster than wall bases do, and the wedge opening up
## between them *is* the ceiling; matched to the lane spread instead, the two
## lines run nearly parallel and the ceiling collapses to a few pixels.
const WALL_HORIZON_SCALE := 0.06

## Rail speed while a wave is on the field: a slow creep, so the world is alive
## without implying the camera is travelling.
const IDLE_SPEED := 0.035

## Rail speed during an advance. Fast enough to read as "we have moved on",
## which is what makes the advance banner mean something.
const ADVANCE_SPEED := 0.85

## How quickly the rail reaches its target speed. The surge has to ramp or the
## floor visibly teleports on the frame a wave ends.
const SPEED_BLEND := 4.0

## Ambient scrap that drifts past during an advance — no threat, and never
## targetable, because it is not a node (§8.1).
const AMBIENT_COUNT := 7

## Where the travelled distance wraps. A multiple of the panel spacing, and an
## even number of panels, so a wrap leaves both the panel positions and their
## light/dark alternation exactly where they were.
const SCROLL_WRAP := 1024.0

const FLOOR_NEAR := Color("241a12")
const FLOOR_FAR := Color("0b0806")
const RUNG_COLOR := Color("3c322a")
const LANE_EDGE := Color("4a3d30")
const HORIZON_COLOR := Color("5d4a35")
const STRIKE_COLOR := Color("ffd34e")
const AMBIENT_COLOR := Color("1c150f")
const WALL_NEAR := Color("3a2c20")
const WALL_FAR := Color("0d0b09")
const WALL_SEAM := Color("6d5a4a")
const CEILING_NEAR := Color("15100c")
const CEILING_FAR := Color("070605")
const CEILING_BEAM := Color("2e241b")
const HAZE := Color("2b2018")
const LIGHT_COLOR := Color("ffd7a0")

## The player's own light: how far down the corridor it reaches, how much of it
## is always on, and how much a landed note adds.
##
## A first-person scene needs a light source at the camera. Without one the
## floor at the player's feet is lit exactly like the floor at the far end,
## which is the tell that there is no space between them — the corridor goes
## back to reading as a painting no matter how good the perspective is.
##
## It is painted on the floor, behind every bot, which is the point: it can
## flare as hard as it likes on a hit and still never hide the thing the player
## is aiming at.
const LIGHT_REACH := 0.42
const LIGHT_REST := 0.11
const LIGHT_FLASH := 0.40

## How fast a note's flare goes out. Driven by the same stepped clock as
## everything else, so Demo's frozen world holds the light where it is rather
## than letting it fade during a freeze nothing else is moving through.
const FLASH_DECAY := 4.5

var _field := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
var _corridor := Rect2(Vector2.ZERO, Vector2(640.0, 360.0))
var _lane_count := 3
var _scroll := 0.0
var _travelled := 0.0
var _speed := IDLE_SPEED
var _advancing := false
var _reduced_motion := false
var _flash := 0.0


func _init() -> void:
	# Behind every bot: the nearest bot sits at z 100, the furthest at 0.
	z_index = -20


## Called once per frame by [EncounterDirector] with the same field rect the
## bots are placed in, and the head bob it placed them with.
##
## The bob moves the corridor but not the backdrop: the walls, floor and
## ceiling sway with the camera while the frame stays filled, so a bob can
## never open a gap at the edge of the screen.
func update_rail(
	delta: float,
	field: Rect2,
	lane_count: int,
	advancing: bool,
	bob: Vector2 = Vector2.ZERO
) -> void:
	_field = field
	_corridor = JamBot.corridor_rect(field)
	_corridor.position += bob
	_lane_count = maxi(lane_count, 1)
	_advancing = advancing

	var target := ADVANCE_SPEED if advancing else IDLE_SPEED
	if _reduced_motion:
		# The rail still moves, because a frozen floor makes an advance
		# indistinguishable from a stall — but it moves slowly enough not to be
		# the large-area scrolling motion the setting exists to avoid.
		target *= 0.25
	_speed = lerpf(_speed, target, clampf(delta * SPEED_BLEND, 0.0, 1.0))
	_travelled = fposmod(_travelled + _speed * delta, SCROLL_WRAP)
	_scroll = fposmod(_travelled, 1.0)
	_flash = maxf(_flash - delta * FLASH_DECAY, 0.0)
	queue_redraw()


## A note landed: flare the player's light. [param strength] is 0 to 1.
##
## Deliberately not a signal the rail listens for. The rail draws what it is
## told and knows nothing about notes, scoring or who played them, which is the
## only reason a headless test can drive the director without an audio stack.
func flash(strength: float) -> void:
	_flash = clampf(maxf(_flash, strength), 0.0, 1.0)


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled


func is_advancing() -> bool:
	return _advancing


## Back to front, because that is the only order in which a corridor closes:
## the backdrop is whatever the geometry fails to cover, the ceiling and floor
## meet the walls at the frame edges, and the strike line is painted on top of
## the floor it marks.
func _draw() -> void:
	_draw_backdrop()
	_draw_ceiling()
	_draw_floor()
	_draw_player_light()
	_draw_rungs()
	_draw_lanes()
	_draw_walls()
	_draw_haze()
	if _advancing:
		_draw_ambient()
	_draw_strike_line()


## The colour a bobbing camera exposes at the edge of the frame. Grown past the
## field so a resize caught mid-frame cannot show the scene behind.
func _draw_backdrop() -> void:
	draw_rect(_field.grow(16.0), FLOOR_FAR)


## Depth as flat bands rather than a gradient texture: the base project draws
## everything procedurally, and ten quads cost nothing on the compatibility
## renderer.
##
## Quads and not rects, because the floor is the lane trapezoid now — the
## corners a full-width rect used to cover are wall, and painting them as floor
## is what made the old rail read as a flat backdrop with lines on it.
func _draw_floor() -> void:
	var bands := 10
	for index in range(bands):
		var top := float(index) / float(bands)
		var bottom := float(index + 1) / float(bands)
		draw_colored_polygon(
			PackedVector2Array([
				_edge_point(-1.0, top),
				_edge_point(1.0, top),
				_edge_point(1.0, bottom),
				_edge_point(-1.0, bottom),
			]),
			FLOOR_FAR.lerp(FLOOR_NEAR, bottom)
		)


## The floor's mirror image, riding on top of the walls. It is what turns two
## walls into a corridor: without it the frame is open at the top and the
## player is outdoors.
##
## The beams matter more than the shading does. A ceiling that is only a dark
## gradient is a dark gradient; beams give the top of the frame features at
## known depths, so the same parallax that sells the walls happens overhead as
## well, where a wide, short playfield leaves the walls very little room.
func _draw_ceiling() -> void:
	var bands := 10
	for index in range(bands):
		var top := float(index) / float(bands)
		var bottom := float(index + 1) / float(bands)
		draw_colored_polygon(
			PackedVector2Array([
				_wall_top(-1.0, top),
				_wall_top(1.0, top),
				_wall_top(1.0, bottom),
				_wall_top(-1.0, bottom),
			]),
			CEILING_FAR.lerp(CEILING_NEAR, bottom)
		)

	for index in range(BEAM_COUNT):
		var unit := fposmod(float(index) / float(BEAM_COUNT) + _scroll, 1.0)
		var progress := unit * unit
		draw_line(
			_wall_top(-1.0, progress),
			_wall_top(1.0, progress),
			Color(CEILING_BEAM, lerpf(0.0, 0.9, progress)),
			lerpf(1.0, 6.0, progress)
		)


## The pool of light the player stands in, falling off with distance.
##
## Bands over the floor rather than a texture or a shader, for the same reason
## the floor itself is bands: the base project draws procedurally and this has
## to run on the compatibility renderer.
func _draw_player_light() -> void:
	var bands := 8
	for index in range(bands):
		var top := lerpf(LIGHT_REACH, 1.0, float(index) / float(bands))
		var bottom := lerpf(LIGHT_REACH, 1.0, float(index + 1) / float(bands))
		draw_colored_polygon(
			PackedVector2Array([
				_edge_point(-1.0, top),
				_edge_point(1.0, top),
				_edge_point(1.0, bottom),
				_edge_point(-1.0, bottom),
			]),
			Color(LIGHT_COLOR, _light_at(bottom) * 0.6)
		)


## How lit a depth is, counting the flare from the last note played. Zero past
## [constant LIGHT_REACH], so the far end of the corridor is never touched by
## the player's own light and stays the dark thing distance is read against.
func _light_at(progress: float) -> float:
	if progress <= LIGHT_REACH:
		return 0.0
	var fall := inverse_lerp(LIGHT_REACH, 1.0, progress)
	return (LIGHT_REST + LIGHT_FLASH * _flash) * fall * fall


## Cross-ties, spaced by a square law so they crowd at the horizon and open out
## at the front. That non-linearity *is* the perspective — the trapezoid the
## lane spread already gives them does the rest.
func _draw_rungs() -> void:
	for index in range(RUNG_COUNT):
		var unit := fposmod(float(index) / float(RUNG_COUNT) + _scroll, 1.0)
		var progress := unit * unit
		var half_width := _half_width_at(progress)
		var y := _y_at(progress)
		var thickness := lerpf(1.0, 4.0, progress)
		draw_line(
			Vector2(_corridor.get_center().x - half_width, y),
			Vector2(_corridor.get_center().x + half_width, y),
			Color(RUNG_COLOR, lerpf(0.25, 0.8, progress)),
			thickness
		)


## The three lanes, drawn as their dividing edges rather than their centres:
## a bot walks down the middle of a lane, so an edge is the line it never
## crosses and a centre line would be something it permanently hides.
func _draw_lanes() -> void:
	draw_line(
		Vector2(_edge_point(-1.0, 0.0).x, _y_at(0.0)),
		Vector2(_edge_point(1.0, 0.0).x, _y_at(0.0)),
		Color(HORIZON_COLOR, 0.55),
		2.0
	)

	var steps := 12
	for edge in range(_lane_count + 1):
		var slot := float(edge) - float(_lane_count) * 0.5
		var points := PackedVector2Array()
		for step in range(steps + 1):
			var progress := float(step) / float(steps)
			points.append(_point_at(slot, progress))
		draw_polyline(points, Color(LANE_EDGE, 0.7), 2.0)


## The two walls, as panels rather than as one long polygon.
##
## A flat wall in a fixed perspective is indistinguishable from a painted
## backdrop, however well it is shaded — nothing on it moves. Panels give the
## surface features at known depths, and a feature at a known depth sweeping
## outwards and growing as it passes is the parallax the whole 2.5D read hangs
## on. It is also the only cue that survives a still screenshot being compared
## with the next one.
func _draw_walls() -> void:
	for side in [-1.0, 1.0]:
		_draw_wall_side(float(side))


func _draw_wall_side(side: float) -> void:
	var span := 1.0 / float(WALL_PANELS)
	# Panels are pinned to travelled distance, not to their index, so each one
	# holds still in the world and the camera moves past it. `cycle` counts the
	# panels that have already swept by, and `index - cycle` is a panel's own
	# name — which is why its shade does not flicker when it wraps.
	var offset := fposmod(_travelled, span)
	var cycle := int(floor(_travelled / span))

	for index in range(-1, WALL_PANELS):
		var near_unit := clampf(offset + float(index + 1) * span, 0.0, 1.0)
		var far_unit := clampf(offset + float(index) * span, 0.0, 1.0)
		var far_progress := far_unit * far_unit
		var near_progress := near_unit * near_unit
		# Guarded in depth, not in unit: the square law means a panel a
		# thousandth of a unit wide down at the horizon is a millionth of the
		# corridor deep, and a quad that thin is collinear by the time it
		# reaches the triangulator.
		if near_progress - far_progress < 0.0005:
			continue

		var shade := WALL_FAR.lerp(WALL_NEAR, near_progress)
		if posmod(index - cycle, 2) == 1:
			shade = shade.darkened(0.28)
		# The same light that pools on the floor has to reach the walls beside
		# it, or a hit lights the ground and leaves the room it is in dark.
		shade = shade.lerp(LIGHT_COLOR, _light_at(near_progress))

		var far_base := _edge_point(side, far_progress)
		var near_base := _edge_point(side, near_progress)
		draw_colored_polygon(
			PackedVector2Array([
				_wall_top(side, far_progress),
				_wall_top(side, near_progress),
				near_base,
				far_base,
			]),
			shade
		)
		# The seam at the panel's near edge, and the strip of floor it stands
		# on. The strip is the brighter of the two: a wall meeting a floor is
		# the line that tells the eye where the ground stops.
		draw_line(
			near_base,
			_wall_top(side, near_progress),
			Color(WALL_SEAM, lerpf(0.0, 0.35, near_progress)),
			lerpf(1.0, 3.0, near_progress)
		)
		draw_line(
			far_base,
			near_base,
			Color(WALL_SEAM, lerpf(0.1, 0.7, near_progress)),
			lerpf(1.0, 4.0, near_progress)
		)


## Dust piling up with distance. Drawn over the geometry and under the bots, so
## the far end of the corridor loses contrast the same way a far bot does.
func _draw_haze() -> void:
	var bands := 6
	for index in range(bands):
		var top := float(index) / float(bands)
		var bottom := float(index + 1) / float(bands)
		draw_rect(
			Rect2(
				Vector2(_field.position.x, _wall_top(-1.0, top).y),
				Vector2(_field.size.x, _y_at(bottom) - _wall_top(-1.0, top).y)
			),
			Color(HAZE, lerpf(0.3, 0.0, bottom) * 0.5)
		)


## Scrap in the middle distance while the rail travels. Deterministic from the
## index, so it needs no RNG state and looks the same every run — which matters
## because a screenshot of a rail advance should be reproducible.
func _draw_ambient() -> void:
	for index in range(AMBIENT_COUNT):
		var phase := float(index) * 0.137 + float(index % 3) * 0.21
		var unit := fposmod(phase + _scroll * 0.8, 1.0)
		var progress := unit * unit * 0.7
		# Kept inside the lane trapezoid: past it is wall now, and scrap
		# drifting through masonry is worse than no scrap at all.
		var slot := (float(index % 5) - 2.0) * 0.62
		var origin := _point_at(slot, progress)
		var size := lerpf(6.0, 26.0, progress)
		draw_rect(
			Rect2(origin - Vector2(size * 0.4, size), Vector2(size * 0.8, size)),
			Color(AMBIENT_COLOR, lerpf(0.2, 0.65, progress))
		)


## Where a bot's beat lands. The player is judged against arrival, so arrival
## is the one place on the floor that is marked (§6).
func _draw_strike_line() -> void:
	var y := _y_at(1.0)
	var half_width := _half_width_at(1.0)
	draw_line(
		Vector2(_corridor.get_center().x - half_width, y),
		Vector2(_corridor.get_center().x + half_width, y),
		Color(STRIKE_COLOR, 0.35),
		3.0
	)


## The projection [JamBot] walks, expressed in lane slots so half-slots give
## lane edges. `slot` 0 is the middle of the field.
func _point_at(slot: float, progress: float) -> Vector2:
	var spread := lerpf(JamBot.HORIZON_LANE_SPREAD, 1.0, progress)
	var lane_width := _corridor.size.x / float(_lane_count)
	return Vector2(
		_corridor.get_center().x + slot * lane_width * spread,
		_y_at(progress)
	)


## The outermost lane edge, which is also where the wall stands. `side` is -1
## for the left wall and 1 for the right.
func _edge_point(side: float, progress: float) -> Vector2:
	return _point_at(side * float(_lane_count) * 0.5, progress)


## The top of the wall at a depth — and, read across both sides, the ceiling.
## Clamped to the frame so the nearest panels stop at the top of the view
## instead of being drawn into the HUD above it.
func _wall_top(side: float, progress: float) -> Vector2:
	var base := _edge_point(side, progress)
	var height := (
		_corridor.size.y
		* WALL_HEIGHT
		* lerpf(WALL_HORIZON_SCALE, 1.0, progress)
	)
	return Vector2(base.x, maxf(base.y - height, _field.position.y))


func _y_at(progress: float) -> float:
	return lerpf(_corridor.position.y, _corridor.end.y, progress)


func _half_width_at(progress: float) -> float:
	var spread := lerpf(JamBot.HORIZON_LANE_SPREAD, 1.0, progress)
	return _corridor.size.x * 0.5 * spread
