extends Node
## Owns the active save profile (character, inventory, progression, economy),
## performs every mutation on it and broadcasts the changes to the UI and actors.

signal profile_loaded
signal gold_changed(gold: int)
signal corrupted_gold_changed(amount: int)
signal xp_changed(level: int, xp: int, needed: int)
signal leveled_up(level: int)
signal inventory_changed
signal equipment_changed
signal points_changed(points: int)
signal stats_changed
signal notified(sender: String, message: String, kind: String)
signal computer_unlocked(id: String)

const SAVE_DIR := "user://saves/"
const SLOT_COUNT := 3
const INVENTORY_SIZE := 36
const SAVE_VERSION := 3
## Items retired by the Stock / Patched / Overclocked / Root catalogue (save version 3)
## and what they turn into, so old saves keep a matching item instead of losing it.
const LEGACY_IDS := {
	"intern_shortsword": "arming_sword", "compliance_longsword": "longsword", "binary_saber": "katana_overclocked",
	"excalibyte": "escape_key", "budget_cut_axe": "hand_axe", "the_downsizer": "battle_axe_overclocked",
	"paper_cut_dagger": "dagger", "keylogger_kris": "dagger_overclocked", "disciplinary_gavel": "flanged_mace",
	"ctrl_alt_maul": "server_rack_maul", "laser_pointer_pike": "spear", "deadline_pike": "halberd_overclocked",
	"overtime_claymore": "claymore_overclocked", "golden_handshake": "surge_protector",
	"business_casual_mail": "squires_gambeson", "cardigan_of_plate": "hauberk", "clean_room_coverall": "hauberk_overclocked",
	"firewall_cuirass": "cuirass_overclocked", "executive_plate": "motherboard_cuirass",
	"visitor_cap": "squires_coif", "safety_hard_hat": "kettle_hat", "noise_cancelling_helm": "kettle_hat_overclocked",
	"vr_visor": "great_helm_overclocked", "ceo_crown": "heatsink_great_helm",
	"pleated_khakis": "squires_chausses", "cargo_greaves": "mail_chausses", "standing_desk_legplates": "greaves_overclocked",
	"golden_parachute_pants": "coolant_greaves", "sensible_loafers": "squires_boots", "steel_toe_sneakers": "riveted_boots",
	"commuter_sabatons": "sabatons_overclocked", "red_carpet_boots": "thermal_paste_boots",
}
const SLOTS := ["weapon", "helmet", "chest", "legs", "boots", "accessory"]

var profile: Dictionary = {}
var stats: Dictionary = {}
var main: Main = null
var world: GameWorld = null
var player: Player = null
var ui: UIRoot = null
var rng := RandomNumberGenerator.new()
var playing := false
var headless := false
var _autosave_t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	headless = DisplayServer.get_name() == "headless"


func _process(delta: float) -> void:
	if not playing or profile.is_empty() or get_tree().paused:
		return
	profile["play_time"] = float(profile.get("play_time", 0.0)) + delta
	_autosave_t += delta
	if _autosave_t > 90.0:
		_autosave_t = 0.0
		save_game()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and playing:
		save_game()


# ------------------------------------------------------------------ profile

func has_profile() -> bool:
	return not profile.is_empty()


func new_profile(char_name: String, appearance: Dictionary, slot: int) -> void:
	var kit: Dictionary = DB.progression.get("starting_kit", {})
	profile = _default_profile()
	profile["slot"] = slot
	profile["name"] = char_name
	profile["appearance"] = appearance.duplicate(true)
	profile["gold"] = int(kit.get("gold", 50))
	profile["created"] = Time.get_datetime_string_from_system()
	for id in kit.get("items", []):
		var inst := Loot.make_instance(str(id), 1)
		if inst.is_empty():
			continue
		add_item(inst, false)
		var d: Dictionary = DB.items[inst.id]
		if kit.get("equip", true) and int(profile.equipment.get(d.slot, -1)) == -1:
			profile.equipment[d.slot] = int(inst.uid)
	refresh_shop()
	recompute()
	Settings.last_slot = slot
	Settings.save_settings()
	save_game()
	profile_loaded.emit()


