class_name ItemUtil
extends RefCounted
## Helpers for item instances: {"uid", "id", "plus", "enchants": [{"options": [...], "chosen": id, "level": n}]}

const ROMAN := ["0", "I", "II", "III", "IV", "V"]


static func def(inst: Dictionary) -> Dictionary:
	return DB.items.get(str(inst.get("id", "")), {})


static func rarity_color(rarity: String) -> Color:
	var r: Dictionary = DB.progression.get("rarities", {}).get(rarity, {})
	return MeshFactory.col(r.get("color", "#cccccc"))


static func rarity_name(rarity: String) -> String:
	var r: Dictionary = DB.progression.get("rarities", {}).get(rarity, {})
	return str(r.get("name", rarity.to_upper()))


static func display_name(inst: Dictionary) -> String:
	var d := def(inst)
	var n := str(d.get("name", "Unknown Item"))
	var plus := int(inst.get("plus", 0))
	return n + (" +%d" % plus if plus > 0 else "")


static func slot_label(d: Dictionary) -> String:
	match str(d.get("slot", "")):
		"weapon": return str(d.get("class", "weapon")).capitalize()
		"armor": return "Armor"
		"accessory": return "Accessory"
	return "Item"


static func bonus_mult(inst: Dictionary) -> float:
	return 1.0 + float(DB.progression.get("blacksmith", {}).get("bonus_per_plus", 0.15)) * int(inst.get("plus", 0))


static func scaled_stats(inst: Dictionary) -> Dictionary:
	var d := def(inst)
	var out: Dictionary = {}
	var mult := bonus_mult(inst)
	var st: Dictionary = d.get("stats", {})
	for k in st:
		var v := float(st[k])
		out[k] = v * mult if v > 0.0 else v
	return out


static func weapon_stats(inst: Dictionary) -> Dictionary:
	var d := def(inst)
	var w := StatCalc.FISTS.duplicate()
	for k in ["attack_speed", "range", "arc", "crit_chance", "crit_mult", "knockback", "stun_chance"]:
		if d.has(k):
			w[k] = float(d[k])
	w["damage"] = float(d.get("damage", 4)) * bonus_mult(inst)
	w["special"] = str(d.get("special", "spin"))
	w["class"] = str(d.get("class", "sword"))
	w["swing"] = str(d.get("swing", "horizontal"))
	w["id"] = str(d.get("id", ""))
	return w


static func enchant_params(enchant_id: String, level: int) -> Dictionary:
	var e: Dictionary = DB.enchantments.get(enchant_id, {})
	var levels: Array = e.get("levels", [])
	if levels.is_empty():
		return {}
	return levels[clampi(level - 1, 0, levels.size() - 1)]


static func enchant_desc(enchant_id: String, level: int) -> String:
	var e: Dictionary = DB.enchantments.get(enchant_id, {})
	var text := str(e.get("description", ""))
	var p := enchant_params(enchant_id, level)
	for k in p:
		var v: Variant = p[k]
		if v is float or v is int:
			text = text.replace("{%s%%}" % k, StatCalc._num(float(v) * 100.0))
			text = text.replace("{%s}" % k, StatCalc._num(float(v)))
		else:
			text = text.replace("{%s}" % k, str(v))
	return text


static func enchant_name(enchant_id: String, level: int = 0) -> String:
	var e: Dictionary = DB.enchantments.get(enchant_id, {})
	var n := str(e.get("name", enchant_id))
	return n + (" " + ROMAN[clampi(level, 0, 5)] if level > 0 else "")


static func active_enchants(inst: Dictionary) -> Array:
	## Built-in effects plus chosen enchantment slots, resolved to their parameters.
	var out: Array = []
	var d := def(inst)
	for fx in d.get("effects", []):
		var id := str(fx.get("enchant", ""))
		if DB.enchantments.has(id):
			out.append(_entry(id, int(fx.get("level", 1)), true))
	for s in inst.get("enchants", []):
		var cid := str(s.get("chosen", ""))
		if cid != "" and int(s.get("level", 0)) > 0 and DB.enchantments.has(cid):
			out.append(_entry(cid, int(s.level), false))
	return out


static func _entry(id: String, level: int, intrinsic: bool) -> Dictionary:
	var e: Dictionary = DB.enchantments[id]
	return {"id": id, "level": level, "effect": str(e.get("effect", "")), "hook": str(e.get("hook", "")),
		"params": enchant_params(id, level), "color": MeshFactory.col(e.get("color", "#ffffff")), "intrinsic": intrinsic}


static func enchant_point_cost(level: int) -> int:
	var costs: Array = DB.progression.get("enchanting", {}).get("point_cost", [1, 2, 3])
	return int(costs[clampi(level - 1, 0, costs.size() - 1)])


static func enchant_gold_cost(level: int) -> int:
	var costs: Array = DB.progression.get("enchanting", {}).get("gold_cost", [0, 40, 100])
	return int(costs[clampi(level - 1, 0, costs.size() - 1)])


