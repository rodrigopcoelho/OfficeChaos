class_name Player
extends CharacterBody3D
## The employee. Mouse & keyboard: WASD move, mouse aim, LMB attack, RMB dodge,
## Space jump, Q special, E interact. Controller (Minecraft Dungeons II layout): left
## stick move, X attack, LB or right-stick flick dodge, A jump, Y special, B interact,
## with aim assist toward the nearest virus in front of you.
## Attacking mid-jump turns the landing into a Slam Impact.

signal hp_changed(hp: float, max_hp: float, shield: float)

const DODGE_TIME := 0.3
const DODGE_SPEED := 15.5
const DODGE_COOLDOWN := 0.75
const MASK_NORMAL := Layers.WORLD | Layers.ENEMIES
const MASK_DODGE := Layers.WORLD
const SWING_DELAY := 0.06
const ASSIST_RANGE := 8.0
const ASSIST_ANGLE := deg_to_rad(70.0)
const JUMP_TIME := 0.55
const JUMP_HEIGHT := 1.15
const SLAM_DIVE := 2.8        # how much faster you come down once a slam is queued
const SLAM_TARGET_MULT := 2.2 # extra damage to the enemy you land on
const SLAM_RADIUS := 3.2      # shockwave reach (plus a bit of weapon reach)
const SLAM_WAVE_MULT := 0.9

var stats: Dictionary = {}
var hp := 100.0
var max_hp := 100.0
var shield := 0.0
var shield_max := 0.0
var shield_interval := 0.0
var shield_t := 0.0
var visual: CharacterVisual
var shield_mesh: MeshInstance3D
var aim_marker: MeshInstance3D
var aim_point := Vector3.ZERO
var aim_target: Enemy = null
var facing := Vector3.FORWARD
var attack_cd := 0.0
var attack_cd_max := 0.5
var special_cd := 0.0
var special_cd_max := 1.0
var dodge_cd := 0.0
var dodge_cd_max := DODGE_COOLDOWN
var dodge_t := 0.0
var dodge_dir := Vector3.ZERO
var dash_t := 0.0
var dash_vel := Vector3.ZERO
var dash_hits: Array = []
var dash_mult := 1.0
var dash_width := 1.5
var invuln := 0.0
var dead := false
var swing_sign := 1.0
var active_enchants: Array = []
var buffs: Dictionary = {}
var force_next_crit := false
var since_hurt := 99.0
var interact_target: Interactable = null
var safe_zone := false
var radius := 0.4
var input_enabled := true
var last_absorb_fx := 0
var _scan_t := 0.0
var _assist_t := 0.0
var _hitstop_cd := 0.0
var _pending: Array = []  # delayed hits: {"t", "kind", ...} resolved in the physics step
var haste := 0.0          # temporary move-speed bonus (Zero Latency effect)
var haste_t := 0.0
var jump_k := -1.0        # 0..1 progress through a jump, < 0 on the ground
var slam_queued := false


func airborne() -> bool:
	return jump_k >= 0.0


func _ready() -> void:
	add_to_group("player")
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	collision_layer = Layers.PLAYER
	collision_mask = MASK_NORMAL
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = 1.6
	shape.shape = cap
	shape.position.y = 0.8
	add_child(shape)
	visual = CharacterVisual.new()
	add_child(visual)
	visual.build(GameState.profile.get("appearance", {}))
	shield_mesh = MeshInstance3D.new()
	shield_mesh.mesh = MeshFactory.mesh_for("gem", Vector3(1.9, 2.4, 1.9))
	shield_mesh.material_override = MeshFactory.unlit_shared(Color(1.0, 0.35, 0.3, 0.16), true)
	shield_mesh.position.y = 1.0
	shield_mesh.visible = false
	shield_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shield_mesh)
	aim_marker = MeshInstance3D.new()
	aim_marker.mesh = MeshFactory.ring_mesh(0.32, 0.42, 24)
	aim_marker.material_override = MeshFactory.unlit_shared(Color(1, 1, 1, 0.55), true)
	aim_marker.top_level = true
	aim_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(aim_marker)
	GameState.player = self
	GameState.stats_changed.connect(_on_stats_changed)
	GameState.equipment_changed.connect(_refresh_visual)
	GameState.leveled_up.connect(_on_level_up)
	GameState.notified.connect(_on_notified)
	refresh_stats(true)
	_refresh_visual()
	aim_point = global_position + facing * 3.0


func _exit_tree() -> void:
	if GameState.player == self:
		GameState.player = null


