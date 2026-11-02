extends Node
## Photographs every level from the game camera and quits (needs a window, not --headless):
##   godot --path . -- --tour
## Saves user://tour/<level>_<n>.png at a spread of walkable spots, plus a close-up of
## the first few marker cells named in SPOTLIGHT (cables, desks...), so art changes can
## be compared before/after without playing through.

const OUT := "user://tour"
const SHOTS_PER_LEVEL := 4
const SPOTLIGHT := {"c": "cables", "d": "desk", "x": "server", "p": "printer"}


func _ready() -> void:
	var ui: CanvasLayer = GameState.main.ui
	ui.visible = false
	DirAccess.make_dir_recursive_absolute(OUT)
	await _run()
	get_tree().quit()


func _run() -> void:
	for level_id in DB.levels:
		GameState.main._load_world(str(level_id), {}, true)
		var w: GameWorld = GameState.main.world
		await GameState.main._await_world_ready()
		w.rig.orbit = false
		w.rig.camera.position = CameraRig.OFFSET
		var spots: Array = []
		var open: Array = []
		for y in w.height:
			for x in w.width:
				if not w.rows[y][x] in GameWorld.SOLID:
					open.append(Vector2i(x, y))
		for i in SHOTS_PER_LEVEL:
			spots.append([str(i), open[int((open.size() - 1) * (i + 0.5) / SHOTS_PER_LEVEL)]])
		for ch in SPOTLIGHT:
			var cells: Array = w._markers.get(ch, [])
			if not cells.is_empty():
				spots.append([SPOTLIGHT[ch], cells[cells.size() / 2]])
		for s in spots:
			w.rig.global_position = w.cell_center(s[1])
			RenderingServer.global_shader_parameter_set("player_pos", w.rig.global_position)
			await _shoot("%s_%s" % [level_id, s[0]])


func _shoot(shot_name: String) -> void:
	for f in 8:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT, shot_name]
	img.save_png(path)
	print("[TOUR] ", ProjectSettings.globalize_path(path))
