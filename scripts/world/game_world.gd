class_name GameWorld
extends Node3D
## Builds a playable level from its ASCII layout in data/levels/*.json:
## geometry, props, lights, interactables, encounters, boss, pathfinding grid.
##
## Performance notes: every static prop is built under `static_root` and then merged
## by MeshBatcher into one mesh per 8 m chunk (draw calls drop from ~1,500 to ~150);
## collision lives on a single StaticBody3D; the first frames after loading render the
## whole map from above (behind the loading fade) so all shaders compile up front.

signal ready_to_show

const CELL := 2.0
const CHUNK_CELLS := 4
const WALLISH := "#REX"
const SOLID := "#REXgdktxpwfh$BNUGCLSVJ"
## Wall-side dressing placed by _populate(): tall plant, bookshelf, vending machine, floor lamp.
const DRESSING := "LSVJ"
const DEFAULT_DRESSING := {"L": 4, "S": 3, "V": 1, "J": 2}
const NO_CELL := Vector2i(-1, -1)

var level_id := ""
var level: Dictionary = {}
var theme: Dictionary = {}
var menu_mode := false
var spawn_request: Dictionary = {}
var rows: Array[String] = []
var width := 0
var height := 0
var astar := AStarGrid2D.new()
var player: Player = null
var rig: CameraRig
var env: Environment
var sun: DirectionalLight3D
var level_root: Node3D
var static_root: Node3D
var sprawl_root: Node3D   # the inaccessible office beyond the walls (OfficeSprawl)
var screens: Array = []   # [world position, facing] of every lit PC screen: enemies emerge from them
var actors_root: Node3D
var pickups_root: Node3D
var fx_root: FxPool
var computers: Array = []
var chests: Array = []
var exits: Array = []
var boss: Boss = null
var flicker: Array = []
var rng := RandomNumberGenerator.new()
var dungeon_cleared := false
var player_start := Vector3.ZERO
var corrupt_origin := Vector3.ZERO
var warmed := false
var build_stats: Dictionary = {}
var _markers: Dictionary = {}
var _space: PhysicsDirectSpaceState3D
var _ray: PhysicsRayQueryParameters3D
var _collision: StaticBody3D
var _box_shapes: Dictionary = {}
var _warm_frames := -1
var _warm_nodes: Array = []
var _warm_cam: Camera3D


func _ready() -> void:
	GameState.world = self
	level = DB.levels.get(level_id, {})
	if level.is_empty():
		push_error("[World] Unknown level '%s', falling back to hub" % level_id)
		level_id = str(DB.manifest.get("hub_level", "hub"))
		level = DB.levels.get(level_id, {})
	theme = level.get("theme", {})
	rng.randomize()
	level_root = _node("Level")
	static_root = _node("Static")
	sprawl_root = _node("Sprawl")
	actors_root = _node("Actors")
	pickups_root = _node("Pickups")
	fx_root = FxPool.new()
	fx_root.name = "Fx"
	add_child(fx_root)
	_parse_map()
	_populate()
	_build_environment()
	_build_floor()
	_build_walls()
	_build_cells()
	_build_lights()
	_build_astar()
	_decorate()
	if not level.get("no_sprawl", false):
		OfficeSprawl.new().build(self)
	_batch_static()
	rig = CameraRig.new()
	add_child(rig)
	_build_motes()
	if menu_mode:
		rig.orbit = true
		rig.orbit_center = Vector3(width * CELL * 0.5, 0, height * CELL * 0.5)
		RenderingServer.global_shader_parameter_set("player_pos", Vector3(0, -100, 0))
	else:
		_spawn_player()
		if not level.get("safe", false):
			_spawn_encounters()
		_spawn_boss()
	_spawn_coworkers()
	apply_quality()
	Audio.set_ambient(str(theme.get("ambient", "office")) if not menu_mode else "menu")
	if GameState.ui:
		GameState.ui.apply_post(theme.get("post", {}))
	_start_warm_up()


func _exit_tree() -> void:
	if GameState.world == self:
		GameState.world = null
	Engine.time_scale = 1.0


func _node(n: String) -> Node3D:
	var x := Node3D.new()
	x.name = n
	add_child(x)
	return x


func _c(key: String, fallback: String) -> Color:
	return MeshFactory.col(theme.get(key, fallback))


# ------------------------------------------------------------------ map helpers

func _parse_map() -> void:
	rows.clear()
	for r in level.get("map", []):
		rows.append(str(r))
	height = rows.size()
	width = 0
	for r in rows:
		width = maxi(width, r.length())
	for i in rows.size():
		while rows[i].length() < width:
			rows[i] += "#"
	for y in height:
		for x in width:
			var ch := rows[y][x]
			if not _markers.has(ch):
				_markers[ch] = []
			_markers[ch].append(Vector2i(x, y))
	var starts: Array = _markers.get("P", [Vector2i(1, 1)])
	player_start = cell_center(starts[0])
	corrupt_origin = player_start


func ch_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return "#"
	return rows[c.y][c.x]


