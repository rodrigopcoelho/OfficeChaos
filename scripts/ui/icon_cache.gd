class_name IconCache
extends Node
## Inventory icons. Every item has baked 2D icon art in res://assets/icons/<id>.png
## (made by `godot --path . -- --icons`, see scripts/debug/icon_baker.gd); items
## without a baked icon fall back to a live render of their 3D model (once per id).

signal icon_ready(id: String)

const ICON_DIR := "res://assets/icons/"

var cache: Dictionary = {}
var _queue: Array[String] = []
var _busy := false
var _vp: SubViewport
var _holder: Node3D
var _cam: Camera3D
var disabled := false


func _ready() -> void:
	disabled = DisplayServer.get_name() == "headless"
	_vp = SubViewport.new()
	_vp.size = Vector2i(128, 128)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 0.95
	_vp.add_child(light)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.position = Vector3(0, 0, 10)
	_cam.size = 2.0
	_vp.add_child(_cam)
	_holder = Node3D.new()
	_vp.add_child(_holder)


func get_icon(id: String) -> Texture2D:
	if cache.has(id):
		return cache[id]
	var baked := _load_baked(id)
	if baked != null:
		cache[id] = baked
		return baked
	if disabled:
		return null
	if not id in _queue:
		_queue.append(id)
		_pump()
	return null


func _load_baked(id: String) -> Texture2D:
	var path := ICON_DIR + id + ".png"
	if ResourceLoader.exists(path):
		return load(path)
	# not imported yet (fresh bake): read the PNG directly
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var id: String = _queue.pop_front()
	var img: Image = await render_image(id, 128, 0.0)
	if img != null and not img.is_empty():
		cache[id] = ImageTexture.create_from_image(img)
		icon_ready.emit(id)
	_busy = false
	_pump()


func render_image(id: String, px: int, outline: float) -> Image:
	## Renders the item's 3D model into a transparent px x px image, framed to fit.
	## `outline` > 0 draws ink lines on the parts (used for the baked icon art).
	_vp.size = Vector2i(px, px)
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.free()
	_holder.transform = Transform3D.IDENTITY
	var d: Dictionary = DB.items.get(id, {})
	var vis: Dictionary = d.get("visual", {})
	var model := Node3D.new()
	_holder.add_child(model)
	var parts: Array = vis.get("parts", [])
	match str(d.get("slot", "")):
		"weapon":
			MeshFactory.build(parts, model, {}, outline)
			model.basis = Basis.looking_at(Vector3(1, 1, 0.25).normalized(), Vector3(0, 0, 1))
		"helmet":
			# authored in head units: shown on a faint head silhouette
			MeshFactory.shape(model, "head", Vector3(0.84, 0.76, 0.76), Vector3.ZERO, Color("#e8d8c8"), 0.0)
			var hn := Node3D.new()
			hn.scale = Vector3(0.84, 0.76, 0.76)
			model.add_child(hn)
			MeshFactory.build(parts, hn, {}, outline)
			model.rotation_degrees = Vector3(15, 200, 0)
		"legs", "boots":
			var col := MeshFactory.col(vis.get("color", "#888888"))
			for sx in [-1.0, 1.0]:
				var anchor := Node3D.new()
				model.add_child(anchor)
				if str(d.slot) == "legs":
					anchor.position = Vector3(sx * 0.15, 0.0, 0)
					MeshFactory.shape(anchor, "capsule", Vector3(0.24, 0.62, 0.25), Vector3.ZERO, col)
					MeshFactory.box(model, Vector3(0.56, 0.12, 0.28), Vector3(0, 0.3, 0), col.darkened(0.15), 0.0, 0.0)
				else:
					anchor.position = Vector3(sx * 0.19, 0.0, 0)
					MeshFactory.shape(anchor, "dome", Vector3(0.3, 0.24, 0.44), Vector3.ZERO, col)
					MeshFactory.box(anchor, Vector3(0.31, 0.06, 0.45), Vector3(0, -0.13, 0), MeshFactory.col(vis.get("sole", col.darkened(0.45))), 0.0, 0.0)
				var pa := Node3D.new()
				pa.scale = Vector3.ONE * 1.25
				anchor.add_child(pa)
				MeshFactory.build(parts, pa, {}, outline)
			model.rotation_degrees = Vector3(18, 210, 0)
		"chest":
			MeshFactory.box(model, Vector3(0.62, 0.7, 0.38), Vector3(0, 0, 0), MeshFactory.col(vis.get("torso_color", "#888888")), 0.0, 0.0)
			MeshFactory.box(model, Vector3(0.09, 0.42, 0.03), Vector3(0, 0.02, 0.2), Color("#7a2e2e"), 0.0, 0.0)
			var top := Node3D.new()
			top.position.y = 0.35
			model.add_child(top)
			MeshFactory.build(parts, top, {}, outline)
			model.rotation_degrees = Vector3(12, 200, 0)
		_:
			if parts.is_empty() or vis.has("ring_color"):
				MeshFactory.shape(model, "torus", Vector3(0.6, 0.1, 0.6), Vector3.ZERO, MeshFactory.col(vis.get("ring_color", "#ffcc33")), 0.6, Vector3(70, 0, 20))
				if not parts.is_empty():
					MeshFactory.build(parts, model, {}, outline)
					for c in model.get_children():
						if c is MeshInstance3D and c.mesh is SphereMesh:
							c.position = Vector3(0, 0.3, 0)
			else:
				MeshFactory.build(parts, model, {}, outline)
				model.rotation_degrees = Vector3(20, 150, 0)
	var aabb := AABB()
	var first := true
	for mi in _all_meshes(model):
		var box: AABB = mi.global_transform * mi.get_aabb()
		aabb = box if first else aabb.merge(box)
		first = false
	if not first:
		_holder.position = -aabb.get_center()
		_cam.size = maxf(maxf(aabb.size.x, aabb.size.y), 0.3) * 1.25
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
