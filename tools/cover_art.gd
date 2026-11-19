extends RefCounted

## Real combat chassis on an industrial gig poster; music and combat never start.
const Helpers = preload("res://tools/cover_art_helpers.gd")
const Drone = preload("res://games/dead_metal_jam/enemies/drone_3d.gd")
const Rusty = preload("res://games/dead_metal_jam/enemies/rusty_clanky.gd")
const Conductor = preload("res://games/dead_metal_jam/enemies/conductor.gd")


## Amber stage cuts and bold lettering keep the metal logo's original icon intact.
static func design() -> Dictionary:
	return {
		"paper": Color("15222b"), "ink": Color("f8ecd3"), "accent": Color("e5a348"),
		"motif": "metal", "camera": Vector3(-13, 7, -6),
		"photo": Rect2(-15, 270, 1054, 620),
		"lettering": [
			{"text": "DEAD METAL", "at": Vector2(55, 163), "size": 168, "angle": -2},
			{"text": "JAM", "at": Vector2(52, 1010), "size": 193, "color": Color("e5a348")},
			{"text": "PLAY THE NOTE.", "at": Vector2(437, 932), "size": 36, "font": "mono"},
			{"text": "BREAK THE BOT.", "at": Vector2(437, 981), "size": 36, "font": "mono"},
		],
	}


## The hidden 2D combat sources only supply each chassis' normal public presentation.
static func build(parent: Node) -> Node:
	var root := Helpers.group(parent)
	for index in 2:
		var source: JamBot = Rusty.new() if index == 0 else Conductor.new()
		root.add_child(source)
		source.hide()
		source.required_note = 7 if index == 0 else 0
		var drone := Drone.new()
		root.add_child(drone)
		drone.configure(source)
		drone.position = Vector3(-1.1, 0, 0.7) if index == 0 else Vector3(1.3, 0.3, -0.6)
		drone.scale = Vector3.ONE * (1.0 if index == 0 else 0.75)
		drone.rotation_degrees.y = -12 if index == 0 else 16
		for key in ["_nameplate", "_attack_back", "_attack_fill"]:
			(drone.get(key) as Node3D).hide()
	return root
