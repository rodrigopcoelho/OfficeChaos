class_name Enemy
extends CharacterBody3D
## Data-driven corrupted process. Stats, movement style, attack pattern, optional
## aura/summon/blink behaviours and appearance all come from enemies.json.

var def: Dictionary = {}
var enemy_id := ""
var display_name := ""
var max_hp := 30.0
var hp := 30.0
var damage := 8.0
var speed := 3.0
var armor := 0.0
var radius := 0.45
var detect_range := 11.0
var poise := 1.0
var reward_mult := 1.0
var tier := 0
var move_style := "chase"
var attack: Dictionary = {}
var state := "chase"
var state_t := 0.0
var attack_cd := 0.6
var aggro := false
var dead := false
var stun_t := 0.0
var dots: Array = []
var buff_t := 0.0
var buff_dmg := 1.0
var buff_spd := 1.0
var pivot: Node3D
var visual: Node3D
var parts: Dictionary = {}
var knock := Vector3.ZERO
var facing := Vector3.FORWARD
var telegraph: Node3D = null
var home := Vector3.ZERO
var wander_target := Vector3.ZERO
var wander_t := 0.0
var path: PackedVector3Array = PackedVector3Array()
var path_i := 0
var path_t := 0.0
var los := false
var los_t := 0.0
var strafe := 1.0
var erratic_t := 0.0
var summon_t := 5.0
var aura_t := 0.0
var anim_t := 0.0
var lunge_t := 0.0
var lunge_hit := false
var hp_bar: Node3D
var hp_fill: Node3D
var move_vel := Vector3.ZERO
var minions: Array = []
var is_boss := false
var height := 1.8
var float_h := 0.0
var aura_ring: MeshInstance3D
var move_blend := 0.0  # smoothed walk amount (knockback no longer jerks the legs)
var corrupted := false  # a stronger variant that drops Corrupted Gold (make_corrupted)
var _corrupt_fx: Node3D
var _hit_tween: Tween


func setup(id: String, level_mult: float = 1.0, clearance_tier: int = 0) -> Enemy:
	enemy_id = id
	setup_from_def(DB.enemies.get(id, {}), level_mult, clearance_tier)
	return self


func setup_from_def(d: Dictionary, level_mult: float, clearance_tier: int) -> void:
	def = d
	tier = clearance_tier
	var cl: Dictionary = DB.progression.get("clearance", {})
	# Difficulty follows the player's gear Power (Minecraft Dungeons style) on top of
	# the level's base difficulty and the Security Clearance tier.
	var pw: Dictionary = DB.progression.get("power", {})
	var p := GameState.power() - 1
	var hp_scale := level_mult * (1.0 + float(cl.get("enemy_hp_per_tier", 0.45)) * tier) * (1.0 + float(pw.get("enemy_hp_per_power", 0.12)) * p)
	var dmg_scale := level_mult * (1.0 + float(cl.get("enemy_damage_per_tier", 0.3)) * tier) * (1.0 + float(pw.get("enemy_damage_per_power", 0.09)) * p)
	reward_mult = level_mult * (1.0 + float(cl.get("reward_per_tier", 0.35)) * tier) * (1.0 + float(pw.get("reward_per_power", 0.06)) * p)
	display_name = str(def.get("name", enemy_id))
	max_hp = float(def.get("hp", 30)) * hp_scale
	hp = max_hp
	damage = float(def.get("damage", 8)) * dmg_scale
	speed = float(def.get("speed", 3.0))
	armor = float(def.get("armor", 0.0))
	radius = float(def.get("radius", 0.45))
	detect_range = float(def.get("detect_range", 11.0))
	poise = float(def.get("poise", 1.0))
	move_style = str(def.get("move", "chase"))
	attack = def.get("attack", {})
	var vis: Dictionary = def.get("visual", {})
	height = float(vis.get("height", 1.8)) * float(vis.get("scale", 1.0))
	float_h = float(vis.get("float", 0.0))


