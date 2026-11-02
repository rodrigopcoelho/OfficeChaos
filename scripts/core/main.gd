class_name Main
extends Node
## Root scene: owns the persistent UI and swaps GameWorld instances (levels).
## Every level load happens behind a fade that only lifts once the new level has
## warmed up its shaders (see GameWorld._start_warm_up).

var world: GameWorld = null
var ui: UIRoot
var _traveling := false
var _last_level_type := ""


func _ready() -> void:
	GameState.main = self
	ui = UIRoot.new()
	add_child(ui)
	var args := OS.get_cmdline_user_args()
	for flag in ["--qa", "--bench", "--chars", "--tour", "--icons"]:
		if flag in args:
			var runner_name: String = {"--qa": "qa_runner", "--bench": "bench_runner", "--chars": "character_sheet", "--tour": "tour_runner", "--icons": "icon_baker"}[flag]
			add_child((load("res://scripts/debug/%s.gd" % runner_name) as GDScript).new())
			return
	ui.fade.modulate.a = 1.0
	go_to_menu()


func go_to_menu() -> void:
	if ui.fade.modulate.a < 0.99:
		await ui.fade_out(0.3)
	GameState.playing = false
	get_tree().paused = false
	_load_world(str(DB.manifest.get("hub_level", "hub")), {}, true)
	ui.show_main_menu()
	await _await_world_ready()
	await ui.fade_in(0.5)


func start_game() -> void:
	GameState.playing = true
	ui.enter_play_mode()
	var lvl := str(GameState.profile.get("current_level", "hub"))
	var lv: Dictionary = DB.levels.get(lvl, {})
	if lv.is_empty() or str(lv.get("type", "")) == "dungeon":
		lvl = str(DB.manifest.get("hub_level", "hub"))
	_last_level_type = ""
	await travel(lvl, {"type": "start"})


func travel(level_id: String, spawn: Dictionary = {}, use_fade: bool = true) -> void:
	if _traveling:
		return
	_traveling = true
	if use_fade:
		await ui.fade_out(0.35)
	else:
		await get_tree().process_frame
	get_tree().paused = false
	ui.app.visible = false
	ui.pause_menu.visible = false
	ui.close_dialog()
	_load_world(level_id, spawn, false)
	var lv: Dictionary = DB.levels.get(level_id, {})
	var t := str(lv.get("type", ""))
	if t != "dungeon":
		GameState.profile["current_level"] = level_id
	if t == "hub" and _last_level_type != "" and _last_level_type != "hub":
		GameState.refresh_shop()
		GameState.notify("Procurement", "New stock has arrived at the Procurement desk.", "shop")
	_last_level_type = t
	GameState.save_game()
	ui.on_level_loaded()
	ui.refresh_pause()
	await _await_world_ready()
	if use_fade:
		await ui.fade_in(0.45)
	_traveling = false


func _await_world_ready() -> void:
	## Waits (bounded) for the new level's shader warm-up frames.
	var frames := 0
	while world != null and is_instance_valid(world) and not world.warmed and frames < 120:
		await get_tree().process_frame
		frames += 1


func _load_world(level_id: String, spawn: Dictionary, menu: bool) -> void:
	if world != null and is_instance_valid(world):
		remove_child(world)
		world.queue_free()
	world = GameWorld.new()
	world.level_id = level_id
	world.spawn_request = spawn
	world.menu_mode = menu
	add_child(world)
	move_child(world, 0)