static func spent_points(inst: Dictionary) -> int:
	var total := 0
	for s in inst.get("enchants", []):
		for l in int(s.get("level", 0)):
			total += enchant_point_cost(l + 1)
	return total


static func sell_price(inst: Dictionary) -> int:
	var d := def(inst)
	return maxi(1, int(round(float(d.get("price", 20)) * float(DB.progression.get("sell_ratio", 0.35)) * (1.0 + 0.5 * int(inst.get("plus", 0))))))


static func upgrade_cost(inst: Dictionary) -> int:
	var bs: Dictionary = DB.progression.get("blacksmith", {})
	var d := def(inst)
	var rm := float(bs.get("rarity_cost_mult", {}).get(str(d.get("rarity", "common")), 1.0))
	return int(round(float(bs.get("cost_base", 45)) * pow(float(bs.get("cost_growth", 1.65)), int(inst.get("plus", 0))) * rm))


static func main_stat_line(inst: Dictionary) -> String:
	var d := def(inst)
	if str(d.get("slot", "")) == "weapon":
		var w := weapon_stats(inst)
		return "%d DMG" % int(round(float(w.damage)))
	var st := scaled_stats(inst)
	if st.has("defense"):
		return "%d DEF" % int(round(float(st.defense)))
	return ItemUtil.rarity_name(str(d.get("rarity", "common")))


static func describe(inst: Dictionary, compare: Dictionary = {}) -> String:
	## BBCode block for RichTextLabel item tooltips / detail panes.
	var d := def(inst)
	if d.is_empty():
		return "Unknown item"
	var rc := rarity_color(str(d.get("rarity", "common"))).to_html(false)
	var lines: Array[String] = []
	lines.append("[font_size=22][b][color=#%s]%s[/color][/b][/font_size]" % [rc, display_name(inst)])
	var req := int(d.get("level_req", 1))
	var req_col := "#c8343c" if GameState.has_profile() and req > int(GameState.profile.level) else "#6e6b66"
	lines.append("[color=#%s]%s[/color] [color=#6e6b66]· %s ·[/color] [color=%s]Requires DATA Lv %d[/color]" % [rc, rarity_name(str(d.get("rarity", "common"))), slot_label(d), req_col, req])
	lines.append("")
	if str(d.get("slot", "")) == "weapon":
		var w := weapon_stats(inst)
		var cw: Dictionary = weapon_stats(compare) if not compare.is_empty() else {}
		lines.append("[b]%s damage[/b]%s" % [StatCalc._num(float(w.damage)), _delta(float(w.damage), float(cw.get("damage", w.damage)))])
		lines.append("%.1f attacks/s%s · %.1fm reach · %d° arc" % [float(w.attack_speed), _delta(float(w.attack_speed), float(cw.get("attack_speed", w.attack_speed))), float(w.range), int(w.arc)])
		lines.append("%d%% crit chance · x%.2f crit damage" % [int(round(float(w.crit_chance) * 100)), float(w.crit_mult)])
		if float(w.stun_chance) > 0:
			lines.append("%d%% chance to stun" % int(round(float(w.stun_chance) * 100)))
		var ab: Dictionary = DB.abilities.get(str(w.special), {})
		if not ab.is_empty():
			lines.append("[color=#6656c9]Q · %s[/color] [color=#6e6b66]- %s[/color]" % [str(ab.get("name", "")), str(ab.get("description", ""))])
	var st := scaled_stats(inst)
	var cst: Dictionary = scaled_stats(compare) if not compare.is_empty() else {}
	for k in st:
		lines.append("%s%s" % [StatCalc.format_stat(k, float(st[k])), _delta(float(st[k]), float(cst.get(k, st[k])), true)])
	var ench := active_enchants(inst)
	var has_slots: bool = not inst.get("enchants", []).is_empty()
	if not ench.is_empty() or has_slots:
		lines.append("")
		lines.append("[b]Effects[/b]")
		for e in ench:
			var tag := " [color=#6e6b66](built-in)[/color]" if e.intrinsic else ""
			lines.append("[color=#%s]■ %s[/color]%s - %s" % [(e.color as Color).to_html(false), enchant_name(e.id, int(e.level)), tag, enchant_desc(e.id, int(e.level))])
		var empty := 0
		for s in inst.get("enchants", []):
			if str(s.get("chosen", "")) == "":
				empty += 1
		if empty > 0:
			lines.append("[color=#6e6b66]%d empty enchantment slot%s (Software Licensing)[/color]" % [empty, "s" if empty > 1 else ""])
	lines.append("")
	lines.append("[i][color=#6e6b66]%s[/color][/i]" % str(d.get("description", "")))
	return "\n".join(lines)


static func _delta(v: float, other: float, _is_stat: bool = false) -> String:
	var dv := v - other
	if absf(dv) < 0.01:
		return ""
	var c := "#3aa55d" if dv > 0 else "#c8343c"
	return " [color=%s](%s%s)[/color]" % [c, "+" if dv > 0 else "", StatCalc._num(dv) if absf(dv) >= 1.0 else "%.2f" % dv]