func make_corrupted() -> void:
	## Turns this enemy into its corrupted variant (call before adding it to the tree).
	var c: Dictionary = DB.progression.get("corrupted", {})
	corrupted = true
	max_hp *= float(c.get("hp_mult", 2.0))
	hp = max_hp
	damage *= float(c.get("damage_mult", 1.45))
	speed *= float(c.get("speed_mult", 1.15))
	armor = minf(0.6, armor + float(c.get("armor_bonus", 0.1)))
	reward_mult *= float(c.get("reward_mult", 1.6))
	poise *= 1.3
	display_name = "Corrupted " + display_name


func _build_corruption_fx() -> void:
	## Glitch-violet aura: a spinning ground sigil, a crown shard and a slightly bigger body.
	_corrupt_fx = Node3D.new()
	add_child(_corrupt_fx)
	var ring := MeshInstance3D.new()
	ring.mesh = MeshFactory.ring_mesh(radius + 0.25, radius + 0.42, 32)
	ring.material_override = MeshFactory.unlit_shared(Color(0.75, 0.25, 1.0, 0.7), true)
	ring.position.y = 0.05
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_corrupt_fx.add_child(ring)
	var shard := MeshInstance3D.new()
	shard.mesh = MeshFactory.mesh_for("gem", Vector3(0.22, 0.34, 0.22))
	shard.material_override = MeshFactory.glow(Color("#c04bff"), 4.0)
	shard.position.y = height + 0.3 + float_h
	shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_corrupt_fx.add_child(shard)
	visual.scale *= 1.12
	Fx.flash(visual, Color("#c04bff"), 0.4)


func _ready() -> void:
	add_to_group("enemies")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = Layers.ENEMIES
	collision_mask = Layers.WORLD | Layers.PLAYER | Layers.ENEMIES
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height * 0.8, radius * 2.0 + 0.1)
	shape.shape = cap
	shape.position.y = cap.height * 0.5
	add_child(shape)
	pivot = Node3D.new()
	add_child(pivot)
	visual = Node3D.new()
	pivot.add_child(visual)
	var vis: Dictionary = def.get("visual", {})
	visual.scale = Vector3.ONE * float(vis.get("scale", 1.0))
	parts = MeshFactory.build(vis.get("parts", []), visual, {}, 0.02, vis.get("groups", {}), true, true)
	if corrupted:
		_build_corruption_fx()
	_build_hp_bar()
	if def.has("aura"):
		aura_ring = MeshInstance3D.new()
		var ar := float(def.aura.get("radius", 8.0))
		aura_ring.mesh = MeshFactory.ring_mesh(ar - 0.15, ar, 48)
		aura_ring.material_override = MeshFactory.unlit(MeshFactory.col(def.get("color", "#c22cff")) * Color(1, 1, 1, 0.35), true)
		aura_ring.position.y = 0.05
		aura_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(aura_ring)
	home = global_position
	wander_target = home
	strafe = 1.0 if randf() < 0.5 else -1.0
	anim_t = randf() * 10.0


static var _quad: QuadMesh


static func _unit_quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2.ONE
	return _quad


func _build_hp_bar() -> void:
	hp_bar = Node3D.new()
	add_child(hp_bar)
	hp_bar.position = Vector3(0, height + 0.45 + float_h, 0)
	hp_bar.rotation.x = CameraRig.PITCH
	var tagged: bool = def.get("elite", false) or corrupted
	var w := 1.4 if tagged else 1.0
	var bg := MeshInstance3D.new()
	bg.mesh = _unit_quad()
	bg.scale = Vector3(w + 0.06, 0.16, 1.0)
	bg.material_override = MeshFactory.unlit_shared(Color(0.05, 0.05, 0.08, 0.85), false, true, 5)
	hp_bar.add_child(bg)
	hp_fill = Node3D.new()
	hp_fill.position = Vector3(-w * 0.5, 0, 0.002)
	hp_bar.add_child(hp_fill)
	var fill := MeshInstance3D.new()
	fill.mesh = _unit_quad()
	fill.scale = Vector3(w, 0.11, 1.0)
	fill.position.x = w * 0.5
	var fcol := Color("#c22cff") if tagged else Color("#e0525a")
	fill.material_override = MeshFactory.unlit_shared(fcol, false, true, 6)
	hp_fill.add_child(fill)
	for mi in [bg, fill]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if tagged:
		var l := Label3D.new()
		l.text = display_name.to_upper()
		l.font_size = 40
		l.outline_size = 10
		l.pixel_size = 0.005
		l.no_depth_test = true
		l.modulate = Color("#e9d5ff")
		l.position = Vector3(0, 0.22, 0)
		hp_bar.add_child(l)
	hp_bar.visible = false


