class_name OfficeSprawl
extends RefCounted
## The office that never ends: around every level the floor plan keeps going as an
## inaccessible, unlit office (the walls keep the player in). Bays of cubicles,
## meeting rooms, lounges, storage and server rows sit on a grid with structural
## pillars, getting darker with distance until they fade into the level's
## "sprawl_dark" colour, so the playable floor reads as one lit corner of a huge
## building. Everything goes under GameWorld.sprawl_root (merged into big chunks,
## no shadows, no collision); only monitor screens keep a faint glow.
## Configure per level with "sprawl": {"bays": {type: weight}, "reach": metres}.

const BAY := Vector2i(6, 5)          # bay size in cells (12 m x 10 m)
const DEFAULT_BAYS := {"desks": 6, "meeting": 1, "lounge": 1, "storage": 1}

var w: GameWorld
var rng := RandomNumberGenerator.new()
var dark := Color("#1b1826")
var rect := Rect2()
var _fade := 0.0                     # 0..1 darkness of the bay being built


func build(world: GameWorld) -> void:
	w = world
	var cfg: Dictionary = w.level.get("sprawl", {})
	rng.seed = hash(w.level_id) + 77
	dark = w._c("sprawl_dark", "#1b1826")
	var c := GameWorld.CELL
	rect = Rect2(0, 0, w.width * c, w.height * c)
	var reach := float(cfg.get("reach", 34.0))
	var bays: Dictionary = cfg.get("bays", DEFAULT_BAYS)
	var bw := BAY.x * c
	var bh := BAY.y * c
	var x0 := floori((rect.position.x - reach) / bw)
	var x1 := ceili((rect.end.x + reach) / bw)
	var z0 := floori((rect.position.y - reach) / bh)
	var z1 := ceili((rect.end.y + reach) / bh)
	var playable := rect.grow(c * 0.5)
	var used := {}
	for bz in range(z0, z1):
		for bx in range(x0, x1):
			var area := Rect2(bx * bw, bz * bh, bw, bh)
			var d := _dist_out(area.get_center())
			if d > reach:
				continue
			var inside := area.intersects(playable)
			if inside and not _all_hidden(area):
				continue
			_fade = 0.5 if inside else clampf(0.4 + d / reach * 0.6, 0.0, 0.92)
			if inside:
				for cell in _cells(area):
					used[cell] = true
			else:
				var south_near := area.position.y > rect.end.y - 0.1 and area.position.y - rect.end.y < 8.0
				_pillar(Vector3(area.position.x, 0, area.position.y), south_near)
			match _pick(bays):
				"desks": _desk_bay(area)
				"meeting": _meeting_bay(area)
				"lounge": _lounge_bay(area)
				"storage": _storage_bay(area)
				"servers": _server_bay(area)
	_fill_hidden(used)


func _hidden(cell: Vector2i) -> bool:
	## A wall cell buried inside a wall mass (no walkable cell around it): no wall
	## mesh is drawn there, so it becomes dim, unreachable office instead.
	if w.ch_at(cell) != "#":
		return false
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if w.ch_at(cell + Vector2i(dx, dy)) != "#":
				return false
	return true


func _cells(area: Rect2) -> Array:
	var out: Array = []
	var c := GameWorld.CELL
	for y in range(floori(area.position.y / c), ceili(area.end.y / c)):
		for x in range(floori(area.position.x / c), ceili(area.end.x / c)):
			out.append(Vector2i(x, y))
	return out


func _all_hidden(area: Rect2) -> bool:
	for cell in _cells(area):
		var inside_map: bool = cell.x >= 0 and cell.y >= 0 and cell.x < w.width and cell.y < w.height
		if inside_map and not _hidden(cell):
			return false
	return true


func _fill_hidden(used: Dictionary) -> void:
	## Hidden wall cells inside the map: a dim floor patch each, and the odd cabinet,
	## desk or box pile where no whole bay fitted.
	var c := GameWorld.CELL
	_fade = 0.5
	for y in w.height:
		for x in w.width:
			var cell := Vector2i(x, y)
			if not _hidden(cell):
				continue
			var p := w.cell_center(cell)
			_box(Vector3(c, 0.02, c), p + Vector3(0, 0.012, 0), w._c("floor_seam", "#69655a"))
			if used.has(cell):
				continue
			var roll := rng.randf()
			if roll < 0.18:
				_desk(p, PI if rng.randf() < 0.5 else 0.0)
			elif roll < 0.3:
				_box(Vector3(0.9, 1.35, 0.8), p + Vector3(0, 0.675, 0), _pp("cabinet", "#a8b4e0"))
			elif roll < 0.38:
				for k in rng.randi_range(1, 3):
					_box(Vector3(0.7, 0.4, 0.5), p + Vector3(rng.randf_range(-0.3, 0.3), 0.2 + (k - 1) * 0.42, 0), Color("#c9955f"))


