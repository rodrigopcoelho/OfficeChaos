class_name Hazard
extends Node3D
## Corrupted floor zone: damages the player over time while they stand inside.

var radius := 2.0
var dps := 10.0
var life := 5.0
var color := Color("#c22cff")
var _tick := 0.0
var _mat: StandardMaterial3D
var _age := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.sector_mesh(radius, 360.0, 0.0, 32)
	_mat = MeshFactory.unlit(Color(color.r, color.g, color.b, 0.0), true)
	mi.material_override = _mat
	mi.position.y = 0.04
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var edge := MeshInstance3D.new()
	edge.mesh = MeshFactory.ring_mesh(radius - 0.15, radius, 40)
	edge.material_override = MeshFactory.unlit_shared(Color(color.r, color.g, color.b, 0.9), true)
	edge.position.y = 0.05
	add_child(edge)
	Fx.burst(global_position + Vector3(0, 0.3, 0), color, 14, 4.0, 0.12, 0.5, 2.0)
	# Rising sparks from one looping emitter (was a new particle node every few frames).
	var sparks := Fx._new_particles()
	sparks.one_shot = false
	sparks.amount = 6
	sparks.lifetime = 0.6
	sparks.explosiveness = 0.0
	sparks.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	sparks.emission_box_extents = Vector3(radius * 0.7, 0.0, radius * 0.7)
	sparks.initial_velocity_min = 0.6
	sparks.initial_velocity_max = 1.5
	sparks.gravity = Vector3(0, 2.5, 0)
	sparks.mesh = Fx.particle_mesh(0.1, color, 3.0)
	sparks.position.y = 0.1
	add_child(sparks)
	sparks.emitting = true


func _physics_process(delta: float) -> void:
	_age += delta
	life -= delta
	_mat.albedo_color.a = (0.35 + 0.15 * sin(_age * 8.0)) * clampf(life, 0.0, 1.0)
	if life <= 0.0:
		queue_free()
		return
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.4
	var p := GameState.player
	if p != null and is_instance_valid(p) and not p.dead:
		var d := Vector2(p.global_position.x - global_position.x, p.global_position.z - global_position.z).length()
		if d <= radius:
			p.take_damage(dps * 0.4)
