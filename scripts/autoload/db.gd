extends Node
## Central content database. Every item, enemy, enchantment, level and price is
## read from the JSON files under res://data so content can be edited without code.

const DATA_ROOT := "res://data/"

var manifest: Dictionary = {}
var items: Dictionary = {}
var enchantments: Dictionary = {}
var enemies: Dictionary = {}
var bosses: Dictionary = {}
var loot_tables: Dictionary = {}
var loot_stages: Dictionary = {}
var shop: Dictionary = {}
var progression: Dictionary = {}
var appearance: Dictionary = {}
var abilities: Dictionary = {}
var passives: Dictionary = {}
var dungeons: Dictionary = {}
var levels: Dictionary = {}
var level_order: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	manifest = read_json("manifest.json")
	progression = read_json("progression.json")
	items.clear()
	var raw: Array = []
	for f in manifest.get("item_files", []):
		for it in read_json(str(f)).get("items", []):
			raw.append([it, str(f)])
	_build_items(raw)
	passives = _index(read_json("passives.json").get("passives", []), "passives.json")
	enchantments = _index(read_json("enchantments.json").get("enchantments", []), "enchantments.json")
	enemies = _index(read_json("enemies.json").get("enemies", []), "enemies.json")
	bosses = _index(read_json("bosses.json").get("bosses", []), "bosses.json")
	dungeons = _index(read_json("dungeons.json").get("dungeons", []), "dungeons.json")
	var lt := read_json("loot_tables.json")
	loot_tables = lt.get("tables", {})
	loot_stages = lt.get("stages", {"early": 0})
	shop = read_json("shop.json")
	appearance = read_json("appearance.json")
	abilities = read_json("abilities.json").get("abilities", {})
	levels.clear()
	level_order.clear()
	for f in manifest.get("level_files", []):
		var lv: Dictionary = read_json(str(f))
		if lv.has("id"):
			levels[str(lv.id)] = lv
			level_order.append(str(lv.id))
	print("[DB] Loaded %d items, %d passives, %d enchantments, %d enemies, %d bosses, %d levels" % [items.size(), passives.size(), enchantments.size(), enemies.size(), bosses.size(), levels.size()])


