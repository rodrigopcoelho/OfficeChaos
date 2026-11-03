class_name HUD
extends Control
## In-game overlay styled as a corporate messenger client: app rail, top search bar,
## presence card with HP/DATA bars, ability tiles, boss bar and interaction prompt.

const RAIL_ITEMS := [
	["profile", "profile", "Profile"],
	["inventory", "items", "Items"],
	["network", "map", "Network"],
	["shop", "shop", "Shop"],
	["forge", "forge", "Forge"],
	["enchant", "enchant", "Upgrades"],
]

var location_label: Label
var gold_label: Label
var cgold_label: Label
var points_label: Label
var avatar_slot: Control
var portrait: AvatarPortrait
var status_dot: Panel
var name_label: Label
var sub_label: Label
var hp_bar: LcdGauge
var shield_bar: ProgressBar
var data_bar: LcdGauge
var q_slot: AbilitySlot
var dodge_slot: AbilitySlot
var weapon_icon: TextureRect
var weapon_label: Label
var prompt_panel: PanelContainer
var prompt_label: Label
var prompt_key: Label
var boss_panel: PanelContainer
var boss_name: Label
var boss_state: Label
var boss_bar: ProgressBar
var boss_trail: ProgressBar
var banner: VBoxContainer
var banner_title: Label
var banner_sub: Label
var rail_buttons: Dictionary = {}
var _trail := 1.0
var _dirty := true
var _avatar_sig := ""
var _watched_player: Object = null  # whose expressions the portrait mirrors
var _weapon_icon_id := ""


