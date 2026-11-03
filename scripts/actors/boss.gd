class_name Boss
extends Enemy
## THE REGIONAL MANAGER (or any boss in bosses.json): multi-phase pattern AI with
## telegraphed attacks. Attack parameters are data-driven.

var boss_def: Dictionary = {}
var phases: Array = []
var phase := 0
var active := false
var busy := false
var invulnerable := false
var think_t := 1.4
var attack_token := 0
var last_attack := ""
var charging := false
var charge_dir := Vector3.ZERO
var charge_left := 0.0
var charge_hit := false
var charge_params: Dictionary = {}
var screen_mat: ShaderMaterial
var arm_raise := 0.0
var _dust: CPUParticles3D


func setup_boss(id: String, level_mult: float, clearance_tier: int) -> Boss:
	enemy_id = id
	is_boss = true
	boss_def = DB.bosses.get(id, {})
	setup_from_def(boss_def, level_mult, clearance_tier)
	phases = boss_def.get("phases", [{"threshold": 1.0, "attacks": ["slam"]}])
	speed = float(phases[0].get("speed", speed))
	return self


func _ready() -> void:
	super._ready()
	if parts.has("#screen"):
		var mi: MeshInstance3D = parts["#screen"]
		screen_mat = MeshFactory.clay(MeshFactory.col(phases[0].get("screen", "#ff4040")), 2.6, 0.02, false, null, true)
		mi.material_override = screen_mat
	_dust = Fx._new_particles()
	_dust.one_shot = false
	_dust.amount = 24
	_dust.lifetime = 0.4
	_dust.explosiveness = 0.0
	_dust.initial_velocity_min = 0.8
	_dust.initial_velocity_max = 2.0
	_dust.gravity = Vector3(0, -9.0, 0)
	_dust.mesh = Fx.particle_mesh(0.15, Color("#6c6f78"), 3.0)
	_dust.position = Vector3(0, 0.3, 0)
	add_child(_dust)
	var light := OmniLight3D.new()
	light.light_color = MeshFactory.col(boss_def.get("color", "#ff2a4a"))
	light.light_energy = 2.0
	light.omni_range = 6.0
	light.position = Vector3(0, 4.5, -1.0)
	add_child(light)


func current_phase() -> Dictionary:
	return phases[clampi(phase, 0, phases.size() - 1)]


func _physics_process(delta: float) -> void:
	if dead:
		return
	anim_t += delta
	_tick_status(delta)
	if dead:
		return
	var p = GameState.player
	var alive_player: bool = p != null and is_instance_valid(p) and not p.dead
	if not active:
		if alive_player and global_position.distance_to(p.global_position) < float(boss_def.get("activate_radius", 14.0)):
			_activate()
		_boss_anim(delta)
		return
	if not alive_player:
		velocity = Vector3.ZERO
		_boss_anim(delta)
		return
	_check_phase()
	var desired := Vector3.ZERO
	if charging:
		_charge_step(delta, p)
	elif stun_t > 0.0:
		stun_t -= delta
	elif not busy:
		var to: Vector3 = p.global_position - global_position
		to.y = 0
		facing = to.normalized() if to.length() > 0.1 else facing
		los_t -= delta
		if los_t <= 0.0:
			los_t = 0.3
			los = GameState.world.has_los(global_position, p.global_position)
		if to.length() > 3.2:
			desired = _chase_dir(p, to.length())
		think_t -= delta
		if think_t <= 0.0:
			_choose_attack(p)
	if not charging:
		move_vel = move_vel.lerp(desired * speed, 1.0 - exp(-6.0 * delta))
		velocity = move_vel + knock
		move_and_slide()
		knock = knock.lerp(Vector3.ZERO, 1.0 - exp(-9.0 * delta))
	global_position.y = 0.0
	_boss_anim(delta)


func _activate() -> void:
	active = true
	aggro = true
	Audio.play("boss_roar")
	Audio.set_ambient("dungeon")
	GameState.world.add_shake(0.6)
	if GameState.ui:
		GameState.ui.glitch_spike(0.8)
	GameState.notify(str(boss_def.get("name", "BOSS")), "Ah, you're here. Please, have a seat. This meeting will be brief.", "boss")


