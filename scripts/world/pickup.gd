class_name Pickup
extends Node3D
## DATA fragments, Gold, Corrupted Gold and dropped equipment. Currencies scatter,
## then get absorbed into the player; equipment waits on the floor under a rarity beam.

var kind := "data"
var amount := 1.0
var item: Dictionary = {}
var vel := Vector3.ZERO
var vy := 0.0
var age := 0.0
var homing := false
var home_speed := 4.0
var mesh_root: Node3D
var _warned := false


func setup(k: String, amt: float, it: Dictionary = {}) -> Pickup:
	kind = k
	amount = amt
	item = it
	return self


func _ready() -> void:
	mesh_root = Node3D.new()
	add_child(mesh_root)
	var a := randf() * TAU
	match kind:
		"data":
			var mi := MeshInstance3D.new()
			mi.mesh = MeshFactory.mesh_for("gem", Vector3(0.26, 0.34, 0.26))
			mi.material_override = MeshFactory.glow(Color("#5ff2d0"), 4.0)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mesh_root.add_child(mi)
			vel = Vector3(cos(a), 0, sin(a)) * randf_range(2.0, 5.0)
			vy = randf_range(4.0, 7.0)
		"gold":
			var mi2 := MeshFactory.kit_instance("cyl", Vector3(0.3, 0.07, 0.3))
			mi2.material_override = MeshFactory.clay(Color("#ffc94a"), 0.4, 0.0)
			mi2.rotation_degrees.x = 90
			mesh_root.add_child(mi2)
			vel = Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 4.0)
			vy = randf_range(5.0, 8.0)
		"cgold":
			var mi3 := MeshFactory.kit_instance("cyl", Vector3(0.36, 0.08, 0.36))
			mi3.material_override = MeshFactory.clay(Color("#7a2cff"), 1.6, 0.0)
			mi3.rotation_degrees.x = 90
			mesh_root.add_child(mi3)
			var rim := MeshFactory.kit_instance("torus", Vector3(0.42, 0.1, 0.42))
			rim.material_override = MeshFactory.clay(Color("#ff4fd8"), 2.2, 0.0)
			rim.rotation_degrees.x = 90
			mesh_root.add_child(rim)
			vel = Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 4.0)
			vy = randf_range(6.0, 9.0)
		"item":
			_build_item_visual()
			vel = Vector3(cos(a), 0, sin(a)) * randf_range(1.0, 2.5)
			vy = 6.0


func _build_item_visual() -> void:
	var d := ItemUtil.def(item)
	var rc := ItemUtil.rarity_color(str(d.get("rarity", "common")))
	var holder := Node3D.new()
	holder.position.y = 0.9
	mesh_root.add_child(holder)
	var vis: Dictionary = d.get("visual", {})
	match str(d.get("slot", "")):
		"weapon":
			var w := Node3D.new()
			w.rotation_degrees = Vector3(-60, 0, 0)
			w.position.y = -0.2
			holder.add_child(w)
			MeshFactory.build(vis.get("parts", []), w, {}, 0.01, {}, true, true)
		"chest":
			MeshFactory.box(holder, Vector3(0.6, 0.65, 0.36), Vector3.ZERO, MeshFactory.col(vis.get("torso_color", "#888888")), 0.0, 0.02)
			var top := Node3D.new()
			top.position.y = 0.33
			holder.add_child(top)
			MeshFactory.build(vis.get("parts", []), top, {}, 0.01, {}, true, true)
		"helmet":
			var hn := Node3D.new()
			hn.scale = Vector3.ONE * 0.75
			holder.add_child(hn)
			MeshFactory.build(vis.get("parts", []), hn, {}, 0.01, {}, true, true)
		"legs", "boots":
			var col := MeshFactory.col(vis.get("color", "#888888"))
			for sx in [-1.0, 1.0]:
				if str(d.slot) == "legs":
					MeshFactory.shape(holder, "capsule", Vector3(0.2, 0.5, 0.21), Vector3(sx * 0.14, 0.0, 0), col)
				else:
					MeshFactory.shape(holder, "dome", Vector3(0.26, 0.2, 0.36), Vector3(sx * 0.16, -0.2, 0), col)
			if not (vis.get("parts", []) as Array).is_empty():
				MeshFactory.build(vis.get("parts", []), holder, {}, 0.01, {}, true, true)
		_:
			if (vis.get("parts", []) as Array).is_empty():
				MeshFactory.shape(holder, "torus", Vector3(0.4, 0.07, 0.4), Vector3.ZERO, MeshFactory.col(vis.get("ring_color", "#ffcc33")), 0.8, Vector3(90, 0, 0))
			else:
				MeshFactory.build(vis.get("parts", []), holder, {}, 0.01, {}, true, true)
	var beam := MeshInstance3D.new()
	beam.mesh = MeshFactory.mesh_for("cyl", Vector3(0.22, 5.0, 0.22))
	beam.material_override = MeshFactory.unlit_shared(Color(rc.r, rc.g, rc.b, 0.3), true)
	beam.position.y = 2.5
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(beam)
	var ring := MeshInstance3D.new()
	ring.mesh = MeshFactory.ring_mesh(0.5, 0.65, 24)
	ring.material_override = MeshFactory.unlit_shared(Color(rc.r, rc.g, rc.b, 0.8), true)
	ring.position.y = 0.04
	add_child(ring)
	var l := Label3D.new()
	l.text = ItemUtil.display_name(item)
	l.font_size = 40
	l.outline_size = 10
	l.pixel_size = 0.006
	l.modulate = rc.lightened(0.2)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position.y = 1.9
	add_child(l)
	var light := OmniLight3D.new()
	light.light_color = rc
	light.light_energy = 1.2 if str(d.get("rarity", "")) == "common" else 2.4
	light.omni_range = 3.0
	light.position.y = 1.0
	add_child(light)