func _update_hp_bar() -> void:
	if hp_bar == null or is_boss:
		return
	hp_bar.visible = hp < max_hp and not dead
	hp_fill.scale.x = clampf(hp / max_hp, 0.001, 1.0)


# ------------------------------------------------------------------ AI

func _physics_process(delta: float) -> void:
	if dead:
		return
	anim_t += delta
	_tick_status(delta)
	if dead:
		return
	var p = GameState.player
	var desired := Vector3.ZERO
	if p == null or not is_instance_valid(p) or p.dead:
		_cancel_attack()
		desired = _wander(delta)
		_move(desired, delta)
		_animate(delta, desired)
		return
	var to_p: Vector3 = p.global_position - global_position
	to_p.y = 0
	var dist := to_p.length()
	los_t -= delta
	if los_t <= 0.0:
		los_t = 0.2 + randf() * 0.1
		los = GameState.world.has_los(global_position, p.global_position)
	if not aggro and ((dist < detect_range and los) or dist < 3.0):
		alert()
	attack_cd = maxf(0.0, attack_cd - delta)
	if stun_t > 0.0:
		stun_t -= delta
		_cancel_attack()
	elif not aggro:
		desired = _wander(delta)
	else:
		match state:
			"windup":
				state_t -= delta
				if state_t <= 0.0:
					_strike(p)
			"lunge":
				lunge_t -= delta
				if not lunge_hit and global_position.distance_to(p.global_position) < radius + 0.9:
					lunge_hit = true
					p.take_damage(damage * buff_dmg, global_position)
				if lunge_t <= 0.0:
					state = "recover"
					state_t = float(attack.get("recover", 0.4))
			"recover":
				state_t -= delta
				desired = _chase_dir(p, dist) * 0.35
				if state_t <= 0.0:
					state = "chase"
			_:
				desired = _chase(p, dist, to_p, delta)
		_behaviours(delta, p, dist)
	if state != "windup" and state != "lunge" and desired.length() > 0.05:
		facing = desired.normalized()
	elif aggro and state == "chase" and dist > 0.1:
		facing = to_p.normalized()
	_move(desired, delta)
	_animate(delta, desired)


func alert() -> void:
	if aggro:
		return
	aggro = true
	Fx.text(global_position + Vector3(0, height + 0.9, 0), "!", Color("#ff4040"), 1.3, 0.5, 0.6)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != self and not e.aggro and global_position.distance_to(e.global_position) < 8.0:
			e.aggro = true


func _wander(delta: float) -> Vector3:
	wander_t -= delta
	if wander_t <= 0.0:
		wander_t = randf_range(2.0, 4.5)
		var cand := home + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		wander_target = cand if GameState.world.is_walkable_pos(cand) else home
	var to := wander_target - global_position
	to.y = 0
	if to.length() < 0.4:
		return Vector3.ZERO
	return to.normalized() * 0.35