func _check_phase() -> void:
	if phase + 1 >= phases.size():
		return
	if hp / max_hp <= float(phases[phase + 1].get("threshold", 0.5)):
		_enter_phase(phase + 1)


func _enter_phase(i: int) -> void:
	phase = i
	attack_token += 1
	charging = false
	busy = true
	invulnerable = true
	var ph := current_phase()
	speed = float(ph.get("speed", speed))
	Audio.play("boss_roar", 2.0)
	GameState.world.add_shake(0.9)
	if GameState.ui:
		GameState.ui.glitch_spike(1.2)
	if screen_mat:
		screen_mat.set_shader_parameter("albedo", MeshFactory.col(ph.get("screen", "#c22cff")))
		screen_mat.set_shader_parameter("emission", MeshFactory.col(ph.get("screen", "#c22cff")))
	Fx.burst(global_position + Vector3(0, 3, 0), MeshFactory.col(ph.get("screen", "#c22cff")), 50, 9.0, 0.2, 1.0, -3.0)
	Fx.ring(global_position, 7.0, MeshFactory.col(ph.get("screen", "#c22cff")), 0.6, 0.3)
	if ph.has("message"):
		GameState.notify(str(boss_def.get("name", "BOSS")), str(ph.message), "boss")
	var tw := create_tween()
	tw.tween_property(visual, "scale", visual.scale * 1.15, 0.3).set_trans(Tween.TRANS_BACK)
	tw.tween_property(visual, "scale", visual.scale, 0.4)
	await _wait(1.8)
	if dead:
		return
	invulnerable = false
	busy = false
	think_t = 0.4


func _choose_attack(p) -> void:
	var options: Array = current_phase().get("attacks", ["slam"]).duplicate()
	if options.size() > 1:
		options.erase(last_attack)
	var to: Vector3 = p.global_position - global_position
	to.y = 0
	var choice := str(options[randi() % options.size()])
	if choice == "summon":
		var alive := get_tree().get_nodes_in_group("enemies").size() - 1
		if alive >= int(boss_def.get("attacks", {}).get("summon", {}).get("max_alive", 5)):
			choice = "slam"
	last_attack = choice
	var params: Dictionary = boss_def.get("attacks", {}).get(choice, {})
	attack_token += 1
	var token := attack_token
	busy = true
	match choice:
		"slam": _atk_slam(params, token)
		"memo_barrage": _atk_barrage(params, token)
		"charge": _atk_charge(params, token)
		"memo_spiral": _atk_spiral(params, token)
		"corrupt_floor": _atk_corrupt(params, token)
		"summon": _atk_summon(params, token)
		_: busy = false


func _done(token: int, params: Dictionary) -> void:
	if token != attack_token or dead:
		return
	await _wait(float(params.get("recover", 0.5)))
	if token != attack_token or dead:
		return
	busy = false
	think_t = float(current_phase().get("pause", 1.0))


func _alive(token: int) -> bool:
	return not dead and token == attack_token and GameState.player != null and is_instance_valid(GameState.player)


# ------------------------------------------------------------------ attacks