func refresh_stats(full_heal: bool = false) -> void:
	stats = GameState.stats
	var ratio := hp / max_hp if max_hp > 0 else 1.0
	max_hp = float(stats.get("max_hp", 100.0))
	hp = max_hp if full_heal else clampf(ratio * max_hp, 1.0, max_hp)
	active_enchants.clear()
	shield_max = 0.0
	shield_interval = 0.0
	for slot in GameState.SLOTS:
		var inst := GameState.equipped(slot)
		if inst.is_empty():
			continue
		for e in ItemUtil.active_enchants(inst):
			active_enchants.append(e)
			if str(e.effect) == "shield_periodic":
				shield_max = maxf(shield_max, float(e.params.get("amount", 15)))
				var iv := float(e.params.get("interval", 10))
				shield_interval = iv if shield_interval <= 0.0 else minf(shield_interval, iv)
	if shield_max <= 0.0:
		shield = 0.0
	var w: Dictionary = stats.get("weapon", StatCalc.FISTS)
	var ab: Dictionary = DB.abilities.get(str(w.get("special", "spin")), {})
	special_cd_max = float(ab.get("cooldown", 6.0)) * (1.0 - float(stats.get("cooldown_pct", 0.0)))
	dodge_cd_max = DODGE_COOLDOWN * (1.0 - float(stats.get("cooldown_pct", 0.0)))
	_emit_hp()


func _on_stats_changed() -> void:
	refresh_stats(false)


func _refresh_visual() -> void:
	visual.set_gear(GameState.equipped_gear())


func _on_level_up(_level: int) -> void:
	refresh_stats(true)
	visual.express("happy", 1.8)
	Audio.play("levelup")
	Fx.burst(global_position + Vector3(0, 1.0, 0), Color("#4fd1b0"), 40, 7.0, 0.16, 1.0, -2.0)
	Fx.ring(global_position, 4.0, Color("#4fd1b0"), 0.6)
	Fx.text(global_position + Vector3(0, 2.6, 0), "PROMOTED!", Color("#4fd1b0"), 1.8, 1.5, 1.4)


func _on_notified(_sender: String, _message: String, kind: String) -> void:
	# Good news shows on the employee's face (rare loot, unlocks, cleared meetings).
	if not dead and kind in ["loot_special", "loot_unique", "unlock", "success"]:
		visual.express("happy", 1.4)


func _emit_hp() -> void:
	hp_changed.emit(hp, max_hp, shield)


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if dead:
		return
	_tick_timers(delta)
	_process_pending(delta)
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_dir := Vector3(input.x, 0, input.y)
	if move_dir.length() > 1.0:
		move_dir = move_dir.normalized()
	_update_aim(move_dir, delta)
	if dodge_t > 0.0:
		dodge_t -= delta
		velocity = dodge_dir * DODGE_SPEED * (0.55 + 0.45 * dodge_t / DODGE_TIME)
		if dodge_t <= 0.0:
			collision_mask = MASK_NORMAL
	elif dash_t > 0.0:
		dash_t -= delta
		velocity = dash_vel
		_dash_hits()
		if dash_t <= 0.0:
			collision_mask = MASK_NORMAL
			velocity *= 0.2
	else:
		var spd := float(stats.get("move_speed_final", 6.5)) * (1.0 + haste)
		if attack_cd > attack_cd_max * 0.45:
			spd *= 0.55
		velocity = velocity.lerp(move_dir * spd, 1.0 - exp(-14.0 * delta))
	move_and_slide()
	global_position.y = 0.0
	var aim_dir := aim_point - global_position
	aim_dir.y = 0
	if aim_dir.length() > 0.2:
		facing = aim_dir.normalized()
	if dodge_t <= 0.0 and dash_t <= 0.0:
		visual.face_smooth(facing, delta, 22.0)
	visual.animate(0.0 if airborne() else Vector2(velocity.x, velocity.z).length() / 6.5, delta)
	_tick_jump(delta)
	if input_enabled and not _pointer_over_ui():
		if Input.is_action_pressed("attack") and airborne() and not slam_queued:
			_queue_slam()
		elif Input.is_action_pressed("attack") and attack_cd <= 0.0 and dodge_t <= 0.0 and dash_t <= 0.0 and not airborne():
			attack()
		if Input.is_action_just_pressed("dodge") and not airborne():
			dodge(move_dir)
	if input_enabled and Input.is_action_just_pressed("jump"):
		jump()
	if input_enabled:
		var flick := Controls.consume_flick()
		if flick != Vector2.ZERO:
			dodge(Vector3(flick.x, 0, flick.y))
		if Input.is_action_just_pressed("special"):
			special()
		var ui_blocks: bool = GameState.ui != null and Time.get_ticks_msec() < GameState.ui.interact_block_until
		if Input.is_action_just_pressed("interact") and not ui_blocks and interact_target != null and is_instance_valid(interact_target):
			interact_target.interact(self)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.1
		_scan_interactables()


