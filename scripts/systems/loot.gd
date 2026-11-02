class_name Loot
extends RefCounted
## Centralized loot generation: rarity selection (per-source tables, game stage and
## the player's loot bonuses), item selection (rarity, drop source, min level),
## Power rolls, passive assignment and upgrade-slot rolls all happen here.


static func roll_power(r: RandomNumberGenerator = null) -> int:
	## Power for a new drop: around the player's gear Power (Minecraft Dungeons style).
	var rr := r if r != null else GameState.rng
	var spread: Array = DB.progression.get("power", {}).get("drop_spread", [-1, 2])
	return maxi(1, GameState.power() + rr.randi_range(int(spread[0]), int(spread[-1])))


static func make_instance(id: String, power: int = -1, r: RandomNumberGenerator = null) -> Dictionary:
	## `power` < 0 rolls a Power around the player's current gear Power.
	var rr := r if r != null else GameState.rng
	var d: Dictionary = DB.items.get(id, {})
	if d.is_empty():
		push_warning("[Loot] Unknown item id " + id)
		return {}
	var inst := {"uid": GameState.next_uid(), "id": id, "power": power if power > 0 else roll_power(rr), "plus": 0,
		"passives": roll_passives(d, rr), "enchants": []}
	var ench_cfg: Dictionary = DB.progression.get("enchanting", {})
	var slots := int(d.get("enchant_slots", ench_cfg.get("slots_by_rarity", {}).get(str(d.get("rarity", "common")), 1)))
	var per_slot := int(ench_cfg.get("options_per_slot", 3))
	var pool := DB.enchant_ids_for_slot(ItemUtil.enchant_group(str(d.get("slot", "weapon"))))
	for fx in d.get("effects", []):
		pool.erase(str(fx.get("enchant", "")))
	_shuffle(pool, rr)
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


static func roll_passives(d: Dictionary, r: RandomNumberGenerator) -> Array:
	## Passive count comes from the rarity; the passives themselves from passives.json,
	## filtered by gear slot and rarity-exclusive passives. No duplicates per item.
	var rarity := str(d.get("rarity", "common"))
	var count := int(ItemUtil.rarity_info(rarity).get("passives", 0))
	if count <= 0:
		return []
	var slot := str(d.get("slot", "weapon"))
	var pool: Array = []
	for pid in DB.passives:
		var p: Dictionary = DB.passives[pid]
		var slots: Array = p.get("slots", [])
		if not (slot in slots or ItemUtil.enchant_group(slot) in slots):
			continue
		if p.has("rarities") and not rarity in p.rarities:
			continue
		if not (p.get("values", {}) as Dictionary).has(rarity):
			continue
		pool.append(str(pid))
	_shuffle(pool, r)
	return pool.slice(0, mini(count, pool.size()))


static func stage() -> String:
	## Game stage for drop tables, from the player's gear Power.
	var st: Dictionary = DB.loot_stages
	var p := GameState.power()
	var best := "early"
	var best_at := -1
	for k in st:
		if p >= int(st[k]) and int(st[k]) > best_at:
			best = str(k)
			best_at = int(st[k])
	return best


static func rarity_weights(t: Dictionary, stats: Dictionary = {}) -> Dictionary:
	## The table's percentages for the current stage, adjusted by the player's loot
	## bonuses: rare_find scales Patched-or-better, unique_find adds to Root. Caps
	## (progression.loot_modifiers) keep Root gear rare.
	var w: Dictionary = t.get("rarity_weights", {"common": 100})
	if w.has("early") or w.has("mid") or w.has("late"):
		w = w.get(stage(), w.values()[0])
	w = w.duplicate()
	var caps: Dictionary = DB.progression.get("loot_modifiers", {})
	var rare_find := clampf(float(stats.get("rare_find", 0.0)), 0.0, float(caps.get("max_rare_find", 0.5)))
	var uniq := maxf(0.0, float(stats.get("unique_find", 0.0)))
	var total := 0.0
	for k in w:
		total += float(w[k])
	if total <= 0.0:
		return w
	if rare_find > 0.0:
		for k in w:
			if k != "common":
				w[k] = float(w[k]) * (1.0 + rare_find)
	if uniq > 0.0 and w.has("unique"):
		var base_u := float(w.unique)
		var add := minf(uniq, float(caps.get("max_unique_add", 0.03))) * total
		w["unique"] = minf(base_u + add, maxf(base_u * float(caps.get("max_unique_mult", 2.0)), add))
	# renormalise to percentages; common absorbs the difference
	var sum := 0.0
	for k in w:
		if k != "common":
			sum += float(w[k])
	if w.has("common"):
		w["common"] = maxf(0.0, total - sum)
	return w


static func roll_table(table_id: String, player_level: int, luck: float = 0.0, rng: RandomNumberGenerator = null, stats: Dictionary = {}) -> Array:
	var r := rng if rng != null else GameState.rng
	var t: Dictionary = DB.loot_tables.get(table_id, {})
	var out: Array = []
	if t.is_empty():
		return out
	var st := stats if not stats.is_empty() else GameState.stats
	var guaranteed: Array = t.get("guaranteed", [])
	for gid in guaranteed:
		var once := bool(t.get("guaranteed_once", false))
		if once and _already_granted(str(gid)):
			continue
		var gi := make_instance(str(gid), -1, r)
		if not gi.is_empty():
			out.append(gi)
			if once and GameState.has_profile():
				var granted: Array = GameState.profile.get("granted", [])
				granted.append(str(gid))
				GameState.profile["granted"] = granted
	var caps: Dictionary = DB.progression.get("loot_modifiers", {})
	var drop_rate := clampf(float(st.get("drop_rate", 0.0)), 0.0, float(caps.get("max_drop_rate", 0.6)))
	var chance := minf(1.0, float(t.get("drop_chance", 0.1)) * (1.0 + drop_rate) + luck)
	var weights := rarity_weights(t, st)
	var source := str(t.get("source", "enemy"))
	for i in int(t.get("rolls", 1)):
		if r.randf() > chance:
			continue
		var rarity := _pick_weighted(weights, r)
		var id := pick_item(rarity, player_level + int(t.get("level_slack", 2)), r, source)
		if id == "" and rarity != "common":
			id = pick_item("common", player_level + int(t.get("level_slack", 2)), r, source)
		if id != "":
			out.append(make_instance(id, -1, r))
	return out


static func _already_granted(id: String) -> bool:
	if not GameState.has_profile():
		return false
	return id in GameState.profile.get("granted", [])


static func pick_item(rarity: String, max_level: int, r: RandomNumberGenerator, source: String = "") -> String:
	var candidates: Array[String] = []
	for id in DB.items:
		var d: Dictionary = DB.items[id]
		if str(d.get("rarity", "")) != rarity or not d.get("droppable", true):
			continue
		if source != "" and not source in d.get("drop_sources", ["enemy", "chest", "boss"]):
			continue
		if int(d.get("min_level", 1)) > max_level:
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
		if x <= 0.0 and float(weights[k]) > 0.0:
			return str(k)
	return str(weights.keys()[0])


static func _shuffle(a: Array, r: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