class LcdGauge extends Control:
	## A gauge drawn like an old handheld's LCD: dark green glass, a monospace label,
	## a row of chunky segments (lit / ghosted) and the reading on the right.
	var max_value := 1.0
	var value := 1.0
	var label := "HP"
	var text := ""
	var lit := Color("#ff7a5a")
	var segments := 20
	const GLASS := Color("#16241c")
	const GHOST := Color(0.55, 0.8, 0.6, 0.12)

	func _init(lbl: String = "HP", col: Color = Color("#ff7a5a"), h: float = 20.0, segs: int = 20) -> void:
		label = lbl
		lit = col
		segments = segs
		custom_minimum_size = Vector2(0, h)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.sb(GLASS, 5, 1, Color(0, 0, 0, 0.5), 0), r)
		var f := UIKit.font_mono
		var fs := int(size.y * 0.6)
		draw_string(f, Vector2(6, size.y * 0.5 + fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#9dffb0"))
		var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2(size.x - tw - 6, size.y * 0.5 + fs * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#9dffb0"))
		var x0 := 6.0 + f.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0
		var x1 := size.x - tw - 12.0
		var seg_w := (x1 - x0) / segments
		var on := int(ceil(clampf(value / maxf(max_value, 0.0001), 0.0, 1.0) * segments - 0.001))
		for i in segments:
			var sr := Rect2(Vector2(x0 + i * seg_w + 1.0, 4.0), Vector2(seg_w - 2.0, size.y - 8.0))
			draw_rect(sr, lit if i < on else GHOST)
		# glass sheen + faint LCD scanlines
		draw_rect(Rect2(Vector2(2, 2), Vector2(size.x - 4, size.y * 0.3)), Color(1, 1, 1, 0.05))
		for y in range(2, int(size.y), 3):
			draw_line(Vector2(2, y), Vector2(size.x - 2, y), Color(0, 0, 0, 0.12))


class AbilitySlot extends Control:
	var key := "Q"
	var title := ""
	var ratio := 0.0
	var remaining := 0.0
	var accent := Color("#6656c9")

	func _init() -> void:
		custom_minimum_size = Vector2(64, 64)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		## A chunky handheld button: beige plastic bezel around a green LCD face.
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UIKit.sb(Color("#e9e1cf"), 16, 3, accent if ratio <= 0.0 else Color("#b9ae97"), 0), r)
		var lcd := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		draw_style_box(UIKit.sb(LcdGauge.GLASS, 9, 0), lcd)
		if ratio > 0.0:
			draw_rect(Rect2(lcd.position + Vector2(0, lcd.size.y * (1.0 - ratio)), Vector2(lcd.size.x, lcd.size.y * ratio)), Color(0, 0, 0, 0.45))
		var f := UIKit.font_mono
		var ready_col := Color("#9dffb0")
		draw_string(f, Vector2(11, 25), key, HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, 14, ready_col if ratio <= 0.0 else Color(ready_col, 0.4))
		if ratio > 0.0:
			draw_string(f, Vector2(0, size.y * 0.72), "%.1f" % remaining, HORIZONTAL_ALIGNMENT_CENTER, size.x, 15, ready_col)
		for y in range(int(lcd.position.y), int(lcd.end.y), 3):
			draw_line(Vector2(lcd.position.x, y), Vector2(lcd.end.x, y), Color(0, 0, 0, 0.12))
		draw_string(f, Vector2(0, size.y + 15), title.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, size.x, 10, Color(1, 1, 1, 0.9))


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_rail()
	_build_topbar()
	_build_profile_card()
	_build_abilities()
	_build_prompt()
	_build_boss_bar()
	_build_banner()
	# Picking up 25 DATA orbs fires 25 signals in a few frames: just mark the card
	# dirty and rebuild it once per frame in _process.
	GameState.gold_changed.connect(func(_g: int) -> void: _dirty = true)
	GameState.corrupted_gold_changed.connect(func(_g: int) -> void: _dirty = true)
	GameState.xp_changed.connect(func(_a: int, _b: int, _c: int) -> void: _dirty = true)
	GameState.points_changed.connect(func(_p: int) -> void: _dirty = true)
	GameState.equipment_changed.connect(func() -> void: _dirty = true)
	GameState.profile_loaded.connect(func() -> void: _dirty = true)
	Controls.device_changed.connect(func(_g: bool) -> void:
		_dirty = true
		set_prompt(prompt_label.text))
	if GameState.ui and GameState.ui.icons:
		GameState.ui.icons.icon_ready.connect(_on_icon_ready)


func _build_rail() -> void:
	var rail := PanelContainer.new()
	rail.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_RAIL, 0, 0, Color.TRANSPARENT, 0))
	UIKit.place(rail, 0, 0, 0, 1, 0, 0, 68, 0)
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(rail)
	var v := UIKit.vbox(2)
	rail.add_child(v)
	var logo := PanelContainer.new()
	logo.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_ACCENT, 10, 0, Color.TRANSPARENT, 0))
	logo.custom_minimum_size = Vector2(44, 44)
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var ll := UIKit.label("OC", 17, Color.WHITE, true)
	ll.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ll.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logo.add_child(ll)
	var top_pad := Control.new()
	top_pad.custom_minimum_size = Vector2(0, 8)
	v.add_child(top_pad)
	v.add_child(logo)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	for item in RAIL_ITEMS:
		var b := _rail_button(item[1], item[2], func() -> void: GameState.ui.open_app(item[0], {}))
		rail_buttons[item[0]] = b
		v.add_child(b)
	v.add_child(UIKit.spacer())
	v.add_child(_rail_button("menu", "Menu", func() -> void: GameState.ui.toggle_pause()))
	var bottom_pad := Control.new()
	bottom_pad.custom_minimum_size = Vector2(0, 8)
	v.add_child(bottom_pad)