func _atk_slam(a: Dictionary, token: int) -> void:
	var p = GameState.player
	var target: Vector3 = p.global_position
	var windup := float(a.get("windup", 1.0)) * (0.8 if phase > 0 else 1.0)
	var r := float(a.get("radius", 3.4))
	Fx.telegraph_circle(target, r, windup)
	Audio.play("telegraph", -4.0)
	arm_raise = 1.0
	var start := global_position
	var land: Vector3 = start
	if start.distance_to(target) > 0.6:
		land = GameState.world.clamp_move(start, (target - start).normalized(), maxf(0.0, start.distance_to(target) - 0.5))
	var tw := create_tween()
	tw.tween_interval(windup * 0.35)
	tw.tween_property(self, "global_position", land, windup * 0.65).set_trans(Tween.TRANS_SINE)
	var hop := create_tween()
	hop.tween_interval(windup * 0.35)
	hop.tween_property(visual, "position:y", 2.2, windup * 0.35).set_ease(Tween.EASE_OUT)
	hop.tween_property(visual, "position:y", 0.0, windup * 0.3).set_ease(Tween.EASE_IN)
	await _wait(windup)
	if not _alive(token):
		arm_raise = 0.0
		return
	arm_raise = 0.0
	Audio.play("slam", 2.0)
	GameState.world.add_shake(0.7)
	Fx.ring(target, r, Color(1, 0.3, 0.2), 0.4, 0.3)
	Fx.burst(target + Vector3(0, 0.2, 0), Color("#6c6f78"), 30, 8.0, 0.2, 0.7)
	Fx.burst(target + Vector3(0, 0.2, 0), MeshFactory.col(current_phase().get("screen", "#ff4040")), 16, 6.0, 0.12, 0.6)
	p = GameState.player
	var to: Vector3 = p.global_position - target
	to.y = 0
	if to.length() <= r + 0.3:
		p.take_damage(damage * float(a.get("damage_mult", 1.5)), target)
	if phase >= int(a.get("zone_in_phase", 1)):
		GameState.world.spawn_hazard(target, float(a.get("zone_radius", 2.5)), damage * float(a.get("zone_dps_mult", 0.6)), float(a.get("zone_duration", 4.0)), MeshFactory.col(current_phase().get("screen", "#c22cff")))
	_done(token, a)


func _atk_barrage(a: Dictionary, token: int) -> void:
	Fx.flash(visual, Color(1, 0.3, 0.3), float(a.get("windup", 0.5)))
	Audio.play("telegraph", -4.0)
	await _wait(float(a.get("windup", 0.5)))
	for v in int(a.get("volleys", 3)):
		if not _alive(token):
			return
		var p = GameState.player
		var to: Vector3 = p.global_position - global_position
		to.y = 0
		facing = to.normalized()
		var count := int(a.get("count", 7))
		var spread := deg_to_rad(float(a.get("spread", 60)))
		var offset := (spread / count) * 0.5 * (v % 2)
		for i in count:
			var ang := lerpf(-spread * 0.5, spread * 0.5, float(i) / maxf(1.0, count - 1)) + offset
			var dir := facing.rotated(Vector3.UP, ang)
			GameState.world.spawn_enemy_projectile(global_position + Vector3(0, 2.2, 0) + dir * 1.5, dir, float(a.get("speed", 11)), damage * float(a.get("damage_mult", 0.5)), Color("#fff4d0"), Callable(), "memo")
		Audio.play("shoot")
		await _wait(float(a.get("interval", 0.35)))
	_done(token, a)


func _atk_charge(a: Dictionary, token: int) -> void:
	var p = GameState.player
	var to: Vector3 = p.global_position - global_position
	to.y = 0
	charge_dir = to.normalized() if to.length() > 0.1 else facing
	facing = charge_dir
	var length := float(a.get("length", 16))
	Fx.telegraph_rect(global_position, charge_dir, length, float(a.get("width", 2.8)), float(a.get("windup", 0.9)))
	Audio.play("telegraph", -2.0)
	await _wait(float(a.get("windup", 0.9)))
	if not _alive(token):
		return
	charging = true
	charge_left = length
	charge_hit = false
	charge_params = a
	Audio.play("boss_roar", -8.0, 0.2)
	while charging and _alive(token):
		await _wait(0.05)
	if not _alive(token):
		return
	_done(token, a)


func _charge_step(delta: float, p) -> void:
	var spd := float(charge_params.get("speed", 20.0))
	velocity = charge_dir * spd
	move_and_slide()
	charge_left -= spd * delta
	if not charge_hit and global_position.distance_to(p.global_position) < radius + 1.0:
		charge_hit = true
		p.take_damage(damage * float(charge_params.get("damage_mult", 1.3)), global_position - charge_dir)
	var hit_wall := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		if c.get_collider() is StaticBody3D and c.get_normal().dot(charge_dir) < -0.5:
			hit_wall = true
	if hit_wall:
		charging = false
		velocity = Vector3.ZERO
		move_vel = Vector3.ZERO
		stun_t = float(charge_params.get("wall_stun", 1.5))
		Audio.play("slam")
		GameState.world.add_shake(0.8)
		Fx.text(global_position + Vector3(0, height + 1.2, 0), "DAZED", Color("#ffe14a"), 1.4)
		Fx.burst(global_position + charge_dir * 1.2 + Vector3(0, 1.5, 0), Color("#d6ccae"), 26, 7.0, 0.18, 0.7)
	elif charge_left <= 0.0:
		charging = false
		velocity = Vector3.ZERO
		move_vel = Vector3.ZERO


