class_name AppWindow
extends Control
## The full-screen "CubeLink" app: every management screen (profile, inventory &
## equipment, shop, blacksmith, upgrades, network map, settings) lives in a channel
## of this window.

const TABS := {
	"profile": {"icon": "profile", "title": "profile", "label": "Profile", "sub": "Your employee record"},
	"inventory": {"icon": "items", "title": "inventory", "label": "Inventory", "sub": "Assigned assets & equipment"},
	"network": {"icon": "map", "title": "network-map", "label": "Network", "sub": "Golden terminal transfer network"},
	"shop": {"icon": "shop", "title": "procurement", "label": "Shop", "sub": "Purchase equipment with Gold", "hub": true},
	"forge": {"icon": "forge", "title": "it-hardware-forge", "label": "Forge", "sub": "Upgrade equipment (Blacksmith)", "hub": true},
	"enchant": {"icon": "enchant", "title": "upgrades", "label": "Upgrades", "sub": "Install and level up item upgrades", "hub": true},
	"settings": {"icon": "settings", "title": "settings", "label": "Settings", "sub": "Preferences & controls"},
}
const TAB_ORDER := ["profile", "inventory", "network", "shop", "forge", "enchant", "settings"]

var tab := "inventory"
var ctx: Dictionary = {}
var window: PanelContainer
var rail_box: VBoxContainer
var title_label: Label
var sub_label: Label
var body: MarginContainer
var selected_uid := -1
var shop_mode := "buy"
var message := ""
var message_ok := true
var _dirty := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	window = PanelContainer.new()
	var win_sb := UIKit.sb(UIKit.C_BG, 6, 1, Color(0, 0, 0, 0.3), 0)
	win_sb.shadow_color = Color(0, 0, 0, 0.35)
	win_sb.shadow_size = 18
	window.add_theme_stylebox_override("panel", win_sb)
	UIKit.place(window, 0.5, 0.5, 0.5, 0.5, -660, -390, 660, 390)
	add_child(window)
	var h := UIKit.hbox(0)
	window.add_child(h)
	var rail := PanelContainer.new()
	rail.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_RAIL, 6, 0, Color.TRANSPARENT, 0))
	rail.custom_minimum_size.x = 76
	h.add_child(rail)
	rail_box = UIKit.vbox(2)
	rail.add_child(rail_box)
	var main := UIKit.vbox(0)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(main)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UIKit.sb(Color.WHITE, 0, 0, Color.TRANSPARENT, 16))
	main.add_child(header)
	var hh := UIKit.hbox(10)
	header.add_child(hh)
	title_label = UIKit.label("# inventory", 20, UIKit.C_TEXT, true)
	hh.add_child(title_label)
	sub_label = UIKit.label("", 13, UIKit.C_MUTED)
	sub_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hh.add_child(sub_label)
	hh.add_child(UIKit.spacer())
	for t in ["Posts", "Files", "Wiki"]:
		# Teams channel tabs: the active one is bold with a brand-coloured underline.
		var tv := UIKit.vbox(4)
		tv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tl := UIKit.label(t, 13, UIKit.C_TEXT if t == "Posts" else UIKit.C_MUTED, t == "Posts")
		tv.add_child(tl)
		var ul := ColorRect.new()
		ul.custom_minimum_size = Vector2(0, 3)
		ul.color = UIKit.C_ACCENT if t == "Posts" else Color.TRANSPARENT
		ul.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tv.add_child(ul)
		hh.add_child(tv)
	var close := UIKit.button("Close  (Esc / B)", close_window, "ghost")
	hh.add_child(close)
	var line := ColorRect.new()
	line.color = UIKit.C_BORDER
	line.custom_minimum_size.y = 1
	main.add_child(line)
	body = MarginContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 18)
	main.add_child(body)
	visible = false
	for sig in [GameState.inventory_changed, GameState.equipment_changed, GameState.gold_changed, GameState.corrupted_gold_changed, GameState.points_changed, GameState.stats_changed, GameState.computer_unlocked]:
		sig.connect(func(_a = null) -> void: _mark_dirty())


func _mark_dirty() -> void:
	if visible and not _dirty:
		_dirty = true
		_rebuild.call_deferred()


