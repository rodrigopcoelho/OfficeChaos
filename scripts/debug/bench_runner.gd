extends Node
## Performance + memory benchmark. Run windowed (it needs the real renderer):
##   godot --path . -- --bench
## Prints per-scene frame times (avg / 1% low / worst), draw calls, objects,
## level build times, combat stress spikes, and a level-cycling leak test.

const SLOT := 2
const SAMPLE_FRAMES := 150

var _times: PackedFloat64Array = PackedFloat64Array()
var _sampling := false
var _last_us := 0
var _god_mode := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run.call_deferred()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _sampling and _last_us > 0:
		var ft := (now - _last_us) / 1000.0
		_times.append(ft)
		if ft > 100.0:
			print("[SPIKE] %.0f ms  (cpu process %.1f ms, physics %.1f ms, draw calls %d)" % [ft, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	_last_us = now
	var p = GameState.player
	if _god_mode and p != null and is_instance_valid(p):
		p.invuln = 1.0
		p.hp = p.max_hp


func _wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func _sample(label: String, frames: int = SAMPLE_FRAMES, driver: Callable = Callable()) -> Dictionary:
	_times = PackedFloat64Array()
	var dc := 0.0
	var objs := 0.0
	var prims := 0.0
	_sampling = true
	for i in frames:
		await get_tree().process_frame
		if driver.is_valid():
			driver.call()
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	_sampling = false
	var sorted := _times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in sorted:
		total += t
	var n := maxi(sorted.size(), 1)
	var r := {
		"label": label,
		"avg_ms": total / n,
		"p99_ms": sorted[int(n * 0.99) - 1] if n > 1 else 0.0,
		"max_ms": sorted[n - 1] if n > 0 else 0.0,
		"draw_calls": dc / frames,
		"objects": objs / frames,
		"prims_k": prims / frames / 1000.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
	}
	print("[BENCH] %-34s avg %6.2f ms (%5.1f fps) | 1%% low %6.2f ms | worst %6.2f ms | draw calls %6.0f | objects %5.0f | prims %6.1fk | nodes %5d" % [
		label, r.avg_ms, 1000.0 / maxf(r.avg_ms, 0.001), r.p99_ms, r.max_ms, r.draw_calls, r.objects, r.prims_k, int(r.nodes)])
	return r


func _walkable_near(target: Vector3) -> Vector3:
	var w = GameState.world
	var c: Vector2i = w.world_to_cell(target)
	for radius in 12:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var cc := c + Vector2i(dx, dy)
				if w.is_walkable_cell(cc):
					return w.cell_center(cc)
	return w.player_start


func _spots() -> Array:
	var w = GameState.world
	var size := Vector3(w.width * w.CELL, 0, w.height * w.CELL)
	return [
		["start", w.player_start],
		["centre", _walkable_near(size * 0.5)],
		["quarter", _walkable_near(Vector3(size.x * 0.3, 0, size.z * 0.7))],
		["far", _walkable_near(Vector3(size.x * 0.8, 0, size.z * 0.3))],
	]


func _leak_snapshot(label: String) -> void:
	print("[LEAK] %-22s objects %6d | nodes %5d | orphan nodes %4d | resources %5d | static mem %6.1f MB | video mem %6.1f MB" % [
		label,
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])


func _apply_toggles() -> void:
	## Experiment switches: --scale=0.5 --shadow=ortho|off --noglow --nopost --nolights --nomsaa --nooutline
	var args := OS.get_cmdline_user_args()
	var w = GameState.world
	for a in args:
		if a.begins_with("--scale="):
			get_viewport().scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			get_viewport().scaling_3d_scale = float(a.get_slice("=", 1))
		elif a == "--nomsaa":
			get_viewport().msaa_3d = Viewport.MSAA_DISABLED
		elif a == "--noglow" and w:
			w.env.glow_enabled = false
		elif a == "--nopost":
			GameState.ui.post_layer.visible = false
		elif a == "--nolights" and w:
			for l in w.find_children("*", "OmniLight3D", true, false):
				l.visible = false
		elif a.begins_with("--shadow=") and w:
			for sun in w.find_children("*", "DirectionalLight3D", true, false):
				match a.get_slice("=", 1):
					"off": sun.shadow_enabled = false
					"ortho": sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
					"2": sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		elif a.begins_with("--shadowdist=") and w:
			for sun in w.find_children("*", "DirectionalLight3D", true, false):
				sun.directional_shadow_max_distance = float(a.get_slice("=", 1))
		elif a == "--noactors" and w:
			for e in w.get_tree().get_nodes_in_group("enemies"):
				e.visible = false
		elif a == "--no3d" and w:
			w.visible = false
		elif a == "--noui":
			GameState.ui.root.visible = false
		elif a == "--nooutline":
			for m in MeshFactory._materials.values():
				(m as ShaderMaterial).next_pass = null


func _quick() -> void:
	var main = GameState.main
	print("[BENCH] quick  args=%s  window=%s  screen scale=%.1f" % [str(OS.get_cmdline_user_args()), str(get_window().size), DisplayServer.screen_get_scale()])
	GameState.delete_slot(SLOT)
	# --quality= is for this run only: creating the bench profile saves the settings
	# file, so put the player's own choice back before quitting.
	var own_quality := Settings.quality
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--quality="):
			Settings.quality = a.get_slice("=", 1)
			Settings.apply()
	if "--noicons" in OS.get_cmdline_user_args():
		GameState.ui.icons.disabled = true
	if "--notoasts" in OS.get_cmdline_user_args():
		GameState.notified.disconnect(GameState.ui.toasts.push)
	GameState.new_profile("Bench", {"body": 0, "palette": 1, "hair": 0}, SLOT)
	await main.start_game()
	_god_mode = true
	for lid in ["hub", "office_floor"]:
		await main.travel(lid, {"type": "start"})
		await _wait(0.6)
		_apply_toggles()
		var sp: Array = _spots()
		GameState.player.global_position = sp[1][1]
		GameState.world.rig.snap()
		await _wait(0.6)
		await _sample("%s / centre" % lid)
	GameState.delete_slot(SLOT)
	Settings.quality = own_quality
	Settings.save_settings()
	get_tree().quit(0)


func _run() -> void:
	if "--quick" in OS.get_cmdline_user_args():
		await _quick()
		return
	var main = GameState.main
	print("[BENCH] ===== OFFICE CHAOS benchmark  (%s, %s) =====" % [RenderingServer.get_video_adapter_name(), ProjectSettings.get_setting("rendering/renderer/rendering_method")])
	GameState.delete_slot(SLOT)
	GameState.new_profile("Bench", {"body": 0, "palette": 1, "hair": 0}, SLOT)
	await main.start_game()
	_god_mode = true
	# --- level build times
	for lid in ["hub", "office_floor", "dungeon_server_room"]:
		var t0 := Time.get_ticks_usec()
		main._load_world(lid, {"type": "start"}, false)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		await _wait(0.2)
		print("[BENCH] build %-22s %7.1f ms" % [lid, ms])
	# --- static scenes
	for lid in ["hub", "office_floor", "dungeon_server_room"]:
		await main.travel(lid, {"type": "start"})
		await _wait(1.0)
		for s in _spots():
			GameState.player.global_position = s[1]
			GameState.world.rig.snap()
			await _wait(0.5)
			await _sample("%s / %s" % [lid, s[0]])
	# --- combat stress: a crowd fighting the player on Floor 7
	await main.travel("office_floor", {"type": "start"})
	await _wait(0.8)
	var arena := _walkable_near(Vector3(48, 0, 30))
	var p = GameState.player
	p.global_position = arena
	GameState.world.rig.snap()
	for i in 22:
		var id: String = ["trojan", "worm", "spyware", "ransomware", "trojan"][i % 5]
		var e = GameState.world.spawn_enemy_near(id, arena, 6.0, 0)
		if e:
			e.aggro = true
	await _wait(0.3)
	await _sample("combat crowd (22 viruses)", 420, _auto_fight)
	# --- boss phase 2 stress
	await main.travel("dungeon_server_room", {"type": "start"})
	await _wait(0.8)
	var boss = GameState.world.boss
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != boss:
			e.die(false)
	p = GameState.player
	p.global_position = boss.global_position + Vector3(0, 0, 7)
	GameState.world.rig.snap()
	await _wait(1.2)
	boss.hp = boss.max_hp * 0.49
	await _wait(2.2)
	await _sample("boss phase 2", 600, _auto_fight)
	# --- leak test: cycle levels and watch object counts
	_leak_snapshot("before cycling")
	for cycle in 4:
		for lid in ["office_floor", "dungeon_server_room", "hub"]:
			await main.travel(lid, {"type": "start"})
			await _wait(0.3)
		await _wait(0.6)
		_leak_snapshot("after cycle %d" % (cycle + 1))
	_god_mode = false
	GameState.delete_slot(SLOT)
	print("[BENCH] ===== done =====")
	get_tree().quit(0)


func _auto_fight() -> void:
	var p = GameState.player
	if p == null or not is_instance_valid(p) or p.dead:
		return
	var best = null
	var best_d := 99.0
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = p.global_position.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	if best == null:
		return
	p.aim_point = best.global_position
	if best_d > 2.0:
		p.velocity = (best.global_position - p.global_position).normalized() * 5.0
	if p.attack_cd <= 0.0:
		p.facing = (best.global_position - p.global_position).normalized()
		p.attack()
	if p.special_cd <= 0.0:
		p.special()
