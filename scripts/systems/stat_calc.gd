class_name StatCalc
extends RefCounted
## Turns a profile's equipment (and its enchantments) into final combat stats.
## Like Minecraft Dungeons, the character level adds nothing: all power is gear.

const FISTS := {"damage": 4.0, "attack_speed": 2.0, "range": 1.6, "arc": 90.0, "crit_chance": 0.05, "crit_mult": 1.5,
	"knockback": 2.0, "stun_chance": 0.0, "special": "spin", "class": "fists", "swing": "horizontal"}


static func compute(profile: Dictionary) -> Dictionary:
	var prog: Dictionary = DB.progression
	var s: Dictionary = {}
	var base: Dictionary = prog.get("base_stats", {})
	for k in base:
		s[k] = float(base[k])
	var weapon: Dictionary = FISTS.duplicate()
	for slot in GameState.SLOTS:
		var inst := equipped_in(profile, slot)
		if inst.is_empty():
			continue
		var item_stats := ItemUtil.scaled_stats(inst)
		for k in item_stats:
			_add(s, k, float(item_stats[k]))
		var pas := ItemUtil.passive_stats(inst)
		for k in pas:
			_add(s, k, float(pas[k]))
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


static func power(profile: Dictionary) -> int:
	## Gear Power: the average Power of everything equipped (1 with nothing on).
	var total := 0
	var n := 0
	for slot in GameState.SLOTS:
		var inst := equipped_in(profile, slot)
		if not inst.is_empty():
			total += int(inst.get("power", 1))
			n += 1
	return maxi(1, int(floor(float(total) / n))) if n > 0 else 1


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