func cell_center(c: Vector2i) -> Vector3:
	return Vector3(c.x * CELL + CELL * 0.5, 0, c.y * CELL + CELL * 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func is_walkable_cell(c: Vector2i) -> bool:
	if c.x < 0 or c.y < 0 or c.x >= width or c.y >= height:
		return false
	return not astar.is_point_solid(c)


func is_walkable_pos(p: Vector3) -> bool:
	return is_walkable_cell(world_to_cell(p))


func nearest_walkable_cell(c: Vector2i, max_radius: int = 2) -> Vector2i:
	## `c` itself if walkable, else the closest walkable cell within max_radius rings.
	if is_walkable_cell(c):
		return c
	for r in range(1, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) == r and is_walkable_cell(c + Vector2i(dx, dy)):
					return c + Vector2i(dx, dy)
	return NO_CELL


func corruption_at(p: Vector3) -> float:
	var d := Vector2(p.x - corrupt_origin.x, p.z - corrupt_origin.z).length()
	var a := float(theme.get("corrupt_start", 999.0))
	var b := float(theme.get("corrupt_end", 1000.0))
	return clampf(float(theme.get("corrupt_base", 0.0)) + clampf((d - a) / maxf(b - a, 0.01), 0.0, 1.0), 0.0, 1.0)


func _open_dir(c: Vector2i) -> Vector3:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		if not ch_at(c + d) in SOLID:
			return Vector3(d.x, 0, d.y)
	return Vector3.BACK


func _wall_side(c: Vector2i) -> Vector2i:
	## Direction of a plain wall touching cell `c` (doors and glass don't count), or ZERO.
	for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		if ch_at(c + d) == "#":
			return d
	return Vector2i.ZERO


func _wall_yaw(c: Vector2i) -> float:
	## Yaw that turns a prop's front (+z) away from its wall.
	var w := _wall_side(c)
	return atan2(float(-w.x), float(-w.y))


func _populate() -> void:
	## Dresses rooms along their walls with tall props (DRESSING) by rewriting floor
	## cells in `rows` before anything is built, so collision, pathfinding and the
	## props themselves all agree. Only cells in rooms at least 4 cells deep qualify,
	## never next to doors, glass, stations or other props, and never against a south
	## wall (those would stand between the camera and the room).
	var weights: Dictionary = level.get("dressing", DEFAULT_DRESSING)
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	if total <= 0.0:
		return
	var density := float(level.get("dressing_density", 0.35))
	var start := world_to_cell(player_start)
	var ring := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
	var cands: Array = []
	for y in range(1, height - 1):
		for x in range(1, width - 1):
			var c := Vector2i(x, y)
			if not ch_at(c) in ".," or c.distance_to(start) < 4.0:
				continue
			var wall := _wall_side(c)
			if wall == Vector2i.ZERO or wall == Vector2i(0, 1):
				continue
			var ok := true
			for d in ring:
				if not ch_at(c + d) in "#.,":
					ok = false
					break
			for k in range(1, 4):
				if ok and not ch_at(c - wall * k) in ".,":
					ok = false
			if ok:
				cands.append(c)
	var order := range(cands.size())
	for i in range(order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = order[i]
		order[i] = order[j]
		order[j] = tmp
	var want := int(cands.size() * density)
	var placed: Array = []
	for i in order:
		if placed.size() >= want:
			break
		var c: Vector2i = cands[i]
		var crowded := false
		for q in placed:
			if maxi(absi(q.x - c.x), absi(q.y - c.y)) < 3:
				crowded = true
				break
		if crowded:
			continue
		var roll := rng.randf() * total
		var pick := str(weights.keys()[0])
		for k in weights:
			roll -= float(weights[k])
			if roll <= 0.0:
				pick = str(k)
				break
		rows[c.y] = rows[c.y].substr(0, c.x) + pick + rows[c.y].substr(c.x + 1)
		_markers[ch_at(c)] = _markers.get(ch_at(c), []) + [c]
		placed.append(c)


# ------------------------------------------------------------------ construction

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	# beyond the out-of-bounds office everything fades into this colour
	env.background_color = _c("sprawl_dark", "#1b1826")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = _c("ambient_color", "#fff6e0")
	env.ambient_light_energy = float(theme.get("ambient_energy", 0.5))
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = float(theme.get("exposure", 1.0))
	# soft glow only on emissive data (the art direction asks for no heavy bloom)
	env.glow_enabled = true
	env.glow_intensity = 0.32
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.ssao_enabled = true  # Forward+ only; ignored by the Compatibility renderer
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	var fog := float(theme.get("fog_density", 0.0))
	env.fog_enabled = fog > 0.0
	env.fog_light_color = _c("fog_color", "#000000")
	env.fog_density = fog
	env.adjustment_enabled = true
	env.adjustment_saturation = float(theme.get("saturation", 1.0))
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 28, 0)
	sun.light_energy = float(theme.get("sun_energy", 0.5))
	sun.light_color = _c("sun_color", "#fff2d8")
	sun.shadow_enabled = true
	sun.shadow_opacity = 1.0
	sun.directional_shadow_max_distance = 30.0
	add_child(sun)


func apply_quality() -> void:
	## Graphics preset from Settings (High = the original look).
	var q := Settings.quality
	if sun:
		sun.shadow_enabled = q != "low"
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if q == "high" else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		# Nothing beyond ~24 m of view depth is on screen from the game camera, so 30 m
		# keeps every visible shadow while skipping off-screen casters (and sharpens them).
		sun.directional_shadow_max_distance = 30.0
	if env:
		env.glow_enabled = q != "low"


func _build_floor() -> void:
	## The floor is cut into chunks so each piece only overlaps a handful of lights
	## (the Compatibility renderer caps lights per object, so one giant floor mesh
	## silently dropped most of the light pools).
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/floor.gdshader")
	mat.set_shader_parameter("base_color", _c("floor_color", "#8a8572"))
	mat.set_shader_parameter("seam_color", _c("floor_seam", "#69655a"))
	mat.set_shader_parameter("pattern", float(theme.get("floor_pattern", 0)))
	mat.set_shader_parameter("tile_size", CELL)
	mat.set_shader_parameter("corrupt_color", _c("corrupt_color", "#c22cff"))
	mat.set_shader_parameter("ink", MeshFactory.INK)
	mat.set_shader_parameter("corrupt_origin", corrupt_origin)
	mat.set_shader_parameter("corrupt_start", float(theme.get("corrupt_start", 999.0)))
	mat.set_shader_parameter("corrupt_end", float(theme.get("corrupt_end", 1000.0)))
	mat.set_shader_parameter("corrupt_base", float(theme.get("corrupt_base", 0.0)))
	mat.set_shader_parameter("play_rect", Vector4(0, 0, width * CELL, height * CELL))
	mat.set_shader_parameter("outside_dark", _c("sprawl_dark", "#1b1826"))
	if not level.get("no_sprawl", false):
		# the floor keeps going under the out-of-bounds office (just below the level's
		# own floor chunks, which cover it inside the walls)
		var far := MeshInstance3D.new()
		var fp := PlaneMesh.new()
		fp.size = Vector2(width * CELL + 160.0, height * CELL + 160.0)
		far.mesh = fp
		far.material_override = mat
		far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		far.position = Vector3(width * CELL * 0.5, -0.01, height * CELL * 0.5)
		level_root.add_child(far)
	var planes: Dictionary = {}
	for cy in range(0, height, CHUNK_CELLS):
		for cx in range(0, width, CHUNK_CELLS):
			var w := mini(CHUNK_CELLS, width - cx)
			var h := mini(CHUNK_CELLS, height - cy)
			var key := Vector2i(w, h)
			if not planes.has(key):
				var pm := PlaneMesh.new()
				pm.size = Vector2(w * CELL, h * CELL)
				planes[key] = pm
			var mi := MeshInstance3D.new()
			mi.mesh = planes[key]
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.position = Vector3((cx + w * 0.5) * CELL, 0.0, (cy + h * 0.5) * CELL)
			level_root.add_child(mi)


func _build_motes() -> void:
	## Dust drifting in the light (or rising data bits, theme "motes_rise") around the
	## camera's view. One CPU particle system, emitted in world space so it trails nicely.
	var col := _c("motes_color", "#fff2c8")
	var pt := CPUParticles3D.new()
	pt.amount = int(theme.get("motes", 70))
	if pt.amount <= 0:
		return
	pt.lifetime = 7.0
	pt.preprocess = 7.0
	pt.local_coords = false
	pt.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	pt.emission_box_extents = Vector3(13, 1.4, 9)
	pt.direction = Vector3.UP
	pt.spread = 180.0
	pt.initial_velocity_min = 0.03
	pt.initial_velocity_max = 0.15
	pt.gravity = Vector3(0.04, 0.12 if theme.get("motes_rise", false) else 0.0, 0.0)
	pt.scale_amount_min = 0.5
	pt.scale_amount_max = 1.3
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var m := MeshFactory.unlit(col, true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	q.material = m
	pt.mesh = q
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.set_color(1, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 0.55))
	ramp.add_point(0.7, Color(1, 1, 1, 0.55))
	pt.color_ramp = ramp
	pt.position = Vector3(0, 1.6, -1.0)
	rig.add_child(pt)


func _static_box(size: Vector3, pos: Vector3) -> void:
	## All level collision shares one StaticBody3D (and one BoxShape3D per size).
	if _collision == null:
		_collision = StaticBody3D.new()
		_collision.name = "Collision"
		_collision.collision_layer = Layers.WORLD
		_collision.collision_mask = 0
		level_root.add_child(_collision)
	var key := size.snapped(Vector3.ONE * 0.001)
	if not _box_shapes.has(key):
		var bs := BoxShape3D.new()
		bs.size = size
		_box_shapes[key] = bs
	var cs := CollisionShape3D.new()
	cs.shape = _box_shapes[key]
	cs.position = pos
	_collision.add_child(cs)


func _build_walls() -> void:
	var wh := float(theme.get("wall_height", 2.4))
	var wall_mat := MeshFactory.clay(_c("wall_color", "#dcd2b4"), 0.0, 0.07, true)
	var trim_mat := MeshFactory.clay(_c("wall_trim", "#a99f84"), 0.0, 0.05, true)
	for y in height:
		var x := 0
		while x < width:
			# Only wall cells that touch a room are built (one cell thick); cells buried
			# in a wall mass are left open for the dim, inaccessible office (OfficeSprawl).
			if rows[y][x] in WALLISH and not _is_border_run(y, x, x + 1):
				var x0 := x
				while x < width and rows[y][x] in WALLISH and not _is_border_run(y, x, x + 1):
					x += 1
				var run := x - x0
				var size := Vector3(run * CELL, wh, CELL)
				var pos := Vector3((x0 + run * 0.5) * CELL, wh * 0.5, (y + 0.5) * CELL)
				var mi := MeshInstance3D.new()
				mi.mesh = MeshFactory.mesh_for("box", size)
				mi.material_override = wall_mat
				mi.position = pos
				static_root.add_child(mi)
				var trim := MeshInstance3D.new()
				trim.mesh = MeshFactory.mesh_for("box", Vector3(run * CELL + 0.05, 0.12, CELL + 0.05))
				trim.material_override = trim_mat
				trim.position = Vector3(pos.x, wh + 0.06, pos.z)
				static_root.add_child(trim)
				_static_box(size, pos)
			else:
				x += 1
	# glass walls
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.75, 0.95, 0.98, 0.28)
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.05
	glass.metallic = 0.3
	var frame := MeshFactory.clay(_c("wall_trim", "#8a8d96"), 0.0, 0.0)
	for c in _markers.get("g", []):
		var p := cell_center(c)
		var horiz: bool = ch_at(c + Vector2i(1, 0)) in "g#R" or ch_at(c + Vector2i(-1, 0)) in "g#R"
		var size := Vector3(CELL, wh, 0.12) if horiz else Vector3(0.12, wh, CELL)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshFactory.mesh_for("box", size)
		mi.material_override = glass
		mi.position = p + Vector3(0, wh * 0.5, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		static_root.add_child(mi)
		for yy in [0.08, wh - 0.04]:
			var f := MeshInstance3D.new()
			f.mesh = MeshFactory.mesh_for("box", Vector3(size.x + 0.04, 0.12, size.z + 0.06))
			f.material_override = frame
			f.position = p + Vector3(0, yy, 0)
			static_root.add_child(f)
		_static_box(size, p + Vector3(0, wh * 0.5, 0))


func _is_border_run(y: int, x0: int, x1: int) -> bool:
	## Wall runs with no walkable neighbour are invisible filler (only collision).
	for x in range(x0, x1):
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var n := ch_at(Vector2i(x, y) + d)
			if not n in "#":
				return false
	return true


func _build_cells() -> void:
	var exits_def: Array = level.get("exits", [])
	var comps_def: Array = level.get("computers", [])
	var stations_def: Dictionary = level.get("stations", {})
	var exit_i := 0
	var comp_i := 0
	var door_cells: Array = []
	for y in height:
		for x in width:
			var c := Vector2i(x, y)
			var ch := rows[y][x]
			var p := cell_center(c)
			var cor := corruption_at(p)
			match ch:
				"d": _prop_desk(p, cor)
				"k": _prop_partition(p, false)
				"h": _prop_partition(p, true)
				"t": _prop_table(p)
				"x": _prop_server(p)
				"p": _prop_printer(p)
				"w": _prop_cooler(p)
				"f": _prop_cabinet(p)
				"c": _prop_cables(p)
				"o": _prop_chair(p, rng.randf() * TAU)
				"L": _prop_floor_plant(p, cor)
				"S": _prop_shelf(p, _wall_yaw(c))
				"V": _prop_vending(p, _wall_yaw(c), cor)
				"J": _prop_lamp(p)
				"R": door_cells.append(c)
				"E":
					var ed: Dictionary = exits_def[exit_i] if exit_i < exits_def.size() else {"to": DB.manifest.get("hub_level", "hub"), "name": "Lobby"}
					exit_i += 1
					var wd := WallDoor.new()
					wd.kind = "elevator"
					wd.face_dir = _open_dir(c)
					wd.target_level = str(ed.get("to", "hub"))
					wd.target_name = str(ed.get("name", "Lobby"))
					wd.position = p
					level_root.add_child(wd)
				"X":
					var xd: Dictionary = level.get("exit_portal", {"to": DB.manifest.get("hub_level", "hub"), "name": "Emergency Exit"})
					var ex := WallDoor.new()
					ex.kind = "exit"
					ex.face_dir = _open_dir(c)
					ex.target_level = str(xd.get("to", "hub"))
					ex.target_name = str(xd.get("name", "Emergency Exit"))
					ex.active = not level.has("boss")
					ex.position = p
					level_root.add_child(ex)
					exits.append(ex)
				"G":
					var cd: Dictionary = comps_def[comp_i] if comp_i < comps_def.size() else {"id": "%s_terminal_%d" % [level_id, comp_i], "name": "Terminal"}
					comp_i += 1
					var gc := GoldenComputer.new()
					gc.computer_id = str(cd.get("id", ""))
					gc.display_name = str(cd.get("name", "Terminal"))
					gc.position = p
					level_root.add_child(gc)
					computers.append(gc)
				"C":
					var chest := RewardChest.new()
					chest.locked = level.has("boss")
					chest.table = str(level.get("chest_table", "chest"))
					chest.gold_range = level.get("chest_gold", [50, 100])
					chest.position = p
					level_root.add_child(chest)
					chests.append(chest)
				_:
					if stations_def.has(ch):
						var sd: Dictionary = stations_def[ch]
						var st := Station.new()
						st.tab = str(sd.get("tab", "shop"))
						st.station_name = str(sd.get("name", "Desk"))
						st.title = str(sd.get("title", "SERVICE"))
						st.npc = sd.get("npc", {})
						st.position = p
						level_root.add_child(st)
	_place_doors(door_cells)


func _place_doors(cells: Array) -> void:
	if cells.is_empty():
		return
	var cfg: Dictionary = level.get("dungeon_doors", {})
	var dungeons: Array = cfg.get("dungeons", [])
	var red: Array = []
	if not dungeons.is_empty():
		var shuffled := cells.duplicate()
		shuffled.shuffle()
		red = shuffled.slice(0, mini(int(cfg.get("count", 1)), shuffled.size()))
	for c in cells:
		var wd := WallDoor.new()
		wd.kind = "door"
		wd.face_dir = _open_dir(c)
		wd.is_red = c in red
		if wd.is_red:
			wd.dungeon_id = str(dungeons[rng.randi() % dungeons.size()])
		wd.position = cell_center(c)
		level_root.add_child(wd)


func _build_astar() -> void:
	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in height:
		for x in width:
			if rows[y][x] in SOLID or rows[y][x] in level.get("stations", {}):
				astar.set_point_solid(Vector2i(x, y), true)


func _build_lights() -> void:
	## Sparse point lights: in the toon shader they paint stepped colour pools on the floor.
	var spacing := int(theme.get("light_spacing", 4))
	var base_col := _c("light_color", "#fff4d8")
	var cor_col := _c("corrupt_light_color", "#ff3366")
	var energy := float(theme.get("light_energy", 1.0))
	var rng_l := float(theme.get("light_range", 7.0))
	for y in height:
		for x in width:
			if x % spacing != 1 or y % spacing != 1:
				continue
			if rows[y][x] in SOLID:
				continue
			var p := cell_center(Vector2i(x, y))
			var cor := corruption_at(p)
			var l := OmniLight3D.new()
			l.light_color = base_col.lerp(cor_col, cor * cor)
			l.light_energy = energy
			l.omni_range = rng_l
			l.omni_attenuation = 1.0
			l.position = p + Vector3(0, 2.6, 0)
			level_root.add_child(l)
			var chance := float(theme.get("flicker_chance", 0.03)) + cor * 0.35
			if rng.randf() < chance:
				flicker.append({"light": l, "energy": energy, "t": rng.randf() * 3.0, "on": true})


func _decorate() -> void:
	# Corporate signage on south-facing wall faces that the camera can see.
	var signs: Array = level.get("signs", [])
	var candidates: Array = []
	for y in range(1, height):
		for x in range(1, width - 1):
			if rows[y - 1][x] == "#" and not rows[y][x] in SOLID and rows[y - 1][x - 1] == "#" and rows[y - 1][x + 1] == "#":
				candidates.append(Vector2i(x, y - 1))
	candidates.shuffle()
	var placed := 0
	for c in candidates:
		if placed >= mini(signs.size() + 4, 10):
			break
		var p := cell_center(c) + Vector3(0, 1.6, CELL * 0.5 + 0.04)
		var plate := MeshInstance3D.new()
		var cor := corruption_at(p)
		var red := cor > 0.5
		plate.mesh = MeshFactory.mesh_for("box", Vector3(1.7, 0.5, 0.04))
		plate.material_override = MeshFactory.clay(_c("sign_color", "#2e2a3f") if not red else Color("#3a0a14"), 0.0, 0.0)
		plate.position = p
		static_root.add_child(plate)
		if placed < signs.size():
			var l := Label3D.new()
			l.text = str(signs[placed])
			l.font_size = 32
			l.pixel_size = 0.0045
			l.modulate = _c("sign_text", "#fdf3d8") if not red else Color("#ff5070")
			l.position = p + Vector3(0, 0, 0.03)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.width = 340
			level_root.add_child(l)
		else:
			_logo(p + Vector3(0, 0, 0.03), red)
		placed += 1
	# The rest of the visible wall faces get posters, clocks, whiteboards and art.
	var hung: Array = []
	for i in range(placed, candidates.size()):
		var c3: Vector2i = candidates[i]
		if hung.size() >= 16:
			break
		var near := false
		for q in hung:
			if absi(q.y - c3.y) < 1 and absi(q.x - c3.x) < 2:
				near = true
				break
		if near or rng.randf() < 0.35:
			continue
		hung.append(c3)
		_wall_decor(cell_center(c3) + Vector3(rng.randf_range(-0.3, 0.3), 0, CELL * 0.5 + 0.03), corruption_at(cell_center(c3)))
	# Loose paper on the floor: a few in tidy areas, drifts of it where corruption hit.
	for i in 90:
		var c4 := Vector2i(rng.randi_range(1, width - 2), rng.randi_range(1, height - 2))
		if not rows[c4.y][c4.x] in ".,":
			continue
		var p4 := cell_center(c4) + Vector3(rng.randf_range(-0.8, 0.8), 0, rng.randf_range(-0.8, 0.8))
		if rng.randf() > 0.12 + corruption_at(p4) * 0.6:
			continue
		var sheet := MeshFactory.box(static_root, Vector3(0.3, 0.008, 0.4), p4 + Vector3(0, 0.005, 0), Color("#fbf7ee").darkened(rng.randf() * 0.08), 0.0, 0.0)
		sheet.rotation.y = rng.randf() * TAU
		sheet.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if theme.has("rug"):
		_rug(player_start, _c("rug", "#7a62c9"))
	# Floating glitch fragments in corrupted zones (unit box scaled: no per-size mesh leak).
	for i in 40:
		var c2 := Vector2i(rng.randi_range(1, width - 2), rng.randi_range(1, height - 2))
		if rows[c2.y][c2.x] in SOLID:
			continue
		var p2 := cell_center(c2)
		var cor2 := corruption_at(p2)
		if cor2 < 0.45 or rng.randf() > cor2:
			continue
		var g := MeshInstance3D.new()
		g.mesh = MeshFactory.unit_box()
		g.material_override = MeshFactory.glow(_c("corrupt_color", "#c22cff"), 2.5)
		g.position = p2 + Vector3(rng.randf_range(-0.8, 0.8), rng.randf_range(1.8, 3.0), rng.randf_range(-0.8, 0.8))
		g.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		g.scale = Vector3.ONE * rng.randf_range(0.15, 0.4)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		level_root.add_child(g)
		flicker.append({"glitch": g, "t": rng.randf() * 2.0, "base": g.position})


func _wall_decor(p: Vector3, cor: float) -> void:
	## One flat decoration on a south-facing wall face (+z is out of the wall).
	var ink := MeshFactory.INK
	match rng.randi() % 4:
		0:  # wall clock
			var c := p + Vector3(0, 1.85, 0)
			MeshFactory.shape(static_root, "cyl", Vector3(0.5, 0.06, 0.5), c, Color("#fbf7ee"), 0.0, Vector3(90, 0, 0))
			MeshFactory.shape(static_root, "torus", Vector3(0.52, 0.1, 0.52), c, Color("#2b2840"), 0.0, Vector3(90, 0, 0))
			var hand := MeshFactory.box(static_root, Vector3(0.025, 0.17, 0.01), c + Vector3(0, 0, 0.04), ink, 0.0, 0.0)
			hand.rotation.z = rng.randf() * TAU
			var hand2 := MeshFactory.box(static_root, Vector3(0.03, 0.12, 0.01), c + Vector3(0, 0, 0.045), ink, 0.0, 0.0)
			hand2.rotation.z = rng.randf() * TAU
			# rotate about the clock centre, not the hand's middle
			for h in [hand, hand2]:
				h.position += Basis(Vector3.BACK, h.rotation.z) * Vector3(0, h.scale.y * 0.5, 0)
		1:  # whiteboard with marker scribbles
			var c := p + Vector3(0, 1.45, 0)
			MeshFactory.box(static_root, Vector3(1.5, 0.95, 0.04), c, Color("#c9cbd6"), 0.0, 0.0)
			MeshFactory.box(static_root, Vector3(1.4, 0.85, 0.02), c + Vector3(0, 0, 0.02), Color("#fdfdf8"), 0.0, 0.0)
			MeshFactory.box(static_root, Vector3(1.2, 0.05, 0.08), c + Vector3(0, -0.5, 0.04), Color("#c9cbd6"), 0.0, 0.0)
			var marker_cols := [Color("#e8505b"), Color("#4d6fd8"), Color("#3aa66b")]
			for i in rng.randi_range(3, 6):
				var line := MeshFactory.box(static_root, Vector3(rng.randf_range(0.2, 0.6), 0.025, 0.01), c + Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.3, 0.3), 0.035), marker_cols[rng.randi() % 3], 0.0, 0.0)
				line.rotation.z = rng.randf_range(-0.5, 0.5) if rng.randf() < 0.4 else 0.0
			if cor > 0.5:
				var slash := MeshFactory.box(static_root, Vector3(0.5, 0.06, 0.01), c + Vector3(0, 0, 0.04), _c("corrupt_color", "#ff4f8b"), 1.5, 0.0)
				slash.rotation.z = 0.6
		2:  # motivational poster
			var c := p + Vector3(0, 1.5, 0)
			var bg := Color(["#5d7bd6", "#f29a5b", "#7fd3c0", "#b58cf0"][rng.randi() % 4])
			if cor > 0.5:
				bg = bg.lerp(_c("corrupt_color", "#ff4f8b"), 0.5)
			MeshFactory.box(static_root, Vector3(0.8, 1.05, 0.03), c, Color("#2b2840"), 0.0, 0.0)
			MeshFactory.box(static_root, Vector3(0.7, 0.95, 0.02), c + Vector3(0, 0, 0.02), bg, 0.0, 0.0)
			MeshFactory.shape(static_root, "cone", Vector3(0.45, 0.4, 0.05), c + Vector3(0, 0.1, 0.03), bg.lightened(0.35))
			MeshFactory.box(static_root, Vector3(0.5, 0.06, 0.01), c + Vector3(0, -0.3, 0.035), Color("#fbf7ee"), 0.0, 0.0)
			MeshFactory.box(static_root, Vector3(0.36, 0.035, 0.01), c + Vector3(0, -0.38, 0.035), Color("#fbf7ee").darkened(0.2), 0.0, 0.0)
		_:  # framed abstract art
			var c := p + Vector3(0, 1.5, 0)
			MeshFactory.box(static_root, Vector3(1.0, 0.7, 0.04), c, Color("#f3eee2"), 0.0, 0.03)
			for i in 3:
				var blob := MeshFactory.shape(static_root, ["sphere", "box", "cone"][i], Vector3(0.22, 0.22, 0.02), c + Vector3(-0.28 + i * 0.28, rng.randf_range(-0.1, 0.1), 0.03), Color(["#e8505b", "#ffcf4a", "#4d6fd8"][rng.randi() % 3]))
				blob.rotation.z = rng.randf() * TAU if i == 2 else 0.0