func _default_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION, "slot": 0, "name": "Employee", "appearance": {"body": 0, "palette": 0, "hair": 0, "face": 0},
		"level": 1, "xp": 0, "gold": 0, "corrupted_gold": 0, "points": 0,
		"inventory": [], "equipment": {"weapon": -1, "helmet": -1, "chest": -1, "legs": -1, "boots": -1, "accessory": -1},
		"unlocked_computers": [], "clearance": 0, "bosses_defeated": {},
		"kills": 0, "deaths": 0, "play_time": 0.0, "next_uid": 1, "shop_stock": [],
		"current_level": str(DB.manifest.get("hub_level", "hub")), "created": "", "dungeons_cleared": 0,
	}


func next_uid() -> int:
	if profile.is_empty():
		# No profile yet (e.g. a preview): never write into the empty profile, which
		# would make has_profile() report a broken save as loaded.
		return -1
	var u := int(profile.get("next_uid", 1))
	profile["next_uid"] = u + 1
	return u


func recompute() -> void:
	stats = StatCalc.compute(profile)
	stats_changed.emit()


func power() -> int:
	## The player's gear Power: drops roll around it and enemies scale to it.
	return StatCalc.power(profile) if not profile.is_empty() else 1


func notify(sender: String, message: String, kind: String = "info") -> void:
	notified.emit(sender, message, kind)


func title_for_level(level: int) -> String:
	var titles: Array = DB.progression.get("titles", ["Employee"])
	return str(titles[clampi((level - 1) / 3, 0, titles.size() - 1)])


# ------------------------------------------------------------------ DATA / GOLD

func xp_needed(level: int) -> int:
	var c: Dictionary = DB.progression.get("xp_curve", {})
	return int(round(float(c.get("base", 40)) * pow(float(c.get("growth", 1.3)), level - 1)))


func add_xp(amount: float) -> void:
	if profile.is_empty():
		return
	var gained := maxi(1, int(round(amount * (1.0 + float(stats.get("data_gain_pct", 0.0))))))
	profile["xp"] = int(profile.xp) + gained
	var max_level := int(DB.progression.get("max_level", 50))
	var leveled := false
	while int(profile.level) < max_level and int(profile.xp) >= xp_needed(int(profile.level)):
		profile["xp"] = int(profile.xp) - xp_needed(int(profile.level))
		profile["level"] = int(profile.level) + 1
		profile["points"] = int(profile.points) + int(DB.progression.get("points_per_level", 2))
		leveled = true
	if leveled:
		recompute()
		points_changed.emit(int(profile.points))
		leveled_up.emit(int(profile.level))
		notify("HR Automated Assistant", "Congratulations! You have been promoted to DATA Level %d (%s). +%d Upgrade Points." % [int(profile.level), title_for_level(int(profile.level)), int(DB.progression.get("points_per_level", 2))], "levelup")
	xp_changed.emit(int(profile.level), int(profile.xp), xp_needed(int(profile.level)))


func add_gold(amount: int, apply_bonus: bool = true) -> int:
	if profile.is_empty():
		return 0
	var g := amount
	if apply_bonus:
		g = int(round(amount * (1.0 + float(stats.get("gold_gain_pct", 0.0)))))
	profile["gold"] = int(profile.gold) + g
	gold_changed.emit(int(profile.gold))
	return g


func spend_gold(amount: int) -> bool:
	if int(profile.get("gold", 0)) < amount:
		return false
	profile["gold"] = int(profile.gold) - amount
	gold_changed.emit(int(profile.gold))
	return true


func add_corrupted_gold(amount: int) -> void:
	## Corrupted Gold only drops from corrupted enemies; it pays for Upgrades.
	if profile.is_empty() or amount <= 0:
		return
	profile["corrupted_gold"] = int(profile.get("corrupted_gold", 0)) + amount
	corrupted_gold_changed.emit(int(profile.corrupted_gold))


func spend_corrupted_gold(amount: int) -> bool:
	if int(profile.get("corrupted_gold", 0)) < amount:
		return false
	profile["corrupted_gold"] = int(profile.corrupted_gold) - amount
	corrupted_gold_changed.emit(int(profile.corrupted_gold))
	return true


func spend_points(amount: int) -> bool:
	if int(profile.get("points", 0)) < amount:
		return false
	profile["points"] = int(profile.points) - amount
	points_changed.emit(int(profile.points))
	return true


# ------------------------------------------------------------------ inventory

func inventory() -> Array:
	return profile.get("inventory", [])