func _tick_timers(delta: float) -> void:
	attack_cd = maxf(0.0, attack_cd - delta)
	special_cd = maxf(0.0, special_cd - delta)
	dodge_cd = maxf(0.0, dodge_cd - delta)
	invuln = maxf(0.0, invuln - delta)
	_hitstop_cd = maxf(0.0, _hitstop_cd - delta)
	haste_t = maxf(0.0, haste_t - delta)
	if haste_t <= 0.0:
		haste = 0.0
	since_hurt += delta
	for k in buffs.keys():
		buffs[k].time -= delta
		if buffs[k].time <= 0.0:
			buffs.erase(k)
	var regen := float(stats.get("hp_regen", 0.5))
	if safe_zone:
		regen = max_hp * 0.25
	if hp < max_hp and (since_hurt > 3.0 or safe_zone):
		hp = minf(max_hp, hp + regen * delta)
		_emit_hp()
	if shield_max > 0.0:
		if shield < shield_max:
			shield_t += delta
			if shield_t >= shield_interval:
				shield_t = 0.0
				shield = shield_max
				Audio.play("shield", -6.0)
				Fx.ring(global_position, 1.6, Color("#ff4d4d"), 0.4)
				_emit_hp()
	shield_mesh.visible = shield > 0.0
	if shield_mesh.visible:
		shield_mesh.rotation.y += delta * 1.5


