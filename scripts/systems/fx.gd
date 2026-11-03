class_name Fx
extends RefCounted
## Small, cheap visual effects: particle bursts, floating numbers, rings, slashes,
## lightning arcs, hit flashes and ground telegraphs. Frequent effects are recycled
## through the level's FxPool instead of being created and freed every hit.

static var _shrink_curve: Curve
static var _flash_mats: Dictionary = {}
static var _particle_meshes: Dictionary = {}


static func root() -> FxPool:
	var w := GameState.world
	if w == null or not is_instance_valid(w) or w.fx_root == null:
		return null
	return w.fx_root


static func _track(n: Node, tw: Tween) -> void:
	n.set_meta("tween", tw)


# ------------------------------------------------------------------ particle bursts

static func _new_particles() -> CPUParticles3D:
	if _shrink_curve == null:
		_shrink_curve = Curve.new()
		_shrink_curve.add_point(Vector2(0, 1))
		_shrink_curve.add_point(Vector2(1, 0))
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.angular_velocity_min = -360
	p.angular_velocity_max = 360
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	p.scale_amount_curve = _shrink_curve
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func particle_mesh(size: float, color: Color, energy: float) -> BoxMesh:
	## Shared glowing cube for particles (cached per size/colour/energy).
	var key := "%.3f|%s|%.1f" % [size, color.to_html(), energy]
	if _particle_meshes.has(key):
		return _particle_meshes[key]
	var m := BoxMesh.new()
	m.size = Vector3.ONE * size
	m.material = MeshFactory.glow(color, energy)
	_particle_meshes[key] = m
	return m


static func burst(pos: Vector3, color: Color, amount: int = 16, speed: float = 5.0, size: float = 0.14, life: float = 0.6, gravity: float = -9.0, energy: float = 3.0) -> void:
	var pool := root()
	if pool == null:
		return
	var p := pool.take("burst", func() -> Node: return Fx._new_particles(), life + 0.15) as CPUParticles3D
	p.amount = maxi(1, amount)
	p.lifetime = life
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, gravity, 0)
	p.mesh = particle_mesh(size, color, energy)
	p.global_position = pos
	p.restart()


# ------------------------------------------------------------------ digitizing

const DATA_CYAN := Color("#40f2ff")
const DATA_GREEN := Color("#7dff6a")


static func _new_binary(digit: String) -> CPUParticles3D:
	var p := _new_particles()
	p.explosiveness = 0.55
	p.spread = 25.0
	p.angular_velocity_min = 0.0
	p.angular_velocity_max = 0.0
	p.mesh = MeshFactory.ring_mesh(0.07, 0.12, 10) if digit == "0" else MeshFactory.mesh_for("box", Vector3(0.05, 0.02, 0.2))
	return p


static func binary(pos: Vector3, color: Color, amount: int = 14, spread_xz: float = 0.5, rise: float = 2.5, life: float = 0.9) -> void:
	## A puff of 0s (flat rings) and 1s (flat bars) floating upward.
	var pool := root()
	if pool == null:
		return
	for digit in ["0", "1"]:
		var p := pool.take("bin" + digit, func() -> Node: return Fx._new_binary(digit), life + 0.2) as CPUParticles3D
		p.amount = maxi(1, amount / 2)
		p.lifetime = life
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(spread_xz, 0.4, spread_xz)
		p.initial_velocity_min = rise * 0.5
		p.initial_velocity_max = rise
		p.gravity = Vector3.ZERO
		p.material_override = MeshFactory.unlit_shared(Color(color.r, color.g, color.b, 0.9), true)
		p.global_position = pos
		p.restart()


static func scan_ring(pos: Vector3, radius: float, height: float, color: Color, duration: float = 0.45) -> void:
	## A horizontal ring that sweeps up through a body, like a scanner pass.
	var pool := root()
	if pool == null:
		return
	var mi := pool.take("ring", func() -> Node: return Fx._new_ring(), duration) as MeshInstance3D
	mi.mesh = MeshFactory.ring_mesh(0.86, 1.0, 40)
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, 0.9)
	mi.global_position = pos + Vector3(0, 0.05, 0)
	mi.scale = Vector3.ONE * radius
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "global_position:y", pos.y + height, duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration * 0.4).set_delay(duration * 0.6)
	tw.chain().tween_callback(mi.hide)
	_track(mi, tw)


static func digitize(pos: Vector3, height: float, color: Color, scale_f: float = 1.0) -> void:
	## Something breaking down into data: scan rings sweep up, the body sheds chunky
	## pixel fragments and dissolves into rising 0s and 1s.
	scan_ring(pos, 0.9 * scale_f, height, DATA_CYAN, 0.45)
	scan_ring(pos, 1.2 * scale_f, height * 0.6, DATA_GREEN, 0.6)
	binary(pos + Vector3(0, height * 0.4, 0), DATA_CYAN, int(18 * scale_f), 0.45 * scale_f, 3.0, 1.0)
	binary(pos + Vector3(0, height * 0.7, 0), DATA_GREEN, int(10 * scale_f), 0.35 * scale_f, 2.2, 0.8)
	burst(pos + Vector3(0, height * 0.5, 0), color, int(14 * scale_f), 4.0, 0.2, 0.6, -6.0, 1.5)