func _rug(p: Vector3, col: Color) -> void:
	## Round lobby rug with a border ring and a centre emblem.
	MeshFactory.shape(static_root, "cyl", Vector3(7.0, 0.02, 7.0), p + Vector3(0, 0.01, 0), col.darkened(0.2))
	MeshFactory.shape(static_root, "cyl", Vector3(6.4, 0.025, 6.4), p + Vector3(0, 0.012, 0), col)
	MeshFactory.shape(static_root, "torus", Vector3(5.2, 0.12, 5.2), p + Vector3(0, 0.02, 0), col.lightened(0.3))
	MeshFactory.shape(static_root, "cyl", Vector3(1.6, 0.03, 1.6), p + Vector3(0, 0.016, 0), col.lightened(0.45))
	for node in static_root.get_children().slice(-4):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _logo(p: Vector3, red: bool) -> void:
	var col := Color("#7fd3c0") if not red else Color("#ff3a5a")
	for i in 3:
		var b := MeshInstance3D.new()
		b.mesh = MeshFactory.mesh_for("box", Vector3(0.12, 0.12 + i * 0.08, 0.02))
		b.material_override = MeshFactory.glow(col, 1.8)
		b.position = p + Vector3(-0.15 + i * 0.15, -0.1 + i * 0.04, 0)
		static_root.add_child(b)


