class_name Coworker
extends Node3D
## Ambient office worker: wanders the level along the A* grid, pauses to sip coffee or
## look around, and turns to watch the player go by. Pure decoration: no collision,
## never blocks anyone (it simply waits while the player stands in its way).

const WALK_SPEED := 1.5
const ARRIVE := 0.15

var visual: CharacterVisual
var _path := PackedVector3Array()
var _wait := 0.0
var _speed := 0.0
var _heading := Vector3.BACK


func _ready() -> void:
	visual = CharacterVisual.new()
	add_child(visual)
	visual.build(_random_look())
	if randf() < 0.6:
		# a mug or a stack of papers in the free hand
		var c := Color(["#ff6b8a", "#5d7bd6", "#7fd3c0", "#ffcf4a", "#fbf7ee"][randi() % 5])
		if randf() < 0.65:
			MeshFactory.shape(visual.offhand, "mug", Vector3(0.13, 0.14, 0.11), Vector3(0, 0.02, -0.06), c)
		else:
			MeshFactory.box(visual.offhand, Vector3(0.24, 0.05, 0.3), Vector3(0, 0.02, -0.08), Color("#fbf7ee"), 0.0, 0.0)
	_wait = randf_range(0.0, 3.0)
	visual.rotation.y = randf() * TAU


static func _random_look() -> Dictionary:
	var look := {}
	for pair in [["bodies", "body"], ["hair_styles", "hair"], ["faces", "face"], ["palettes", "palette"]]:
		look[pair[1]] = randi() % maxi((DB.appearance.get(pair[0], []) as Array).size(), 1)
	return look


func _physics_process(delta: float) -> void:
	var w: GameWorld = GameState.world
	if w == null:
		return
	var target_speed := 0.0
	var p = GameState.player
	var near_player := false
	var to_player := Vector3.ZERO
	if p != null and is_instance_valid(p):
		to_player = p.global_position - global_position
		to_player.y = 0
		near_player = to_player.length() < 3.0
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_pick_destination(w)
	elif _path.is_empty():
		_wait = randf_range(2.0, 6.0)
		if randf() < 0.3:
			visual.express("happy", 1.2)
	else:
		var goal := _path[0]
		var to := goal - global_position
		to.y = 0
		if to.length() < ARRIVE:
			_path.remove_at(0)
		else:
			_heading = to.normalized()
			# make way: hold still while the player stands right in front
			var blocked := near_player and to_player.length() < 1.3 and _heading.dot(to_player.normalized()) > 0.5
			target_speed = 0.0 if blocked else WALK_SPEED
	_speed = lerpf(_speed, target_speed, 1.0 - exp(-6.0 * delta))
	global_position += _heading * _speed * delta
	if _speed > 0.2:
		visual.face_smooth(_heading, delta, 7.0)
	elif near_player:
		visual.face_smooth(to_player.normalized(), delta, 3.0)
	visual.animate(_speed / 6.5 * 2.2, delta)


func _pick_destination(w: GameWorld) -> void:
	for attempt in 10:
		var c := Vector2i(randi_range(1, w.width - 2), randi_range(1, w.height - 2))
		if not w.is_walkable_cell(c):
			continue
		var path := w.find_path(global_position, w.cell_center(c))
		if path.size() >= 2:
			# jitter the waypoints so walkers don't all march down cell centres
			for i in range(1, path.size()):
				path[i] += Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			path.remove_at(0)
			_path = path
			return
	_wait = 1.0
