extends Node
## Automated play-through used for testing: run with
##   godot --path . -- --qa            (headless-friendly, prints PASS/FAIL)
##   godot --path . -- --qa --shots    (also saves screenshots to user://qa_shots)
## It drives the real game systems: character creation, hub shopping, combat,
## loot, levelling, terminals, the dungeon, the boss, death/respawn and saving.

const SLOT := 2

var failures: Array[String] = []
var passes := 0
var shots := false
var shot_i := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shots = "--shots" in OS.get_cmdline_user_args()
	_run.call_deferred()


func check(cond: bool, what: String) -> void:
	if cond:
		passes += 1
		print("[QA] PASS  ", what)
	else:
		failures.append(what)
		print("[QA] FAIL  ", what)


func wait(t: float) -> void:
	await get_tree().create_timer(t, true, false, true).timeout


func wait_until(cond: Callable, timeout: float) -> void:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await get_tree().process_frame


func frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String) -> void:
	if not shots:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://qa_shots")
	var path := "user://qa_shots/%02d_%s.png" % [shot_i, name]
	shot_i += 1
	img.save_png(path)
	print("[QA] screenshot ", ProjectSettings.globalize_path(path))


func _run() -> void:
	var main = GameState.main
	print("[QA] ===== OFFICE CHAOS automated play-through =====")
	# --- data
	check(DB.items.size() >= 13, "content: >= 10 weapons + armor + accessories loaded (%d items)" % DB.items.size())
	var per_slot := {}
	for id in DB.items:
		var sl := str(DB.items[id].slot)
		per_slot[sl] = int(per_slot.get(sl, 0)) + 1
	check(int(per_slot.get("weapon", 0)) == 68, "content: 68 weapons (17 basic x 3 tiers + 17 Root) (%d)" % int(per_slot.get("weapon", 0)))
	var armor_total := 0
	for sl in ["helmet", "chest", "legs", "boots"]:
		armor_total += int(per_slot.get(sl, 0))
		check(int(per_slot.get(sl, 0)) == 14, "content: 14 %s variants (3 basic x 3 + 5 Root) (%d)" % [sl, int(per_slot.get(sl, 0))])
	check(armor_total == 56, "content: 56 armor variants (%d)" % armor_total)
	check(not per_slot.has("armor"), "no items left in the old single armor slot")
	check(DB.items.has("arming_sword_patched") and DB.items.has("arming_sword_overclocked") and str(DB.items.alt_f4.class) == "sword", "tiers expand and Root items inherit their base weapon")
	var missing_icons := 0
	for id in DB.items:
		if not FileAccess.file_exists(ProjectSettings.globalize_path(IconCache.ICON_DIR + str(id) + ".png")):
			missing_icons += 1
	check(missing_icons == 0, "every item has baked 2D icon art (%d missing)" % missing_icons)
	await _rarity_tests()
	check(DB.enchantments.size() >= 5, "content: %d enchantments" % DB.enchantments.size())
	check(DB.enemies.size() >= 4, "content: %d enemy types" % DB.enemies.size())
	# --- main menu
	main.go_to_menu()
	await wait_until(func() -> bool: return GameState.world != null and GameState.world.warmed, 10.0)
	await wait(0.6)
	await shot("main_menu")
	check(GameState.world != null and GameState.world.menu_mode, "main menu shows the live lobby")
	ui_click_new_hire()
	await wait(0.6)
	await shot("char_create")
	# --- character creation
	GameState.delete_slot(SLOT)
	GameState.new_profile("QA Tester", {"body": 1, "palette": 4, "hair": 2}, SLOT)
	check(GameState.has_profile(), "character created")
	check(not GameState.equipped("weapon").is_empty(), "starting weapon equipped")
	check(not GameState.equipped("chest").is_empty() and not GameState.equipped("legs").is_empty() and not GameState.equipped("boots").is_empty(), "starting chestplate, leggings and boots equipped")
	check(GameState.power() == 1, "a new hire starts at Power 1")
	await main.start_game()
	await wait(0.8)
	check(GameState.world.level_id == "hub", "game starts in the hub")
	check(GameState.player != null, "player spawned")
	await shot("hub")
	# --- character look and expressions
	var vis: CharacterVisual = GameState.player.visual
	check(vis.face_mesh != null and vis.torso.material_override is ShaderMaterial, "employee has a painted face and suit")
	vis.express("hurt", 0.3)
	await wait(0.05)
	check(vis.mood == "hurt" and GameState.ui.hud.portrait.figure.mood == "hurt", "face reacts and the HUD portrait mirrors it")
	await wait(0.5)
	check(vis.mood == "neutral" and GameState.ui.hud.portrait.figure.mood == "neutral", "expression returns to neutral")
	# --- stations
	var stations := get_tree().get_nodes_in_group("interactables").filter(func(n): return n is Station)
	check(stations.size() == 3, "hub has 3 service stations (%d)" % stations.size())
	for t in ["shop", "forge", "enchant", "inventory", "profile", "network"]:
		GameState.ui.open_app(t)
		await frames(3)
		check(GameState.ui.app.visible and GameState.ui.app.tab == t, "app tab '%s' opens" % t)
		if t == "inventory" or t == "shop":
			await wait(0.4)
			await shot("app_" + t)
	GameState.ui.app.close_window()
	check(not get_tree().paused, "closing the app unpauses")
	# --- shop
	GameState.profile.gold = 2000
	var stock: Array = GameState.profile.shop_stock
	check(stock.size() > 0, "shop has stock (%d)" % stock.size())
	var bought_uid := int(stock[0].uid)
	var err := GameState.buy_shop_item(bought_uid)
	check(err == "" and not GameState.find_item(bought_uid).is_empty(), "buy item from shop")
	# --- blacksmith
	var w := GameState.equipped("weapon")
	var dmg0 := float(GameState.stats.weapon.damage)
	err = GameState.upgrade_item(int(w.uid))
	check(err == "" and float(GameState.stats.weapon.damage) > dmg0, "blacksmith upgrade raises damage (%.1f -> %.1f)" % [dmg0, float(GameState.stats.weapon.damage)])
	# --- upgrades (formerly enchanting): points to install, Corrupted Gold to level up
	GameState.profile.points = 10
	var slot0: Dictionary = w.enchants[0]
	var opt := str(slot0.options[0])
	err = GameState.choose_enchant(int(w.uid), 0, opt)
	check(err == "", "install upgrade " + opt)
	GameState.profile.corrupted_gold = 0
	err = GameState.upgrade_enchant(int(w.uid), 0)
	check(err != "" and int(w.enchants[0].level) == 1, "levelling an upgrade needs Corrupted Gold")
	GameState.add_corrupted_gold(50)
	err = GameState.upgrade_enchant(int(w.uid), 0)
	check(err == "" and int(w.enchants[0].level) == 2 and int(GameState.profile.corrupted_gold) < 50, "level upgrade to II with Corrupted Gold")
	check(GameState.player.active_enchants.size() >= 1, "player picks up active upgrades")
	# --- Power: gear is the only source of stats
	var hp0 := float(GameState.stats.max_hp)
	var dmg1 := float(GameState.stats.weapon.damage)
	var strong := Loot.make_instance(str(w.id), 6)
	GameState.add_item(strong, false)
	GameState.equip(int(strong.uid))
	check(float(GameState.stats.weapon.damage) > dmg1 * 1.3, "a Power 6 copy of the weapon hits harder (%.1f -> %.1f)" % [dmg1, float(GameState.stats.weapon.damage)])
	check(GameState.power() > 1, "equipping higher-Power gear raises your Power (%d)" % GameState.power())
	var scaled_enemy := Enemy.new().setup("trojan", 1.0, 0)
	GameState.equip(int(w.uid))
	var base_enemy := Enemy.new().setup("trojan", 1.0, 0)
	check(scaled_enemy.max_hp > base_enemy.max_hp, "viruses scale to your Power (%.0f vs %.0f HP)" % [scaled_enemy.max_hp, base_enemy.max_hp])
	scaled_enemy.free()
	base_enemy.free()
	check(float(GameState.stats.max_hp) == hp0, "no stat changes from swapping back")
	# --- go to the office through the elevator
	await main.travel("office_floor", {"type": "start"})
	await wait(0.8)
	check(GameState.world.level_id == "office_floor", "elevator to office floor")
	var enemies := get_tree().get_nodes_in_group("enemies")
	check(enemies.size() >= 15, "office has encounters (%d enemies)" % enemies.size())
	GameState.player.global_position = GameState.world.computers[0].global_position + Vector3(0, 0, 2.5)
	await wait(0.3)
	check(GameState.is_computer_unlocked("floor7_elevator"), "golden computer unlocks when the player walks up")
	var reds := get_tree().get_nodes_in_group("interactables").filter(func(n): return n is WallDoor and n.is_red)
	check(reds.size() == 1, "exactly one red meeting room door")
	await shot("office")
	# --- combat: fight the first encounter for real
	var p: Player = GameState.player
	var target: Enemy = null
	for e in enemies:
		if e.enemy_id == "trojan":
			target = e
			break
	var xp0 := int(GameState.profile.xp) + int(GameState.profile.level) * 100000
	var gold0 := int(GameState.profile.gold)
	p.global_position = target.global_position + Vector3(1.5, 0, 0)
	await frames(2)
	var swings := 0
	while is_instance_valid(target) and not target.dead and swings < 40:
		p.aim_point = target.global_position
		p.facing = (target.global_position - p.global_position).normalized()
		p.attack_cd = 0.0
		p.attack()
		swings += 1
		p.hp = p.max_hp
		await wait(0.12)
	check(not is_instance_valid(target) or target.dead, "player melee kills a Process Worker (%d swings)" % swings)
	await shot("combat")
	await wait(1.6)
	var xp1 := int(GameState.profile.xp) + int(GameState.profile.level) * 100000
	check(xp1 > xp0, "DATA absorbed after kill")
	check(int(GameState.profile.gold) > gold0, "Gold collected after kill")
	# --- jump and Slam Impact
	await _slam_test(p)
	# --- corrupted enemies drop Corrupted Gold
	var plain := Enemy.new().setup("trojan", 1.0, 0)
	var cor := Enemy.new().setup("trojan", 1.0, 0)
	cor.make_corrupted()
	check(cor.corrupted and cor.max_hp > plain.max_hp * 1.5 and cor.damage > plain.damage, "corrupted variant has better stats (%.0f vs %.0f HP)" % [cor.max_hp, plain.max_hp])
	plain.free()
	GameState.world.actors_root.add_child(cor)
	cor.global_position = p.global_position + Vector3(2, 0, 0)
	await frames(2)
	var cg0 := int(GameState.profile.corrupted_gold)
	cor.die(true)
	await wait(1.6)
	check(int(GameState.profile.corrupted_gold) > cg0, "corrupted enemy drops Corrupted Gold (%d -> %d)" % [cg0, int(GameState.profile.corrupted_gold)])
	# --- enemy AI hurts the player
	var hp_before := p.hp
	var attacker: Enemy = null
	for e in get_tree().get_nodes_in_group("enemies"):
		if not e.dead:
			attacker = e
			break
	p.global_position = attacker.global_position + Vector3(1.2, 0, 0)
	p.input_enabled = false
	var t0 := 0.0
	while p.hp >= hp_before and t0 < 6.0:
		await wait(0.1)
		t0 += 0.1
	check(p.hp < hp_before, "enemy AI detects, approaches and damages player")
	p.input_enabled = true
	p.hp = p.max_hp
	# --- loot drop
	var drop := Loot.make_instance("katana_overclocked")
	GameState.world.drop_rewards(p.global_position, 0.0, 0, "")
	var pk := Pickup.new().setup("item", 0.0, drop)
	GameState.world.pickups_root.add_child(pk)
	pk.global_position = p.global_position
	await wait(1.2)
	check(not GameState.find_item(int(drop.uid)).is_empty(), "walking over dropped equipment picks it up")
	check(int(drop.get("power", 0)) >= 1, "dropped gear rolls a Power (%d)" % int(drop.get("power", 0)))
	var hp_lv := float(GameState.stats.max_hp)
	var pts_lv := int(GameState.profile.points)
	GameState.add_xp(400)
	check(int(GameState.profile.level) >= 3, "DATA levels up (now Lv%d)" % int(GameState.profile.level))
	check(float(GameState.stats.max_hp) == hp_lv and int(GameState.profile.points) > pts_lv, "levelling grants Upgrade Points but no stats")
	check(GameState.equip(int(drop.uid)), "equip the dropped Overclocked Katana (no level gate)")
	await _controller_tests(p)
	# --- special abilities
	for wid in ["arming_sword", "hand_axe", "dagger", "flanged_mace", "spear"]:
		var inst := Loot.make_instance(wid)
		GameState.add_item(inst, false)
		GameState.equip(int(inst.uid))
		p.special_cd = 0.0
		p.special()
		await wait(0.4)
		check(p.special_cd > 0.0, "special ability works with " + wid)
	GameState.equip(int(drop.uid))
	# --- network closet terminal
	var gc2 = null
	for g in GameState.world.computers:
		if g.computer_id == "floor7_network_closet":
			gc2 = g
	p.global_position = gc2.global_position + Vector3(0, 0, 2)
	await wait(0.4)
	check(GameState.is_computer_unlocked("floor7_network_closet"), "second golden computer unlocks when reached")
	# --- teleport via network
	await main.travel("hub", {"type": "computer", "id": "lobby_terminal"})
	await wait(0.5)
	check(GameState.world.level_id == "hub", "teleport to lobby terminal")
	await main.travel("office_floor", {"type": "computer", "id": "floor7_network_closet"})
	await wait(0.5)
	p = GameState.player
	check(p.global_position.distance_to(GameState.world.computers[1].global_position) < 5.0, "teleport lands at the chosen terminal")
	# --- red door -> dungeon
	reds = get_tree().get_nodes_in_group("interactables").filter(func(n): return n is WallDoor and n.is_red)
	reds[0].interact(p)
	await frames(2)
	check(GameState.ui.dialog_layer.get_child_count() > 0, "red door shows the meeting invite")
	await shot("invite")
	GameState.ui.close_dialog()
	await main.travel("dungeon_server_room", {"type": "start"})
	await wait(0.8)
	check(GameState.world.level_id == "dungeon_server_room", "entered dungeon")
	check(GameState.world.boss != null, "dungeon has a boss")
	check(get_tree().get_nodes_in_group("enemies").size() >= 15, "dungeon has encounters")
	await shot("dungeon")
	# --- boss fight: walk in, get it active, fight via real hits
	p = GameState.player
	var boss: Boss = GameState.world.boss
	for e in get_tree().get_nodes_in_group("enemies"):
		if e != boss:
			e.die(false)
	await wait(0.3)
	p.global_position = boss.global_position + Vector3(0, 0, 8)
	await wait(1.2)
	check(boss.active, "boss activates when the player approaches")
	await shot("boss")
	var saw_phase2 := false
	var hits := 0
	var timeout := 0.0
	# Power is what makes you strong now: hand the tester a Power 25 weapon.
	GameState.equipped("weapon")["power"] = 25
	GameState.recompute()
	while not boss.dead and timeout < 120.0:
		p.hp = p.max_hp
		p.global_position = boss.global_position + (p.global_position - boss.global_position).normalized() * 2.5
		p.aim_point = boss.global_position
		p.facing = (boss.global_position - p.global_position).normalized()
		p.attack_cd = 0.0
		p.attack()
		hits += 1
		if boss.phase >= 1:
			if not saw_phase2:
				await shot("boss_phase2")
			saw_phase2 = true
		await wait(0.15)
		timeout += 0.15
	check(saw_phase2, "boss entered phase 2")
	check(boss.dead, "boss defeated through combat (%d swings)" % hits)
	await wait(3.5)
	await shot("boss_dead")
	check(GameState.clearance() >= 1, "boss kill raises Security Clearance")
	var chest = GameState.world.chests[0]
	check(not chest.locked, "reward chest unlocked")
	var inv0 := GameState.inventory().size()
	p.global_position = chest.global_position + Vector3(0, 0, 2.0)
	chest.interact(p)
	await wait(2.0)
	check(GameState.inventory().size() > inv0, "chest + boss loot collected (%d -> %d items)" % [inv0, GameState.inventory().size()])
	check(GameState.world.exits[0].enabled, "exit unlocked after the boss")
	# --- death and respawn
	var gold_before := int(GameState.profile.gold)
	var items_before := GameState.inventory().size()
	var lvl_before := int(GameState.profile.level)
	p.invuln = 0.0
	p.take_damage(999999.0)
	check(p.dead, "player can die")
	check(p.visual.mood == "ko", "knocked-out face on death")
	await wait(1.8)
	check(GameState.ui.death_screen.visible, "death screen shown")
	await shot("death")
	GameState.ui.respawn()
	await wait(1.4)
	check(GameState.world.level_id == "hub", "respawn in hub")
	check(int(GameState.profile.gold) == gold_before and GameState.inventory().size() == items_before and int(GameState.profile.level) == lvl_before, "nothing lost on death")
	check(GameState.player.hp == GameState.player.max_hp, "respawn at full health")
	# --- save / load
	var snapshot := JSON.stringify(GameState.profile)
	check(GameState.save_game(), "save game")
	GameState.profile = {}
	check(GameState.load_game(SLOT), "load game")
	check(int(GameState.profile.gold) == gold_before and GameState.inventory().size() == items_before, "loaded profile matches")
	check(GameState.is_computer_unlocked("floor7_network_closet") and GameState.clearance() >= 1, "terminals & clearance persisted")
	check(not GameState.equipped("weapon").is_empty() and int(GameState.equipped("weapon").enchants.size()) >= 0, "equipment persisted")
	var _unused := snapshot
	# --- save slots show character portraits
	await main.go_to_menu()
	var menu: MainMenu = GameState.ui.menu_layer.get_child(GameState.ui.menu_layer.get_child_count() - 1)
	menu.show_load()
	await wait(0.4)
	var used := 0
	for i in GameState.SLOT_COUNT:
		if not GameState.slot_summary(i).is_empty():
			used += 1
	check(menu.find_children("*", "AvatarPortrait", true, false).size() == used, "save slots show %d character portraits" % used)
	await shot("load_menu")
	GameState.delete_slot(SLOT)
	print("[QA] ===== %d passed, %d failed =====" % [passes, failures.size()])
	for f in failures:
		print("[QA]   failed: ", f)
	get_tree().quit(1 if failures.size() > 0 else 0)


