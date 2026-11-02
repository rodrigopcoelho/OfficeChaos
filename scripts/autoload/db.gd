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
var shop: Dictionary = {}
var progression: Dictionary = {}
var appearance: Dictionary = {}
var abilities: Dictionary = {}
var dungeons: Dictionary = {}
var levels: Dictionary = {}
var level_order: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	manifest = read_json("manifest.json")
	items.clear()
	for f in manifest.get("item_files", []):
		for it in read_json(str(f)).get("items", []):
			_register(items, it, str(f))
	enchantments = _index(read_json("enchantments.json").get("enchantments", []), "enchantments.json")
	enemies = _index(read_json("enemies.json").get("enemies", []), "enemies.json")
	bosses = _index(read_json("bosses.json").get("bosses", []), "bosses.json")
	dungeons = _index(read_json("dungeons.json").get("dungeons", []), "dungeons.json")
	loot_tables = read_json("loot_tables.json").get("tables", {})
	shop = read_json("shop.json")
	progression = read_json("progression.json")
	appearance = read_json("appearance.json")
	abilities = read_json("abilities.json").get("abilities", {})
	levels.clear()
	level_order.clear()
	for f in manifest.get("level_files", []):
		var lv: Dictionary = read_json(str(f))
		if lv.has("id"):
			levels[str(lv.id)] = lv
			level_order.append(str(lv.id))
	print("[DB] Loaded %d items, %d enchantments, %d enemies, %d bosses, %d levels" % [items.size(), enchantments.size(), enemies.size(), bosses.size(), levels.size()])


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