func _chase(p, dist: float, to_p: Vector3, delta: float) -> Vector3:
	var a_range := float(attack.get("range", 1.6))
	match move_style:
		"kite":
			var pref := float(def.get("preferred_range", 7.0))
			if los and dist <= a_range and attack_cd <= 0.0:
				_begin_windup(p)
				return Vector3.ZERO
			var perp := Vector3(-to_p.z, 0, to_p.x).normalized() * strafe
			if dist < pref - 1.5:
				return (-to_p.normalized() + perp * 0.4).normalized()
			if dist > pref + 1.0 or not los:
				return _chase_dir(p, dist)
			erratic_t -= delta
			if erratic_t <= 0.0:
				erratic_t = randf_range(1.0, 2.5)
				strafe = -strafe
			return perp * 0.6
		"erratic":
			erratic_t -= delta
			if erratic_t <= 0.0:
				erratic_t = randf_range(0.25, 0.7)
				strafe = 1.0 if randf() < 0.5 else -1.0
			var blink: Dictionary = def.get("blink", {})
			if not blink.is_empty() and dist > 3.0 and randf() < float(blink.get("chance_per_sec", 0.2)) * delta:
				_blink(p, float(blink.get("distance", 3.0)))
			if dist <= a_range and attack_cd <= 0.0 and los:
				_begin_windup(p)
				return Vector3.ZERO
			var dir := _chase_dir(p, dist)
			var side := Vector3(-dir.z, 0, dir.x) * strafe
			return (dir + side * 0.9).normalized()
		_:
			if dist <= a_range and attack_cd <= 0.0 and los:
				_begin_windup(p)
				return Vector3.ZERO
			if dist <= a_range * 0.75:
				return Vector3.ZERO
			return _chase_dir(p, dist)


func _chase_dir(p, _dist: float) -> Vector3:
	var to: Vector3 = p.global_position - global_position
	to.y = 0
	if los:
		path = PackedVector3Array()
		return to.normalized()
	path_t -= get_physics_process_delta_time()
	if path_t <= 0.0 or path.size() == 0:
		path_t = 0.5 + randf() * 0.2
		path = GameState.world.find_path(global_position, p.global_position)
		path_i = 1
	while path_i < path.size() and Vector2(path[path_i].x - global_position.x, path[path_i].z - global_position.z).length() < 0.7:
		path_i += 1
	if path_i < path.size():
		var t := path[path_i] - global_position
		t.y = 0
		return t.normalized()
	return to.normalized()


func _blink(p, distance: float) -> void:
	var to: Vector3 = p.global_position - global_position
	to.y = 0
	var side := Vector3(-to.z, 0, to.x).normalized() * (1.0 if randf() < 0.5 else -1.0)
	var dest := global_position + (to.normalized() + side * 0.6).normalized() * distance
	if not GameState.world.is_walkable_pos(dest) or not GameState.world.has_los(global_position, dest):
		return
	Fx.burst(global_position + Vector3(0, 0.5, 0), MeshFactory.col(def.get("color", "#39ff88")), 10, 3.0, 0.1, 0.3, 0.0)
	global_position = dest
	Fx.burst(global_position + Vector3(0, 0.5, 0), MeshFactory.col(def.get("color", "#39ff88")), 10, 3.0, 0.1, 0.3, 0.0)
	Audio.play("zap", -12.0)


func _begin_windup(p) -> void:
	state = "windup"
	state_t = float(attack.get("windup", 0.5))
	var to: Vector3 = p.global_position - global_position
	to.y = 0
	if to.length() > 0.05:
		facing = to.normalized()
	# (the pivot turns to `facing` quickly in _animate rather than snapping)
	var tcol := Color(1, 0.15, 0.2)
	match str(attack.get("type", "melee")):
		"melee":
			telegraph = Fx.telegraph_sector(pivot, float(attack.get("range", 1.6)) + 0.3, float(attack.get("arc", 100)), state_t, tcol)
		"slam":
			telegraph = Fx.telegraph_circle(global_position, float(attack.get("radius", 2.5)), state_t, tcol)
		"lunge":
			telegraph = Fx.telegraph_rect(global_position, facing, float(attack.get("distance", 3.0)) + 0.8, radius * 2.2, state_t, tcol)
		"projectile":
			Fx.flash(visual, MeshFactory.col(attack.get("color", "#c050ff")), state_t)
	Audio.play("telegraph", -14.0)