static func pixel_hit(pos: Vector3, color: Color, crit: bool) -> void:
	## Chunky pixel burst for a landed hit (crits add a puff of binary).
	burst(pos, color, 6 if not crit else 11, 4.5, 0.17 if not crit else 0.22, 0.32, -6.0, 1.6)
	burst(pos, Color.WHITE, 3 if not crit else 6, 3.5, 0.12, 0.25, -4.0, 2.0)
	if crit:
		binary(pos, DATA_CYAN, 8, 0.3, 2.0, 0.5)


# ------------------------------------------------------------------ floating text

static func _new_label() -> Label3D:
	var l := Label3D.new()
	l.font_size = 64
	l.outline_size = 14
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	return l


static func text(pos: Vector3, msg: String, color: Color, size: float = 1.0, rise: float = 1.3, life: float = 0.8) -> void:
	var pool := root()
	if pool == null:
		return
	var l := pool.take("text", func() -> Node: return Fx._new_label(), life) as Label3D
	l.text = msg
	l.modulate = color
	l.pixel_size = 0.0055 * size
	l.global_position = pos
	l.scale = Vector3.ONE * 0.4
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "global_position", pos + Vector3(randf_range(-0.3, 0.3), rise, 0), life).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(l, "modulate:a", 0.0, life * 0.4).set_delay(life * 0.6)
	tw.chain().tween_callback(l.hide)
	_track(l, tw)


static func damage_number(pos: Vector3, amount: float, crit: bool, color: Color = Color(1, 1, 1)) -> void:
	if not Settings.damage_numbers:
		return
	var s := str(int(round(amount)))
	if crit:
		text(pos + Vector3(0, 0.3, 0), s + "!", Color(1.0, 0.85, 0.2), 1.6, 1.6, 0.9)
	else:
		text(pos, s, color, 1.0)


# ------------------------------------------------------------------ rings & slashes

static func _new_ring() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = MeshFactory.ring_mesh(0.82, 1.0, 48)
	mi.material_override = MeshFactory.unlit(Color.WHITE, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func ring(pos: Vector3, radius: float, color: Color, duration: float = 0.35, thickness: float = 0.18) -> void:
	var pool := root()
	if pool == null:
		return
	var mi := pool.take("ring", func() -> Node: return Fx._new_ring(), duration) as MeshInstance3D
	mi.mesh = MeshFactory.ring_mesh(1.0 - thickness, 1.0, 48)
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = color
	mi.global_position = pos + Vector3(0, 0.06, 0)
	mi.scale = Vector3.ONE * maxf(radius * 0.15, 0.1)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE * radius, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, duration).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(mi.hide)
	_track(mi, tw)


static func _new_slash() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.material_override = MeshFactory.unlit(Color.WHITE, true)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func slash(pos: Vector3, dir: Vector3, reach: float, arc: float, color: Color, sign_dir: float = 1.0) -> void:
	var pool := root()
	if pool == null:
		return
	var mi := pool.take("slash", func() -> Node: return Fx._new_slash(), 0.2) as MeshInstance3D
	mi.mesh = MeshFactory.sector_mesh(reach, minf(arc, 359.0), reach * 0.45, 20)
	var mat := mi.material_override as StandardMaterial3D
	mat.albedo_color = Color(color.r, color.g, color.b, 0.55)
	mi.global_position = pos + Vector3(0, 0.9, 0)
	mi.rotation = Vector3(0, atan2(-dir.x, -dir.z), 0)
	mi.scale = Vector3(0.75 * sign_dir, 1, 0.75)
	var tw := mi.create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.05 * sign_dir, 1, 1.05), 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	tw.chain().tween_callback(mi.hide)
	_track(mi, tw)


# ------------------------------------------------------------------ lightning

const BOLT_SEGMENTS := 5


static func _new_bolt() -> Node3D:
	var holder := Node3D.new()
	for i in BOLT_SEGMENTS:
		var mi := MeshInstance3D.new()
		mi.mesh = MeshFactory.unit_box()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	return holder


