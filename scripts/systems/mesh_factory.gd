class_name MeshFactory
extends RefCounted
## Builds chunky toon meshes from JSON-friendly part descriptions:
## {"shape": "box|softbox|sphere|cyl|cone|gem|torus|capsule|dome|head|blazer", "size": [x,y,z], "pos": [x,y,z], "rot": [deg,deg,deg],
##  "color": "#hex" or palette token, "emit": energy, "emit_color": "#hex", "group": "arm_l", "name": "screen"}
## Shapes come from the Blender mesh kit (assets/meshes/kit.glb); materials are cached
## and described in _mat_info so MeshBatcher can merge parts into a few draw calls.

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/outline.gdshader")
const KIT_PATH := "res://assets/meshes/kit.glb"
const INK := Color("#1f1726")

static var _kit: Dictionary = {}
static var _kit_loaded := false
static var _materials: Dictionary = {}
static var _mat_info: Dictionary = {}
static var _meshes: Dictionary = {}
static var _glow: Dictionary = {}
static var _unlit: Dictionary = {}
static var _outlines: Dictionary = {}


static func col(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if v is Color:
		return v
	if v is String:
		var s: String = v
		if Color.html_is_valid(s):
			return Color.html(s)
		return fallback
	if v is Array and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)
	return fallback