func _dist_out(p: Vector2) -> float:
	var dx := maxf(maxf(rect.position.x - p.x, p.x - rect.end.x), 0.0)
	var dz := maxf(maxf(rect.position.y - p.y, p.y - rect.end.y), 0.0)
	return Vector2(dx, dz).length()


func _pick(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var r := rng.randf() * total
	for k in weights:
		r -= float(weights[k])
		if r <= 0.0:
			return str(k)
	return str(weights.keys()[0])


# ------------------------------------------------------------------ parts

func _tone(col: Color) -> Color:
	# quantised so neighbouring bays share materials
	return col.lerp(dark, snappedf(_fade, 0.08))


func _box(size: Vector3, pos: Vector3, col: Color, yaw: float = 0.0, emit: float = 0.0) -> void:
	var mi := MeshFactory.kit_instance("box", size)
	var tc := _tone(col) if emit <= 0.0 else col.lerp(dark, _fade * 0.5)
	mi.material_override = MeshFactory.clay(tc, emit * (1.0 - _fade * 0.6), 0.0)
	mi.position = pos
	mi.rotation.y = yaw
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.sprawl_root.add_child(mi)


func _shape(kind: String, size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshFactory.kit_instance(kind, size)
	mi.material_override = MeshFactory.clay(_tone(col), 0.0, 0.0)
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.sprawl_root.add_child(mi)


func _pp(key: String, fallback: String) -> Color:
	return w._pp(key, fallback)


func _pillar(p: Vector3, south_near: bool) -> void:
	## Structural columns on the bay grid (kept wall-height right behind the camera).
	var h := 2.4 if south_near else 3.2
	_box(Vector3(0.9, h, 0.9), p + Vector3(0, h * 0.5, 0), w._c("wall_color", "#dcd2b4"))
	_box(Vector3(1.05, 0.15, 1.05), p + Vector3(0, 0.075, 0), w._c("wall_trim", "#a99f84"))


func _desk(p: Vector3, yaw: float) -> void:
	## Cheap far-away desk: top, pedestal, monitor with a faint screen, chair.
	var b := Basis(Vector3.UP, yaw)
	var wood := _pp("desk", "#f2cf83")
	_box(Vector3(1.7, 0.1, 0.85), p + b * Vector3(0, 0.76, 0), wood, yaw)
	_box(Vector3(0.5, 0.7, 0.8), p + b * Vector3(0.55, 0.36, 0), wood.darkened(0.12), yaw)
	_box(Vector3(0.58, 0.48, 0.45), p + b * Vector3(-0.2, 1.06, -0.15), _pp("crt", "#efe4c9"), yaw)
	if rng.randf() < 0.7:
		_box(Vector3(0.44, 0.3, 0.02), p + b * Vector3(-0.2, 1.08, 0.08), w._c("screen_color", "#7fd3c0"), yaw, 0.9)
	var chair := _pp("chair", "#5d6bb5")
	_box(Vector3(0.5, 0.12, 0.5), p + b * Vector3(0, 0.48, 0.75), chair, yaw)
	_box(Vector3(0.48, 0.5, 0.1), p + b * Vector3(0, 0.78, 0.98), chair, yaw)


func _desk_bay(a: Rect2) -> void:
	## Two rows of desks facing a fabric partition spine.
	var spine := a.position.y + a.size.y * 0.5
	var part := _pp("partition", "#9fc9bf")
	_box(Vector3(a.size.x - 2.4, 1.3, 0.14), Vector3(a.get_center().x, 0.65, spine), part)
	for i in 3:
		var x := a.position.x + 2.6 + i * 3.4
		if rng.randf() < 0.9:
			_desk(Vector3(x, 0, spine - 0.6), PI)
		if rng.randf() < 0.9:
			_desk(Vector3(x, 0, spine + 0.6), 0.0)


func _meeting_bay(a: Rect2) -> void:
	## A meeting room: low walls on two sides, a long table, chairs, a whiteboard.
	var c := Vector3(a.get_center().x, 0, a.get_center().y)
	var wall := w._c("wall_color", "#dcd2b4")
	_box(Vector3(a.size.x - 2.0, 1.1, 0.16), Vector3(c.x, 0.55, a.position.y + 1.0), wall)
	_box(Vector3(0.16, 1.1, a.size.y - 2.0), Vector3(a.position.x + 1.0, 0.55, c.z), wall)
	var top := _pp("table", "#d9805f")
	_box(Vector3(5.0, 0.12, 1.8), c + Vector3(0, 0.78, 0), top)
	_box(Vector3(4.2, 0.7, 0.4), c + Vector3(0, 0.36, 0), top.darkened(0.3))
	var chair := _pp("chair", "#5d6bb5")
	for i in 4:
		for side in [-1.0, 1.0]:
			_box(Vector3(0.5, 0.5, 0.5), c + Vector3(-1.8 + i * 1.2, 0.45, side * 1.3), chair)
	_box(Vector3(2.2, 1.3, 0.06), c + Vector3(0, 1.4, -a.size.y * 0.5 + 1.2), Color("#fbfbf6"))


func _lounge_bay(a: Rect2) -> void:
	## Break area: sofas around a coffee table, plants, a vending machine, a cooler.
	var c := Vector3(a.get_center().x, 0, a.get_center().y)
	var sofa := Color(["#e8505b", "#4d6fd8", "#7fd3c0", "#f29a5b"][rng.randi() % 4])
	_shape("softbox", Vector3(3.0, 0.6, 1.0), c + Vector3(0, 0.3, -1.6), sofa)
	_shape("softbox", Vector3(3.0, 0.7, 0.3), c + Vector3(0, 0.7, -2.05), sofa.darkened(0.15))
	_shape("softbox", Vector3(1.0, 0.6, 2.4), c + Vector3(-2.2, 0.3, 0), sofa)
	_box(Vector3(1.6, 0.4, 1.0), c + Vector3(0, 0.2, 0), _pp("desk", "#f2cf83").darkened(0.2))
	for sx in [-1.0, 1.0]:
		var pp := c + Vector3(sx * (a.size.x * 0.5 - 1.2), 0, a.size.y * 0.5 - 1.2)
		_shape("pot", Vector3(0.6, 0.6, 0.6), pp + Vector3(0, 0.3, 0), Color("#d9805f"))
		_shape("sphere", Vector3(1.0, 1.2, 1.0), pp + Vector3(0, 1.1, 0), _pp("plant", "#6fbf73"))
	_box(Vector3(1.1, 2.0, 0.8), c + Vector3(a.size.x * 0.5 - 1.2, 1.0, -1.6), Color("#e8505b"))
	_box(Vector3(0.7, 1.2, 0.02), c + Vector3(a.size.x * 0.5 - 1.3, 1.25, -1.19), Color("#ffe8a0"), 0.0, 0.6)


func _storage_bay(a: Rect2) -> void:
	## Rows of filing cabinets and stacked archive boxes.
	var cab := _pp("cabinet", "#a8b4e0")
	for row in 2:
		var z := a.position.y + 2.5 + row * 4.0
		for i in 6:
			var x := a.position.x + 1.8 + i * 1.6
			if rng.randf() < 0.8:
				_box(Vector3(0.9, 1.35, 0.8), Vector3(x, 0.675, z), cab)
			elif rng.randf() < 0.7:
				for k in rng.randi_range(1, 3):
					_box(Vector3(0.7, 0.4, 0.5), Vector3(x, 0.2 + k * 0.42 - 0.42, z), Color("#c9955f"))


func _server_bay(a: Rect2) -> void:
	## Server-room rows: racks with dim status lights.
	var body := _pp("server", "#2f3157")
	var leds := [Color("#7dffb0"), Color("#6fd8ff"), Color("#ff4f8b"), Color("#ffcf4a")]
	for row in 2:
		var z := a.position.y + 2.6 + row * 4.4
		for i in 6:
			if rng.randf() < 0.15:
				continue
			var x := a.position.x + 1.6 + i * 1.6
			_box(Vector3(1.3, 2.2, 1.2), Vector3(x, 1.1, z), body)
			for k in 3:
				_box(Vector3(0.6, 0.05, 0.02), Vector3(x, 0.6 + k * 0.5, z + 0.61), leds[rng.randi() % leds.size()], 0.0, 1.6)
