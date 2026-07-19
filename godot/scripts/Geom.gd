## Procedural geometry helpers — the Godot equivalent of the web build's
## box / cyl / sph / cone / grp / mat primitives. Everything in this game is
## built from these; there are no imported art assets.
class_name Geom
extends RefCounted

# Material cache keyed by 0xRRGGBB int, mirroring the JS MAT{} cache.
static var _mat_cache: Dictionary = {}

## Lambert-ish material for a 0xRRGGBB color (matches MeshLambertMaterial look:
## fully rough, no metallic/specular).
static func mat(color: int) -> StandardMaterial3D:
	if not _mat_cache.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.hex((color << 8) | 0xff)
		m.roughness = 1.0
		m.metallic = 0.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mat_cache[color] = m
	return _mat_cache[color]

## Translucent material for windows / fireplace glass (three.js
## MeshLambertMaterial with transparent:true, opacity:o).
static func translucent(color: int, opacity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.hex((color << 8) | 0xff)
	m.albedo_color.a = opacity
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return m

## Torus (donut) primitive — the equivalent of three.js TorusGeometry(radius, tube)
## and (approximately) TorusKnotGeometry. inner = radius - tube, outer = radius + tube.
static func torus(radius: float, tube: float, color: int, x: float, y: float, z: float, parent: Node3D) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 12
	mesh.ring_segments = 8
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi

## A transparent, unlit material used for invisible click hit-pads.
static func _hit_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0, 0, 0, 0)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	return m

static func box(w: float, h: float, d: float, color: int, x: float, y: float, z: float, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, h, d)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi

static func cyl(rt: float, rb: float, h: float, color: int, x: float, y: float, z: float, parent: Node3D, seg: int = 10) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = rt
	mesh.bottom_radius = rb
	mesh.height = h
	mesh.radial_segments = seg
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi

static func sph(r: float, color: int, x: float, y: float, z: float, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 8
	mesh.rings = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi

static func cone(r: float, h: float, color: int, x: float, y: float, z: float, parent: Node3D, seg: int = 8) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = r
	mesh.height = h
	mesh.radial_segments = seg
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(color)
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi

## A grouping node (three.js Group -> Node3D).
static func grp(x: float, y: float, z: float, parent: Node3D) -> Node3D:
	var g := Node3D.new()
	g.position = Vector3(x, y, z)
	parent.add_child(g)
	return g

## Invisible padded sphere hitbox so tiny interactables are easy to click.
static func hit_pad(parent: Node3D, r: float, x: float = 0.0, y: float = 0.12, z: float = 0.0) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = r
	mesh.height = r * 2.0
	mesh.radial_segments = 6
	mesh.rings = 5
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _hit_mat()
	mi.position = Vector3(x, y, z)
	parent.add_child(mi)
	return mi
