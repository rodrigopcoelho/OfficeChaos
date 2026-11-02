class_name Projectile
extends Node3D
## Straight-flying projectile. Hostile ones hurt the player; friendly ones (DATA waves)
## pierce through enemies. Walls stop both.

var vel := Vector3.ZERO
var damage := 5.0
var hit_radius := 0.45
var life := 4.0
var hostile := true
var on_hit: Callable
var color := Color.WHITE
var style := "orb"
var mult := 0.5
var _hit: Array = []


func _ready() -> void:
	var mi := MeshInstance3D.new()
	match style:
		"memo":
			mi.mesh = MeshFactory.mesh_for("box", Vector3(0.42, 0.05, 0.55))
			mi.material_override = MeshFactory.clay(color, 1.6, 0.0)
		"wave":
			mi.mesh = MeshFactory.sector_mesh(1.4, 80.0, 1.0, 10)
			mi.material_override = MeshFactory.unlit(Color(color.r, color.g, color.b, 0.75), true)
		_:
			mi.mesh = MeshFactory.mesh_for("gem", Vector3(0.42, 0.42, 0.42))
			mi.material_override = MeshFactory.glow(color, 3.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	if vel.length() > 0.01:
		rotation.y = atan2(-vel.x, -vel.z)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var next := global_position + vel * delta
	if GameState.world == null or not GameState.world.ray_clear(global_position, next):
		Fx.burst(global_position, color, 6, 3.0, 0.08, 0.3, 0.0)
		queue_free()
		return
	global_position = next
	if style == "memo":
		rotation.y += delta * 12.0
	if hostile:
		var p = GameState.player
		if p != null and is_instance_valid(p) and not p.dead:
			var d := Vector2(p.global_position.x - next.x, p.global_position.z - next.z).length()
			if d < hit_radius + float(p.radius):
				if p.invuln <= 0.0:
					p.take_damage(damage, global_position - vel.normalized())
					if on_hit.is_valid():
						on_hit.call()
					Fx.burst(global_position, color, 8, 3.0, 0.08, 0.3, 0.0)
					queue_free()
	else:
		for e in Combat.enemies_in_radius(global_position, hit_radius):
			if e in _hit:
				continue
			_hit.append(e)
			Combat.player_strike(GameState.player, e, mult, {"proc": true, "knockback_mult": 0.5})