func _cancel_attack() -> void:
	if telegraph != null and is_instance_valid(telegraph):
		telegraph.queue_free()
	telegraph = null
	if state == "windup" or state == "lunge":
		state = "chase"


func _strike(p) -> void:
	telegraph = null
	state = "recover"
	state_t = float(attack.get("recover", 0.4))
	attack_cd = float(attack.get("cooldown", 1.2))
	var dmg := damage * buff_dmg
	var to: Vector3 = p.global_position - global_position
	to.y = 0
	match str(attack.get("type", "melee")):
		"melee":
			knock += facing * 3.0
			var reach := float(attack.get("range", 1.6)) + float(p.radius) + 0.3
			var half := deg_to_rad(float(attack.get("arc", 100))) * 0.5 + 0.25
			if to.length() <= reach and (to.length() < 0.5 or absf(facing.angle_to(to.normalized())) <= half):
				p.take_damage(dmg, global_position)
			Audio.play("swing", -6.0)
		"slam":
			var r := float(attack.get("radius", 2.5))
			Fx.ring(global_position, r, Color(1, 0.4, 0.2), 0.3)
			Fx.burst(global_position + Vector3(0, 0.2, 0), Color("#6c6f78"), 14, 5.0, 0.15, 0.5)
			Audio.play("slam", -6.0)
			GameState.world.add_shake(0.25)
			if to.length() <= r + 0.3:
				p.take_damage(dmg, global_position)
		"lunge":
			state = "lunge"
			lunge_t = float(attack.get("lunge_time", 0.22))
			lunge_hit = false
			Audio.play("dodge", -8.0)
		"projectile":
			var count := int(attack.get("count", 1))
			var spread := deg_to_rad(float(attack.get("spread", 0)))
			var base_dir := to.normalized()
			for i in count:
				var a := 0.0 if count == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (count - 1))
				var dir := base_dir.rotated(Vector3.UP, a)
				var drain := float(attack.get("drain", 0.0))
				var cb := Callable()
				if drain > 0.0:
					cb = _on_drain_hit.bind(dmg * drain)
				GameState.world.spawn_enemy_projectile(global_position + Vector3(0, 1.1 + float_h * 0.5, 0) + dir * 0.6, dir, float(attack.get("speed", 9.0)), dmg, MeshFactory.col(attack.get("color", "#c050ff")), cb)
			Audio.play("shoot", -6.0)


func _on_drain_hit(amount: float) -> void:
	if dead:
		return
	hp = minf(max_hp, hp + amount)
	_update_hp_bar()
	var p = GameState.player
	if p != null and is_instance_valid(p):
		Fx.lightning(global_position + Vector3(0, 1.2, 0), p.global_position + Vector3(0, 1.0, 0), Color("#c050ff"), 0.3)
		Fx.text(p.global_position + Vector3(0, 2.6, 0), "DRAINED", Color("#c050ff"), 0.8)


func _behaviours(delta: float, _p, dist: float) -> void:
	if def.has("aura"):
		aura_t -= delta
		if aura_t <= 0.0:
			aura_t = 0.5
			var a: Dictionary = def.aura
			for e in Combat.enemies_in_radius(global_position, float(a.get("radius", 8.0)), self):
				e.buff_t = 1.0
				e.buff_dmg = float(a.get("damage_mult", 1.25))
				e.buff_spd = float(a.get("speed_mult", 1.3))
	if def.has("summon") and dist < 16.0:
		summon_t -= delta
		if summon_t <= 0.0:
			var s: Dictionary = def.summon
			summon_t = float(s.get("interval", 9.0))
			minions = minions.filter(func(m): return is_instance_valid(m) and not m.dead)
			var n := mini(int(s.get("count", 2)), int(s.get("max", 3)) - minions.size())
			if n > 0:
				Fx.text(global_position + Vector3(0, height + 0.9, 0), "DELEGATING!", MeshFactory.col(def.get("color", "#c22cff")), 1.0)
				for i in n:
					var m := GameState.world.spawn_enemy_near(str(s.get("id", "trojan")), global_position, 2.5, tier, -1.0, true)
					if m != null:
						m.aggro = true
						minions.append(m)