func find_item(uid: int) -> Dictionary:
	for it in inventory():
		if int(it.uid) == uid:
			return it
	return {}


func equipped(slot: String) -> Dictionary:
	var u := int(profile.get("equipment", {}).get(slot, -1))
	return {} if u < 0 else find_item(u)


func equipped_gear() -> Dictionary:
	## {slot: item instance} for every gear slot ({} where empty).
	var out := {}
	for s in SLOTS:
		out[s] = equipped(s)
	return out


func is_equipped(uid: int) -> bool:
	for s in SLOTS:
		if int(profile.equipment.get(s, -1)) == uid:
			return true
	return false


func unequipped_count() -> int:
	var n := 0
	for it in inventory():
		if not is_equipped(int(it.uid)):
			n += 1
	return n


func inventory_full() -> bool:
	return unequipped_count() >= INVENTORY_SIZE


func add_item(inst: Dictionary, announce: bool = true) -> bool:
	if inst.is_empty() or inventory_full():
		return false
	profile.inventory.append(inst)
	inventory_changed.emit()
	if announce:
		var d: Dictionary = DB.items.get(inst.id, {})
		notify("Asset Management", "New asset assigned: %s (%s)." % [ItemUtil.display_name(inst), ItemUtil.rarity_name(str(d.get("rarity", "common")))], "loot_" + str(d.get("rarity", "common")))
	return true


func remove_item(uid: int) -> void:
	var inv := inventory()
	for i in inv.size():
		if int(inv[i].uid) == uid:
			inv.remove_at(i)
			break
	for s in SLOTS:
		if int(profile.equipment.get(s, -1)) == uid:
			profile.equipment[s] = -1
	inventory_changed.emit()


func can_equip(inst: Dictionary) -> bool:
	# No level gate (Minecraft Dungeons style): any item can be worn; Power is the progression.
	var d: Dictionary = DB.items.get(inst.get("id", ""), {})
	return not d.is_empty() and str(d.get("slot", "")) in SLOTS


func equip(uid: int) -> bool:
	var inst := find_item(uid)
	if inst.is_empty() or not can_equip(inst):
		return false
	var d: Dictionary = DB.items[inst.id]
	profile.equipment[str(d.slot)] = uid
	recompute()
	equipment_changed.emit()
	inventory_changed.emit()
	Audio.play("item", -4.0)
	return true


func sell_item(uid: int) -> int:
	var inst := find_item(uid)
	if inst.is_empty() or is_equipped(uid):
		return 0
	var price := ItemUtil.sell_price(inst)
	var refund := ItemUtil.spent_points(inst) if DB.progression.get("enchanting", {}).get("refund_on_sell", true) else 0
	remove_item(uid)
	add_gold(price, false)
	if refund > 0:
		profile["points"] = int(profile.points) + refund
		points_changed.emit(int(profile.points))
	return price


# ------------------------------------------------------------------ shop

func refresh_shop() -> void:
	var cfg: Dictionary = DB.shop
	var pool: Array = []
	var lvl := int(profile.get("level", 1))
	var slack := int(cfg.get("level_slack", 3))
	var weights: Dictionary = {}
	var rw: Dictionary = cfg.get("rarity_weights", {})
	for id in DB.items:
		if rw.has(str(DB.items[id].get("rarity", ""))):
			weights[str(id)] = float(rw[str(DB.items[id].rarity)])
	for e in cfg.get("pool", []):
		weights[str(e.get("id", ""))] = float(e.get("weight", 1))
	for id in weights:
		var d: Dictionary = DB.items.get(id, {})
		if d.is_empty() or float(weights[id]) <= 0.0 or int(d.get("min_level", 1)) > lvl + slack:
			continue
		pool.append({"id": id, "weight": weights[id]})
	var stock: Array = []
	var picked: Array = []
	for i in int(cfg.get("stock_size", 8)):
		var total := 0.0
		for e in pool:
			if not e.id in picked:
				total += float(e.get("weight", 1))
		if total <= 0.0:
			break
		var r := rng.randf() * total
		for e in pool:
			if e.id in picked:
				continue
			r -= float(e.get("weight", 1))
			if r <= 0.0:
				picked.append(e.id)
				var inst := Loot.make_instance(str(e.id))
				if not inst.is_empty():
					stock.append(inst)
				break
	profile["shop_stock"] = stock
	inventory_changed.emit()


