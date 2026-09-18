class_name DmjMeshKit
extends RefCounted

## Low-poly, lit geometry shared by the rooms, robots and weapon effects.
static var _materials: Dictionary[String, StandardMaterial3D] = {}


static func material(color: Color, luminous := false) -> StandardMaterial3D:
	var key := "%s:%s" % [color.to_html(), luminous]
	if not _materials.has(key):
		var surface := StandardMaterial3D.new()
		surface.albedo_color = color
		surface.roughness = 0.72
		surface.metallic = 0.35 if not luminous else 0.0
		if luminous:
			surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			surface.emission_enabled = true
			surface.emission = color
		_materials[key] = surface
	return _materials[key]


static func mesh(
	parent: Node3D, shape: Mesh, at: Vector3, color: Color, luminous := false
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = shape
	instance.material_override = material(color, luminous)
	instance.position = at
	if luminous:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


static func box(
	parent: Node3D, dimensions: Vector3, at: Vector3, color: Color, luminous := false
) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = dimensions
	return mesh(parent, shape, at, color, luminous)


static func cylinder(
	parent: Node3D, radius: float, height: float, at: Vector3, color: Color,
	luminous := false, top_radius := -1.0
) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.bottom_radius = radius
	shape.top_radius = radius if top_radius < 0.0 else top_radius
	shape.height = height
	shape.radial_segments = 16
	return mesh(parent, shape, at, color, luminous)


static func sphere(
	parent: Node3D, radius: float, at: Vector3, color: Color, luminous := false
) -> MeshInstance3D:
	var shape := SphereMesh.new()
	shape.radius = radius
	shape.height = radius * 2.0
	shape.radial_segments = 16
	shape.rings = 8
	return mesh(parent, shape, at, color, luminous)


static func ring(
	parent: Node3D, radius: float, thickness: float, at: Vector3, color: Color
) -> MeshInstance3D:
	var shape := TorusMesh.new()
	shape.inner_radius = maxf(radius - thickness, 0.01)
	shape.outer_radius = radius + thickness
	shape.rings = 32
	shape.ring_segments = 8
	return mesh(parent, shape, at, color, true)


static func beam(
	parent: Node3D, from: Vector3, to: Vector3, width: float, color: Color,
	luminous := true
) -> MeshInstance3D:
	var direction := to - from
	var instance := cylinder(
		parent, width, maxf(direction.length(), 0.001), (from + to) * 0.5, color, luminous
	)
	if direction.length_squared() > 0.000001:
		instance.quaternion = Quaternion(Vector3.UP, direction.normalized())
	return instance


static func label(
	parent: Node3D, text: String, at: Vector3, font_size := 48, color := Color.WHITE
) -> Label3D:
	var caption := Label3D.new()
	caption.text = text
	caption.position = at
	caption.font_size = font_size
	caption.pixel_size = 0.008
	caption.outline_size = 8
	caption.modulate = color
	caption.outline_modulate = DmjPalette.INK
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.shaded = false
	parent.add_child(caption)
	return caption