func _batch_static() -> void:
	## Merges everything under static_root into one mesh per chunk (and per shadow mode).
	## Toon parts share one vertex-coloured material; other materials (glow LEDs, glass)
	## are merged per material.
	var t0 := Time.get_ticks_usec()
	var batched := _node("Batched")
	var counts := _batch_root(static_root, CELL * CHUNK_CELLS, true, batched)
	# The out-of-bounds office is big, distant and unlit: larger chunks, no shadows.
	var counts2 := _batch_root(sprawl_root, CELL * 12, false, batched)
	remove_child(static_root)
	static_root.queue_free()
	remove_child(sprawl_root)
	sprawl_root.queue_free()
	build_stats = {"parts": counts.x + counts2.x, "batches": counts.y + counts2.y, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


func _batch_root(src: Node3D, chunk: float, shadows: bool, batched: Node3D) -> Vector2i:
	## Returns (parts merged, batches made).
	var toon: Dictionary = {}
	var plain: Dictionary = {}
	var parts := 0
	for node in src.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var p := mi.global_position
		var ck := Vector2i(floori(p.x / chunk), floori(p.z / chunk))
		parts += 1
		if MeshBatcher.can_batch(mi):
			var info := MeshFactory.material_info(mi.material_override)
			var key := "%d,%d|%s" % [ck.x, ck.y, info.fade]
			if not toon.has(key):
				toon[key] = {"batch": MeshBatcher.new(), "fade": bool(info.fade), "shadow": shadows}
			(toon[key].batch as MeshBatcher).add(mi, mi.global_transform)
		elif mi.mesh != null and mi.mesh.get_surface_count() == 1:
			var mat := mi.material_override
			var key2 := "%d,%d|%d|%d" % [ck.x, ck.y, mat.get_instance_id() if mat else 0, mi.cast_shadow]
			if not plain.has(key2):
				plain[key2] = {"batch": MeshBatcher.new(), "material": mat, "shadow": mi.cast_shadow}
			(plain[key2].batch as MeshBatcher).add_raw(mi.mesh, mi.global_transform)
	for k in toon:
		var e: Dictionary = toon[k]
		batched.add_child((e.batch as MeshBatcher).instance(bool(e.fade), bool(e.shadow)))
	for k in plain:
		var e2: Dictionary = plain[k]
		var mi2 := MeshInstance3D.new()
		mi2.mesh = (e2.batch as MeshBatcher).commit()
		mi2.material_override = e2.material
		mi2.cast_shadow = e2.shadow if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		batched.add_child(mi2)
	return Vector2i(parts, toon.size() + plain.size())


# ------------------------------------------------------------------ props

func _rot_node(p: Vector3, yaw: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.position = p
	n.rotation.y = yaw
	static_root.add_child(n)
	return n


func _pp(key: String, fallback: String) -> Color:
	## Prop colours come from the level theme's "props" palette (falls back to defaults).
	return MeshFactory.col(theme.get("props", {}).get(key, fallback))


func _stroke(n: Node3D, size: Vector3, pos: Vector3, rot_z: float) -> void:
	var mi := MeshFactory.box(n, size, pos, MeshFactory.INK, 0.0, 0.0)
	mi.rotation.z = rot_z


func _screen_face(n: Node3D, pos: Vector3, w: float, h: float, cor: float) -> void:
	## Little drawn faces on CRT screens, cheerful in the clean office, angry where corrupted.
	var ink := MeshFactory.INK
	var angry := cor > 0.45
	var mood := rng.randi() % 4
	var ex := w * 0.22
	if angry:
		_stroke(n, Vector3(w * 0.16, h * 0.08, 0.01), pos + Vector3(-ex, h * 0.18, 0.02), -0.4)
		_stroke(n, Vector3(w * 0.16, h * 0.08, 0.01), pos + Vector3(ex, h * 0.18, 0.02), 0.4)
		MeshFactory.box(n, Vector3(w * 0.1, h * 0.12, 0.01), pos + Vector3(-ex, h * 0.02, 0.02), ink, 0.0, 0.0)
		MeshFactory.box(n, Vector3(w * 0.1, h * 0.12, 0.01), pos + Vector3(ex, h * 0.02, 0.02), ink, 0.0, 0.0)
		MeshFactory.box(n, Vector3(w * 0.4, h * 0.06, 0.01), pos + Vector3(0, -h * 0.22, 0.02), ink, 0.0, 0.0)
		return
	match mood:
		0:  # ^ ^
			for sx in [-1.0, 1.0]:
				_stroke(n, Vector3(w * 0.12, h * 0.05, 0.01), pos + Vector3(sx * ex - w * 0.04, h * 0.08, 0.02), 0.6)
				_stroke(n, Vector3(w * 0.12, h * 0.05, 0.01), pos + Vector3(sx * ex + w * 0.04, h * 0.08, 0.02), -0.6)
		1:  # . _ .
			MeshFactory.box(n, Vector3(w * 0.08, h * 0.12, 0.01), pos + Vector3(-ex, h * 0.08, 0.02), ink, 0.0, 0.0)
			MeshFactory.box(n, Vector3(w * 0.08, h * 0.12, 0.01), pos + Vector3(ex, h * 0.08, 0.02), ink, 0.0, 0.0)
			MeshFactory.box(n, Vector3(w * 0.2, h * 0.05, 0.01), pos + Vector3(0, -h * 0.15, 0.02), ink, 0.0, 0.0)
		2:  # > <
			for sx in [-1.0, 1.0]:
				_stroke(n, Vector3(w * 0.12, h * 0.05, 0.01), pos + Vector3(sx * ex, h * 0.12, 0.02), 0.5 * sx)
				_stroke(n, Vector3(w * 0.12, h * 0.05, 0.01), pos + Vector3(sx * ex, h * 0.0, 0.02), -0.5 * sx)
		_:  # spreadsheet
			for i in 3:
				MeshFactory.box(n, Vector3(w * 0.7, h * 0.04, 0.01), pos + Vector3(0, h * (0.2 - i * 0.18), 0.02), ink.lerp(Color.WHITE, 0.3), 0.0, 0.0)


func _prop_monitor(n: Node3D, pos: Vector3, cor: float, scale_f: float = 1.0) -> void:
	var crt := _pp("crt", "#efe4c9")
	var w := 0.62 * scale_f
	var h := 0.52 * scale_f
	MeshFactory.box(n, Vector3(w, h, 0.5 * scale_f), pos, crt)
	MeshFactory.box(n, Vector3(0.24 * scale_f, 0.08, 0.24 * scale_f), pos + Vector3(0, -h * 0.5 - 0.03, -0.02), crt.darkened(0.12))
	var on := rng.randf() < 0.85
	var screen_col := _c("screen_color", "#7fd3c0").lerp(_c("corrupt_color", "#ff4f8b"), clampf(cor * 1.4, 0.0, 1.0))
	var spos := pos + Vector3(0, 0.01, 0.25 * scale_f + 0.005)
	MeshFactory.box(n, Vector3(w * 0.76, h * 0.68, 0.02), spos, screen_col if on else Color("#2a2836"), 0.9 if on else 0.0, 0.0)
	if on:
		_screen_face(n, spos, w * 0.76, h * 0.68, cor)
		screens.append({"pos": n.to_global(spos), "facing": (n.global_basis * Vector3.BACK).normalized(), "used": 0})


const MUG_COLORS := ["#ff6b8a", "#5d7bd6", "#7fd3c0", "#ffcf4a", "#fbf7ee", "#b58cf0"]
const STICKY_COLORS := ["#ffe66b", "#ff9fc0", "#9fe3ff", "#b6f29a"]


func _prop_mug(n: Node3D, pos: Vector3, s: float = 1.0) -> void:
	MeshFactory.shape(n, "mug", Vector3(0.13, 0.14, 0.11) * s, pos + Vector3(0, 0.07 * s, 0), Color(MUG_COLORS[rng.randi() % MUG_COLORS.size()]), 0.0, Vector3(0, rng.randf() * 360.0, 0))


func _prop_papers(n: Node3D, pos: Vector3, count: int, spread: float = 0.08) -> void:
	for i in count:
		var sheet := MeshFactory.box(n, Vector3(0.3, 0.012, 0.4), pos + Vector3(rng.randf_range(-spread, spread), 0.006 + i * 0.013, rng.randf_range(-spread, spread)), Color("#fbf7ee").darkened(rng.randf() * 0.06), 0.0, 0.0)
		sheet.rotation.y = rng.randf_range(-0.3, 0.3)


func _prop_plant_small(n: Node3D, pos: Vector3) -> void:
	## Desk succulent: a little pot with a rosette of leaves.
	MeshFactory.shape(n, "pot", Vector3(0.2, 0.18, 0.2), pos + Vector3(0, 0.09, 0), Color("#d9805f"))
	var green := _pp("plant", "#6fbf73")
	for i in 5:
		_leaf(n, pos + Vector3(0, 0.2, 0), TAU * i / 5.0 + rng.randf() * 0.4, 0.5, Vector3(0.09, 0.07, 0.2), green.lightened(rng.randf() * 0.15))


func _leaf(n: Node3D, base: Vector3, yaw: float, pitch: float, size: Vector3, color: Color) -> void:
	## The kit leaf points along -z (its length is size.z) and arches up; `base` is its stem.
	var dir := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	var leaf := MeshFactory.shape(n, "leaf", size, base + dir * size.z * 0.5, color)
	leaf.rotation = Vector3(pitch, yaw, 0)


func _prop_desk(p: Vector3, cor: float) -> void:
	var n := _rot_node(p)
	var wood := _pp("desk", "#f2cf83")
	var leg := wood.darkened(0.3)
	# top with a darker lip, slab leg on the left, drawer pedestal on the right
	MeshFactory.box(n, Vector3(1.8, 0.1, 0.95), Vector3(0, 0.76, -0.1), wood)
	MeshFactory.box(n, Vector3(1.82, 0.035, 0.97), Vector3(0, 0.7, -0.1), wood.darkened(0.2), 0.0, 0.0)
	MeshFactory.box(n, Vector3(0.1, 0.7, 0.85), Vector3(-0.82, 0.35, -0.1), wood.darkened(0.15))
	MeshFactory.box(n, Vector3(1.2, 0.42, 0.05), Vector3(-0.2, 0.46, -0.52), wood.darkened(0.22), 0.0, 0.0)
	MeshFactory.box(n, Vector3(0.55, 0.66, 0.85), Vector3(0.55, 0.36, -0.1), wood.darkened(0.08))
	for i in 3:
		MeshFactory.box(n, Vector3(0.48, 0.18, 0.02), Vector3(0.55, 0.15 + i * 0.21, 0.33), wood.darkened(0.02), 0.0, 0.0)
		MeshFactory.box(n, Vector3(0.16, 0.035, 0.03), Vector3(0.55, 0.2 + i * 0.21, 0.35), leg.darkened(0.3), 0.0, 0.0)
	_prop_monitor(n, Vector3(-0.2, 1.08, -0.25), cor)
	# keyboard with key rows, and a mouse on a pad
	var crt := _pp("crt", "#efe4c9")
	MeshFactory.box(n, Vector3(0.6, 0.05, 0.2), Vector3(-0.2, 0.83, 0.2), crt.darkened(0.05))
	for r in 3:
		MeshFactory.box(n, Vector3(0.5, 0.012, 0.035), Vector3(-0.2, 0.86, 0.14 + r * 0.05), crt.darkened(0.25), 0.0, 0.0)
	MeshFactory.box(n, Vector3(0.22, 0.01, 0.2), Vector3(0.24, 0.815, 0.2), Color("#3a3560"), 0.0, 0.0)
	MeshFactory.shape(n, "softbox", Vector3(0.07, 0.04, 0.1), Vector3(0.24, 0.84, 0.2), crt)
	# a little personal clutter, different on every desk
	if rng.randf() < 0.55:
		_prop_papers(n, Vector3(0.48, 0.81, -0.05), rng.randi_range(2, 6))
	if rng.randf() < 0.7:
		_prop_mug(n, Vector3(0.66, 0.81, 0.18))
	if rng.randf() < 0.35:
		_prop_plant_small(n, Vector3(0.68, 0.81, -0.38))
	elif rng.randf() < 0.4:
		# photo frame
		var f := MeshFactory.box(n, Vector3(0.18, 0.22, 0.03), Vector3(0.68, 0.93, -0.38), Color("#2b2840"), 0.0, 0.0)
		f.rotation = Vector3(-0.2, -0.5, 0)
		# (kit parts are sized through node scale, so the photo can't be the frame's child)
		var ph := MeshFactory.box(n, Vector3(0.13, 0.16, 0.01), f.position + Basis.from_euler(f.rotation) * Vector3(0, 0, 0.02), Color(STICKY_COLORS[rng.randi() % STICKY_COLORS.size()]).lightened(0.3), 0.0, 0.0)
		ph.rotation = f.rotation
	# sticky notes on the monitor bezel
	for i in rng.randi_range(0, 2):
		var note := MeshFactory.box(n, Vector3(0.09, 0.09, 0.01), Vector3(-0.2 + (0.27 if i == 0 else -0.27), 1.2 - i * 0.1, 0.01), Color(STICKY_COLORS[rng.randi() % STICKY_COLORS.size()]), 0.0, 0.0)
		note.rotation.z = rng.randf_range(-0.25, 0.25)
	_prop_chair(p + Vector3(0, 0, 0.85), rng.randf_range(-0.5, 0.5) + PI)
	_static_box(Vector3(1.8, 1.0, 1.0), p + Vector3(0, 0.5, -0.1))


func _prop_chair(p: Vector3, yaw: float) -> void:
	## Office swivel chair: padded seat and back, armrests, gas lift and a 5-star base on casters.
	var n := _rot_node(p, yaw)
	var c := _pp("chair", "#5d6bb5")
	var metal := Color("#2b2840")
	MeshFactory.shape(n, "softbox", Vector3(0.54, 0.13, 0.52), Vector3(0, 0.48, 0), c)
	MeshFactory.shape(n, "softbox", Vector3(0.5, 0.56, 0.13), Vector3(0, 0.82, 0.24), c, 0.0, Vector3(-8, 0, 0))
	MeshFactory.box(n, Vector3(0.06, 0.2, 0.05), Vector3(0, 0.6, 0.27), metal, 0.0, 0.0)
	for sx in [-1.0, 1.0]:
		MeshFactory.box(n, Vector3(0.05, 0.16, 0.05), Vector3(sx * 0.28, 0.6, 0.02), metal, 0.0, 0.0)
		MeshFactory.box(n, Vector3(0.07, 0.04, 0.26), Vector3(sx * 0.28, 0.69, 0.0), metal.lightened(0.15), 0.0, 0.0)
	MeshFactory.shape(n, "cyl", Vector3(0.07, 0.36, 0.07), Vector3(0, 0.25, 0), metal.lightened(0.25))
	for i in 5:
		var a := TAU * i / 5.0
		var spoke := MeshFactory.box(n, Vector3(0.05, 0.04, 0.3), Vector3(sin(a) * 0.14, 0.07, cos(a) * 0.14), metal, 0.0, 0.0)
		spoke.rotation.y = a
		MeshFactory.shape(n, "sphere", Vector3(0.07, 0.07, 0.07), Vector3(sin(a) * 0.29, 0.035, cos(a) * 0.29), metal.darkened(0.3))


func _prop_partition(p: Vector3, horizontal: bool) -> void:
	## Fabric cubicle panel with an aluminium cap and the odd pinned note.
	var size := Vector3(CELL, 1.35, 0.16) if horizontal else Vector3(0.16, 1.35, CELL)
	var col := _pp("partition", "#9fc9bf")
	MeshFactory.box(static_root, size, p + Vector3(0, 0.675, 0), col, 0.0, 0.03)
	var cap := Vector3(size.x + 0.02, 0.06, size.z + 0.04)
	MeshFactory.box(static_root, cap, p + Vector3(0, 1.36, 0), Color("#d9dbe6"), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(size.x + 0.01, 0.08, size.z + 0.02), p + Vector3(0, 0.04, 0), col.darkened(0.35), 0.0, 0.0)
	# notes on the face the camera sees (+z for horizontal panels, +x for vertical)
	for i in rng.randi_range(0, 3):
		var along := rng.randf_range(-0.7, 0.7)
		var y := rng.randf_range(0.7, 1.15)
		var face := Vector3(along, y, size.z * 0.5 + 0.01) if horizontal else Vector3(size.x * 0.5 + 0.01, y, along)
		var note_size := Vector3(0.14, 0.14, 0.01) if horizontal else Vector3(0.01, 0.14, 0.14)
		var note := MeshFactory.box(static_root, note_size, p + face, Color(STICKY_COLORS[rng.randi() % STICKY_COLORS.size()]), 0.0, 0.0)
		if horizontal:
			note.rotation.z = rng.randf_range(-0.3, 0.3)
		else:
			note.rotation.x = rng.randf_range(-0.3, 0.3)
	_static_box(size, p + Vector3(0, 0.675, 0))


func _prop_table(p: Vector3) -> void:
	## Meeting-table cells join into one long table; each cell adds its own clutter.
	var top := _pp("table", "#d9805f")
	MeshFactory.box(static_root, Vector3(CELL - 0.02, 0.12, CELL - 0.02), p + Vector3(0, 0.78, 0), top, 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(CELL - 0.3, 0.06, CELL - 0.3), p + Vector3(0, 0.69, 0), top.darkened(0.3), 0.0, 0.0)
	MeshFactory.shape(static_root, "cyl", Vector3(0.22, 0.66, 0.22), p + Vector3(0, 0.35, 0), Color("#2b2840"))
	MeshFactory.shape(static_root, "cyl", Vector3(0.7, 0.05, 0.7), p + Vector3(0, 0.025, 0), Color("#2b2840"))
	var roll := rng.randf()
	var spot := p + Vector3(rng.randf_range(-0.45, 0.45), 0.84, rng.randf_range(-0.45, 0.45))
	if roll < 0.25:
		_prop_papers(static_root, spot, rng.randi_range(1, 4), 0.15)
	elif roll < 0.45:
		_prop_mug(static_root, spot)
	elif roll < 0.6:
		# open laptop
		var lap := _rot_node(spot, rng.randf_range(-0.6, 0.6) + (PI if rng.randf() < 0.5 else 0.0))
		MeshFactory.box(lap, Vector3(0.42, 0.025, 0.3), Vector3(0, 0.012, 0), Color("#b9bfd0"), 0.0, 0.0)
		var lid := MeshFactory.box(lap, Vector3(0.42, 0.28, 0.02), Vector3(0, 0.14, -0.16), Color("#b9bfd0"), 0.0, 0.0)
		lid.rotation.x = -0.3
		var scr := MeshFactory.box(lap, Vector3(0.36, 0.22, 0.01), Vector3(0, 0.14, -0.145), _c("screen_color", "#7fd3c0"), 0.8, 0.0)
		scr.rotation.x = -0.3
	elif roll < 0.68:
		_prop_plant_small(static_root, spot)
	_static_box(Vector3(CELL, 0.9, CELL), p + Vector3(0, 0.45, 0))


func _prop_server(p: Vector3) -> void:
	## Rack cabinet: bezel frame, vented door, rack units with LEDs, cable tray on top.
	var body := _pp("server", "#2f3157")
	MeshFactory.box(static_root, Vector3(1.3, 2.2, 1.2), p + Vector3(0, 1.1, 0), body, 0.0, 0.035)
	MeshFactory.box(static_root, Vector3(1.1, 2.0, 0.04), p + Vector3(0, 1.12, 0.6), body.darkened(0.35), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(1.34, 0.08, 1.24), p + Vector3(0, 0.04, 0), body.darkened(0.5), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(1.0, 0.1, 0.9), p + Vector3(0, 2.25, 0), Color("#4a4d70"), 0.0, 0.0)
	for i in 3:
		MeshFactory.shape(static_root, "cyl", Vector3(0.06, 1.0, 0.06), p + Vector3(-0.3 + i * 0.3, 2.33, 0), Color(["#2b2840", "#5d6bb5", "#ff4f8b"][i]), 0.0, Vector3(90, 0, 0))
	var cols := [Color("#7dffb0"), Color("#6fd8ff"), Color("#ff4f8b"), Color("#ffcf4a")]
	for i in 6:
		var y := 0.35 + i * 0.3
		MeshFactory.box(static_root, Vector3(1.0, 0.24, 0.03), p + Vector3(0, y, 0.62), body.lightened(0.12), 0.0, 0.0)
		var led := MeshInstance3D.new()
		led.mesh = MeshFactory.mesh_for("box", Vector3(0.5, 0.05, 0.02))
		led.material_override = MeshFactory.glow(cols[rng.randi() % cols.size()], 2.0)
		led.position = p + Vector3(-0.15, y, 0.64)
		led.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if rng.randf() < 0.3:
			level_root.add_child(led)  # blinking LEDs stay separate nodes
			flicker.append({"blink": led, "t": rng.randf()})
		else:
			static_root.add_child(led)
		for k in 3:
			var dot := MeshInstance3D.new()
			dot.mesh = MeshFactory.mesh_for("box", Vector3(0.05, 0.05, 0.02))
			dot.material_override = MeshFactory.glow(cols[(i + k) % cols.size()], 2.5)
			dot.position = p + Vector3(0.22 + k * 0.08, y, 0.64)
			dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			static_root.add_child(dot)
	# the rack's status panel works as a screen viruses can climb out of
	screens.append({"pos": p + Vector3(0, 1.2, 0.66), "facing": Vector3.BACK, "used": 0})
	_static_box(Vector3(1.3, 2.2, 1.2), p + Vector3(0, 1.1, 0))


func _prop_printer(p: Vector3) -> void:
	## Office copier: paper drawers, scanner lid, control panel, output tray with a print.
	var c := _pp("printer", "#e9e4f2")
	MeshFactory.box(static_root, Vector3(1.3, 0.95, 1.0), p + Vector3(0, 0.475, 0), c)
	for i in 2:
		MeshFactory.box(static_root, Vector3(1.1, 0.02, 0.02), p + Vector3(0, 0.3 + i * 0.25, 0.51), c.darkened(0.3), 0.0, 0.0)
		MeshFactory.box(static_root, Vector3(0.3, 0.04, 0.03), p + Vector3(0, 0.2 + i * 0.25, 0.52), c.darkened(0.45), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(1.2, 0.14, 0.9), p + Vector3(0, 1.0, 0), c.darkened(0.15))
	MeshFactory.box(static_root, Vector3(0.9, 0.02, 0.6), p + Vector3(-0.1, 1.08, 0), Color("#3a3560"), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(0.36, 0.08, 0.22), p + Vector3(0.42, 1.0, 0.42), Color("#3a3560"), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(0.2, 0.01, 0.1), p + Vector3(0.38, 1.045, 0.42), _c("screen_color", "#7fd3c0"), 1.2, 0.0)
	MeshFactory.box(static_root, Vector3(0.6, 0.04, 0.35), p + Vector3(0, 0.75, 0.6), c.darkened(0.1), 0.0, 0.0)
	_prop_papers(static_root, p + Vector3(0, 0.77, 0.62), rng.randi_range(1, 3), 0.03)
	MeshFactory.box(static_root, Vector3(0.06, 0.06, 0.02), p + Vector3(0.55, 1.0, 0.52), Color("#7dffb0"), 3.0, 0.0)
	_static_box(Vector3(1.3, 1.0, 1.0), p + Vector3(0, 0.5, 0))


func _prop_cooler(p: Vector3) -> void:
	## Water cooler: cabinet, two taps, drip tray, an upturned jug and a cup dispenser.
	MeshFactory.box(static_root, Vector3(0.5, 1.0, 0.5), p + Vector3(0, 0.5, 0), Color("#fbf7ee"))
	MeshFactory.box(static_root, Vector3(0.3, 0.04, 0.12), p + Vector3(0, 0.62, 0.28), Color("#b9bfd0"), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(0.06, 0.07, 0.06), p + Vector3(-0.08, 0.82, 0.27), Color("#5d7bd6"), 0.0, 0.0)
	MeshFactory.box(static_root, Vector3(0.06, 0.07, 0.06), p + Vector3(0.08, 0.82, 0.27), Color("#ff6b6b"), 0.0, 0.0)
	MeshFactory.shape(static_root, "jug", Vector3(0.46, 0.6, 0.46), p + Vector3(0, 1.31, 0), Color("#8fd6f2"), 0.25)
	MeshFactory.shape(static_root, "cyl", Vector3(0.09, 0.3, 0.09), p + Vector3(0.3, 0.65, 0.05), Color("#fbf7ee"))
	_static_box(Vector3(0.6, 1.6, 0.6), p + Vector3(0, 0.8, 0))


func _prop_cabinet(p: Vector3) -> void:
	## Filing cabinet: three framed drawers with handles and label slots.
	var c := _pp("cabinet", "#a8b4e0")
	MeshFactory.box(static_root, Vector3(0.9, 1.35, 0.8), p + Vector3(0, 0.675, 0), c)
	for i in 3:
		var y := 0.25 + i * 0.42
		MeshFactory.box(static_root, Vector3(0.78, 0.36, 0.03), p + Vector3(0, y, 0.41), c.lightened(0.08), 0.0, 0.0)
		MeshFactory.box(static_root, Vector3(0.25, 0.05, 0.04), p + Vector3(0, y + 0.06, 0.44), c.darkened(0.45), 0.0, 0.0)
		MeshFactory.box(static_root, Vector3(0.16, 0.07, 0.01), p + Vector3(0, y - 0.07, 0.43), Color("#fbf7ee"), 0.0, 0.0)
	if rng.randf() < 0.5:
		_prop_papers(static_root, p + Vector3(rng.randf_range(-0.15, 0.15), 1.35, 0), rng.randi_range(2, 7), 0.04)
	elif rng.randf() < 0.5:
		_prop_plant_small(static_root, p + Vector3(0.15, 1.35, 0))
	_static_box(Vector3(0.9, 1.35, 0.8), p + Vector3(0, 0.675, 0))


func _prop_cables(p: Vector3) -> void:
	## A tangle of curved floor cables around a power strip. The cables mostly run
	## along one direction (like a real cable run) with a little spread.
	var cor := corruption_at(p)
	var cols := [Color("#2b2840"), Color("#3a3560"), Color("#5d6bb5"), Color("#e8e2f8"), Color("#ffcf4a")]
	var hot := _c("corrupt_color", "#ff4f8b")
	var run_yaw := rng.randf() * TAU
	var strip := _rot_node(p + Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3)), run_yaw + rng.randf_range(-0.4, 0.4))
	MeshFactory.box(strip, Vector3(0.62, 0.09, 0.16), Vector3(0, 0.045, 0), Color("#f3eee2"), 0.0, 0.025)
	for i in 3:
		MeshFactory.box(strip, Vector3(0.1, 0.06, 0.1), Vector3(-0.18 + i * 0.15, 0.11, 0), Color("#2b2840"), 0.0, 0.0)
	MeshFactory.box(strip, Vector3(0.07, 0.03, 0.07), Vector3(0.25, 0.1, 0), Color("#ff5a4a") if cor > 0.45 else Color("#7dffb0"), 2.5, 0.0)
	for i in rng.randi_range(3, 5):
		var col: Color = cols[rng.randi() % cols.size()]
		var emit := 0.0
		if rng.randf() < cor * 0.3:
			col = hot
			emit = 0.8
		var n := _rot_node(p + Vector3(rng.randf_range(-0.35, 0.35), 0, rng.randf_range(-0.35, 0.35)), run_yaw + rng.randf_range(-0.5, 0.5) + (PI if rng.randf() < 0.5 else 0.0))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshFactory.cable_mesh(rng.randi())
		mi.material_override = MeshFactory.clay(col, emit, 0.022)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(mi)
		# a plug on one end, the other end disappears under the strip or a desk
		MeshFactory.box(n, Vector3(0.15, 0.08, 0.1), Vector3(1.34, 0.04, 0), Color("#2b2840"), 0.0, 0.022)
		MeshFactory.box(n, Vector3(0.06, 0.02, 0.06), Vector3(1.43, 0.04, 0), Color("#c9c3d8"), 0.0, 0.0)