func pad_button(button: int, pressed: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button as JoyButton
	e.pressed = pressed
	Input.parse_input_event(e)


func pad_tap(button: int) -> void:
	pad_button(button, true)
	await frames(2)
	pad_button(button, false)
	await frames(2)


func pad_axis(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis as JoyAxis
	e.axis_value = value
	Input.parse_input_event(e)


func _controller_tests(p: Player) -> void:
	## Drives the game with simulated controller input (Minecraft Dungeons II layout).
	var ui := GameState.ui
	p.attack_cd = 0.0
	pad_button(JOY_BUTTON_X, true)
	await frames(3)
	check(Controls.gamepad, "controller: pressing a pad button switches to controller mode")
	check(p.attack_cd > 0.0, "controller: X attacks")
	pad_button(JOY_BUTTON_X, false)
	await wait(0.4)
	p.global_position = GameState.world.player_start
	pad_axis(JOY_AXIS_LEFT_X, 1.0)
	await wait(0.25)
	check(p.velocity.x > 2.0, "controller: left stick moves (vx=%.1f)" % p.velocity.x)
	pad_axis(JOY_AXIS_LEFT_X, 0.0)
	await wait(0.3)
	p.dodge_cd = 0.0
	pad_axis(JOY_AXIS_RIGHT_X, 0.0)
	pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await frames(2)
	pad_axis(JOY_AXIS_RIGHT_Y, 1.0)
	await frames(3)
	check(p.dodge_t > 0.0 or p.dodge_cd > 0.0, "controller: right-stick flick dodges")
	pad_axis(JOY_AXIS_RIGHT_Y, 0.0)
	await wait(0.9)
	p.dodge_cd = 0.0
	await pad_tap(JOY_BUTTON_LEFT_SHOULDER)
	check(p.dodge_cd > 0.0, "controller: LB dodges")
	await wait(0.5)  # specials are blocked mid-roll
	p.special_cd = 0.0
	await pad_tap(JOY_BUTTON_Y)
	check(p.special_cd > 0.0, "controller: Y uses the special ability")
	await wait(0.6)
	await pad_tap(JOY_BUTTON_A)
	check(p.airborne(), "controller: A jumps")
	await wait(0.7)
	await pad_tap(JOY_BUTTON_DPAD_UP)
	check(ui.app.visible and ui.app.tab == "inventory", "controller: D-pad Up opens the inventory")
	await frames(3)
	var owner := ui.get_viewport().gui_get_focus_owner()
	check(owner != null and ui.app.is_ancestor_of(owner), "controller: menu has a focused control")
	await pad_tap(JOY_BUTTON_DPAD_RIGHT)
	await wait(0.3)
	await shot("controller_focus")
	await pad_tap(JOY_BUTTON_DPAD_UP)
	check(ui.app.visible, "controller: D-pad navigates inside menus instead of closing them")
	await pad_tap(JOY_BUTTON_RIGHT_SHOULDER)
	check(ui.app.tab == "network", "controller: RB switches to the next tab (%s)" % ui.app.tab)
	await pad_tap(JOY_BUTTON_LEFT_SHOULDER)
	check(ui.app.tab == "inventory", "controller: LB switches back")
	await pad_tap(JOY_BUTTON_B)
	check(not ui.app.visible and not get_tree().paused, "controller: B closes the menu and resumes")
	await pad_tap(JOY_BUTTON_START)
	check(ui.pause_menu.visible, "controller: Menu opens the pause menu")
	await frames(3)
	owner = ui.get_viewport().gui_get_focus_owner()
	check(owner != null and ui.pause_menu.is_ancestor_of(owner), "controller: pause menu focuses a button")
	await pad_tap(JOY_BUTTON_B)
	check(not ui.pause_menu.visible, "controller: B resumes from the pause menu")
	await pad_tap(JOY_BUTTON_BACK)
	check(ui.app.visible and ui.app.tab == "network", "controller: View opens the network map")
	await pad_tap(JOY_BUTTON_B)
	check(Controls.pad_text("special") == "Y" and Controls.prompt("interact") == "B" and Controls.pad_text("jump") == "A", "controller: HUD prompts show pad buttons (A jump, B interact)")
	Settings.rebind_pad("special", _pad_event(JOY_BUTTON_B))
	check(Controls.pad_text("special") == "B" and InputMap.action_has_event("special", _pad_event(JOY_BUTTON_B)), "controller: special can be rebound to B")
	Settings.reset_bindings()
	Settings.apply_bindings()
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(20, 0)
	Input.parse_input_event(mm)
	await frames(2)
	check(not Controls.gamepad and Controls.prompt("interact") == "E", "controller: moving the mouse switches back to keyboard prompts")


func _rarity_tests() -> void:
	## Stock / Patched / Overclocked / Root: stat scaling, passive counts, drop tables.
	var r := RandomNumberGenerator.new()
	r.seed = 7
	var dmg := []
	for id in ["longsword", "longsword_patched", "longsword_overclocked", "escape_key"]:
		dmg.append(float(ItemUtil.weapon_stats({"id": id, "power": 1}).damage))
	check(dmg[0] < dmg[1] and dmg[1] < dmg[2] and dmg[2] < dmg[3], "higher rarity, higher stats (%s)" % str(dmg))
	var counts := []
	for id in ["hauberk", "hauberk_patched", "hauberk_overclocked", "glitch_hauberk"]:
		counts.append((Loot.make_instance(id, 1, r).get("passives", []) as Array).size())
	check(counts == [0, 1, 2, 2], "passive count follows rarity (%s)" % str(counts))
	var root := Loot.make_instance("alt_f4", 1, r)
	check(ItemUtil.active_enchants(root).size() >= 1, "Root items carry a unique effect")
	for tid in DB.loot_tables:
		var w: Dictionary = DB.loot_tables[tid].get("rarity_weights", {})
		for st in w:
			var sum := 0.0
			for k in w[st]:
				sum += float(w[st][k])
			check(absf(sum - 100.0) < 0.01, "loot table %s/%s adds up to 100%% (%.1f)" % [tid, st, sum])
	var base := Loot.rarity_weights(DB.loot_tables.basic, {})
	var boosted := Loot.rarity_weights(DB.loot_tables.basic, {"unique_find": 1.0, "rare_find": 5.0})
	check(float(boosted.get("unique", 0)) <= maxf(float(base.get("unique", 0)) * 2.0, 3.0) + 0.001, "loot bonuses are capped (Root %.2f%% -> %.2f%%)" % [float(base.get("unique", 0)), float(boosted.get("unique", 0))])
	var boss := Loot.rarity_weights(DB.loot_tables.boss, {})
	check(float(boss.get("unique", 0)) > float(base.get("unique", 0)) * 5.0, "bosses have far better Root odds")


func _slam_test(p: Player) -> void:
	## Jump, attack mid-air, land: the enemy in front takes boosted damage and the
	## shockwave hurts and knocks back a second one.
	for e in Combat.enemies_in_radius(p.global_position, 10.0):
		e.die(false)
	await wait(0.4)
	var front := GameState.world.spawn_enemy_near("trojan", p.global_position + Vector3(0, 0, -1.2), 0.0, 0, 1.0)
	var side := GameState.world.spawn_enemy_near("trojan", p.global_position + Vector3(2.2, 0, 0.6), 0.0, 0, 1.0)
	for e in [front, side]:
		e.max_hp = 9999.0
		e.hp = 9999.0
		e.armor = 0.0
	await frames(2)
	for e in [front, side]:
		e.stun_t = 10.0  # hold them in place so "nearest" is deterministic
	p.force_next_crit = false
	p.facing = Vector3(0, 0, -1)
	p.aim_point = p.global_position + p.facing * 3.0
	p.jump()
	await wait(0.12)
	check(p.airborne() and p.visual.position.y > 0.2, "jump lifts the employee (%.2f m)" % p.visual.position.y)
	var side_pos: Vector3 = side.global_position
	p._queue_slam()
	await wait_until(func() -> bool: return not p.airborne(), 2.0)
	await wait(0.15)
	var front_dmg := 9999.0 - front.hp
	var side_dmg := 9999.0 - side.hp
	check(front_dmg > 0.0 and side_dmg > 0.0, "Slam Impact damages the target and the shockwave hits around (%.0f / %.0f)" % [front_dmg, side_dmg])
	check(front_dmg > side_dmg, "the slam target takes extra damage")
	check(side.global_position.distance_to(p.global_position) > side_pos.distance_to(p.global_position), "the shockwave knocks mobs back")
	for e in [front, side]:
		if is_instance_valid(e):
			e.die(false)
	await wait(0.4)


func _pad_event(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button as JoyButton
	return e


func ui_click_new_hire() -> void:
	GameState.ui.show_char_create()