static func vec3(v: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if v is Vector3:
		return v
	if v is Array:
		var a: Array = v
		if a.size() >= 3:
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if a.size() == 1:
			return Vector3.ONE * float(a[0])
	if v is float or v is int:
		return Vector3.ONE * float(v)
	return fallback


static func clay(color: Color, emit: float = 0.0, outline: float = 0.03, fade: bool = false, emit_color: Variant = null, unique: bool = false) -> ShaderMaterial:
	## Flat toon material. `outline` is the ink line width in metres (0 = no line).
	## `fade` dithers the surface away when it hides the player (walls); those are
	## hard-edged BoxMeshes, so their outline extrudes in box mode.
	## `unique` materials are never cached (callers animate their parameters) and
	## therefore never batched.
	var ec: Color = color if emit_color == null else col(emit_color, color)
	var width := 0.0 if outline <= 0.001 else clampf(outline, 0.022, 0.05)
	var key := "%s|%s|%.2f|%.3f|%s" % [color.to_html(), ec.to_html(), emit, width, fade]
	if not unique and _materials.has(key):
		return _materials[key]
	var m := ShaderMaterial.new()
	m.shader = TOON_SHADER
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("emission", ec)
	m.set_shader_parameter("emission_energy", emit)
	m.set_shader_parameter("occlude_fade", 1.0 if fade else 0.0)
	if width > 0.0:
		m.next_pass = outline_pass(width, fade)
	if not unique:
		_materials[key] = m
		_mat_info[m] = {"albedo": color, "emit_color": ec, "emit": emit, "width": width, "fade": fade}
	return m


static func outline_pass(width: float, fade: bool = false) -> ShaderMaterial:
	## Shared ink-line pass (next_pass) for toon-style materials, `width` in metres.
	var key := "%.3f|%s" % [width, fade]
	if _outlines.has(key):
		return _outlines[key]
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter("ink", INK)
	o.set_shader_parameter("width", width)
	o.set_shader_parameter("box_mode", 1.0 if fade else 0.0)
	o.set_shader_parameter("occlude_fade", 1.0 if fade else 0.0)
	_outlines[key] = o
	return o


static func material_info(m: Material) -> Dictionary:
	## Parameters of a shared toon material, or {} for anything MeshBatcher must not merge.
	return _mat_info.get(m, {})


static func kit_mesh(shape_name: String) -> Mesh:
	## Rounded unit meshes built in Blender (tools/blender/build_mesh_kit.py).
	if not _kit_loaded:
		_kit_loaded = true
		if ResourceLoader.exists(KIT_PATH):
			var scene: PackedScene = load(KIT_PATH)
			if scene:
				var inst := scene.instantiate()
				for n in inst.find_children("*", "MeshInstance3D", true, false):
					_kit[str(n.name)] = (n as MeshInstance3D).mesh
				inst.free()
		if _kit.is_empty():
			push_warning("[MeshFactory] Mesh kit missing, using built-in primitives")
	return _kit.get(shape_name)


static func kit_instance(shape_name: String, size: Vector3) -> MeshInstance3D:
	## A MeshInstance3D of a kit shape scaled to `size` (falls back to primitives).
	var mi := MeshInstance3D.new()
	var key := "box" if shape_name in ["box", ""] else shape_name
	var m := kit_mesh(key)
	if m != null:
		mi.mesh = m
		mi.scale = Vector3(maxf(size.x, 0.001), maxf(size.y, 0.001), maxf(size.z, 0.001))
	else:
		mi.mesh = mesh_for(shape_name, size)
	return mi


static func line_width(size: Vector3, requested: float) -> float:
	## Tiny details (eyes, LEDs, buttons) get no ink line.
	if requested <= 0.001 or size.x + size.y + size.z < 0.33 or minf(size.x, minf(size.y, size.z)) < 0.012:
		return 0.0
	return requested


static func unlit(color: Color, additive: bool = false, no_depth: bool = false) -> StandardMaterial3D:
	## A fresh unshaded material (callers fade its alpha individually).
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = no_depth
	m.disable_receive_shadows = true
	return m


static func unlit_shared(color: Color, additive: bool = false, no_depth: bool = false, priority: int = 0) -> StandardMaterial3D:
	## Cached unshaded material for things whose colour never changes (HP bars, beams).
	var key := "%s|%s|%s|%d" % [color.to_html(), additive, no_depth, priority]
	if _unlit.has(key):
		return _unlit[key]
	var m := unlit(color, additive, no_depth)
	m.render_priority = priority
	_unlit[key] = m
	return m


static func glow(color: Color, energy: float = 3.0) -> StandardMaterial3D:
	var key := "%s|%.1f" % [color.to_html(), energy]
	if _glow.has(key):
		return _glow[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_receive_shadows = true
	_glow[key] = m
	return m


static func unit_box() -> BoxMesh:
	## 1x1x1 box for things sized through node scale (keeps the mesh cache bounded).
	return mesh_for("box", Vector3.ONE) as BoxMesh


static func mesh_for(shape: String, size: Vector3) -> Mesh:
	## Built-in primitives, cached by shape+size. Only call this with a bounded set of
	## sizes (constants or data values); random sizes should scale unit_box() instead.
	var key := "%s|%s" % [shape, size]
	if _meshes.has(key):
		return _meshes[key]
	var m: Mesh
	match shape:
		"capsule":
			var cp := CapsuleMesh.new()
			cp.radius = minf(size.x, size.z) * 0.5
			cp.height = maxf(size.y, cp.radius * 2.0)
			m = cp
		"blazer":
			var bz := CylinderMesh.new()
			bz.top_radius = size.x * 0.4
			bz.bottom_radius = size.x * 0.5
			bz.height = size.y
			m = bz
		"sphere", "head", "dome":
			var s := SphereMesh.new()
			s.radius = size.x * 0.5
			s.height = size.y
			s.radial_segments = 8
			s.rings = 5
			m = s
		"gem":
			var g := SphereMesh.new()
			g.radius = size.x * 0.5
			g.height = size.y
			g.radial_segments = 4
			g.rings = 2
			m = g
		"cyl":
			var c := CylinderMesh.new()
			c.top_radius = size.x * 0.5
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 8
			c.rings = 1
			m = c
		"cone":
			var k := CylinderMesh.new()
			k.top_radius = 0.0
			k.bottom_radius = size.x * 0.5
			k.height = size.y
			k.radial_segments = 8
			k.rings = 1
			m = k
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = size.x * 0.5 - size.y
			t.outer_radius = size.x * 0.5
			t.rings = 12
			t.ring_segments = 6
			m = t
		_:
			var b := BoxMesh.new()
			b.size = size
			m = b
	_meshes[key] = m
	return m


static func resolve_color(v: Variant, palette: Dictionary) -> Color:
	if v is String and palette.has(v):
		return col(palette[v])
	return col(v)


static func build(parts: Array, parent: Node3D, palette: Dictionary = {}, outline: float = 0.03, groups_def: Dictionary = {}, shadows: bool = true, merge: bool = false) -> Dictionary:
	## Returns {group_name: Node3D, "#part_name": MeshInstance3D}.
	## With merge = true the parts of each group are combined by MeshBatcher into one
	## mesh (named parts stay separate so callers can still animate/recolour them).
	var out: Dictionary = {}
	var named: Array = []
	for gname in groups_def:
		var g := Node3D.new()
		g.name = str(gname)
		g.position = vec3(groups_def[gname].get("pivot", [0, 0, 0]))
		parent.add_child(g)
		out[str(gname)] = g
	for p in parts:
		var pd: Dictionary = p
		var psize := vec3(pd.get("size", [0.5, 0.5, 0.5]), Vector3.ONE * 0.5)
		var mi := kit_instance(str(pd.get("shape", "box")), psize)
		var emit := float(pd.get("emit", 0.0))
		var line := line_width(psize, float(pd.get("outline", outline)))
		mi.material_override = clay(resolve_color(pd.get("color", "#ffffff"), palette), emit, line, false, pd.get("emit_color", null))
		mi.rotation_degrees = vec3(pd.get("rot", [0, 0, 0]))
		if not shadows or emit > 0.0:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var pos := vec3(pd.get("pos", [0, 0, 0]))
		var gname := str(pd.get("group", ""))
		var target: Node3D = parent
		if gname != "":
			if not out.has(gname):
				var g2 := Node3D.new()
				g2.name = gname
				parent.add_child(g2)
				out[gname] = g2
			target = out[gname]
			pos -= target.position
		mi.position = pos
		target.add_child(mi)
		if pd.has("name"):
			out["#" + str(pd.name)] = mi
			named.append(mi)
	if merge:
		MeshBatcher.merge_children(parent, named)
		for k in out:
			if out[k] is Node3D and not out[k] is MeshInstance3D:
				MeshBatcher.merge_children(out[k], named)
	return out


static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emit: float = 0.0, outline: float = 0.04, fade: bool = false) -> MeshInstance3D:
	var mi := kit_instance("box", size)
	mi.material_override = clay(color, emit, line_width(size, outline), fade)
	mi.position = pos
	if emit > 0.0:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


static func shape(parent: Node3D, kind: String, size: Vector3, pos: Vector3, color: Color, emit: float = 0.0, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := kit_instance(kind, size)
	mi.material_override = clay(color, emit, line_width(size, 0.03))
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


static func sector_mesh(radius: float, arc_deg: float, inner: float = 0.0, segments: int = 24) -> ArrayMesh:
	var key := "sector|%.2f|%.1f|%.2f|%d" % [radius, arc_deg, inner, segments]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a0 := -deg_to_rad(arc_deg) * 0.5
	var step := deg_to_rad(arc_deg) / segments
	for i in segments:
		var a := a0 + step * i
		var b := a + step
		var o1 := Vector3(sin(a), 0, -cos(a)) * radius
		var o2 := Vector3(sin(b), 0, -cos(b)) * radius
		var i1 := Vector3(sin(a), 0, -cos(a)) * inner
		var i2 := Vector3(sin(b), 0, -cos(b)) * inner
		for v in [i1, o1, o2, i1, o2, i2]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var m := st.commit()
	_meshes[key] = m
	return m


static func ring_mesh(inner: float, outer: float, segments: int = 40) -> ArrayMesh:
	return sector_mesh(outer, 360.0, inner, segments)