func _atk_spiral(a: Dictionary, token: int) -> void:
	Fx.flash(visual, MeshFactory.col(current_phase().get("screen", "#c22cff")), float(a.get("windup", 0.6)))
	Audio.play("telegraph", -2.0)
	await _wait(float(a.get("windup", 0.6)))
	var t := 0.0
	var ang := randf() * TAU
	var arms := int(a.get("arms", 4))
	var interval := float(a.get("interval", 0.14))
	while t < float(a.get("duration", 3.0)):
		if not _alive(token):
			return
		for i in arms:
			var dir := Vector3.FORWARD.rotated(Vector3.UP, ang + TAU * i / arms)
			GameState.world.spawn_enemy_projectile(global_position + Vector3(0, 1.4, 0) + dir * 1.4, dir, float(a.get("speed", 8.5)), damage * float(a.get("damage_mult", 0.45)), MeshFactory.col(current_phase().get("screen", "#c22cff")), Callable(), "orb")
		ang += deg_to_rad(float(a.get("turn", 17)))
		Audio.play("shoot", -10.0)
		await _wait(interval)
		t += interval
	_done(token, a)


func _atk_corrupt(a: Dictionary, token: int) -> void:
	var p = GameState.player
	var spots: Array[Vector3] = [p.global_position]
	var spread := float(a.get("spread", 7.0))
	var tries := 0
	while spots.size() < int(a.get("count", 5)) and tries < 30:
		tries += 1
		var c: Vector3 = p.global_position + Vector3(randf_range(-spread, spread), 0, randf_range(-spread, spread))
		if GameState.world.is_walkable_pos(c):
			spots.append(c)
	var r := float(a.get("radius", 2.3))
	var col := MeshFactory.col(current_phase().get("screen", "#c22cff"))
	for s in spots:
		Fx.telegraph_circle(s, r, float(a.get("windup", 1.1)), col)
	Audio.play("telegraph", -2.0)
	arm_raise = 1.0
	await _wait(float(a.get("windup", 1.1)))
	arm_raise = 0.0
	if not _alive(token):
		return
	for s in spots:
		GameState.world.spawn_hazard(s, r, damage * float(a.get("dps_mult", 0.7)), float(a.get("duration", 6.0)), col)
	Audio.play("zap")
	GameState.world.add_shake(0.3)
	_done(token, a)


func _atk_summon(a: Dictionary, token: int) -> void:
	Fx.text(global_position + Vector3(0, height + 1.4, 0), "CIRCLE BACK!", Color("#ff8fb0"), 1.4)
	arm_raise = 1.0
	await _wait(0.6)
	arm_raise = 0.0
	if not _alive(token):
		return
	var pool: Array = a.get("pool", ["trojan"])
	for i in int(a.get("count", 3)):
		var m := GameState.world.spawn_enemy_near(str(pool[randi() % pool.size()]), global_position, 4.0, tier, -1.0, true)
		if m != null:
			m.aggro = true
	Audio.play("teleport", -4.0)
	_done(token, a)


# ------------------------------------------------------------------ damage / death

func take_hit(dmg: float, crit: bool, from_pos: Vector3, knockback: float) -> bool:
	if dead:
		return false
	if invulnerable:
		Fx.text(global_position + Vector3(0, height + 0.8, 0), "IMMUNE", Color(0.8, 0.8, 0.8), 0.8)
		return false
	if not active:
		_activate()
	return super.take_hit(dmg, crit, from_pos, knockback * 0.15)