func _rail_button(icon: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(68, 56)
	b.add_theme_stylebox_override("normal", UIKit.sb(Color(0, 0, 0, 0), 0, 0))
	b.add_theme_stylebox_override("hover", UIKit.sb(UIKit.C_RAIL_HI, 0, 0))
	b.add_theme_stylebox_override("pressed", UIKit.sb(UIKit.C_ACCENT, 0, 0))
	b.tooltip_text = text
	var ic := RailIcon.new(icon, Color("#d9d4ea"))
	UIKit.place(ic, 0.5, 0, 0.5, 0, -11, 8, 11, 30)
	b.add_child(ic)
	var l := UIKit.label(text, 10, Color("#c9c3dc"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UIKit.place(l, 0, 0, 1, 0, 0, 33, 0, 50)
	b.add_child(l)
	b.pressed.connect(func() -> void:
		Audio.play("ui_click", -6.0, 0.05, 0.0)
		cb.call())
	return b


func _build_topbar() -> void:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_TITLEBAR, 0, 0, Color.TRANSPARENT, 8))
	UIKit.place(bar, 0, 0, 1, 0, 68, 0, 0, 48)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var h := UIKit.hbox(12)
	bar.add_child(h)
	var app := UIKit.label("CubeLink", 15, Color("#e9e4ff"), true)
	app.custom_minimum_size.x = 90
	h.add_child(app)
	var search := PanelContainer.new()
	search.add_theme_stylebox_override("panel", UIKit.sb(Color("#f5f5f5"), 4, 0, Color.TRANSPARENT, 10))
	search.custom_minimum_size = Vector2(460, 30)
	search.mouse_filter = Control.MOUSE_FILTER_IGNORE
	location_label = UIKit.label("Search", 13, UIKit.C_MUTED)
	search.add_child(location_label)
	h.add_child(UIKit.spacer())
	h.add_child(search)
	h.add_child(UIKit.spacer())
	points_label = UIKit.label("", 13, Color("#7ff0d0"), true)
	h.add_child(points_label)
	h.add_child(_currency_chip(UIKit.C_GOLD, Color("#ffe08a"), "Gold"))
	gold_label = UIKit.label("0", 16, Color("#ffd66b"), true)
	gold_label.tooltip_text = "Gold"
	h.add_child(gold_label)
	h.add_child(_currency_chip(Color("#7a2cff"), Color("#ff4fd8"), "Corrupted Gold"))
	cgold_label = UIKit.label("0", 16, Color("#d9a6ff"), true)
	h.add_child(cgold_label)
	var pad := Control.new()
	pad.custom_minimum_size.x = 8
	h.add_child(pad)


func _currency_chip(fill: Color, rim: Color, tip: String) -> Panel:
	var coin := Panel.new()
	coin.custom_minimum_size = Vector2(16, 16)
	coin.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	coin.add_theme_stylebox_override("panel", UIKit.sb(fill, 8, 2, rim, 0))
	coin.tooltip_text = tip
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return coin


func _build_profile_card() -> void:
	var card := PanelContainer.new()
	# Handheld-device card: rounded beige plastic bezel with a soft shadow.
	var card_sb := UIKit.sb(Color("#e9e1cf"), 18, 3, Color("#b9ae97"), 12)
	card_sb.shadow_color = Color(0, 0, 0, 0.25)
	card_sb.shadow_size = 8
	card_sb.shadow_offset = Vector2(0, 2)
	card.add_theme_stylebox_override("panel", card_sb)
	UIKit.place(card, 0, 1, 0, 1, 84, -132, 464, -16)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var h := UIKit.hbox(12)
	card.add_child(h)
	avatar_slot = Control.new()
	avatar_slot.custom_minimum_size = Vector2(56, 56)
	avatar_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	avatar_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(avatar_slot)
	portrait = AvatarPortrait.new(56)
	portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	avatar_slot.add_child(portrait)
	status_dot = Panel.new()
	status_dot.size = Vector2(17, 17)
	status_dot.position = Vector2(40, 40)
	status_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_slot.add_child(status_dot)
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	name_label = UIKit.label("Employee", 16, Color("#2b2840"), true)
	v.add_child(name_label)
	sub_label = UIKit.label("", 11, Color("#6b5e48"))
	sub_label.add_theme_font_override("font", UIKit.font_mono)
	v.add_child(sub_label)
	shield_bar = UIKit.bar(Color("#ff6a5a"), 4, Color(0, 0, 0, 0))
	v.add_child(shield_bar)
	hp_bar = LcdGauge.new("HP", Color("#ff7a5a"), 22, 20)
	v.add_child(hp_bar)
	data_bar = LcdGauge.new("DATA", Color("#40f2ff"), 16, 24)
	v.add_child(data_bar)


func _build_abilities() -> void:
	var h := UIKit.hbox(12)
	UIKit.place(h, 0, 1, 0, 1, 480, -112, 760, -34)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	var wp := PanelContainer.new()
	wp.add_theme_stylebox_override("panel", UIKit.sb(Color("#e9e1cf"), 16, 3, Color("#b9ae97"), 6))
	wp.custom_minimum_size = Vector2(64, 64)
	wp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon_icon = TextureRect.new()
	weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wp.add_child(weapon_icon)
	var wv := UIKit.vbox(2)
	wv.add_child(wp)
	weapon_label = UIKit.label("", 10, Color(1, 1, 1, 0.9))
	weapon_label.add_theme_font_override("font", UIKit.font_mono)
	weapon_label.custom_minimum_size.x = 64
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_label.clip_text = true
	wv.add_child(weapon_label)
	wv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(wv)
	q_slot = AbilitySlot.new()
	h.add_child(q_slot)
	dodge_slot = AbilitySlot.new()
	dodge_slot.title = "Dodge"
	dodge_slot.accent = Color("#4fd1b0")
	h.add_child(dodge_slot)


func _build_prompt() -> void:
	prompt_panel = PanelContainer.new()
	prompt_panel.add_theme_stylebox_override("panel", UIKit.sb(Color(0.13, 0.12, 0.17, 0.92), 18, 1, UIKit.C_ACCENT_HI, 14))
	prompt_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(prompt_panel, 0.5, 1, 0.5, 1, -260, -200, 260, -160)
	add_child(prompt_panel)
	var h := UIKit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	prompt_panel.add_child(h)
	var key := UIKit.pill("E", UIKit.C_ACCENT, Color.WHITE, 14)
	prompt_key = key.get_child(0)
	h.add_child(key)
	prompt_label = UIKit.label("", 15, Color.WHITE)
	h.add_child(prompt_label)
	prompt_panel.visible = false


func _build_boss_bar() -> void:
	boss_panel = PanelContainer.new()
	boss_panel.add_theme_stylebox_override("panel", UIKit.sb(Color(0.1, 0.06, 0.1, 0.9), 10, 1, Color("#ff2a4a"), 12))
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(boss_panel, 0.5, 0, 0.5, 0, -380, 62, 380, 132)
	add_child(boss_panel)
	var v := UIKit.vbox(4)
	boss_panel.add_child(v)
	var h := UIKit.hbox(10)
	v.add_child(h)
	boss_name = UIKit.label("BOSS", 17, Color("#ffd0d6"), true)
	h.add_child(boss_name)
	h.add_child(UIKit.spacer())
	boss_state = UIKit.label("", 12, Color("#ff8090"), true)
	h.add_child(boss_state)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 16)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(holder)
	boss_trail = UIKit.bar(Color(1, 1, 1, 0.75), 16, Color(1, 1, 1, 0.08))
	boss_trail.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(boss_trail)
	boss_bar = UIKit.bar(Color("#e0284a"), 16, Color(0, 0, 0, 0))
	boss_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.add_child(boss_bar)
	boss_panel.visible = false