func _wall_box(n: Node3D, size: Vector3, pos: Vector3, color: Color, emit: float = 0.0, outline: float = 0.03) -> MeshInstance3D:
	## Tall wall-side props dither away when they hide the player, like walls do.
	var mi := MeshFactory.box(n, size, pos, color, emit, outline)
	mi.material_override = MeshFactory.clay(color, emit, MeshFactory.line_width(size, outline), true)
	return mi


func _yaw_box(size: Vector3, center: Vector3, yaw: float) -> void:
	## Collision for a prop turned by a multiple of 90 degrees.
	var s := size if absf(sin(yaw)) < 0.5 else Vector3(size.z, size.y, size.x)
	_static_box(s, center)


func _prop_floor_plant(p: Vector3, cor: float) -> void:
	## Big potted office plant; in corrupted zones it droops and turns glitch-pink.
	var n := _rot_node(p + Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2)), rng.randf() * TAU)
	var pot_col := Color(["#d9805f", "#f3eee2", "#5d6bb5", "#2b2840"][rng.randi() % 4])
	MeshFactory.shape(n, "pot", Vector3(0.6, 0.62, 0.6), Vector3(0, 0.31, 0), pot_col)
	MeshFactory.shape(n, "cyl", Vector3(0.48, 0.03, 0.48), Vector3(0, 0.6, 0), Color("#5a3d2e"))
	var green := _pp("plant", "#6fbf73").lerp(_c("corrupt_color", "#ff4f8b"), clampf(cor - 0.4, 0.0, 0.6))
	var droop := clampf(cor - 0.4, 0.0, 0.6)
	var count := rng.randi_range(9, 13)
	for i in count:
		var tall := float(i % 3 == 0)
		var yaw := TAU * i / count + rng.randf_range(-0.25, 0.25)
		var pitch := lerpf(0.35, 1.15, tall) + rng.randf_range(-0.15, 0.15) - droop
		var len := rng.randf_range(0.55, 0.8) + tall * 0.25
		_leaf(n, Vector3(0, 0.58 + tall * 0.15, 0), yaw, pitch, Vector3(0.24, 0.13, len), green.darkened(rng.randf() * 0.2).lightened(tall * 0.1))
	_static_box(Vector3(0.7, 1.4, 0.7), p + Vector3(0, 0.7, 0))