func _tick_status(delta: float) -> void:
	if buff_t > 0.0:
		buff_t -= delta
		if buff_t <= 0.0:
			buff_dmg = 1.0
			buff_spd = 1.0
	if dots.is_empty():
		return
	for d in dots:
		d.t -= delta
		d.tick -= delta
		if d.tick <= 0.0:
			d.tick = 0.5
			var amount := float(d.dps) * 0.5
			hp -= amount
			Fx.damage_number(global_position + Vector3(randf_range(-0.3, 0.3), height, 0), amount, false, d.color)
			Fx.burst(global_position + Vector3(0, height * 0.6, 0), d.color, 4, 2.0, 0.08, 0.35, 2.0)
			_update_hp_bar()
			if hp <= 0.0:
				die(true)
				return
	dots = dots.filter(func(d): return d.t > 0.0)


func _move(desired: Vector3, delta: float) -> void:
	## Steering velocity and knockback are tracked separately so wall collisions
	## (which rewrite `velocity`) never leak into the next frame's steering.
	var spd := speed * buff_spd
	if stun_t > 0.0:
		spd = 0.0
	if state == "lunge":
		move_vel = facing * float(attack.get("distance", 3.0)) / maxf(0.05, float(attack.get("lunge_time", 0.22)))
	else:
		move_vel = move_vel.lerp(desired * spd, 1.0 - exp(-10.0 * delta))
	velocity = move_vel + knock
	move_and_slide()
	knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-9.0 * delta))
	global_position.y = 0.0


func _animate(delta: float, desired: Vector3) -> void:
	var turn_speed := 24.0 if state == "windup" or state == "lunge" else 10.0
	pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-turn_speed * delta))
	var raw := clampf(Vector2(move_vel.x, move_vel.z).length() / maxf(speed, 0.1), 0.0, 1.0)
	move_blend = lerpf(move_blend, raw, 1.0 - exp(-8.0 * delta))
	var moving := move_blend
	var t := anim_t * (5.0 + speed * 1.5)
	visual.position.y = float_h + (sin(anim_t * 2.5) * 0.15 if float_h > 0.0 else absf(sin(t)) * 0.08 * moving)
	if parts.has("leg_l"):
		parts.leg_l.rotation.x = sin(t) * 0.7 * moving
	if parts.has("leg_r"):
		parts.leg_r.rotation.x = -sin(t) * 0.7 * moving
	var arm_swing := sin(t) * 0.5 * moving
	var lean := 0.0
	if state == "windup":
		lean = 0.3
		arm_swing = -1.4
	elif state == "recover":
		lean = -0.15
	if parts.has("arm_l"):
		parts.arm_l.rotation.x = lerpf(parts.arm_l.rotation.x, -arm_swing, 12.0 * delta)
	if parts.has("arm_r"):
		parts.arm_r.rotation.x = lerpf(parts.arm_r.rotation.x, arm_swing if state != "windup" else -1.4, 12.0 * delta)
	visual.rotation.x = lerpf(visual.rotation.x, lean, 10.0 * delta)
	if stun_t > 0.0:
		visual.rotation.z = sin(anim_t * 20.0) * 0.12
	else:
		visual.rotation.z = lerpf(visual.rotation.z, 0.0, 8.0 * delta)
	if parts.has("head") and randf() < 0.01:
		parts.head.position.x += randf_range(-0.06, 0.06)
	elif parts.has("head"):
		parts.head.position.x = lerpf(parts.head.position.x, 0.0, 10.0 * delta)
	if aura_ring:
		aura_ring.rotation.y += delta * 0.6
	if _corrupt_fx:
		_corrupt_fx.rotation.y += delta * 1.4
		_corrupt_fx.get_child(1).position.y = height + 0.3 + float_h + sin(anim_t * 3.0) * 0.08