func _physics_process(delta: float) -> void:
	age += delta
	var p := GameState.player
	var valid: bool = p != null and is_instance_valid(p) and not p.dead
	if not homing:
		position += vel * delta
		vy -= 20.0 * delta
		mesh_root.position.y += vy * delta
		if mesh_root.position.y < 0.35:
			mesh_root.position.y = 0.35
			vy = absf(vy) * 0.35 if absf(vy) > 1.5 else 0.0
			vel *= 0.6
		vel = vel.lerp(Vector3.ZERO, 1.0 - exp(-3.0 * delta))
		mesh_root.rotation.y += delta * 3.0
		if kind == "item":
			mesh_root.position.y = maxf(mesh_root.position.y, 0.35) + sin(age * 2.5) * 0.002
	if not valid:
		return
	var to: Vector3 = p.global_position + Vector3(0, 1.0, 0) - (global_position + mesh_root.position)
	var dist := to.length()
	match kind:
		"data", "gold", "cgold":
			var magnet := float(p.stats.get("pickup_radius", 5.0)) * (2.0 if kind == "data" else 1.0)
			if age > 0.45 and dist < magnet:
				homing = true
			if homing:
				home_speed = minf(32.0, home_speed + 45.0 * delta)
				global_position += to.normalized() * minf(home_speed * delta, dist)
				mesh_root.scale = Vector3.ONE * clampf(dist / 2.0, 0.4, 1.0)
				if dist < 0.6:
					_collect(p)
		"item":
			var flat := Vector2(to.x, to.z).length()
			if age > 0.6 and flat < 1.5:
				if GameState.add_item(item):
					_collect(p)
				elif not _warned:
					_warned = true
					GameState.notify("Asset Management", "Inventory full! Salvage something to pick up %s." % ItemUtil.display_name(item), "warn")


func _collect(p: Player) -> void:
	# A boss drops ~25 orbs at once: absorb sparkles are throttled to one every 60 ms.
	var now := Time.get_ticks_msec()
	var sparkle := now - p.last_absorb_fx > 60
	if sparkle:
		p.last_absorb_fx = now
	match kind:
		"data":
			GameState.add_xp(amount)
			Audio.play("data", -6.0, 0.15, 0.03)
			if sparkle:
				Fx.burst(p.global_position + Vector3(0, 1.0, 0), Color("#5ff2d0"), 5, 2.5, 0.07, 0.3, 3.0, 4.0)
				Fx.flash(p.visual, Color("#5ff2d0"), 0.05)
		"gold":
			var got := GameState.add_gold(int(amount))
			Audio.play("gold", -6.0, 0.1, 0.03)
			if sparkle:
				Fx.burst(p.global_position + Vector3(0, 1.2, 0), Color("#ffcc33"), 4, 2.5, 0.07, 0.3, 3.0)
			if got >= 10:
				Fx.text(p.global_position + Vector3(0, 2.4, 0), "+%d Gold" % got, Color("#ffcc33"), 0.8)
		"cgold":
			GameState.add_corrupted_gold(int(amount))
			Audio.play("gold", -3.0, 0.1, -0.25)
			Fx.burst(p.global_position + Vector3(0, 1.2, 0), Color("#b24bff"), 8, 3.0, 0.08, 0.4, 3.0)
			Fx.text(p.global_position + Vector3(0, 2.6, 0), "+%d Corrupted Gold" % int(amount), Color("#d48bff"), 0.9)
		"item":
			Audio.play("item")
			var rc := ItemUtil.rarity_color(str(ItemUtil.def(item).get("rarity", "common")))
			Fx.burst(global_position + Vector3(0, 1.0, 0), rc, 20, 5.0, 0.12, 0.6)
	queue_free()