func _prop_shelf(p: Vector3, yaw: float) -> void:
	## Bookshelf against the wall, filled with books, binders and the odd box or plant.
	var n := _rot_node(p, yaw)
	var wood := _pp("desk", "#f2cf83").darkened(0.15)
	var z := -0.72
	var w := 1.7
	var h := 2.0
	_wall_box(n, Vector3(0.08, h, 0.46), Vector3(-w * 0.5, h * 0.5, z), wood)
	_wall_box(n, Vector3(0.08, h, 0.46), Vector3(w * 0.5, h * 0.5, z), wood)
	_wall_box(n, Vector3(w, h, 0.04), Vector3(0, h * 0.5, z - 0.21), wood.darkened(0.25), 0.0, 0.0)
	var book_cols := ["#e86f6f", "#5d7bd6", "#ffcf4a", "#7fd3c0", "#b58cf0", "#fbf7ee", "#f29a5b", "#3a3560"]
	for s in 4:
		var y := 0.06 + s * 0.48
		_wall_box(n, Vector3(w, 0.06, 0.46), Vector3(0, y, z), wood.darkened(0.05), 0.0, 0.025)
		if s == 3:
			break
		var x := -w * 0.5 + 0.08
		while x < w * 0.5 - 0.12:
			var bw := rng.randf_range(0.05, 0.11)
			var bh := rng.randf_range(0.26, 0.38)
			if rng.randf() < 0.08:
				x += 0.15  # a gap
				continue
			var book := _wall_box(n, Vector3(bw, bh, 0.32), Vector3(x + bw * 0.5, y + 0.03 + bh * 0.5, z + 0.03), Color(book_cols[rng.randi() % book_cols.size()]), 0.0, 0.0)
			if rng.randf() < 0.06:
				book.rotation.z = 0.25
			x += bw + 0.008
	var top_y := 0.06 + 3 * 0.48 + 0.03
	if rng.randf() < 0.5:
		_prop_plant_small(n, Vector3(rng.randf_range(-0.5, 0.5), top_y, z))
	else:
		_wall_box(n, Vector3(0.5, 0.3, 0.36), Vector3(rng.randf_range(-0.4, 0.4), top_y + 0.15, z), Color("#c9955f"))
	_yaw_box(Vector3(w + 0.08, h, 0.5), p + Basis(Vector3.UP, yaw) * Vector3(0, h * 0.5, z), yaw)


