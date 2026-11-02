class_name StatCalc
extends RefCounted
## Turns a profile (level, upgrades, equipment, enchantments) into final combat stats.

const FISTS := {"damage": 4.0, "attack_speed": 2.0, "range": 1.6, "arc": 90.0, "crit_chance": 0.05, "crit_mult": 1.5,
	"knockback": 2.0, "stun_chance": 0.0, "special": "spin", "class": "fists", "swing": "horizontal"}


static func compute(profile: Dictionary) -> Dictionary:
	var prog: Dictionary = DB.progression
	var s: Dictionary = {}
	var base: Dictionary = prog.get("base_stats", {})
	for k in base:
		s[k] = float(base[k])
	var lvl := int(profile.get("level", 1))
	var per: Dictionary = prog.get("per_level", {})
	for k in per:
		_add(s, k, float(per[k]) * (lvl - 1))
	var ups: Dictionary = profile.get("upgrades", {})
	for up in prog.get("stat_upgrades", []):
		var rank := int(ups.get(str(up.get("id", "")), 0))
		if rank <= 0:
			continue
		var per_rank: Dictionary = up.get("stats", {})
		for k in per_rank:
			_add(s, k, float(per_rank[k]) * rank)
	var weapon: Dictionary = FISTS.duplicate()
	for slot in ["weapon", "armor", "accessory"]:
		var inst := equipped_in(profile, slot)
		if inst.is_empty():
			continue
		var item_stats := ItemUtil.scaled_stats(inst)
		for k in item_stats:
			_add(s, k, float(item_stats[k]))
		if slot == "weapon":
			weapon = ItemUtil.weapon_stats(inst)
		for e in ItemUtil.active_enchants(inst):
			if str(e.effect) == "stat_bonus":
				_add(s, str(e.params.get("stat", "")), float(e.params.get("value", 0.0)))
	s["weapon"] = weapon
	s["crit_chance"] = clampf(float(s.get("crit_chance", 0.0)), 0.0, 0.95)
	s["block_chance"] = clampf(float(s.get("block_chance", 0.0)), 0.0, 0.6)
	s["cooldown_pct"] = clampf(float(s.get("cooldown_pct", 0.0)), 0.0, 0.6)
	s["move_speed_final"] = float(s.get("move_speed", 6.5)) * maxf(0.4, 1.0 + float(s.get("move_speed_pct", 0.0)))
	return s


static func equipped_in(profile: Dictionary, slot: String) -> Dictionary:
	var uid := int(profile.get("equipment", {}).get(slot, -1))
	if uid < 0:
		return {}
	for it in profile.get("inventory", []):
		if int(it.uid) == uid:
			return it
	return {}


static func _add(s: Dictionary, k: String, v: float) -> void:
	if k == "":
		return
	s[k] = float(s.get(k, 0.0)) + v


static func upgrade_def(id: String) -> Dictionary:
	for up in DB.progression.get("stat_upgrades", []):
		if str(up.get("id", "")) == id:
			return up
	return {}


static func upgrade_gold_cost(up: Dictionary, rank: int) -> int:
	return int(round(float(up.get("gold_base", 50)) * pow(float(up.get("gold_growth", 1.4)), rank)))


static func upgrade_level_req(up: Dictionary, rank: int) -> int:
	return 1 + rank * int(up.get("level_step", 1))


static func format_stat(key: String, value: float) -> String:
	var names: Dictionary = DB.progression.get("stat_names", {})
	var info: Dictionary = names.get(key, {"name": key.capitalize(), "pct": false})
	var sign_str := "+" if value >= 0 else ""
	if info.get("pct", false):
		return "%s%s%% %s" % [sign_str, _num(value * 100.0), info.name]
	return "%s%s %s" % [sign_str, _num(value), info.name]


static func _num(v: float) -> String:
	if absf(v - round(v)) < 0.05:
		return str(int(round(v)))
	return "%.1f" % v