func open(t: String, context: Dictionary = {}) -> void:
	if not TABS.has(t):
		t = "inventory"
	if t != tab:
		selected_uid = -1
		message = ""
	tab = t
	ctx = context
	visible = true
	modulate.a = 0.0
	window.scale = Vector2(0.97, 0.97)
	window.pivot_offset = window.size * 0.5
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.15)
	tw.tween_property(window, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_rebuild()


func close_window() -> void:
	visible = false
	ctx = {}
	if GameState.ui:
		GameState.ui.refresh_pause()


func _in_hub() -> bool:
	var w = GameState.world
	return w != null and is_instance_valid(w) and str(w.level.get("type", "")) == "hub"


func _rebuild() -> void:
	_dirty = false
	if not visible:
		return
	# Remember what the controller cursor was on so a rebuild (e.g. after Equip) keeps it.
	var owner := get_viewport().gui_get_focus_owner()
	var focus_key := str(owner.get_meta("focus_key", "")) if owner != null and is_ancestor_of(owner) else ""
	UIKit.clear(rail_box)
	var pad := Control.new()
	pad.custom_minimum_size.y = 12
	rail_box.add_child(pad)
	for t in TAB_ORDER:
		rail_box.add_child(_rail_button(t))
	var info: Dictionary = TABS[tab]
	title_label.text = "# " + str(info.title)
	sub_label.text = str(info.sub)
	UIKit.clear(body)
	if info.get("hub", false) and not _in_hub():
		body.add_child(_locked_notice())
		return
	match tab:
		"profile": _tab_profile()
		"inventory": _tab_inventory()
		"shop": _tab_shop()
		"forge": _tab_forge()
		"enchant": _tab_enchant()
		"network": _tab_network()
		"settings": body.add_child(SettingsPanel.new())
	if Controls.gamepad:
		(func() -> void:
			if not UIKit.restore_focus(self, focus_key):
				focus_default()).call_deferred()


func focus_default() -> void:
	## Controller entry point: the first item/button of the channel, else its rail tab.
	if not visible:
		return
	if not UIKit.focus_first(body):
		UIKit.restore_focus(rail_box, "tab:" + tab)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var step := 0
	if event.is_action_pressed("ui_tab_prev"):
		step = -1
	elif event.is_action_pressed("ui_tab_next"):
		step = 1
	if step != 0:
		get_viewport().set_input_as_handled()
		var i := TAB_ORDER.find(tab)
		Audio.play("ui_click", -6.0, 0.05, 0.0)
		open(TAB_ORDER[posmod(i + step, TAB_ORDER.size())], {})
		if Controls.gamepad:
			focus_default.call_deferred()


func _rail_button(t: String) -> Button:
	var info: Dictionary = TABS[t]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("focus_key", "tab:" + t)
	b.custom_minimum_size = Vector2(76, 58)
	var active := t == tab
	b.add_theme_stylebox_override("normal", UIKit.sb(UIKit.C_RAIL_HI if active else Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("hover", UIKit.sb(UIKit.C_RAIL_HI, 0, 0))
	b.add_theme_stylebox_override("pressed", UIKit.sb(UIKit.C_ACCENT, 0, 0))
	if active:
		var mark := Panel.new()
		mark.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_ACCENT_HI, 2, 0))
		UIKit.place(mark, 0, 0.2, 0, 0.8, 0, 0, 4, 0)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(mark)
	var ic := RailIcon.new(str(info.icon), Color.WHITE if active else Color("#bdb6d4"))
	UIKit.place(ic, 0.5, 0, 0.5, 0, -11, 9, 11, 31)
	b.add_child(ic)
	var l := UIKit.label(str(info.get("label", t.capitalize())), 10, Color.WHITE if active else Color("#bdb6d4"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.place(l, 0, 0, 1, 0, 0, 35, 0, 52)
	b.add_child(l)
	if info.get("hub", false) and not _in_hub():
		b.modulate.a = 0.45
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", -6.0, 0.05, 0.0)
		open(t, {}))
	return b


func _locked_notice() -> Control:
	var c := CenterContainer.new()
	var p := UIKit.panel(Color.WHITE, 12, 28)
	c.add_child(p)
	var v := UIKit.vbox(10)
	p.add_child(v)
	v.add_child(UIKit.label("This channel is on-site only", 20, UIKit.C_TEXT, true))
	var l := UIKit.label("Services like Procurement, the IT Hardware Forge and Upgrades are only staffed\nin The Lobby (Floor 0). Return through an elevator, a golden terminal, or the pause menu.", 14, UIKit.C_MUTED)
	v.add_child(l)
	return c


func _set_message(text: String, ok: bool) -> void:
	message = text
	message_ok = ok
	if not ok:
		Audio.play("deny", -4.0)


func _message_label() -> Label:
	var l := UIKit.label(message, 13, UIKit.C_OK if message_ok else UIKit.C_DANGER, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


# ------------------------------------------------------------------ shared layout

func _split() -> Array:
	## Returns [left VBox, right detail VBox].
	var h := UIKit.hbox(18)
	body.add_child(h)
	var left := UIKit.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(left)
	var right_panel := UIKit.panel(Color.WHITE, 10, 16)
	right_panel.custom_minimum_size.x = 420
	h.add_child(right_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right_panel.add_child(scroll)
	var right := UIKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(right)
	return [left, right]


func _grid(parent: Control, columns: int) -> GridContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	parent.add_child(scroll)
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	scroll.add_child(g)
	return g


func _select(uid: int) -> void:
	selected_uid = uid
	message = ""
	_rebuild()


func _sorted_items(include_equipped: bool) -> Array:
	var out: Array = []
	for it in GameState.inventory():
		if include_equipped or not GameState.is_equipped(int(it.uid)):
			out.append(it)
	var slot_order := {}
	for i in GameState.SLOTS.size():
		slot_order[GameState.SLOTS[i]] = i
	out.sort_custom(func(a, b) -> bool:
		var ea := 0 if GameState.is_equipped(int(a.uid)) else 1
		var eb := 0 if GameState.is_equipped(int(b.uid)) else 1
		if ea != eb:
			return ea < eb
		var da := ItemUtil.def(a)
		var db := ItemUtil.def(b)
		var sa: int = slot_order.get(str(da.get("slot", "")), 3)
		var sb2: int = slot_order.get(str(db.get("slot", "")), 3)
		if sa != sb2:
			return sa < sb2
		return ItemUtil.rarity_order(str(da.get("rarity", ""))) < ItemUtil.rarity_order(str(db.get("rarity", ""))))
	return out


func _detail(right: VBoxContainer, inst: Dictionary, show_compare: bool = true) -> void:
	var d := ItemUtil.def(inst)
	var top := UIKit.hbox(12)
	right.add_child(top)
	top.add_child(UIKit.item_card(inst, false, Callable(), 96))
	var compare: Dictionary = {}
	if show_compare:
		var eq := GameState.equipped(str(d.get("slot", "")))
		if not eq.is_empty() and int(eq.uid) != int(inst.get("uid", -1)):
			compare = eq
	right.add_child(UIKit.rich(ItemUtil.describe(inst, compare)))
	if not compare.is_empty():
		right.add_child(UIKit.label("Compared with equipped: " + ItemUtil.display_name(compare), 11, UIKit.C_MUTED))


# ------------------------------------------------------------------ profile

func _tab_profile() -> void:
	var pr := GameState.profile
	var s := GameState.stats
	var h := UIKit.hbox(24)
	body.add_child(h)
	var left := UIKit.vbox(8)
	h.add_child(left)
	var prev := CharacterPreview.new(Vector2(320, 430))
	left.add_child(prev)
	prev.set_appearance(pr.appearance)
	prev.set_gear(GameState.equipped_gear())
	var right := UIKit.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	var nh := UIKit.hbox(12)
	right.add_child(nh)
	nh.add_child(UIKit.label(str(pr.name), 28, UIKit.C_TEXT, true))
	nh.add_child(UIKit.pill("Power %d" % GameState.power(), Color("#e2aa2c")))
	nh.add_child(UIKit.pill(GameState.title_for_level(int(pr.level)), UIKit.C_ACCENT))
	nh.add_child(UIKit.pill("Security Clearance T%d" % GameState.clearance(), Color("#c22cff")))
	var lvl := int(pr.level)
	right.add_child(UIKit.label("DATA Level %d   ·   %d / %d DATA to next promotion   ·   %d Upgrade Points unspent" % [lvl, int(pr.xp), GameState.xp_needed(lvl), int(pr.points)], 14, UIKit.C_MUTED))
	right.add_child(UIKit.label("Your Power is the average Power of your equipped gear. Viruses scale to it, and new gear drops around it. Promotions grant Upgrade Points only.", 12, UIKit.C_MUTED))
	right.add_child(UIKit.label("%d Gold   ·   %d Corrupted Gold" % [int(pr.gold), int(pr.get("corrupted_gold", 0))], 14, UIKit.C_TEXT, true))
	var xb := UIKit.bar(UIKit.C_DATA, 12)
	xb.max_value = GameState.xp_needed(lvl)
	xb.value = int(pr.xp)
	right.add_child(xb)
	var cols := UIKit.hbox(30)
	right.add_child(cols)
	var c1 := UIKit.vbox(6)
	cols.add_child(c1)
	c1.add_child(UIKit.section("Attributes"))
	var w: Dictionary = s.get("weapon", {})
	var lines := [
		["Max HP", str(int(s.get("max_hp", 0)))],
		["Defense", "%d  (-%d%% damage taken)" % [int(s.get("defense", 0)), int(100.0 * float(s.get("defense", 0)) / (float(s.get("defense", 0)) + 60.0))]],
		["Damage bonus", "+%d%%" % int(round(float(s.get("damage_pct", 0)) * 100))],
		["Crit chance", "%d%%" % int(round((float(s.get("crit_chance", 0)) + float(w.get("crit_chance", 0))) * 100))],
		["Move speed", "%.1f m/s" % float(s.get("move_speed_final", 6.5))],
		["HP regen", "%.1f /s" % float(s.get("hp_regen", 0))],
		["Block chance", "%d%%" % int(round(float(s.get("block_chance", 0)) * 100))],
		["DATA gain", "+%d%%" % int(round(float(s.get("data_gain_pct", 0)) * 100))],
		["Cooldown reduction", "%d%%" % int(round(float(s.get("cooldown_pct", 0)) * 100))],
	]
	for l in lines:
		var row := UIKit.hbox(10)
		var k := UIKit.label(l[0], 14, UIKit.C_MUTED)
		k.custom_minimum_size.x = 160
		row.add_child(k)
		row.add_child(UIKit.label(l[1], 14, UIKit.C_TEXT, true))
		c1.add_child(row)
	var c2 := UIKit.vbox(6)
	cols.add_child(c2)
	c2.add_child(UIKit.section("Weapon"))
	var weapon := GameState.equipped("weapon")
	c2.add_child(UIKit.label(ItemUtil.display_name(weapon) if not weapon.is_empty() else "Unarmed", 15, UIKit.C_TEXT, true))
	c2.add_child(UIKit.label("%d damage  ·  %.1f attacks/s  ·  %.1fm reach" % [int(float(w.get("damage", 0)) * (1.0 + float(s.get("damage_pct", 0)))), float(w.get("attack_speed", 0)), float(w.get("range", 0))], 13, UIKit.C_MUTED))
	var ab: Dictionary = DB.abilities.get(str(w.get("special", "")), {})
	c2.add_child(UIKit.label("Q: %s (%ds)" % [str(ab.get("name", "-")), int(ab.get("cooldown", 0))], 13, UIKit.C_ACCENT))
	var sp := Control.new()
	sp.custom_minimum_size.y = 10
	c2.add_child(sp)
	c2.add_child(UIKit.section("Record"))
	for l in [["Viruses terminated", str(int(pr.get("kills", 0)))], ["Sessions terminated", str(int(pr.get("deaths", 0)))], ["Dungeons cleared", str(int(pr.get("dungeons_cleared", 0)))], ["Terminals unlocked", str((pr.get("unlocked_computers", []) as Array).size())], ["Time on the clock", UIKit.time_str(float(pr.get("play_time", 0)))]]:
		var row2 := UIKit.hbox(10)
		var k2 := UIKit.label(l[0], 14, UIKit.C_MUTED)
		k2.custom_minimum_size.x = 160
		row2.add_child(k2)
		row2.add_child(UIKit.label(l[1], 14, UIKit.C_TEXT, true))
		c2.add_child(row2)


# ------------------------------------------------------------------ inventory

func _tab_inventory() -> void:
	var lr := _split()
	var left: VBoxContainer = lr[0]
	var right: VBoxContainer = lr[1]
	left.add_child(UIKit.section("Equipped"))
	var eq := UIKit.hbox(12)
	left.add_child(eq)
	for slot in GameState.SLOTS:
		var v := UIKit.vbox(4)
		eq.add_child(v)
		var inst := GameState.equipped(slot)
		var slot_name := str(ItemUtil.SLOT_NAMES.get(slot, slot.capitalize()))
		if inst.is_empty():
			v.add_child(UIKit.empty_slot(88, slot_name))
		else:
			v.add_child(UIKit.item_card(inst, int(inst.uid) == selected_uid, _select.bind(int(inst.uid)), 88))
		v.add_child(UIKit.label(slot_name, 12, UIKit.C_MUTED, true))
	left.add_child(UIKit.section("Inventory  %d / %d   ·   Power %d" % [GameState.unequipped_count(), GameState.INVENTORY_SIZE, GameState.power()]))
	var grid := _grid(left, 8)
	var count := 0
	for it in _sorted_items(false):
		grid.add_child(UIKit.item_card(it, int(it.uid) == selected_uid, _select.bind(int(it.uid)), 84))
		count += 1
	for i in range(count, GameState.INVENTORY_SIZE):
		grid.add_child(UIKit.empty_slot(84))
	var inst2 := GameState.find_item(selected_uid)
	if inst2.is_empty():
		right.add_child(UIKit.label("Select an item", 18, UIKit.C_TEXT, true))
		var hint := UIKit.label("Click any asset to see its stats, Power, effects and upgrade slots.\n\nEquip it to swap gear instantly, or salvage what you don't need for Gold.\nHigher-Power gear raises your Power (and the viruses' with it).\nUpgrade and reforge equipment at the Lobby service desks.", 13, UIKit.C_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(hint)
		return
	_detail(right, inst2)
	var actions := UIKit.hbox(8)
	right.add_child(actions)
	var uid := int(inst2.uid)
	if GameState.is_equipped(uid):
		actions.add_child(UIKit.pill("EQUIPPED", UIKit.C_OK))
	else:
		var can := GameState.can_equip(inst2)
		var eb := UIKit.button("Equip", func() -> void:
			if GameState.equip(uid):
				_set_message("Equipped " + ItemUtil.display_name(inst2) + ".", true)
			_rebuild(), "primary", 120)
		eb.disabled = not can
		actions.add_child(eb)
		var price := ItemUtil.sell_price(inst2)
		actions.add_child(UIKit.button("Salvage (+%d Gold)" % price, func() -> void:
			var got := GameState.sell_item(uid)
			Audio.play("gold")
			_set_message("Salvaged for %d Gold." % got, true)
			selected_uid = -1
			_rebuild(), "default"))
	if message != "":
		right.add_child(_message_label())


# ------------------------------------------------------------------ shop

func _tab_shop() -> void:
	var lr := _split()
	var left: VBoxContainer = lr[0]
	var right: VBoxContainer = lr[1]
	var top := UIKit.hbox(8)
	left.add_child(top)
	top.add_child(UIKit.button("Buy", func() -> void:
		shop_mode = "buy"
		selected_uid = -1
		_rebuild(), "primary" if shop_mode == "buy" else "default", 90))
	top.add_child(UIKit.button("Sell", func() -> void:
		shop_mode = "sell"
		selected_uid = -1
		_rebuild(), "primary" if shop_mode == "sell" else "default", 90))
	top.add_child(UIKit.spacer())
	top.add_child(UIKit.label("%d Gold" % int(GameState.profile.gold), 16, UIKit.C_GOLD, true))
	var cost := int(DB.shop.get("refresh_cost", 30))
	var rb := UIKit.button("Request new catalogue (%d Gold)" % cost, func() -> void:
		if GameState.paid_refresh_shop():
			Audio.play("buy")
			_set_message("Catalogue refreshed.", true)
		else:
			_set_message("Not enough Gold.", false)
		selected_uid = -1
		_rebuild())
	top.add_child(rb)
	var selected: Dictionary = {}
	if shop_mode == "buy":
		left.add_child(UIKit.section("Today's catalogue  ·  restocks every time you return from the field"))
		var grid := _grid(left, 4)
		for it in GameState.profile.get("shop_stock", []):
			var v := UIKit.vbox(4)
			grid.add_child(v)
			v.add_child(UIKit.item_card(it, int(it.uid) == selected_uid, _select.bind(int(it.uid)), 120))
			var price := GameState.shop_price(it)
			v.add_child(UIKit.label(ItemUtil.display_name(it), 12, UIKit.C_TEXT, true))
			v.add_child(UIKit.label("%d Gold" % price, 13, UIKit.C_GOLD if int(GameState.profile.gold) >= price else UIKit.C_DANGER, true))
			if int(it.uid) == selected_uid:
				selected = it
		if (GameState.profile.get("shop_stock", []) as Array).is_empty():
			left.add_child(UIKit.label("Sold out. Request a new catalogue or come back later.", 14, UIKit.C_MUTED))
	else:
		left.add_child(UIKit.section("Your unequipped assets"))
		var grid2 := _grid(left, 8)
		for it in _sorted_items(false):
			grid2.add_child(UIKit.item_card(it, int(it.uid) == selected_uid, _select.bind(int(it.uid)), 84))
			if int(it.uid) == selected_uid:
				selected = it
	if selected.is_empty():
		right.add_child(UIKit.label("Procurement", 18, UIKit.C_TEXT, true))
		var t := UIKit.label("Select an item to review the vendor specification.\n\nAll purchases are final. Please retain your receipt for audit purposes.", 13, UIKit.C_MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(t)
	else:
		_detail(right, selected)
		var uid := int(selected.uid)
		if shop_mode == "buy":
			var price2 := GameState.shop_price(selected)
			var bb := UIKit.button("Buy for %d Gold" % price2, func() -> void:
				var err := GameState.buy_shop_item(uid)
				if err == "":
					_set_message("Purchased! It's in your inventory.", true)
					selected_uid = -1
				else:
					_set_message(err, false)
				_rebuild(), "primary")
			bb.disabled = int(GameState.profile.gold) < price2
			right.add_child(bb)
		else:
			var sp := ItemUtil.sell_price(selected)
			right.add_child(UIKit.button("Sell for %d Gold" % sp, func() -> void:
				GameState.sell_item(uid)
				Audio.play("gold")
				_set_message("Sold for %d Gold." % sp, true)
				selected_uid = -1
				_rebuild(), "primary"))
	if message != "":
		right.add_child(_message_label())


# ------------------------------------------------------------------ forge

func _tab_forge() -> void:
	var lr := _split()
	var left: VBoxContainer = lr[0]
	var right: VBoxContainer = lr[1]
	left.add_child(UIKit.label("Each upgrade adds +%d%% to the item's damage or defense. Equipped items are listed first." % int(float(DB.progression.blacksmith.get("bonus_per_plus", 0.15)) * 100), 13, UIKit.C_MUTED))
	var grid := _grid(left, 8)
	for it in _sorted_items(true):
		grid.add_child(UIKit.item_card(it, int(it.uid) == selected_uid, _select.bind(int(it.uid)), 84, "E" if GameState.is_equipped(int(it.uid)) else ""))
	var inst := GameState.find_item(selected_uid)
	if inst.is_empty():
		right.add_child(UIKit.label("IT Hardware Forge", 18, UIKit.C_TEXT, true))
		var t := UIKit.label("\"We can make it faster, stronger, and slightly on fire.\"\n\nSelect a weapon, armor piece or accessory to reforge it with Gold.", 13, UIKit.C_MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(t)
	else:
		var max_plus := int(DB.progression.blacksmith.get("max_plus", 5))
		var plus := int(inst.get("plus", 0))
		if plus < max_plus:
			var preview := inst.duplicate(true)
			preview["plus"] = plus + 1
			right.add_child(UIKit.label("Upgrade preview: +%d  →  +%d" % [plus, plus + 1], 14, UIKit.C_ACCENT, true))
			right.add_child(UIKit.rich(ItemUtil.describe(preview, inst)))
			var cost := ItemUtil.upgrade_cost(inst)
			var uid := int(inst.uid)
			var b := UIKit.button("Reforge for %d Gold" % cost, func() -> void:
				var err := GameState.upgrade_item(uid)
				_set_message("Upgrade complete!" if err == "" else err, err == "")
				_rebuild(), "primary")
			b.disabled = int(GameState.profile.gold) < cost
			right.add_child(b)
		else:
			_detail(right, inst, false)
			right.add_child(UIKit.pill("MAXIMUM UPGRADE (+%d)" % max_plus, UIKit.C_OK))
	if message != "":
		right.add_child(_message_label())


# ------------------------------------------------------------------ enchanting

func _tab_enchant() -> void:
	var lr := _split()
	var left: VBoxContainer = lr[0]
	var right: VBoxContainer = lr[1]
	var head := UIKit.hbox(10)
	left.add_child(head)
	head.add_child(UIKit.label("%d Upgrade Points" % int(GameState.profile.points), 16, UIKit.C_DATA, true))
	head.add_child(UIKit.label("%d Corrupted Gold" % int(GameState.profile.get("corrupted_gold", 0)), 16, Color("#8a3fd6"), true))
	head.add_child(UIKit.label("  ·  points come with every promotion; Corrupted Gold drops from corrupted viruses", 12, UIKit.C_MUTED))
	var grid := _grid(left, 8)
	for it in _sorted_items(true):
		grid.add_child(UIKit.item_card(it, int(it.uid) == selected_uid, _select.bind(int(it.uid)), 84, "E" if GameState.is_equipped(int(it.uid)) else ""))
	var inst := GameState.find_item(selected_uid)
	if inst.is_empty():
		right.add_child(UIKit.label("Upgrades", 18, UIKit.C_TEXT, true))
		var t := UIKit.label("Every item has upgrade slots (Common 1, Special 2, Unique 3). Each slot offers a choice of effects. Pick one with an Upgrade Point, then level it from I to III with Upgrade Points and Corrupted Gold.", 13, UIKit.C_MUTED)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(t)
		if message != "":
			right.add_child(_message_label())
		return
	var top := UIKit.hbox(12)
	right.add_child(top)
	top.add_child(UIKit.item_card(inst, false, Callable(), 72))
	var tv := UIKit.vbox(2)
	top.add_child(tv)
	var d := ItemUtil.def(inst)
	tv.add_child(UIKit.label(ItemUtil.display_name(inst), 17, ItemUtil.rarity_color(str(d.get("rarity", "common"))).darkened(0.2), true))
	tv.add_child(UIKit.label("%s · %s" % [ItemUtil.rarity_name(str(d.get("rarity", ""))), ItemUtil.slot_label(d)], 12, UIKit.C_MUTED))
	for fx in d.get("effects", []):
		var eid := str(fx.get("enchant", ""))
		right.add_child(UIKit.rich("[color=#6e6b66]Built-in:[/color] [b]%s[/b] - %s" % [ItemUtil.enchant_name(eid, int(fx.get("level", 1))), ItemUtil.enchant_desc(eid, int(fx.get("level", 1)))]))
	var uid := int(inst.uid)
	var slots: Array = inst.get("enchants", [])
	for i in slots.size():
		var s: Dictionary = slots[i]
		var card := UIKit.panel(Color("#faf9f6"), 8, 12)
		right.add_child(card)
		var v := UIKit.vbox(6)
		card.add_child(v)
		var chosen := str(s.get("chosen", ""))
		var lvl := int(s.get("level", 0))
		if chosen == "":
			v.add_child(UIKit.label("Slot %d  ·  choose one (%d Upgrade Point)" % [i + 1, ItemUtil.enchant_point_cost(1)], 13, UIKit.C_MUTED, true))
			for opt in s.get("options", []):
				var oid := str(opt)
				var e: Dictionary = DB.enchantments.get(oid, {})
				var ob := UIKit.button("", func() -> void:
					var err := GameState.choose_enchant(uid, i, oid)
					_set_message("Installed %s!" % ItemUtil.enchant_name(oid, 1) if err == "" else err, err == "")
					_rebuild())
				ob.custom_minimum_size = Vector2(0, 54)
				ob.alignment = HORIZONTAL_ALIGNMENT_LEFT
				var r := UIKit.rich("[color=#%s][b]%s[/b][/color]  %s" % [MeshFactory.col(e.get("color", "#6656c9")).darkened(0.25).to_html(false), ItemUtil.enchant_name(oid, 1), ItemUtil.enchant_desc(oid, 1)])
				r.mouse_filter = Control.MOUSE_FILTER_IGNORE
				UIKit.place(r, 0, 0, 1, 1, 12, 6, -12, -4)
				r.add_theme_font_size_override("normal_font_size", 13)
				r.add_theme_font_size_override("bold_font_size", 13)
				ob.add_child(r)
				ob.disabled = int(GameState.profile.points) < ItemUtil.enchant_point_cost(1)
				v.add_child(ob)
		else:
			var e2: Dictionary = DB.enchantments.get(chosen, {})
			var col := MeshFactory.col(e2.get("color", "#6656c9")).darkened(0.25)
			v.add_child(UIKit.rich("[color=#%s][b]%s[/b][/color]  -  %s" % [col.to_html(false), ItemUtil.enchant_name(chosen, lvl), ItemUtil.enchant_desc(chosen, lvl)]))
			var max_lvl := int(DB.progression.enchanting.get("max_level", 3))
			if lvl < max_lvl:
				v.add_child(UIKit.rich("[color=#6e6b66]Next (%s): %s[/color]" % [ItemUtil.ROMAN[lvl + 1], ItemUtil.enchant_desc(chosen, lvl + 1)]))
				var pts := ItemUtil.enchant_point_cost(lvl + 1)
				var cgold := ItemUtil.enchant_gold_cost(lvl + 1)
				var ub := UIKit.button("Level up to %s  (%d Upgrade Points, %d Corrupted Gold)" % [ItemUtil.ROMAN[lvl + 1], pts, cgold], func() -> void:
					var err := GameState.upgrade_enchant(uid, i)
					_set_message("Upgrade levelled up!" if err == "" else err, err == "")
					_rebuild(), "primary")
				ub.disabled = int(GameState.profile.points) < pts or int(GameState.profile.get("corrupted_gold", 0)) < cgold
				v.add_child(ub)
			else:
				v.add_child(UIKit.pill("MAX LEVEL", UIKit.C_OK))
	if slots.is_empty():
		right.add_child(UIKit.label("This item has no upgrade slots.", 13, UIKit.C_MUTED))
	if message != "":
		right.add_child(_message_label())


# ------------------------------------------------------------------ network map

func _tab_network() -> void:
	var from_id := str(ctx.get("from_computer", ""))
	var v := UIKit.vbox(10)
	body.add_child(v)
	var info := UIKit.label("Connected from: %s" % _computer_name(from_id) if from_id != "" else "Viewing only. Connect from a golden terminal to transfer between nodes.", 14, UIKit.C_ACCENT if from_id != "" else UIKit.C_MUTED, true)
	v.add_child(info)
	var canvas := NetworkCanvas.new()
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.from_id = from_id
	canvas.on_travel = func(level_id: String, comp_id: String) -> void:
		close_window()
		Audio.play("teleport")
		GameState.main.travel(level_id, {"type": "computer", "id": comp_id})
	v.add_child(canvas)


func _computer_name(id: String) -> String:
	for c in DB.level_computers():
		if c.id == id:
			return str(c.name)
	return id


class NetworkCanvas extends Control:
	var from_id := ""
	var on_travel: Callable
	var _nodes: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		resized.connect(_layout)
		_layout.call_deferred()

	func _layout() -> void:
		for c in get_children():
			c.queue_free()
		_nodes.clear()
		var cols: Array = []
		for lid in DB.level_order:
			var lv: Dictionary = DB.levels[lid]
			if (lv.get("computers", []) as Array).is_empty():
				continue
			cols.append(lid)
		var col_w := size.x / maxf(1.0, cols.size())
		for ci in cols.size():
			var lid: String = cols[ci]
			var lv2: Dictionary = DB.levels[lid]
			var head := UIKit.label(str(lv2.get("name", lid)).to_upper(), 13, UIKit.C_MUTED, true)
			head.position = Vector2(col_w * ci + 20, 6)
			add_child(head)
			var sub := UIKit.label(str(lv2.get("subtitle", "")), 11, UIKit.C_MUTED)
			sub.position = Vector2(col_w * ci + 20, 26)
			add_child(sub)
			var comps: Array = lv2.get("computers", [])
			for i in comps.size():
				var c: Dictionary = comps[i]
				var cid := str(c.id)
				var unlocked := GameState.is_computer_unlocked(cid)
				var here := cid == from_id
				var b := Button.new()
				b.focus_mode = Control.FOCUS_ALL
				b.custom_minimum_size = Vector2(minf(col_w - 60, 280), 70)
				b.size = b.custom_minimum_size
				b.position = Vector2(col_w * ci + 20, 70 + i * 120)
				var border := Color("#d9a520") if unlocked else Color("#c8c4ba")
				b.add_theme_stylebox_override("normal", UIKit.sb(Color("#fffbea") if unlocked else Color("#eeece6"), 10, 3 if here else 2, UIKit.C_ACCENT if here else border, 12))
				b.add_theme_stylebox_override("hover", UIKit.sb(Color("#fff3c4"), 10, 3, UIKit.C_ACCENT_HI, 12))
				b.add_theme_stylebox_override("disabled", UIKit.sb(Color("#eeece6"), 10, 2, border, 12))
				b.text = "%s\n%s" % [str(c.get("name", cid)), "YOU ARE HERE" if here else ("Online - click to transfer" if unlocked and from_id != "" else ("Online" if unlocked else "Offline - not yet discovered"))]
				b.add_theme_font_size_override("font_size", 13)
				b.disabled = not unlocked or here or from_id == ""
				b.pressed.connect(func() -> void: on_travel.call(lid, cid))
				add_child(b)
				_nodes.append({"pos": b.position + b.size * 0.5, "unlocked": unlocked, "col": ci})
		queue_redraw()

	func _draw() -> void:
		draw_style_box(UIKit.sb(Color(1, 1, 1, 0.6), 10, 1, UIKit.C_BORDER, 0), Rect2(Vector2.ZERO, size))
		for x in range(0, int(size.x), 40):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(0, 0, 0, 0.03))
		for y in range(0, int(size.y), 40):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(0, 0, 0, 0.03))
		var hub_node = null
		for n in _nodes:
			if n.col == 0:
				hub_node = n
				break
		var prev = null
		for n in _nodes:
			if prev != null and prev.col == n.col:
				_link(prev, n)
			elif hub_node != null and n != hub_node and (prev == null or prev.col != n.col):
				_link(hub_node, n)
			prev = n

	func _link(a: Dictionary, b: Dictionary) -> void:
		var on: bool = a.unlocked and b.unlocked
		var col := Color("#d9a520") if on else Color(0, 0, 0, 0.15)
		draw_line(a.pos, b.pos, col, 4.0 if on else 2.0, true)