func _prop_vending(p: Vector3, yaw: float, cor: float) -> void:
	## Snack machine: lit window of snack rows, glowing header, coin panel, pickup flap.
	var n := _rot_node(p, yaw)
	var body := Color("#e8505b") if rng.randf() < 0.5 else Color("#4d6fd8")
	var z := -0.55
	_wall_box(n, Vector3(1.15, 2.1, 0.8), Vector3(0, 1.05, z), body)
	var glass_col := Color("#1d2240").lerp(_c("corrupt_color", "#ff4f8b"), clampf(cor - 0.5, 0.0, 0.5) * 0.4)
	MeshFactory.box(n, Vector3(0.72, 1.35, 0.02), Vector3(-0.14, 1.25, z + 0.41), glass_col, 0.0, 0.0)
	var snack_cols := ["#ffcf4a", "#ff6b8a", "#7fd3c0", "#f29a5b", "#b58cf0", "#fbf7ee"]
	for r in 5:
		var rc := Color(snack_cols[rng.randi() % snack_cols.size()])
		for k in 4:
			MeshFactory.box(n, Vector3(0.12, 0.17, 0.03), Vector3(-0.39 + k * 0.165, 0.73 + r * 0.25, z + 0.43), rc if rng.randf() > 0.15 else rc.darkened(0.6), 0.6, 0.0)
	MeshFactory.box(n, Vector3(1.0, 0.18, 0.03), Vector3(0, 2.0, z + 0.41), Color("#fff6dc"), 1.6, 0.0)
	MeshFactory.box(n, Vector3(0.24, 0.5, 0.03), Vector3(0.4, 1.4, z + 0.41), Color("#2b2840"), 0.0, 0.0)
	MeshFactory.box(n, Vector3(0.12, 0.05, 0.02), Vector3(0.4, 1.5, z + 0.43), Color("#7dffb0") if cor < 0.5 else Color("#ff5a4a"), 2.0, 0.0)
	MeshFactory.box(n, Vector3(0.7, 0.22, 0.03), Vector3(-0.14, 0.32, z + 0.41), Color("#2b2840"), 0.0, 0.0)
	_yaw_box(Vector3(1.15, 2.1, 0.8), p + Basis(Vector3.UP, yaw) * Vector3(0, 1.05, z), yaw)


func _prop_lamp(p: Vector3) -> void:
	## Floor lamp with a warm glowing shade.
	var metal := Color("#2b2840")
	MeshFactory.shape(static_root, "cyl", Vector3(0.4, 0.05, 0.4), p + Vector3(0, 0.025, 0), metal)
	MeshFactory.shape(static_root, "cyl", Vector3(0.05, 1.6, 0.05), p + Vector3(0, 0.82, 0), metal.lightened(0.2))
	MeshFactory.shape(static_root, "cyl", Vector3(0.5, 0.4, 0.5), p + Vector3(0, 1.72, 0), Color("#ffe2a8"), 1.4)
	_static_box(Vector3(0.45, 1.9, 0.45), p + Vector3(0, 0.95, 0))


# ------------------------------------------------------------------ shader warm-up

func _start_warm_up() -> void:
	## Shaders compile the first time something is drawn, which on macOS OpenGL
	## froze the game for ~0.45 s mid-fight. For a few frames behind the loading
	## fade we look at the whole level from above and show one of every effect,
	## so every material compiles now.
	_warm_cam = Camera3D.new()
	_warm_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_warm_cam.size = maxf(width, height) * CELL * 1.05
	_warm_cam.near = 1.0
	_warm_cam.far = 80.0
	add_child(_warm_cam)
	# Close enough that the floor sits inside the sun's shadow distance (shadow shaders compile too).
	_warm_cam.global_position = Vector3(width * CELL * 0.5, 28.0, height * CELL * 0.5)
	_warm_cam.rotation_degrees = Vector3(-90, 0, 0)
	_warm_cam.current = true
	var c := Vector3(width * CELL * 0.5, 0.0, height * CELL * 0.5)
	var holder := Node3D.new()
	add_child(holder)
	_warm_nodes.append(holder)
	Fx.burst(c + Vector3(0, 1, 0), Color.WHITE, 4, 1.0)
	Fx.text(c + Vector3(0, 2, 0), "0123456789!+GSTUNEDOPRMAIXLBCKHVWY-%", Color.WHITE)
	Fx.damage_number(c + Vector3(1, 2, 0), 12.0, true)
	Fx.ring(c, 1.0, Color.WHITE)
	Fx.digitize(c, 1.5, Color.WHITE)
	Fx.pixel_hit(c + Vector3(0, 1, 0), Color.WHITE, true)
	Fx.slash(c, Vector3.FORWARD, 2.0, 110.0, Color.WHITE)
	Fx.lightning(c + Vector3(0, 1, 0), c + Vector3(2, 1, 0), Color.WHITE)
	Fx.telegraph_circle(c, 1.0, 0.5)
	Fx.telegraph_rect(c, Vector3.FORWARD, 2.0, 1.0, 0.5)
	Fx.telegraph_sector(holder, 1.5, 90.0, 0.5)
	spawn_hazard(c, 1.0, 0.0, 0.3, Color.WHITE)
	for style in ["orb", "memo", "wave"]:
		var pr := Projectile.new()
		pr.style = style
		pr.hostile = style != "wave"
		pr.life = 0.15
		pr.damage = 0.0
		fx_root.add_child(pr)
		pr.global_position = c + Vector3(0, 1, 0)
	var samples := [
		[MeshFactory.mesh_for("gem", Vector3(0.3, 0.3, 0.3)), MeshFactory.glow(Color("#5ff2d0"), 4.0)],
		[MeshFactory.mesh_for("cyl", Vector3(0.2, 1.0, 0.2)), MeshFactory.unlit_shared(Color(1, 1, 1, 0.3), true)],
		[MeshFactory.unit_box(), MeshFactory.unlit_shared(Color(0.05, 0.05, 0.08, 0.85), false, true, 5)],
		[MeshFactory.unit_box(), MeshFactory.unlit(Color(1, 0.3, 0.3, 0.16), true)],
	]
	for s in samples:
		var mi := MeshInstance3D.new()
		mi.mesh = s[0]
		mi.material_override = s[1]
		holder.add_child(mi)
		mi.global_position = c + Vector3(0, 1.5, 0)
	for b in [BaseMaterial3D.BILLBOARD_ENABLED, BaseMaterial3D.BILLBOARD_FIXED_Y, BaseMaterial3D.BILLBOARD_DISABLED]:
		for nd in [true, false]:
			var l := Label3D.new()
			l.text = "Ag"
			l.billboard = b
			l.no_depth_test = nd
			l.outline_size = 10
			holder.add_child(l)
			l.global_position = c + Vector3(0, 2.0, 0)
	Fx.flash(holder, Color.WHITE, 0.2)
	_warm_frames = 0


