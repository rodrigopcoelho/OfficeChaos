class_name MeshBatcher
extends RefCounted
## Merges many toon-shaded parts into one vertex-coloured mesh.
## Albedo, emission and ink-line width move from per-material uniforms into vertex
## attributes (COLOR, UV, UV2), so a whole room — or a whole character limb — renders
## in one draw call plus one outline pass instead of one pair per part. Normals are
## transformed with the inverse-transpose so scaled kit shapes shade exactly as before.

const EMIT_SCALE := 4.0  # COLOR.a stores emission energy / EMIT_SCALE (see toon.gdshader)

static var _arrays: Dictionary = {}
static var _batch_mats: Dictionary = {}

var verts := PackedVector3Array()
var normals := PackedVector3Array()
var colors := PackedColorArray()
var uv := PackedVector2Array()
var uv2 := PackedVector2Array()
var indices := PackedInt32Array()
var count := 0


static func material(fade: bool) -> ShaderMaterial:
	## Shared material for every batched mesh (fade = wall dithering near the player).
	if _batch_mats.has(fade):
		return _batch_mats[fade]
	var m := ShaderMaterial.new()
	m.shader = MeshFactory.TOON_SHADER
	m.set_shader_parameter("vertex_colors", 1.0)
	m.set_shader_parameter("occlude_fade", 1.0 if fade else 0.0)
	var o := ShaderMaterial.new()
	o.shader = MeshFactory.OUTLINE_SHADER
	o.set_shader_parameter("ink", MeshFactory.INK)
	o.set_shader_parameter("vertex_mode", 1.0)
	o.set_shader_parameter("occlude_fade", 1.0 if fade else 0.0)
	m.next_pass = o
	_batch_mats[fade] = m
	return m


static func can_batch(mi: MeshInstance3D) -> bool:
	if mi == null or mi.mesh == null or not mi.visible or mi.has_meta("no_batch"):
		return false
	if mi.material_overlay != null or mi.mesh.get_surface_count() != 1:
		return false
	var info := MeshFactory.material_info(mi.material_override)
	if info.is_empty():
		return false
	# Emission is reconstructed as albedo * energy, so a different glow colour can't merge.
	return float(info.emit) <= 0.0 or (info.emit_color as Color).is_equal_approx(info.albedo)


static func _mesh_arrays(m: Mesh) -> Array:
	## [vertices, normals, indices] of a single-surface mesh (cached for shared meshes).
	if _arrays.has(m):
		return _arrays[m]
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
	var idx: PackedInt32Array
	if a[Mesh.ARRAY_INDEX] != null:
		idx = a[Mesh.ARRAY_INDEX]
	else:
		idx = PackedInt32Array(range(v.size()))
	if n.size() != v.size():
		n = PackedVector3Array()
		n.resize(v.size())
		n.fill(Vector3.UP)
	var out := [v, n, idx]
	_arrays[m] = out
	return out


func add(mi: MeshInstance3D, xf: Transform3D) -> void:
	## Appends `mi` (a can_batch() mesh) transformed by `xf` into this batch.
	var info := MeshFactory.material_info(mi.material_override)
	var albedo: Color = info.albedo
	var tint := Color(albedo.r, albedo.g, albedo.b, clampf(float(info.emit) / EMIT_SCALE, 0.0, 1.0))
	_append(mi.mesh, xf, tint, float(info.width), bool(info.fade))


func add_raw(m: Mesh, xf: Transform3D) -> void:
	## Geometry only, for meshes that keep their own (non-toon) material: glow LEDs, glass.
	_append(m, xf, Color.WHITE, 0.0, false)


func _append(m: Mesh, xf: Transform3D, tint: Color, w: float, boxed: bool) -> void:
	var a := _mesh_arrays(m)
	var v: PackedVector3Array = a[0]
	var n: PackedVector3Array = a[1]
	var idx: PackedInt32Array = a[2]
	var nv := v.size()
	var base := verts.size()
	verts.append_array(xf * v)
	var nxf := Transform3D(xf.basis.inverse().transposed(), Vector3.ZERO)
	var tn: PackedVector3Array = nxf * n
	for i in nv:
		tn[i] = tn[i].normalized()
	normals.append_array(tn)
	var c := PackedColorArray()
	c.resize(nv)
	c.fill(tint)
	colors.append_array(c)
	var u := PackedVector2Array()
	u.resize(nv)
	var u2 := PackedVector2Array()
	u2.resize(nv)
	if boxed and w > 0.0:
		# Hard-edged wall boxes extrude along sign(local vertex), like the unbatched shader.
		for i in nv:
			var d: Vector3 = xf.basis * v[i].sign()
			u[i] = Vector2(-w, d.y)
			u2[i] = Vector2(d.x, d.z)
	else:
		u.fill(Vector2(w, 0.0))
	uv.append_array(u)
	uv2.append_array(u2)
	var shifted := idx.duplicate()
	for i in shifted.size():
		shifted[i] += base
	indices.append_array(shifted)
	count += 1


func commit() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = indices
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func instance(fade: bool, shadows: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = commit()
	mi.material_override = material(fade)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func merge_children(node: Node3D, exclude: Array = []) -> void:
	## Replaces the batchable direct MeshInstance3D children of `node` with a single
	## mesh. Used for characters/props whose groups move as a whole. (Splitting by
	## shadow mode doubled the draw calls just to stop tiny glowing bits casting
	## shadows nobody can see.)
	var batch := MeshBatcher.new()
	var merged: Array = []
	var shadows := false
	for c in node.get_children():
		if c is MeshInstance3D and not c in exclude and can_batch(c):
			batch.add(c, (c as MeshInstance3D).transform)
			merged.append(c)
			shadows = shadows or (c as MeshInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if merged.size() < 2:
		return
	for c in merged:
		node.remove_child(c)
		c.queue_free()
	node.add_child(batch.instance(false, shadows))


static func clear_cache() -> void:
	_arrays.clear()