func shop_price(inst: Dictionary) -> int:
	var d: Dictionary = DB.items.get(inst.get("id", ""), {})
	return int(round(float(d.get("price", 50)) * float(DB.shop.get("price_mult", 1.0)) * ItemUtil.power_mult(inst) * ItemUtil.price_rarity_mult(inst)))


func buy_shop_item(uid: int) -> String:
	var stock: Array = profile.get("shop_stock", [])
	for i in stock.size():
		var inst: Dictionary = stock[i]
		if int(inst.uid) != uid:
			continue
		if inventory_full():
			return "Inventory is full."
		var price := shop_price(inst)
		if not spend_gold(price):
			return "Not enough Gold."
		stock.remove_at(i)
		add_item(inst, false)
		Audio.play("buy")
		notify("Procurement", "Purchase approved: %s for %d Gold." % [ItemUtil.display_name(inst), price], "shop")
		return ""
	return "Item no longer in stock."


func paid_refresh_shop() -> bool:
	if not spend_gold(int(DB.shop.get("refresh_cost", 30))):
		return false
	refresh_shop()
	return true


# ------------------------------------------------------------------ blacksmith & enchanting

func upgrade_item(uid: int) -> String:
	var inst := find_item(uid)
	if inst.is_empty():
		return "Item not found."
	if int(inst.get("plus", 0)) >= int(DB.progression.blacksmith.get("max_plus", 5)):
		return "Already at maximum upgrade."
	var cost := ItemUtil.upgrade_cost(inst)
	if not spend_gold(cost):
		return "Not enough Gold."
	inst["plus"] = int(inst.get("plus", 0)) + 1
	recompute()
	inventory_changed.emit()
	equipment_changed.emit()
	Audio.play("forge")
	return ""


func choose_enchant(uid: int, slot_i: int, enchant_id: String) -> String:
	var inst := find_item(uid)
	if inst.is_empty():
		return "Item not found."
	var slots: Array = inst.get("enchants", [])
	if slot_i < 0 or slot_i >= slots.size():
		return "Invalid slot."
	var s: Dictionary = slots[slot_i]
	if str(s.get("chosen", "")) != "":
		return "Slot already enchanted."
	if not enchant_id in s.get("options", []):
		return "Not an option for this slot."
	var cost := ItemUtil.enchant_point_cost(1)
	if not spend_points(cost):
		return "Not enough Upgrade Points."
	s["chosen"] = enchant_id
	s["level"] = 1
	recompute()
	inventory_changed.emit()
	equipment_changed.emit()
	Audio.play("enchant")
	return ""


func upgrade_enchant(uid: int, slot_i: int) -> String:
	var inst := find_item(uid)
	if inst.is_empty():
		return "Item not found."
	var s: Dictionary = inst.enchants[slot_i]
	var lvl := int(s.get("level", 0))
	var max_lvl := int(DB.progression.enchanting.get("max_level", 3))
	if lvl <= 0 or lvl >= max_lvl:
		return "Cannot upgrade further."
	var pts := ItemUtil.enchant_point_cost(lvl + 1)
	var cgold := ItemUtil.enchant_gold_cost(lvl + 1)
	if int(profile.points) < pts:
		return "Not enough Upgrade Points."
	if int(profile.get("corrupted_gold", 0)) < cgold:
		return "Not enough Corrupted Gold."
	spend_points(pts)
	spend_corrupted_gold(cgold)
	s["level"] = lvl + 1
	recompute()
	inventory_changed.emit()
	equipment_changed.emit()
	Audio.play("enchant")
	return ""


# ------------------------------------------------------------------ world progression

func unlock_computer(id: String) -> bool:
	var list: Array = profile.get("unlocked_computers", [])
	if id in list:
		return false
	list.append(id)
	profile["unlocked_computers"] = list
	computer_unlocked.emit(id)
	save_game()
	return true


func is_computer_unlocked(id: String) -> bool:
	return id in profile.get("unlocked_computers", [])


func clearance() -> int:
	return int(profile.get("clearance", 0))


func on_boss_defeated(boss_id: String) -> void:
	var bd: Dictionary = profile.get("bosses_defeated", {})
	bd[boss_id] = int(bd.get(boss_id, 0)) + 1
	profile["bosses_defeated"] = bd
	profile["dungeons_cleared"] = int(profile.get("dungeons_cleared", 0)) + 1
	var max_tier := int(DB.progression.get("clearance", {}).get("max_tier", 10))
	profile["clearance"] = mini(clearance() + 1, max_tier)
	save_game()