static func lightning(a: Vector3, b: Vector3, color: Color, life: float = 0.22) -> void:
	var pool := root()
	if pool == null:
		return
	var holder := pool.take("bolt", func() -> Node: return Fx._new_bolt(), life) as Node3D
	var pts: Array[Vector3] = [a]
	for i in range(1, BOLT_SEGMENTS):
		var t := float(i) / BOLT_SEGMENTS
		pts.append(a.lerp(b, t) + Vector3(randf_range(-0.35, 0.35), randf_range(-0.25, 0.25), randf_range(-0.35, 0.35)))
	pts.append(b)
	var mat := MeshFactory.glow(color, 4.0)
	for i in BOLT_SEGMENTS:
		var mi := holder.get_child(i) as MeshInstance3D
		var p0 := pts[i]
		var p1 := pts[i + 1]
		var len := p0.distance_to(p1)
		mi.visible = len > 0.01
		if not mi.visible:
			continue
		mi.material_override = mat
		var bb := Basis.IDENTITY
		if absf((p1 - p0).normalized().dot(Vector3.UP)) < 0.99:
			bb = Basis.looking_at(p1 - p0, Vector3.UP)
		mi.global_transform = Transform3D(Basis(bb.x * 0.07, bb.y * 0.07, bb.z * len), (p0 + p1) * 0.5)
	var tw := holder.create_tween()
	tw.tween_interval(life)
	tw.tween_callback(holder.hide)
	_track(holder, tw)


# ------------------------------------------------------------------ hit flash

static func flash(target: Node3D, color: Color, duration: float = 0.1) -> void:
	if target == null or not is_instance_valid(target):
		return
	var key := color.to_html()
	if not _flash_mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(color.r, color.g, color.b, 0.8)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_flash_mats[key] = m
	var mat: StandardMaterial3D = _flash_mats[key]
	var meshes := target.find_children("*", "MeshInstance3D", true, false)
	if target is MeshInstance3D:
		meshes.append(target)
	for mi in meshes:
		(mi as MeshInstance3D).material_overlay = mat
	var timer := target.get_tree().create_timer(duration, false)
	timer.timeout.connect(func() -> void:
		for mi in meshes:
			if is_instance_valid(mi) and mi.material_overlay == mat:
				mi.material_overlay = null)


# ------------------------------------------------------------------ telegraphs

static func telegraph_circle(pos: Vector3, radius: float, duration: float, color: Color = Color(1, 0.15, 0.2)) -> Node3D:
	var r := root()
	if r == null:
		return null
	var holder := Node3D.new()
	r.add_child(holder)
	holder.global_position = pos + Vector3(0, 0.04, 0)
	var edge := MeshInstance3D.new()
	edge.mesh = MeshFactory.ring_mesh(radius - 0.12, radius, 48)
	edge.material_override = MeshFactory.unlit_shared(Color(color.r, color.g, color.b, 0.85), true)
	holder.add_child(edge)
	var fill := MeshInstance3D.new()
	fill.mesh = MeshFactory.sector_mesh(radius, 360.0, 0.0, 40)
	fill.material_override = MeshFactory.unlit_shared(Color(color.r, color.g, color.b, 0.28), true)
	fill.scale = Vector3(0.05, 1, 0.05)
	fill.position.y = 0.01
	holder.add_child(fill)
	for mi in [edge, fill]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := holder.create_tween()
	tw.tween_property(fill, "scale", Vector3.ONE, duration)
	tw.tween_callback(holder.queue_free)
	return holder


static func telegraph_sector(parent: Node3D, reach: float, arc: float, duration: float, color: Color = Color(1, 0.15, 0.2)) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = Vector3(0, 0.05, 0)
	var fill := MeshInstance3D.new()
	fill.mesh = MeshFactory.sector_mesh(reach, arc, 0.3, 20)
	var fm := MeshFactory.unlit(Color(color.r, color.g, color.b, 0.1), true)
	fill.material_override = fm
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(fill)
	var tw := holder.create_tween()
	tw.tween_property(fm, "albedo_color:a", 0.55, duration)
	tw.tween_callback(holder.queue_free)
	return holder


static func telegraph_rect(pos: Vector3, dir: Vector3, length: float, width: float, duration: float, color: Color = Color(1, 0.15, 0.2)) -> Node3D:
	var r := root()
	if r == null:
		return null
	var holder := Node3D.new()
	r.add_child(holder)
	holder.global_position = pos + Vector3(0, 0.05, 0)
	holder.rotation.y = atan2(-dir.x, -dir.z)
	var outline := MeshInstance3D.new()
	outline.mesh = MeshFactory.unit_box()
	outline.material_override = MeshFactory.unlit_shared(Color(color.r, color.g, color.b, 0.18), true)
	outline.position = Vector3(0, 0, -length * 0.5)
	outline.scale = Vector3(width, 0.01, length)
	holder.add_child(outline)
	var fill_pivot := Node3D.new()
	holder.add_child(fill_pivot)
	var fill := MeshInstance3D.new()
	fill.mesh = MeshFactory.unit_box()
	fill.material_override = MeshFactory.unlit_shared(Color(color.r, color.g, color.b, 0.35), true)
	fill.position = Vector3(0, 0.005, -length * 0.5)
	fill.scale = Vector3(width, 0.012, length)
	fill_pivot.add_child(fill)
	fill_pivot.scale = Vector3(1, 1, 0.02)
	for mi in [outline, fill]:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tw := holder.create_tween()
	tw.tween_property(fill_pivot, "scale", Vector3.ONE, duration)
	tw.tween_callback(holder.queue_free)
	return holder
