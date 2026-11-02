extends Node
## Renders reference sheets of the character art and quits (needs a window, not --headless):
##   godot --path . -- --chars
## Saves user://char_sheet/*.png: every hairstyle, every face, the expressions and
## body/palette combinations (front, orthographic), plus the same lineup from the game
## camera's angle and distance ("top") and at 2x zoom ("top_zoom"), and the four
## Lobby service desks with their NPCs ("stations"). Lobby lighting.

const OUT := "user://char_sheet"
const ROW_H := 2.0

var _root: Node3D
var _cam: Camera3D
var _floor: MeshInstance3D


func _ready() -> void:
	var ui: CanvasLayer = GameState.main.ui
	ui.visible = false
	_root = Node3D.new()
	add_child(_root)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#d9d3e8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a58ed8")
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	_root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = 0.45
	sun.light_color = Color("#fff1d6")
	sun.shadow_enabled = true
	_root.add_child(sun)
	_floor = MeshInstance3D.new()
	_floor.mesh = MeshFactory.unit_box()
	_floor.scale = Vector3(40, 0.1, 40)
	_floor.position.y = -0.05
	_floor.material_override = MeshFactory.clay(Color("#c9c0aa"), 0.0, 0.0)
	_root.add_child(_floor)
	_cam = Camera3D.new()
	_root.add_child(_cam)
	_cam.make_current()
	DirAccess.make_dir_recursive_absolute(OUT)
	await _run()
	get_tree().quit()


func _run() -> void:
	var n_hair: int = (DB.appearance.get("hair_styles", []) as Array).size()
	var n_face: int = (DB.appearance.get("faces", []) as Array).size()
	var n_pal: int = (DB.appearance.get("palettes", []) as Array).size()
	var list: Array = []
	for i in n_hair:
		list.append({"body": 0, "hair": i, "face": i % n_face, "palette": i % n_pal})
	await _front("hair", list, 6, 0.35)
	list = []
	for i in n_face:
		list.append({"body": 0, "hair": 0, "face": i, "palette": (i + 3) % n_pal})
	await _front("faces", list, 5, 0.0)
	list = []
	for m in ["neutral", "blink", "happy", "hurt", "ko"]:
		list.append({"body": 2, "hair": 3, "face": 1, "palette": 5, "mood": m})
	await _front("moods", list, 5, 0.0)
	list = []
	for i in 10:
		list.append({"body": i % 5, "hair": (i * 3) % n_hair, "face": (i * 2) % n_face, "palette": i % n_pal, "equip": i % 2 == 0})
	await _front("bodies", list, 5, 0.5)
	await _top("top", list, 1.0)
	await _top("top_zoom", list, 0.5)
	await _stations()


func _clear() -> void:
	for c in _root.get_children():
		if c is CharacterVisual or c is Station:
			_root.remove_child(c)
			c.queue_free()


func _spawn(list: Array, cols: int, spacing: float, on_floor: bool, turn: float) -> void:
	_clear()
	for i in list.size():
		var app: Dictionary = list[i]
		var v := CharacterVisual.new()
		_root.add_child(v)
		v.build(app)
		var x := (i % cols - (cols - 1) * 0.5) * spacing
		var row := i / cols
		v.position = Vector3(x, 0, row * spacing) if on_floor else Vector3(x, -row * ROW_H, 0)
		v.rotation.y = PI + turn
		if app.get("equip", false):
			v.set_equipment({"id": "intern_shortsword", "plus": 0}, {"id": "business_casual_mail", "plus": 0}, {})
		match str(app.get("mood", "")):
			"blink":
				v._face_mat.set_shader_parameter("blink", 1.0)
				v.mood = "frozen"  # stops the blink animation from reopening the eyes
			"happy", "hurt", "ko":
				v.express(str(app.mood))


func _front(sheet_name: String, list: Array, cols: int, turn: float) -> void:
	## Orthographic front view, rows stacked vertically like a sprite sheet.
	_floor.visible = false
	var spacing := 1.45
	_spawn(list, cols, spacing, false, turn)
	var rows := ceili(list.size() / float(cols))
	var top := 1.8
	var bottom := -(rows - 1) * ROW_H - 0.1
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = maxf(top - bottom + 0.3, (cols * spacing + 0.2) * 9.0 / 16.0)
	_cam.rotation = Vector3(deg_to_rad(-8.0), 0, 0)
	_cam.position = Vector3(0, (top + bottom) * 0.5 + 10.0 * tan(deg_to_rad(8.0)), 10.0)
	await _shoot(sheet_name)


func _top(sheet_name: String, list: Array, zoom: float) -> void:
	## The game camera (fov 40, looking down ~56 degrees from 18 m) over the lineup.
	_floor.visible = true
	_spawn(list, 5, 1.5, true, 0.5)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_cam.rotation = Vector3(-atan2(15.0, 10.2), 0, 0)
	_cam.position = Vector3(0, 0, 0.75) + Vector3(0, 15.0, 10.2) * zoom
	await _shoot(sheet_name)


func _stations() -> void:
	_clear()
	_floor.visible = true
	var defs: Dictionary = DB.levels.get("hub", {}).get("stations", {})
	var i := 0
	for key in defs:
		var sd: Dictionary = defs[key]
		var st := Station.new()
		st.tab = str(sd.get("tab", "shop"))
		st.station_name = str(sd.get("name", "Desk"))
		st.title = str(sd.get("title", "SERVICE"))
		st.npc = sd.get("npc", {})
		st.position = Vector3((i - (defs.size() - 1) * 0.5) * 4.6, 0, 0)
		_root.add_child(st)
		i += 1
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	_cam.fov = 40.0
	_cam.rotation = Vector3(-atan2(15.0, 10.2), 0, 0)
	_cam.position = Vector3(0, 0, 0.5) + Vector3(0, 15.0, 10.2) * 0.85
	await _shoot("stations")


func _shoot(sheet_name: String) -> void:
	for f in 6:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, sheet_name]
	img.save_png(path)
	print("[CHARS] ", ProjectSettings.globalize_path(path))