# ------------------------------------------------------------------ damage

func take_hit(dmg: float, crit: bool, from_pos: Vector3, knockback: float) -> bool:
	if dead:
		return false
	var final := dmg * (1.0 - armor)
	hp -= final
	alert()
	Fx.damage_number(global_position + Vector3(randf_range(-0.3, 0.3), height + 0.2, 0), final, crit)
	Fx.flash(visual, Color(1, 1, 1), 0.08)
	# squash-and-recover punch (on the pivot: the visual's scale belongs to boss/death tweens)
	if _hit_tween:
		_hit_tween.kill()
	var punch := (0.2 if crit else 0.12) * (0.35 if is_boss else 1.0)
	pivot.scale = Vector3(1.0 + punch * 0.8, 1.0 - punch, 1.0 + punch * 0.8)
	_hit_tween = create_tween()
	_hit_tween.tween_property(pivot, "scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.burst(global_position + Vector3(0, height * 0.55, 0), MeshFactory.col(def.get("color", "#ff4040")), 5 if not crit else 10, 4.0, 0.09, 0.35)
	Audio.play("crit" if crit else "hit", -2.0)
	var dir := global_position - from_pos
	dir.y = 0
	if dir.length() > 0.01:
		knock += dir.normalized() * knockback / maxf(poise, 0.5)
	_update_hp_bar()
	if hp <= 0.0:
		die(true)
		return true
	return false


func add_dot(dps: float, duration: float, color: Color) -> void:
	if dead:
		return
	dots.append({"dps": dps, "t": duration, "tick": 0.5, "color": color})


func stun(duration: float) -> void:
	if dead:
		return
	var d := duration * (0.25 if is_boss else 1.0)
	if d <= 0.05:
		return
	if stun_t <= 0.0:
		Fx.text(global_position + Vector3(0, height + 0.6, 0), "STUNNED", Color("#ffe14a"), 0.8)
	stun_t = maxf(stun_t, d)


func die(by_player: bool = true) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	_cancel_attack()
	if hp_bar:
		hp_bar.visible = false
	if aura_ring:
		aura_ring.visible = false
	if by_player and GameState.has_profile():
		GameState.profile["kills"] = int(GameState.profile.get("kills", 0)) + 1
	var gold_range: Array = def.get("gold", [1, 3])
	var gold := int(round(randi_range(int(gold_range[0]), int(gold_range[-1])) * reward_mult))
	GameState.world.drop_rewards(global_position, float(def.get("data", 5)) * reward_mult, gold, str(def.get("loot_table", "basic")))
	if corrupted:
		var cr: Array = DB.progression.get("corrupted", {}).get("corrupted_gold", [2, 4])
		GameState.world.spawn_corrupted_gold(global_position, int(round(randi_range(int(cr[0]), int(cr[-1])) * maxf(1.0, reward_mult / 1.6))))
		if _corrupt_fx:
			_corrupt_fx.visible = false
	var c := MeshFactory.col(def.get("color", "#ff4040"))
	Audio.play("enemy_die", -2.0)
	Fx.burst(global_position + Vector3(0, height * 0.5, 0), c, 22, 6.0, 0.15, 0.7)
	Fx.burst(global_position + Vector3(0, height * 0.5, 0), Color(0.9, 0.9, 0.85), 10, 4.0, 0.2, 0.6)
	var tw := create_tween()
	tw.tween_property(visual, "scale", visual.scale * Vector3(1.4, 0.6, 1.4), 0.08)
	tw.tween_property(visual, "position:x", 0.15, 0.04)
	tw.tween_property(visual, "position:x", -0.15, 0.04)
	tw.tween_property(visual, "scale", Vector3(visual.scale.x * 1.6, 0.02, visual.scale.z * 1.6), 0.18)
	tw.tween_callback(queue_free)
