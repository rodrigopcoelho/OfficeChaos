class_name Loot
extends RefCounted
## Creates item instances (with rolled enchantment options) and resolves loot tables.


static func make_instance(id: String) -> Dictionary:
	var d: Dictionary = DB.items.get(id, {})
	if d.is_empty():
		push_warning("[Loot] Unknown item id " + id)
		return {}
	var inst := {"uid": GameState.next_uid(), "id": id, "plus": 0, "enchants": []}
	var ench_cfg: Dictionary = DB.progression.get("enchanting", {})
	var slots := int(d.get("enchant_slots", ench_cfg.get("slots_by_rarity", {}).get(str(d.get("rarity", "common")), 1)))
	var per_slot := int(ench_cfg.get("options_per_slot", 3))
	var pool := DB.enchant_ids_for_slot(str(d.get("slot", "weapon")))
	for fx in d.get("effects", []):
		pool.erase(str(fx.get("enchant", "")))
	pool.shuffle()
	var used: Array[String] = []
	for i in slots:
		var options: Array = []
		for e in pool:
			if options.size() >= per_slot:
				break
			if not e in used:
				options.append(e)
				used.append(e)
		if options.size() < per_slot:
			for e in pool:
				if options.size() >= per_slot:
					break
				if not e in options:
					options.append(e)
		if not options.is_empty():
			inst.enchants.append({"options": options, "chosen": "", "level": 0})
	return inst


static func roll_table(table_id: String, player_level: int, luck: float = 0.0, rng: RandomNumberGenerator = null) -> Array:
	var r := rng if rng != null else GameState.rng
	var t: Dictionary = DB.loot_tables.get(table_id, {})
	var out: Array = []
	if t.is_empty():
		return out
	var guaranteed: Array = t.get("guaranteed", [])
	for gid in guaranteed:
		var once := bool(t.get("guaranteed_once", false))
		if once and _already_granted(str(gid)):
			continue
		var gi := make_instance(str(gid))
		if not gi.is_empty():
			out.append(gi)
			if once and GameState.has_profile():
				var granted: Array = GameState.profile.get("granted", [])
				granted.append(str(gid))
				GameState.profile["granted"] = granted
	for i in int(t.get("rolls", 1)):
		if r.randf() > float(t.get("drop_chance", 0.1)) + luck:
			continue
		var rarity := _pick_weighted(t.get("rarity_weights", {"common": 1}), r)
		var id := pick_item(rarity, player_level + int(t.get("level_slack", 2)), r)
		if id != "":
			out.append(make_instance(id))
	return out


static func _already_granted(id: String) -> bool:
	if not GameState.has_profile():
		return false
	return id in GameState.profile.get("granted", [])


static func pick_item(rarity: String, max_level: int, r: RandomNumberGenerator) -> String:
	var candidates: Array[String] = []
	for id in DB.items:
		var d: Dictionary = DB.items[id]
		if str(d.get("rarity", "")) != rarity or not d.get("droppable", true):
			continue
		if d.has("droppable_from"):
			continue
		if int(d.get("level_req", 1)) > max_level:
			continue
		candidates.append(str(id))
	if candidates.is_empty():
		return ""
	return candidates[r.randi() % candidates.size()]


static func _pick_weighted(weights: Dictionary, r: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var x := r.randf() * total
	for k in weights:
		x -= float(weights[k])
		if x <= 0.0:
			return str(k)
	return str(weights.keys()[0])