func _finish_warm_up() -> void:
	_warm_frames = -1
	for n in _warm_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_warm_nodes.clear()
	if is_instance_valid(_warm_cam):
		_warm_cam.queue_free()
	if rig and rig.camera:
		rig.camera.current = true
	warmed = true
	ready_to_show.emit()


# ------------------------------------------------------------------ actors

func _spawn_player() -> void:
	player = Player.new()
	var pos := player_start
	if str(spawn_request.get("type", "")) == "computer":
		for gc in computers:
			if gc.computer_id == str(spawn_request.get("id", "")):
				var c := world_to_cell(gc.position)
				pos = cell_center(c) + _open_dir(c) * CELL
				break
	player.position = pos
	player.safe_zone = bool(level.get("safe", false))
	actors_root.add_child(player)
	rig.target = player
	rig.snap()


func _spawn_coworkers() -> void:
	## Ambient staff wandering the level ("coworkers" in the level JSON).
	var open: Array = []
	for y in height:
		for x in width:
			if rows[y][x] in ".," and cell_center(Vector2i(x, y)).distance_to(player_start) > 4.0:
				open.append(Vector2i(x, y))
	for i in mini(int(level.get("coworkers", 0)), open.size()):
		var cw := Coworker.new()
		cw.position = cell_center(open[rng.randi() % open.size()])
		actors_root.add_child(cw)


func _spawn_encounters() -> void:
	var enc: Dictionary = level.get("encounters", {})
	var lm := float(level.get("enemy_level", 1.0))
	for key in enc:
		for c in _markers.get(str(key), []):
			var e: Dictionary = enc[key]
			var spread := float(e.get("spread", 3.0))
			for pair in e.get("enemies", []):
				for i in int(pair[1]):
					spawn_enemy_near(str(pair[0]), cell_center(c), spread, GameState.clearance(), lm, false, true)


func _spawn_boss() -> void:
	if not level.has("boss"):
		return
	var ks: Array = _markers.get("K", [])
	if ks.is_empty():
		return
	boss = Boss.new()
	boss.setup_boss(str(level.boss), float(level.get("enemy_level", 1.0)), GameState.clearance())
	boss.position = cell_center(ks[0])
	boss.facing = Vector3.BACK
	actors_root.add_child(boss)


func _screen_near(pos: Vector3, max_dist: float = 9.0) -> Dictionary:
	## The closest lit screen with room left (3 viruses per screen), or {}.
	var best: Dictionary = {}
	var best_d := max_dist
	for s in screens:
		var d: float = Vector2(s.pos.x - pos.x, s.pos.z - pos.z).length()
		if d < best_d and int(s.used) < 3:
			best_d = d
			best = s
	return best


func spawn_enemy_near(id: String, center: Vector3, spread: float, tier: int, level_mult: float = -1.0, spawn_fx: bool = false, from_screen: bool = false) -> Enemy:
	if not DB.enemies.has(id):
		push_warning("[World] Unknown enemy id " + id)
		return null
	var lm := level_mult if level_mult > 0.0 else float(level.get("enemy_level", 1.0))
	var pos := center
	for attempt in 12:
		var cand := center + Vector3(rng.randf_range(-spread, spread), 0, rng.randf_range(-spread, spread))
		if is_walkable_pos(cand):
			pos = cand
			break
	var e := Enemy.new().setup(id, lm, tier)
	e.position = pos
	var cc: Dictionary = DB.progression.get("corrupted", {})
	if not level.get("safe", false) and rng.randf() < float(cc.get("base_chance", 0.06)) + float(cc.get("per_corruption", 0.22)) * corruption_at(pos):
		e.make_corrupted()
	if from_screen and not menu_mode:
		# encounter viruses wait inside a nearby PC screen and climb out when you come
		var s := _screen_near(pos)
		if not s.is_empty():
			s.used = int(s.used) + 1
			e.hide_in_screen(s.pos, s.facing)
	actors_root.add_child(e)
	if spawn_fx and not menu_mode:
		Fx.burst(pos + Vector3(0, 1, 0), MeshFactory.col(DB.enemies[id].get("color", "#ff4040")), 16, 5.0, 0.12, 0.5)
	return e


func spawn_enemy_projectile(pos: Vector3, dir: Vector3, spd: float, dmg: float, color: Color, on_hit: Callable = Callable(), style: String = "orb") -> void:
	var pr := Projectile.new()
	pr.vel = dir.normalized() * spd
	pr.damage = dmg
	pr.color = color
	pr.on_hit = on_hit
	pr.style = style
	pr.hostile = true
	fx_root.add_child(pr)
	pr.global_position = pos


func spawn_player_wave(pos: Vector3, dir: Vector3, mult: float, spd: float, reach: float, color: Color) -> void:
	var pr := Projectile.new()
	pr.vel = dir.normalized() * spd
	pr.mult = mult
	pr.color = color
	pr.style = "wave"
	pr.hostile = false
	pr.hit_radius = 1.3
	pr.life = reach / maxf(spd, 0.1)
	fx_root.add_child(pr)
	pr.global_position = pos + Vector3(0, 0.9, 0)


func spawn_hazard(pos: Vector3, r: float, dps: float, duration: float, color: Color) -> void:
	var h := Hazard.new()
	h.radius = r
	h.dps = dps
	h.life = duration
	h.color = color
	h.position = Vector3(pos.x, 0, pos.z)  # before add_child: _ready bursts at its position
	fx_root.add_child(h)


func spawn_gold(pos: Vector3, amount: int) -> void:
	var n := clampi(amount, 1, 8)
	for i in n:
		var pk := Pickup.new().setup("gold", float(amount) / n)
		pickups_root.add_child(pk)
		pk.global_position = Vector3(pos.x, 0, pos.z)


func spawn_corrupted_gold(pos: Vector3, amount: int) -> void:
	var n := clampi(amount, 1, 5)
	for i in n:
		# whole coins only: the remainder goes on the first ones
		var pk := Pickup.new().setup("cgold", float(amount / n + (1 if i < amount % n else 0)))
		pickups_root.add_child(pk)
		pk.global_position = Vector3(pos.x, 0, pos.z)


func drop_rewards(pos: Vector3, data: float, gold: int, table: String) -> void:
	var flat := Vector3(pos.x, 0, pos.z)
	var n_data := clampi(int(data / 4.0), 2, 18)
	for i in n_data:
		var pk := Pickup.new().setup("data", data / n_data)
		pickups_root.add_child(pk)
		pk.global_position = flat
	if gold > 0:
		spawn_gold(flat, gold)
	if GameState.has_profile():
		var luck := float(GameState.stats.get("loot_luck", 0.0))
		for inst in Loot.roll_table(table, int(GameState.profile.get("level", 1)), luck):
			var it := Pickup.new().setup("item", 0.0, inst)
			pickups_root.add_child(it)
			it.global_position = flat


func on_boss_defeated(b: Boss) -> void:
	dungeon_cleared = true
	for c in chests:
		c.unlock()
	for x in exits:
		x.set_active(true)
	GameState.on_boss_defeated(str(b.enemy_id))
	GameState.notify("Facilities Bot", "The meeting has been adjourned. Your Performance Bonus is waiting and the Emergency Exit is now unlocked. Security Clearance raised to Tier %d: the office is more dangerous, and more rewarding." % GameState.clearance(), "success")
	Audio.set_ambient("office")


# ------------------------------------------------------------------ queries

func has_los(a: Vector3, b: Vector3) -> bool:
	return ray_clear(a + Vector3(0, 0.6, 0), b + Vector3(0, 0.6, 0))


func ray_clear(a: Vector3, b: Vector3) -> bool:
	## True when no level geometry blocks a→b. The query object is reused: projectiles
	## call this every physics frame.
	if _space == null:
		_space = get_world_3d().direct_space_state
		_ray = PhysicsRayQueryParameters3D.create(a, b, Layers.WORLD)
	_ray.from = a
	_ray.to = b
	return _space.intersect_ray(_ray).is_empty()


func clamp_move(from: Vector3, dir: Vector3, dist: float) -> Vector3:
	## Furthest walkable point along dir (stops before walls).
	var best := from
	var steps := int(ceil(dist / 0.25))
	for i in range(1, steps + 1):
		var p := from + dir.normalized() * minf(i * 0.25, dist)
		if not is_walkable_pos(p) or not ray_clear(from + Vector3(0, 0.6, 0), p + Vector3(0, 0.6, 0)):
			break
		best = p
	return best


func find_path(from: Vector3, to: Vector3) -> PackedVector3Array:
	## A* over the cell grid. Ends standing beside a desk/table (inside a solid cell's
	## margin) snap to the nearest walkable cell instead of failing.
	var out := PackedVector3Array()
	var a := nearest_walkable_cell(world_to_cell(from))
	var b := nearest_walkable_cell(world_to_cell(to))
	if a == NO_CELL or b == NO_CELL:
		return out
	var ids := astar.get_id_path(a, b, true)
	for c in ids:
		out.append(cell_center(c))
	return out


func add_shake(amount: float) -> void:
	if rig:
		rig.shake = minf(1.2, maxf(rig.shake, amount))
	if amount >= 0.3:
		Controls.rumble(clampf(amount * 0.5, 0.0, 1.0), clampf(amount, 0.0, 1.0), 0.12 + amount * 0.15)


func hitstop(duration: float) -> void:
	Engine.time_scale = 0.05
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(func() -> void: Engine.time_scale = 1.0)


func _process(delta: float) -> void:
	if _warm_frames >= 0:
		_warm_frames += 1
		if _warm_frames >= 4:
			_finish_warm_up()
	if player != null and is_instance_valid(player):
		RenderingServer.global_shader_parameter_set("player_pos", player.global_position)
	for f in flicker:
		f.t -= delta
		if f.has("light"):
			if f.t <= 0.0:
				f.on = not f.on
				f.t = rng.randf_range(0.03, 0.15) if not f.on else rng.randf_range(0.1, 3.5)
				f.light.light_energy = f.energy if f.on else f.energy * 0.08
		elif f.has("blink"):
			if f.t <= 0.0:
				f.t = rng.randf_range(0.1, 0.8)
				f.blink.visible = not f.blink.visible
		elif f.has("glitch"):
			f.glitch.rotation.y += delta * 0.7
			if f.t <= 0.0:
				f.t = rng.randf_range(0.5, 2.5)
				f.glitch.position = f.base + Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.2, 0.2), 0)