func read_json(rel_path: String) -> Dictionary:
	var path := DATA_ROOT + rel_path
	if not FileAccess.file_exists(path):
		push_error("[DB] Missing data file: " + path)
		return {}
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("[DB] JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	push_error("[DB] %s must contain a JSON object" % path)
	return {}


func _index(arr: Array, source: String) -> Dictionary:
	var out: Dictionary = {}
	for e in arr:
		_register(out, e, source)
	return out


func _register(target: Dictionary, entry: Variant, source: String) -> void:
	if not entry is Dictionary or not (entry as Dictionary).has("id"):
		push_warning("[DB] Entry without id in " + source)
		return
	var id := str(entry.id)
	if target.has(id):
		push_warning("[DB] Duplicate id '%s' in %s (overriding)" % [id, source])
	target[id] = entry


# ------------------------------------------------------------------ item generation

const INHERITED := ["class", "damage", "attack_speed", "range", "arc", "crit_chance", "crit_mult", "knockback", "stun_chance", "special", "swing", "stats"]
const TAPE := "#d9d2bd"
const PATCHED_GLOW := "#8dffa0"   # tier glow: Patched = soft green
const OVERCLOCK_GLOW := "#ff9a3a" # Overclocked = orange
const ROOT_GLOW := "#3ff1fe"      # Root = cyan; this exact colour flickers (toon.gdshader)
const GLITCH_PINK := "#ff4fd8"


func _build_items(raw: Array) -> void:
	## Expands authored items into the final catalogue: basic items ("tiers": true)
	## become one variant per rarity in progression.tiers, Root items inherit the
	## combat fields of their "base" item, and every item gets min_level and
	## drop_sources defaults so the loot system can treat them alike.
	var tiers: Dictionary = progression.get("tiers", {})
	var bases: Dictionary = {}
	for pair in raw:
		var it: Dictionary = pair[0]
		if it.get("tiers", false):
			bases[str(it.get("id", ""))] = it
	for pair in raw:
		var it: Dictionary = pair[0]
		if it.get("tiers", false):
			var step := 0
			for rarity in tiers:
				if rarity.begins_with("_"):
					continue
				var t: Dictionary = tiers[rarity]
				var v: Dictionary = it.duplicate(true)
				v.erase("tiers")
				v["id"] = str(it.id) + str(t.get("suffix", ""))
				v["name"] = str(t.get("prefix", "")) + str(it.name)
				v["rarity"] = rarity
				v["tier_of"] = str(it.id)
				v["min_level"] = int(it.get("min_level", 1)) + step
				v["visual"] = _tier_visual(it.get("visual", {}), step, str(it.get("slot", "")) == "weapon")
				_finish_item(v)
				_register(items, v, pair[1])
				step += 1
		else:
			var r: Dictionary = (it as Dictionary).duplicate(true)
			if r.has("base") and bases.has(str(r.base)):
				var b: Dictionary = bases[str(r.base)]
				for k in INHERITED:
					if b.has(k) and not r.has(k):
						r[k] = (b[k] as Dictionary).duplicate(true) if b[k] is Dictionary else b[k]
				r["base_name"] = str(b.get("name", ""))
			if str(r.get("rarity", "")) == "unique" and str(r.get("slot", "")) != "accessory":
				r["visual"] = _root_visual(r.get("visual", {}))
			_finish_item(r)
			_register(items, r, pair[1])


func _finish_item(it: Dictionary) -> void:
	if not it.has("min_level"):
		it["min_level"] = int(it.get("level_req", 1))
	it["level_req"] = int(it.min_level)
	if not it.has("drop_sources"):
		it["drop_sources"] = ["enemy", "chest", "boss"]
	if not it.has("effects"):
		it["effects"] = []
	if not it.has("rarity"):
		it["rarity"] = "common"


func _tier_visual(vis: Dictionary, step: int, weapon: bool) -> Dictionary:
	## Tier art on top of the Stock model, on every "role" part. Weapons: Patched (step 1)
	## wraps the part in a strip of tape; Overclocked (step 2) adds the tape plus a
	## glowing inlay along it. Armor: Patched sews a patch on the front; Overclocked
	## adds the patch and a glowing trim line.
	var out: Dictionary = vis.duplicate(true)
	if step <= 0:
		return out
	var parts: Array = out.get("parts", [])
	var extra: Array = []
	for p in parts:
		if not (p as Dictionary).has("role"):
			continue
		var s: Array = p.get("size", [0.1, 0.1, 0.1])
		var pos: Array = p.get("pos", [0, 0, 0])
		var glow := PATCHED_GLOW if step == 1 else OVERCLOCK_GLOW
		var glow_e := 1.0 if step == 1 else 2.2
		if not weapon:
			var front := float(pos[2]) - float(s[2]) * 0.5 - 0.012
			extra.append({"shape": "box", "size": [float(s[0]) * 0.28, float(s[1]) * 0.3, 0.03], "pos": [float(pos[0]) + float(s[0]) * 0.18, float(pos[1]) + float(s[1]) * 0.12, front], "color": TAPE})
			extra.append({"shape": "box", "size": [float(s[0]) * 0.2, 0.012, 0.035], "pos": [float(pos[0]) + float(s[0]) * 0.18, float(pos[1]) + float(s[1]) * 0.12, front - 0.004], "color": "#8a7a5e"})
			extra.append({"shape": "box", "size": [float(s[0]) * 0.9, maxf(0.03, float(s[1]) * 0.06), 0.03], "pos": [float(pos[0]), float(pos[1]) - float(s[1]) * 0.18, front], "color": glow, "emit": glow_e})
			continue
		var long := 0
		var thin := 0
		for i in 3:
			if float(s[i]) > float(s[long]):
				long = i
			if float(s[i]) < float(s[thin]):
				thin = i
		# tape band: wraps the two short axes, narrow along the long one
		var band := [float(s[0]) * 1.08 + 0.012, float(s[1]) * 1.08 + 0.012, float(s[2]) * 1.08 + 0.012]
		band[long] = maxf(0.05, float(s[long]) * 0.16)
		var bpos := [float(pos[0]), float(pos[1]), float(pos[2])]
		bpos[long] += float(s[long]) * 0.18
		extra.append({"shape": "box", "size": band, "pos": bpos, "rot": p.get("rot", [0, 0, 0]), "color": TAPE})
		var inlay := [float(s[0]) * 0.3, float(s[1]) * 0.3, float(s[2]) * 0.3]
		inlay[long] = float(s[long]) * 0.8
		inlay[thin] = float(s[thin]) * 1.25 + 0.006
		extra.append({"shape": "box", "size": inlay, "pos": pos, "rot": p.get("rot", [0, 0, 0]), "color": glow, "emit": glow_e})
	parts.append_array(extra)
	out["parts"] = parts
	return out


func _root_visual(vis: Dictionary) -> Dictionary:
	## Root gear: glowing cyan circuit veins along the biggest part, plus unstable
	## glitch fragments (cyan / pink) hanging off its edges. ROOT_GLOW flickers.
	var out: Dictionary = vis.duplicate(true)
	var parts: Array = out.get("parts", [])
	if parts.is_empty():
		return out
	var big: Dictionary = parts[0]
	var best := 0.0
	for p in parts:
		var s: Array = p.get("size", [0.1, 0.1, 0.1])
		var vol := float(s[0]) * float(s[1]) * float(s[2])
		if vol > best:
			best = vol
			big = p
	var s2: Array = big.get("size", [0.1, 0.1, 0.1])
	var pos: Array = big.get("pos", [0, 0, 0])
	var rot: Array = big.get("rot", [0, 0, 0])
	var long := 0
	var thin := 0
	for i in 3:
		if float(s2[i]) > float(s2[long]):
			long = i
		if float(s2[i]) < float(s2[thin]):
			thin = i
	var mid := 3 - long - thin
	for k in [-1.0, 1.0]:
		var vein := [0.0, 0.0, 0.0]
		vein[long] = float(s2[long]) * 0.7
		vein[thin] = float(s2[thin]) + 0.02
		vein[mid] = maxf(0.012, float(s2[mid]) * 0.07)
		var vp := [float(pos[0]), float(pos[1]), float(pos[2])]
		vp[mid] += k * float(s2[mid]) * 0.22
		vp[long] += k * float(s2[long]) * 0.06
		parts.append({"shape": "box", "size": vein, "pos": vp, "rot": rot, "color": ROOT_GLOW, "emit": 2.4})
	# glitch edges: small displaced blocks at both ends of the part
	for k in [-1.0, 1.0]:
		var gp := [float(pos[0]), float(pos[1]), float(pos[2])]
		gp[long] += k * float(s2[long]) * 0.42
		gp[mid] += k * float(s2[mid]) * 0.55
		var gs := [0.0, 0.0, 0.0]
		gs[long] = maxf(0.04, float(s2[long]) * 0.08)
		gs[mid] = maxf(0.03, float(s2[mid]) * 0.18)
		gs[thin] = float(s2[thin]) + 0.01
		parts.append({"shape": "box", "size": gs, "pos": gp, "rot": rot, "color": ROOT_GLOW if k < 0 else GLITCH_PINK, "emit": 2.0})
	out["parts"] = parts
	return out


func items_of(slot: String = "", rarity: String = "") -> Array[String]:
	var out: Array[String] = []
	for id in items:
		var d: Dictionary = items[id]
		if (slot == "" or str(d.get("slot", "")) == slot) and (rarity == "" or str(d.get("rarity", "")) == rarity):
			out.append(str(id))
	return out


func level_computers() -> Array:
	## [{id, name, level, level_name}] for every golden computer in level order.
	var out: Array = []
	for lid in level_order:
		var lv: Dictionary = levels[lid]
		for c in lv.get("computers", []):
			out.append({"id": str(c.id), "name": str(c.get("name", c.id)), "level": lid, "level_name": str(lv.get("name", lid))})
	return out


func enchant_ids_for_slot(slot: String, rollable_only: bool = true) -> Array[String]:
	var out: Array[String] = []
	for id in enchantments:
		var e: Dictionary = enchantments[id]
		if rollable_only and not e.get("rollable", true):
			continue
		if slot in e.get("slots", []):
			out.append(str(id))
	return out
