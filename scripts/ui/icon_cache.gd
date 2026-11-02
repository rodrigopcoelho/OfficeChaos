class_name IconCache
extends Node
## Renders item meshes into small textures (once per item id) for inventory cards.

signal icon_ready(id: String)

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
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = env
	_vp.add_child(we)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -35, 0)
	light.light_energy = 1.3
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
	if disabled:
		return null
	if not id in _queue:
		_queue.append(id)
		_pump()
	return null


func _pump() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var id: String = _queue.pop_front()
	await _render(id)
	_busy = false
	_pump()


func _render(id: String) -> void:
	for c in _holder.get_children():
		_holder.remove_child(c)
		c.free()
	_holder.transform = Transform3D.IDENTITY
	var d: Dictionary = DB.items.get(id, {})
	var vis: Dictionary = d.get("visual", {})
	var model := Node3D.new()
	_holder.add_child(model)
	match str(d.get("slot", "")):
		"weapon":
			MeshFactory.build(vis.get("parts", []), model, {}, 0.0)
			model.basis = Basis.looking_at(Vector3(1, 1, 0.25).normalized(), Vector3(0, 0, 1))
		"armor":
			MeshFactory.box(model, Vector3(0.62, 0.7, 0.38), Vector3(0, 0, 0), MeshFactory.col(vis.get("torso_color", "#888888")), 0.0, 0.0)
			MeshFactory.box(model, Vector3(0.09, 0.42, 0.03), Vector3(0, 0.02, 0.2), Color("#7a2e2e"), 0.0, 0.0)
			var top := Node3D.new()
			top.position.y = 0.35
			model.add_child(top)
			MeshFactory.build(vis.get("parts", []), top, {}, 0.0)
			model.rotation_degrees = Vector3(12, 200, 0)
		_:
			if (vis.get("parts", []) as Array).is_empty() or vis.has("ring_color"):
				MeshFactory.shape(model, "torus", Vector3(0.6, 0.1, 0.6), Vector3.ZERO, MeshFactory.col(vis.get("ring_color", "#ffcc33")), 0.6, Vector3(70, 0, 20))
				if not (vis.get("parts", []) as Array).is_empty():
					MeshFactory.build(vis.get("parts", []), model, {}, 0.0)
					for c in model.get_children():
						if c is MeshInstance3D and c.mesh is SphereMesh:
							c.position = Vector3(0, 0.3, 0)
			else:
				MeshFactory.build(vis.get("parts", []), model, {}, 0.0)
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
	var img := _vp.get_texture().get_image()
	if img != null and not img.is_empty():
		cache[id] = ImageTexture.create_from_image(img)
		icon_ready.emit(id)


func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out