func _process_pending(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var a: Dictionary = _pending[i]
		a.t -= delta
		if a.t > 0.0:
			continue
		_pending.remove_at(i)
		match str(a.kind):
			"swing":
				for e in Combat.enemies_in_arc(global_position, a.dir, a.reach, a.arc):
					Combat.player_strike(self, e, 1.0)
				Enchants.run("on_swing", self, {"player": self, "dir": a.dir})
			"quake":
				_resolve_quake(a.ab)


func _pointer_over_ui() -> bool:
	if Controls.gamepad:
		return false
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP


func _update_aim(move_dir: Vector3, delta: float) -> void:
	if Controls.gamepad:
		# Minecraft Dungeons style: face where you walk, snap to the nearest virus ahead.
		var ref := move_dir.normalized() if move_dir.length() > 0.2 else facing
		_assist_t -= delta
		if _assist_t <= 0.0:
			_assist_t = 0.1
			aim_target = _assist_pick(ref) if Settings.aim_assist else null
		if aim_target != null and (not is_instance_valid(aim_target) or aim_target.dead):
			aim_target = null
		if aim_target != null:
			aim_point = aim_target.global_position
		else:
			aim_point = global_position + ref * 2.5
		aim_marker.global_position = aim_point + Vector3(0, 0.05, 0)
		return
	aim_target = null
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var mp := get_viewport().get_mouse_position()
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(from, dir)
	if hit != null:
		aim_point = hit
		aim_marker.global_position = aim_point + Vector3(0, 0.05, 0)


func _assist_pick(ref: Vector3) -> Enemy:
	var best: Enemy = null
	var best_score := INF
	for n in get_tree().get_nodes_in_group("enemies"):
		var e := n as Enemy
		if e == null or e.dead:
			continue
		var to := e.global_position - global_position
		to.y = 0
		var d := to.length()
		if d > ASSIST_RANGE or d < 0.01:
			continue
		var ang := absf(ref.angle_to(to / d))
		if ang > ASSIST_ANGLE and d > 2.0:
			continue
		var score := d + ang * 3.0
		if score < best_score:
			best_score = score
			best = e
	return best


func _scan_interactables() -> void:
	var best: Interactable = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactables"):
		var it := n as Interactable
		if it == null or not it.can_interact(self):
			continue
		var d: float = global_position.distance_to(it.global_position)
		if d <= it.radius and d < best_d:
			best_d = d
			best = it
	interact_target = best
	if GameState.ui:
		GameState.ui.set_prompt(best.get_prompt() if best != null else "")


# ------------------------------------------------------------------ combat

func damage_multiplier() -> float:
	var m := 1.0 + float(stats.get("damage_pct", 0.0))
	for k in buffs:
		m += float(buffs[k].value)
	return m


func add_buff(buff_name: String, value: float, duration: float) -> void:
	buffs[buff_name] = {"value": value, "time": duration}


func add_haste(value: float, duration: float) -> void:
	haste = maxf(haste, value)
	haste_t = maxf(haste_t, duration)


func attack() -> void:
	var w: Dictionary = stats.get("weapon", StatCalc.FISTS)
	var aspd := float(w.get("attack_speed", 1.5)) * (1.0 + float(stats.get("attack_speed_pct", 0.0)))
	attack_cd_max = 1.0 / maxf(0.2, aspd)
	attack_cd = attack_cd_max
	visual.face(facing)
	visual.swing(swing_sign, float(w.get("arc", 100)), minf(attack_cd_max, 0.6), str(w.get("swing", "horizontal")))
	Audio.play("swing", -2.0, 0.15)
	var reach := float(w.get("range", 2.0))
	var arc := float(w.get("arc", 100))
	Fx.slash(global_position, facing, reach, arc, Color(1, 1, 1), swing_sign)
	velocity += facing * 2.5
	swing_sign *= -1.0
	_pending.append({"t": SWING_DELAY, "kind": "swing", "dir": facing, "reach": reach, "arc": arc})


func on_hit_landed(crit: bool) -> void:
	if GameState.world:
		GameState.world.add_shake(0.18 if crit else 0.08)
		if _hitstop_cd <= 0.0:
			_hitstop_cd = 0.12
			GameState.world.hitstop(0.05 if crit else 0.03)


func jump() -> void:
	if airborne() or dodge_t > 0.0 or dash_t > 0.0 or dead:
		return
	jump_k = 0.0
	slam_queued = false
	visual.hop()
	Audio.play("dodge", -6.0, 0.1)
	Fx.burst(global_position + Vector3(0, 0.15, 0), Color(0.9, 0.9, 1.0), 6, 2.0, 0.1, 0.3, 0.0, 1.0)


func _tick_jump(delta: float) -> void:
	## The hop is purely visual (the body stays on the floor plane for collision and
	## pathing); a parabola lifts the character, and a queued slam dives it back down.
	if not airborne():
		return
	jump_k += delta / JUMP_TIME * (SLAM_DIVE if slam_queued and jump_k >= 0.35 else 1.0)
	if jump_k >= 1.0:
		jump_k = -1.0
		visual.position.y = 0.0
		visual.land(slam_queued)
		if slam_queued:
			slam_queued = false
			_resolve_slam()
		else:
			Fx.burst(global_position + Vector3(0, 0.1, 0), Color(0.9, 0.9, 1.0), 5, 1.5, 0.08, 0.25, 0.0, 1.0)
		return
	visual.position.y = 4.0 * JUMP_HEIGHT * jump_k * (1.0 - jump_k)


func _queue_slam() -> void:
	slam_queued = true
	# hang for a beat at the apex if still rising, then come down hard
	jump_k = maxf(jump_k, 0.35)
	visual.swing(1.0, 90.0, 0.45, "chop")
	Audio.play("swing", 0.0, 0.1)


func _resolve_slam() -> void:
	## Slam Impact: the enemy you land on takes extra damage; a shockwave hurts and
	## throws back everything around you.
	var w: Dictionary = stats.get("weapon", StatCalc.FISTS)
	var reach := float(w.get("range", 2.0))
	var target: Enemy = null
	var best := INF
	# the enemy you come down on: the closest one within weapon reach, any direction
	for e in Combat.enemies_in_radius(global_position, reach + 0.6):
		var d: float = global_position.distance_to(e.global_position)
		if d < best:
			best = d
			target = e
	if target != null:
		Combat.player_strike(self, target, SLAM_TARGET_MULT, {"knockback_mult": 1.6, "slam": true})
	var r := SLAM_RADIUS + reach * 0.25
	for e in Combat.enemies_in_radius(global_position, r):
		if e != target:
			Combat.player_strike(self, e, SLAM_WAVE_MULT, {"knockback_mult": 3.0, "slam": true})
	attack_cd = maxf(attack_cd, 0.25)
	invuln = maxf(invuln, 0.15)
	Audio.play("slam")
	GameState.world.add_shake(0.55)
	Fx.ring(global_position, r, Color("#ffd75e"), 0.4, 0.35)
	Fx.ring(global_position, r * 0.55, Color(1, 1, 1), 0.25, 0.25)
	Fx.burst(global_position + Vector3(0, 0.2, 0), Color("#d6ccae"), 26, 7.0, 0.16, 0.55)
	Fx.text(global_position + Vector3(0, 2.4, 0), "SLAM!", Color("#ffd75e"), 0.7)


func dodge(move_dir: Vector3) -> void:
	if dodge_cd > 0.0 or dodge_t > 0.0:
		return
	dodge_dir = move_dir.normalized() if move_dir.length() > 0.1 else facing
	dodge_t = DODGE_TIME
	dodge_cd = dodge_cd_max
	invuln = maxf(invuln, DODGE_TIME + 0.06)
	collision_mask = MASK_DODGE
	visual.face(dodge_dir)
	visual.roll(DODGE_TIME)
	Audio.play("dodge")
	Fx.burst(global_position + Vector3(0, 0.4, 0), Color(0.9, 0.9, 1.0), 8, 2.0, 0.12, 0.35, 0.0, 1.5)


func special() -> void:
	if special_cd > 0.0 or dodge_t > 0.0 or dash_t > 0.0:
		return
	var w: Dictionary = stats.get("weapon", StatCalc.FISTS)
	var ab: Dictionary = DB.abilities.get(str(w.get("special", "spin")), {})
	if ab.is_empty():
		return
	special_cd = special_cd_max
	var mult := float(ab.get("damage_mult", 1.5))
	match str(ab.get("type", "spin")):
		"spin":
			var r := float(ab.get("radius", 3.2))
			visual.spin(0.45)
			Audio.play("swing", 2.0)
			Fx.ring(global_position, r, Color(0.8, 0.95, 1.0), 0.35, 0.3)
			Fx.slash(global_position, facing, r, 359.0, Color(0.7, 0.95, 1.0))
			for e in Combat.enemies_in_arc(global_position, facing, r, 360.0):
				Combat.player_strike(self, e, mult, {"knockback_mult": 1.8})
		"cleave":
			var reach := float(ab.get("range", 4.2))
			var arc := float(ab.get("arc", 170))
			visual.swing(swing_sign, arc, 0.5, "horizontal")
			Audio.play("slam", -4.0)
			Fx.slash(global_position, facing, reach, arc, Color(1.0, 0.75, 0.4))
			GameState.world.add_shake(0.35)
			for e in Combat.enemies_in_arc(global_position, facing, reach, arc):
				Combat.player_strike(self, e, mult, {"knockback_mult": 2.5})
		"blink":
			var max_d := float(ab.get("distance", 7.0))
			var dist := max_d if (Controls.gamepad and aim_target == null) else minf(max_d, global_position.distance_to(aim_point))
			var target: Vector3 = GameState.world.clamp_move(global_position, facing, dist)
			Fx.burst(global_position + Vector3(0, 1, 0), Color("#39ff88"), 18, 4.0, 0.12, 0.4, 0.0)
			global_position = target
			Audio.play("teleport", -4.0)
			Fx.burst(global_position + Vector3(0, 1, 0), Color("#39ff88"), 24, 6.0, 0.12, 0.5, 0.0)
			visual.spin(0.3)
			var r2 := float(ab.get("radius", 2.5))
			Fx.ring(global_position, r2, Color("#39ff88"), 0.3)
			for e in Combat.enemies_in_arc(global_position, facing, r2, 360.0):
				Combat.player_strike(self, e, mult, {"force_crit": true})
			invuln = maxf(invuln, 0.3)
		"quake":
			visual.swing(1.0, 90.0, 0.5, "chop")
			_pending.append({"t": 0.18, "kind": "quake", "ab": ab})
		"lunge":
			var dist2 := float(ab.get("distance", 8.0))
			dash_t = 0.24
			dash_vel = facing * dist2 / 0.24
			dash_hits = []
			dash_mult = mult
			dash_width = float(ab.get("width", 1.8))
			invuln = maxf(invuln, 0.3)
			collision_mask = MASK_DODGE
			visual.face(facing)
			visual.swing(1.0, 30.0, 0.35, "thrust")
			Audio.play("dodge", 2.0)
			Fx.slash(global_position, facing, 3.0, 40.0, Color("#ff9a3a"))


func _resolve_quake(ab: Dictionary) -> void:
	var r3 := float(ab.get("radius", 4.5))
	var mult := float(ab.get("damage_mult", 1.8))
	Audio.play("slam")
	GameState.world.add_shake(0.6)
	Fx.ring(global_position, r3, Color("#ffe14a"), 0.45, 0.35)
	Fx.burst(global_position + Vector3(0, 0.2, 0), Color("#d6ccae"), 30, 7.0, 0.18, 0.6)
	for e in Combat.enemies_in_arc(global_position, facing, r3, 360.0):
		Combat.player_strike(self, e, mult, {"knockback_mult": 1.5})
		if is_instance_valid(e) and not e.dead:
			e.stun(float(ab.get("stun", 1.5)))


func _dash_hits() -> void:
	for e in Combat.enemies_in_radius(global_position, dash_width):
		if e in dash_hits:
			continue
		dash_hits.append(e)
		Combat.player_strike(self, e, dash_mult, {"knockback_mult": 1.2})


func glitch_behind(target: Enemy) -> void:
	var to: Vector3 = target.global_position - global_position
	to.y = 0
	var dest: Vector3 = target.global_position + to.normalized() * (target.radius + 0.9)
	if GameState.world.is_walkable_pos(dest):
		Fx.burst(global_position + Vector3(0, 1, 0), Color("#39ff88"), 12, 3.0, 0.1, 0.35, 0.0)
		global_position = dest
		facing = -to.normalized()
		visual.face(facing)
		Fx.burst(global_position + Vector3(0, 1, 0), Color("#39ff88"), 12, 3.0, 0.1, 0.35, 0.0)
		Fx.text(global_position + Vector3(0, 2.3, 0), "GLITCH", Color("#39ff88"), 0.8)
		Audio.play("teleport", -10.0)


func take_damage(amount: float, source_pos: Vector3 = Vector3.ZERO) -> void:
	if dead or invuln > 0.0 or amount <= 0.0:
		return
	if randf() < float(stats.get("block_chance", 0.0)):
		Audio.play("block")
		Fx.text(global_position + Vector3(0, 2.2, 0), "BLOCKED", Color(0.6, 0.8, 1.0), 0.9)
		invuln = 0.2
		return
	var armor := float(stats.get("defense", 0.0))
	var dmg := amount * (1.0 - armor / (armor + 60.0))
	if shield > 0.0:
		var absorbed := minf(shield, dmg)
		shield -= absorbed
		dmg -= absorbed
		shield_t = 0.0
		Fx.burst(global_position + Vector3(0, 1, 0), Color("#ff4d4d"), 6, 3.0, 0.1, 0.3, 0.0)
		if dmg <= 0.0:
			Audio.play("block", -4.0)
			invuln = 0.2
			_emit_hp()
			return
	hp -= dmg
	since_hurt = 0.0
	invuln = 0.3
	Fx.flash(visual, Color(1, 0.2, 0.2), 0.12)
	visual.express("hurt", 0.45)
	Fx.damage_number(global_position + Vector3(0, 2.0, 0), dmg, false, Color(1.0, 0.35, 0.35))
	Audio.play("hurt")
	if source_pos != Vector3.ZERO:
		var kb := global_position - source_pos
		kb.y = 0
		velocity += kb.normalized() * 6.0
	if GameState.world:
		GameState.world.add_shake(0.3)
	if GameState.ui:
		GameState.ui.damage_flash(clampf(dmg / max_hp * 3.0, 0.25, 1.0))
	_emit_hp()
	if hp <= 0.0:
		die()


func heal(amount: float, show: bool = true) -> void:
	if dead or amount <= 0.0 or hp >= max_hp:
		return
	hp = minf(max_hp, hp + amount)
	if show and amount >= 1.0:
		Fx.text(global_position + Vector3(0, 2.1, 0), "+%d" % int(round(amount)), Color("#5fe3b0"), 0.9)
	_emit_hp()


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	velocity = Vector3.ZERO
	interact_target = null
	_pending.clear()
	if GameState.ui:
		GameState.ui.set_prompt("")
	jump_k = -1.0
	slam_queued = false
	visual.position.y = 0.0
	visual.die()
	Audio.play("death")
	Fx.burst(global_position + Vector3(0, 1, 0), Color("#ff3a3a"), 40, 6.0, 0.14, 1.0)
	_emit_hp()
	GameState.on_player_died()
	await _wait(1.2)
	if GameState.ui:
		GameState.ui.show_death()


func _wait(t: float) -> void:
	var timer := Timer.new()
	timer.one_shot = true
	add_child(timer)
	timer.start(t)
	await timer.timeout
	timer.queue_free()
