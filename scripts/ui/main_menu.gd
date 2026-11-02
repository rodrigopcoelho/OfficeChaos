class_name MainMenu
extends Control
## Title screen ("sign-in" page) over the live 3D lobby, with save slot loading.

const FEED := [
	["Facilities Bot", "Reminder: the fluorescent lights are working as intended."],
	["HR Automated Assistant", "Welcome to your first day. Your desk has been assigned. Your weapon has been assigned."],
	["IT Helpdesk", "Please do not engage corrupted processes without a valid DATA licence."],
	["The Regional Manager", "Quick sync in Server Room B? Attendance is not optional."],
	["Security", "Red meeting room doors have been sighted on Floor 7. Do not open them. (Please open them.)"],
]

var _content: VBoxContainer
var _side: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var grad := ColorRect.new()
	grad.color = Color(0.05, 0.04, 0.09, 0.55)
	grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(grad)
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UIKit.sb(Color(0.1, 0.09, 0.14, 0.94), 0, 0, Color.TRANSPARENT, 44))
	UIKit.place(left, 0, 0, 0, 1, 0, 0, 520, 0)
	add_child(left)
	_content = UIKit.vbox(12)
	left.add_child(_content)
	_side = Control.new()
	_side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(_side, 1, 0, 1, 1, -460, 70, -40, -40)
	add_child(_side)
	_build_feed()
	show_home()


func _header() -> void:
	UIKit.clear(_content)
	var logo := UIKit.hbox(12)
	_content.add_child(logo)
	var sq := PanelContainer.new()
	sq.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_ACCENT, 10, 0, Color.TRANSPARENT, 0))
	sq.custom_minimum_size = Vector2(46, 46)
	var sl := UIKit.label("OC", 18, Color.WHITE, true)
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sq.add_child(sl)
	logo.add_child(sq)
	var lv := UIKit.vbox(0)
	logo.add_child(lv)
	lv.add_child(UIKit.label("CubeLink Workspace", 14, Color("#bdb6d4"), true))
	lv.add_child(UIKit.label("Halverson-Kray Corporation  ·  Internal Network", 11, Color("#8a84a0")))
	var sp := Control.new()
	sp.custom_minimum_size.y = 40
	_content.add_child(sp)
	var title := UIKit.label("OFFICE\nCHAOS", 76, Color("#f2f1ed"), true)
	title.add_theme_constant_override("line_spacing", -18)
	_content.add_child(title)
	_content.add_child(UIKit.label("A medieval loot RPG trapped inside the corporate simulation.", 14, Color("#b8b2cc")))
	var sp2 := Control.new()
	sp2.custom_minimum_size.y = 28
	_content.add_child(sp2)


func show_home() -> void:
	_header()
	var last := Settings.last_slot
	var summary := GameState.slot_summary(last) if last >= 0 else {}
	if not summary.is_empty():
		var b := UIKit.button("Continue  ·  %s (DATA Lv %d)" % [summary.name, int(summary.level)], func() -> void: _load(last), "primary")
		b.custom_minimum_size.y = 48
		_content.add_child(b)
	var nb := UIKit.button("New Hire  (Create Character)", func() -> void: GameState.ui.show_char_create(), "primary" if summary.is_empty() else "dark")
	nb.custom_minimum_size.y = 48
	_content.add_child(nb)
	var lb := UIKit.button("Load Profile", show_load, "dark")
	lb.custom_minimum_size.y = 44
	_content.add_child(lb)
	var stb := UIKit.button("Settings", show_settings, "dark")
	stb.custom_minimum_size.y = 44
	_content.add_child(stb)
	var qb := UIKit.button("Clock Out (Quit)", func() -> void: get_tree().quit(), "dark")
	qb.custom_minimum_size.y = 44
	_content.add_child(qb)
	_content.add_child(UIKit.spacer())
	_content.add_child(UIKit.label("v0.1.0 demo  ·  WASD move · Mouse aim · LMB attack · RMB dodge · Q special · E interact · I inventory · M map · Esc pause", 11, Color("#8a84a0")))
	_content.add_child(UIKit.label("Controller  ·  LS move · X attack · LB / RS flick dodge · Y special · A interact · D-pad Up inventory · View map · Menu pause", 11, Color("#8a84a0")))
	GameState.ui.focus_default()


func show_load() -> void:
	_header()
	_content.add_child(UIKit.label("Employee profiles", 16, Color("#f2f1ed"), true))
	for slot in GameState.SLOT_COUNT:
		var s := GameState.slot_summary(slot)
		var row := UIKit.panel(Color(1, 1, 1, 0.06), 10, 12, 1, Color(1, 1, 1, 0.1))
		_content.add_child(row)
		var h := UIKit.hbox(12)
		row.add_child(h)
		if s.is_empty():
			h.add_child(UIKit.avatar("--", Color("#4a4658"), 40))
			h.add_child(UIKit.label("Slot %d  ·  empty" % (slot + 1), 15, Color("#8a84a0")))
			continue
		var face := AvatarPortrait.new(44)
		face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		face.show_profile(s.appearance)
		h.add_child(face)
		var v := UIKit.vbox(0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(UIKit.label(str(s.name), 15, Color.WHITE, true))
		v.add_child(UIKit.label("DATA Lv %d · %d GOLD · Clearance T%d · %s" % [int(s.level), int(s.gold), int(s.clearance), UIKit.time_str(float(s.play_time))], 12, Color("#b8b2cc")))
		h.add_child(UIKit.button("Load", _load.bind(slot), "primary", 80))
		h.add_child(UIKit.button("Delete", func() -> void:
			GameState.delete_slot(slot)
			show_load(), "dark", 80))
	var sp := Control.new()
	sp.custom_minimum_size.y = 10
	_content.add_child(sp)
	_content.add_child(UIKit.button("Back", show_home, "dark"))
	GameState.ui.focus_default()


func show_settings() -> void:
	UIKit.clear(_content)
	_content.add_child(UIKit.label("Settings", 22, Color.WHITE, true))
	var card := UIKit.panel(Color.WHITE, 10, 14)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 600)
	_content.add_child(card)
	var sp := SettingsPanel.new()
	card.add_child(sp)
	_content.add_child(UIKit.button("Back", show_home, "dark"))
	GameState.ui.focus_default()


func _load(slot: int) -> void:
	if GameState.load_game(slot):
		GameState.main.start_game()


func _build_feed() -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.sb(Color(1, 1, 1, 0.92), 12, 0, Color.TRANSPARENT, 16))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIKit.place(card, 0, 0, 1, 0, 0, 0, 0, 420)
	_side.add_child(card)
	var v := UIKit.vbox(10)
	card.add_child(v)
	v.add_child(UIKit.label("# announcements", 16, UIKit.C_TEXT, true))
	for i in FEED.size():
		var item: Array = FEED[i]
		var row := UIKit.hbox(10)
		v.add_child(row)
		var col: Color = Toasts.SENDER_COLORS.get(item[0], Color("#c8343c"))
		row.add_child(UIKit.avatar(UIKit.initials(item[0]), col, 32))
		var tv := UIKit.vbox(0)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tv)
		tv.add_child(UIKit.label(item[0], 12, UIKit.C_TEXT, true))
		var msg := UIKit.label(item[1], 12, UIKit.C_MUTED)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		msg.custom_minimum_size.x = 330
		tv.add_child(msg)