func die(_by_player: bool = true) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	attack_token += 1
	charging = false
	busy = true
	remove_from_group("enemies")
	collision_layer = 0
	collision_mask = 0
	if GameState.has_profile():
		GameState.profile["kills"] = int(GameState.profile.get("kills", 0)) + 1
	Audio.play("boss_roar", 0.0, 0.0)
	GameState.notify(str(boss_def.get("name", "BOSS")), "This... isn't... a good fit... for the company...", "boss")
	for e in get_tree().get_nodes_in_group("enemies"):
		e.die(false)
	_death_sequence()


func _death_sequence() -> void:
	var col := MeshFactory.col(current_phase().get("screen", "#ff4040"))
	for i in 12:
		await _wait(0.17)
		var off := Vector3(randf_range(-1.2, 1.2), randf_range(0.5, 4.5), randf_range(-1.0, 1.0))
		Fx.burst(global_position + off, col if i % 2 == 0 else Color(1, 0.9, 0.6), 12, 5.0, 0.14, 0.5)
		Audio.play("hit", -2.0, 0.3)
		visual.position = Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
		if screen_mat:
			screen_mat.set_shader_parameter("emission_energy", 0.0 if i % 2 == 0 else 5.0)
		if GameState.ui:
			GameState.ui.glitch_spike(0.35)
	Audio.play("explosion", 4.0)
	GameState.world.add_shake(1.2)
	if GameState.ui:
		GameState.ui.glitch_spike(1.5)
	Fx.burst(global_position + Vector3(0, 2.5, 0), Color.WHITE, 60, 12.0, 0.2, 1.0, -6.0)
	Fx.burst(global_position + Vector3(0, 2.5, 0), col, 60, 9.0, 0.25, 1.2, -6.0)
	Fx.ring(global_position, 9.0, col, 0.8, 0.3)
	Fx.digitize(global_position, height, col, 3.0)
	if parts.has("head"):
		var head: Node3D = parts.head
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(head, "position:y", 0.4, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(head, "rotation:z", 1.2, 0.7)
	var gold_range: Array = boss_def.get("gold", [150, 200])
	GameState.world.drop_rewards(global_position, float(boss_def.get("data", 200)) * reward_mult, int(randi_range(int(gold_range[0]), int(gold_range[-1])) * reward_mult), str(boss_def.get("loot_table", "boss")))
	GameState.world.on_boss_defeated(self)
	if screen_mat:
		screen_mat.set_shader_parameter("emission_energy", 0.0)
	var sink := create_tween()
	sink.tween_interval(0.8)
	sink.tween_property(visual, "scale", Vector3(visual.scale.x * 1.3, 0.05, visual.scale.z * 1.3), 1.2).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	sink.tween_callback(queue_free)


func _boss_anim(delta: float) -> void:
	if _dust and _dust.emitting != charging:
		_dust.emitting = charging
	pivot.rotation.y = lerp_angle(pivot.rotation.y, atan2(-facing.x, -facing.z), 1.0 - exp(-(14.0 if charging else 5.0) * delta))
	var raw := clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.1), 0.0, 1.0)
	move_blend = lerpf(move_blend, raw, 1.0 - exp(-8.0 * delta))
	var moving := move_blend
	var t := anim_t * 5.0
	if parts.has("leg_l"):
		parts.leg_l.rotation.x = sin(t) * 0.5 * moving
		parts.leg_r.rotation.x = -sin(t) * 0.5 * moving
	var raise := lerpf(0.0, -2.6, arm_raise)
	for side in ["arm_l", "arm_r"]:
		if parts.has(side):
			var arm: Node3D = parts[side]
			var idle := sin(anim_t * 1.7 + (0.0 if side == "arm_l" else PI)) * 0.25
			arm.rotation.x = lerpf(arm.rotation.x, raise + idle, 8.0 * delta)
			arm.rotation.z = sin(anim_t * 2.3) * 0.1
	if parts.has("head"):
		var head: Node3D = parts.head
		if randf() < 0.02:
			head.position.x = randf_range(-0.12, 0.12)
		else:
			head.position.x = lerpf(head.position.x, 0.0, 8.0 * delta)
	visual.rotation.z = sin(anim_t * 20.0) * 0.06 if stun_t > 0.0 else lerpf(visual.rotation.z, 0.0, 6.0 * delta)


func _wait(t: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(t)
	await timer.timeout
	timer.queue_free()