func _build_banner() -> void:
	banner = UIKit.vbox(2)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(banner, 0.5, 0, 0.5, 0, -400, 150, 400, 240)
	add_child(banner)
	banner_title = UIKit.label("", 40, Color.WHITE, true)
	banner_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_title.add_theme_constant_override("outline_size", 10)
	banner_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	banner.add_child(banner_title)
	banner_sub = UIKit.label("", 16, Color(1, 1, 1, 0.8))
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_sub.add_theme_constant_override("outline_size", 6)
	banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	banner.add_child(banner_sub)
	banner.modulate.a = 0.0


func show_banner(title: String, sub: String) -> void:
	banner_title.text = title.to_upper()
	banner_sub.text = sub
	var tw := create_tween()
	tw.tween_property(banner, "modulate:a", 1.0, 0.5)
	tw.tween_interval(2.2)
	tw.tween_property(banner, "modulate:a", 0.0, 0.8)


func set_prompt(text: String) -> void:
	prompt_panel.visible = text != ""
	prompt_label.text = text
	prompt_key.text = Controls.prompt("interact")


func refresh() -> void:
	_dirty = true


func _on_icon_ready(id: String) -> void:
	if id == _weapon_icon_id:
		weapon_icon.texture = GameState.ui.icons.cache.get(id)