func on_player_died() -> void:
	profile["deaths"] = int(profile.get("deaths", 0)) + 1
	save_game()


# ------------------------------------------------------------------ persistence

func slot_path(slot: int) -> String:
	return SAVE_DIR + "slot_%d.json" % slot


func save_game() -> bool:
	if profile.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(slot_path(int(profile.slot)), FileAccess.WRITE)
	if f == null:
		push_error("[Save] Cannot write " + slot_path(int(profile.slot)))
		return false
	f.store_string(JSON.stringify(profile, "\t"))
	f.close()
	return true


func read_slot(slot: int) -> Dictionary:
	var path := slot_path(slot)
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func load_game(slot: int) -> bool:
	var data := read_slot(slot)
	if data.is_empty():
		return false
	profile = _default_profile()
	for k in data:
		profile[k] = data[k]
	profile["slot"] = slot
	_normalize()
	recompute()
	Settings.last_slot = slot
	Settings.save_settings()
	profile_loaded.emit()
	return true


func slot_summary(slot: int) -> Dictionary:
	var d := read_slot(slot)
	if d.is_empty():
		return {}
	return {"name": str(d.get("name", "?")), "level": int(d.get("level", 1)), "gold": int(d.get("gold", 0)), "corrupted_gold": int(d.get("corrupted_gold", 0)),
		"play_time": float(d.get("play_time", 0.0)), "clearance": int(d.get("clearance", 0)), "appearance": d.get("appearance", {})}


func delete_slot(slot: int) -> void:
	var path := slot_path(slot)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if Settings.last_slot == slot:
		Settings.last_slot = -1
		Settings.save_settings()


func _normalize() -> void:
	## JSON turns ints into floats and content may have been removed since saving.
	for k in ["level", "xp", "gold", "corrupted_gold", "points", "next_uid", "clearance", "kills", "deaths", "slot", "dungeons_cleared"]:
		profile[k] = int(profile.get(k, 0))
	# Version 1 saves: the single "armor" slot became the chestplate, and items had no Power.
	var eq_old: Dictionary = profile.get("equipment", {})
	if eq_old.has("armor"):
		if int(eq_old.get("chest", -1)) < 0:
			eq_old["chest"] = eq_old.armor
		eq_old.erase("armor")
	profile.erase("upgrades")
	profile["version"] = SAVE_VERSION
	var clean: Array = []
	for it in profile.get("inventory", []) + profile.get("shop_stock", []):
		if it is Dictionary and LEGACY_IDS.has(str(it.get("id", ""))):
			it["id"] = LEGACY_IDS[str(it.id)]
			if not it.has("passives"):
				it["passives"] = Loot.roll_passives(DB.items.get(str(it.id), {}), rng)
	for it in profile.get("inventory", []):
		if it is Dictionary and DB.items.has(str(it.get("id", ""))):
			it["uid"] = int(it.uid)
			it["power"] = maxi(1, int(it.get("power", 1)))
			it["plus"] = int(it.get("plus", 0))
			if not it.has("passives"):
				it["passives"] = []
			for s in it.get("enchants", []):
				s["level"] = int(s.get("level", 0))
			clean.append(it)
	profile["inventory"] = clean
	var eq: Dictionary = profile.get("equipment", {})
	for s in SLOTS:
		var u := int(eq.get(s, -1))
		eq[s] = u if not find_item(u).is_empty() else -1
	profile["equipment"] = eq
	for it in profile.get("shop_stock", []):
		it["uid"] = int(it.uid)
		it["power"] = maxi(1, int(it.get("power", 1)))
	var stock: Array = []
	for it in profile.get("shop_stock", []):
		if DB.items.has(str(it.get("id", ""))):
			stock.append(it)
	profile["shop_stock"] = stock
	var max_uid := 0
	for it in clean + stock:
		max_uid = maxi(max_uid, int(it.uid))
	profile["next_uid"] = maxi(int(profile.next_uid), max_uid + 1)
	if not DB.levels.has(str(profile.get("current_level", ""))):
		profile["current_level"] = str(DB.manifest.get("hub_level", "hub"))
