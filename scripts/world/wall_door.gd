class_name WallDoor
extends Interactable
## Anything mounted in a wall cell: meeting-room doors (red = dungeon entrance),
## elevators between floors, and the dungeon's emergency exit.

var kind := "door"          # door | elevator | exit
var face_dir := Vector3.BACK
var is_red := false
var dungeon_id := ""
var target_level := ""
var target_name := ""
var active := true
var _slab_mat: ShaderMaterial
var _light: OmniLight3D
var _label: Label3D
var _t := 0.0


func _ready() -> void:
	super._ready()
	radius = 3.0
	var face := Node3D.new()
	add_child(face)
	face.rotation.y = atan2(face_dir.x, face_dir.z)
	face.position = face_dir * 1.0
	match kind:
		"elevator": _build_elevator(face)
		"exit": _build_exit(face)
		_: _build_door(face)
	MeshBatcher.merge_children(face)
	_update_state()


func _build_door(face: Node3D) -> void:
	MeshFactory.box(face, Vector3(1.7, 2.3, 0.12), Vector3(0, 1.15, 0.0), Color("#4a3a2c"), 0.0, 0.02)
	var slab := MeshFactory.box(face, Vector3(1.4, 2.1, 0.1), Vector3(0, 1.05, 0.06), Color("#b38b5d"), 0.0, 0.02)
	MeshFactory.box(face, Vector3(0.1, 0.1, 0.1), Vector3(0.5, 1.05, 0.13), Color("#d0c090"), 0.3, 0.0)
	MeshFactory.box(face, Vector3(0.6, 0.18, 0.04), Vector3(0, 1.7, 0.12), Color("#e8e4d8"), 0.0, 0.0)
	if is_red:
		_slab_mat = MeshFactory.clay(Color("#b01020"), 2.0, 0.02, false, Color("#ff2030"), true)
		slab.material_override = _slab_mat
		_light = OmniLight3D.new()
		_light.light_color = Color("#ff2030")
		_light.light_energy = 3.0
		_light.omni_range = 6.0
		_light.position = Vector3(0, 1.4, 1.2)
		face.add_child(_light)
		_label = Interactable.label3d(face, "MEETING IN PROGRESS", Vector3(0, 2.9, 0.4), Color("#ff5060"), 0.75)
		var sparks := Fx._new_particles()
		sparks.one_shot = false
		sparks.amount = 3
		sparks.lifetime = 0.5
		sparks.explosiveness = 0.0
		sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		sparks.emission_box_extents = Vector3(0.7, 0.85, 0.0)
		sparks.initial_velocity_min = 0.4
		sparks.initial_velocity_max = 1.0
		sparks.gravity = Vector3(0, 1.5, 0)
		sparks.mesh = Fx.particle_mesh(0.08, Color("#ff2030"), 3.0)
		add_child(sparks)
		sparks.position = face_dir * 1.3 + Vector3(0, 1.15, 0)
		sparks.emitting = true
		prompt = "Open the red meeting room door"
	else:
		Interactable.label3d(face, "CONF. ROOM", Vector3(0, 2.6, 0.3), Color(0.9, 0.88, 0.8, 0.7), 0.5)


func _build_elevator(face: Node3D) -> void:
	MeshFactory.box(face, Vector3(1.9, 2.4, 0.14), Vector3(0, 1.2, 0), Color("#7a7d86"), 0.0, 0.02)
	MeshFactory.box(face, Vector3(0.78, 2.1, 0.08), Vector3(-0.4, 1.05, 0.09), Color("#b8bcc4"), 0.0, 0.01)
	MeshFactory.box(face, Vector3(0.78, 2.1, 0.08), Vector3(0.4, 1.05, 0.09), Color("#b8bcc4"), 0.0, 0.01)
	MeshFactory.box(face, Vector3(0.14, 0.3, 0.06), Vector3(1.05, 1.2, 0.1), Color("#33343a"), 0.0, 0.0)
	MeshFactory.box(face, Vector3(0.07, 0.07, 0.04), Vector3(1.05, 1.27, 0.14), Color("#ffcc55"), 3.0, 0.0)
	MeshFactory.box(face, Vector3(0.07, 0.07, 0.04), Vector3(1.05, 1.13, 0.14), Color("#ffcc55"), 3.0, 0.0)
	MeshFactory.box(face, Vector3(0.7, 0.22, 0.04), Vector3(0, 2.25, 0.1), Color("#1a1a1a"), 0.0, 0.0)
	_label = Interactable.label3d(face, "ELEVATOR - " + target_name.to_upper(), Vector3(0, 2.9, 0.4), Color("#ffd27a"), 0.6)
	prompt = "Take the elevator to %s" % target_name


func _build_exit(face: Node3D) -> void:
	MeshFactory.box(face, Vector3(1.9, 2.4, 0.14), Vector3(0, 1.2, 0), Color("#3a3d44"), 0.0, 0.02)
	var slab := MeshFactory.box(face, Vector3(1.5, 2.1, 0.1), Vector3(0, 1.05, 0.08), Color("#2f6f4a"), 0.0, 0.02)
	_slab_mat = MeshFactory.clay(Color("#2f6f4a"), 0.0, 0.02, false, Color("#39ff88"), true)
	slab.material_override = _slab_mat
	MeshFactory.box(face, Vector3(0.9, 0.3, 0.06), Vector3(0, 2.35, 0.12), Color("#39ff88"), 2.5, 0.0)
	_light = OmniLight3D.new()
	_light.light_color = Color("#39ff88")
	_light.omni_range = 7.0
	_light.position = Vector3(0, 1.8, 1.4)
	face.add_child(_light)
	_label = Interactable.label3d(face, "EMERGENCY EXIT", Vector3(0, 3.0, 0.4), Color("#7dffb0"), 0.7)


func set_active(v: bool) -> void:
	active = v
	_update_state()


func _update_state() -> void:
	match kind:
		"door":
			enabled = is_red
		"exit":
			enabled = active
			prompt = "Leave through the %s (return to the Lobby)" % target_name if active else "Locked - defeat the boss"
			if _slab_mat:
				_slab_mat.set_shader_parameter("emission_energy", 1.6 if active else 0.0)
			if _light:
				_light.light_energy = 2.5 if active else 0.0
			if _label:
				_label.text = "EMERGENCY EXIT" if active else "EXIT LOCKED"
				_label.modulate = Color("#7dffb0") if active else Color("#ff6070")
		"elevator":
			enabled = true


func _process(delta: float) -> void:
	if kind == "door" and is_red and _slab_mat:
		_t += delta
		var pulse := 1.5 + sin(_t * 3.0) * 0.8 + (2.0 if randf() < 0.03 else 0.0)
		_slab_mat.set_shader_parameter("emission_energy", pulse)
		if _light:
			_light.light_energy = 2.0 + pulse * 0.6


func interact(_player) -> void:
	if not enabled or GameState.ui == null:
		return
	match kind:
		"door":
			Audio.play("door")
			GameState.ui.show_dungeon_invite(dungeon_id)
		"elevator":
			Audio.play("door")
			GameState.main.travel(target_level, {"type": "start"})
		"exit":
			Audio.play("teleport")
			GameState.main.travel(target_level, {"type": "start"})