func _refresh_profile() -> void:
	_dirty = false
	if not GameState.has_profile():
		return
	var pr := GameState.profile
	gold_label.text = str(int(pr.gold))
	cgold_label.text = str(int(pr.get("corrupted_gold", 0)))
	points_label.text = "%d Upgrade Points" % int(pr.points) if int(pr.points) > 0 else ""
	name_label.text = str(pr.name)
	var lvl := int(pr.level)
	var status := "Available"
	var w = GameState.world
	if w != null and is_instance_valid(w):
		location_label.text = "Search   |   %s - %s" % [str(w.level.get("name", "")), str(w.level.get("subtitle", ""))]
		match str(w.level.get("type", "")):
			"dungeon": status = "Do not disturb"
			"field": status = "Busy"
	sub_label.text = "Power %d  ·  DATA Lv %d  ·  %s" % [GameState.power(), lvl, status]
	var need := GameState.xp_needed(lvl)
	data_bar.max_value = need
	data_bar.value = int(pr.xp)
	data_bar.text = "%d/%d" % [int(pr.xp), need]
	var armor := GameState.equipped("chest")
	var helmet := GameState.equipped("helmet")
	var sig := "%s|%s|%s|%s" % [JSON.stringify(pr.appearance), armor.get("id", ""), helmet.get("id", ""), status]
	if sig != _avatar_sig:
		_avatar_sig = sig
		portrait.show_profile(pr.appearance, armor, helmet)
		# Teams presence: Available green, Busy / Do not disturb red.
		var st_col := UIKit.C_OK if status == "Available" else UIKit.C_DANGER
		status_dot.add_theme_stylebox_override("panel", UIKit.sb(st_col, 9, 2, Color.WHITE, 0))
	var weapon := GameState.equipped("weapon")
	var ws: Dictionary = GameState.stats.get("weapon", {})
	var ab: Dictionary = DB.abilities.get(str(ws.get("special", "spin")), {})
	q_slot.key = Controls.prompt("special")
	q_slot.title = str(ab.get("name", "Special"))
	var dodge_key := Controls.prompt("dodge")
	dodge_slot.key = "RMB" if dodge_key == "Right Mouse" else dodge_key
	weapon_label.text = ItemUtil.display_name(weapon) if not weapon.is_empty() else "Fists"
	var wid := str(weapon.get("id", ""))
	if wid != _weapon_icon_id:
		_weapon_icon_id = wid
		weapon_icon.texture = GameState.ui.icons.get_icon(wid) if wid != "" and GameState.ui and GameState.ui.icons else null
	_update_rail()


func _update_rail() -> void:
	var w = GameState.world
	var in_hub: bool = w != null and is_instance_valid(w) and str(w.level.get("type", "")) == "hub"
	for t in ["shop", "forge", "enchant"]:
		if rail_buttons.has(t):
			rail_buttons[t].modulate.a = 1.0 if in_hub else 0.4


func _process(delta: float) -> void:
	if _dirty and visible:
		_refresh_profile()
	var p = GameState.player
	if p != _watched_player:
		# A new level spawned a new Player: mirror its expressions on the portrait.
		_watched_player = p
		if p != null and is_instance_valid(p) and p.visual:
			p.visual.expression_changed.connect(func(mood: String, _hold: float) -> void: portrait.express(mood))
	if p != null and is_instance_valid(p):
		hp_bar.max_value = p.max_hp
		hp_bar.value = p.hp
		hp_bar.text = "%d/%d" % [int(ceil(p.hp)), int(p.max_hp)]
		shield_bar.visible = p.shield_max > 0.0
		shield_bar.max_value = maxf(p.shield_max, 1.0)
		shield_bar.value = p.shield
		q_slot.ratio = p.special_cd / maxf(p.special_cd_max, 0.01)
		q_slot.remaining = p.special_cd
		q_slot.queue_redraw()
		dodge_slot.ratio = p.dodge_cd / maxf(p.dodge_cd_max, 0.01)
		dodge_slot.remaining = p.dodge_cd
		dodge_slot.queue_redraw()
	var w = GameState.world
	var b = w.boss if w != null and is_instance_valid(w) else null
	if b != null and is_instance_valid(b) and b.active and not b.dead:
		boss_panel.visible = true
		boss_name.text = str(b.boss_def.get("name", "BOSS"))
		boss_state.text = "Status: " + str(b.current_phase().get("name", ""))
		var ratio: float = b.hp / b.max_hp
		boss_bar.max_value = 1.0
		boss_bar.value = ratio
		_trail = lerpf(_trail, ratio, 1.0 - exp(-2.5 * delta)) if _trail > ratio else ratio
		boss_trail.max_value = 1.0
		boss_trail.value = _trail
	else:
		boss_panel.visible = false
		_trail = 1.0
