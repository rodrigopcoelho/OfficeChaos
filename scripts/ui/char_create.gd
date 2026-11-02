class_name CharCreate
extends Control
## "New Employee Onboarding" form: name, body type, badge-photo face, hairstyle, palette, save slot.

const RANDOM_NAMES := ["Dana Whitlock", "Morgan Pell", "Avery Quill", "Jordan Fenn", "Riley Tamsin", "Casey Brandt", "Sam Okafor", "Robin Haldane", "Quinn Ellery", "Alex Moreno"]

var appearance := {"body": 0, "palette": 0, "hair": 0, "face": 0}
var slot := 0
var name_edit: LineEdit
var preview: CharacterPreview
var cycler_labels: Dictionary = {}  # appearance key -> Label
var palette_box: HFlowContainer
var slot_box: VBoxContainer
var error_label: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.09, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	slot = _first_free_slot()
	var card := UIKit.panel(UIKit.C_BG, 14, 0)
	UIKit.place(card, 0.5, 0.5, 0.5, 0.5, -620, -380, 620, 380)
	add_child(card)
	var outer := UIKit.vbox(0)
	card.add_child(outer)
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_RAIL, 0, 0, Color.TRANSPARENT, 18))
	outer.add_child(header)
	var hh := UIKit.hbox(12)
	header.add_child(hh)
	var hv := UIKit.vbox(0)
	hh.add_child(hv)
	hv.add_child(UIKit.label("NEW EMPLOYEE ONBOARDING FORM", 20, Color.WHITE, true))
	hv.add_child(UIKit.label("Halverson-Kray Corporation  ·  Form HK-0001  ·  Please complete all fields", 12, Color("#bdb6d4")))
	var m := MarginContainer.new()
	for s in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + s, 24)
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(m)
	var h := UIKit.hbox(28)
	m.add_child(h)
	var form := UIKit.vbox(10)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(form)
	form.add_child(UIKit.section("1. Legal name"))
	var nh := UIKit.hbox(8)
	form.add_child(nh)
	name_edit = LineEdit.new()
	name_edit.placeholder_text = "Enter your name"
	name_edit.max_length = 22
	name_edit.custom_minimum_size = Vector2(320, 40)
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text = RANDOM_NAMES[randi() % RANDOM_NAMES.size()]
	name_edit.focus_mode = Control.FOCUS_CLICK  # controller navigation skips text entry (Randomize instead)
	nh.add_child(name_edit)
	nh.add_child(UIKit.button("Randomize", func() -> void: name_edit.text = RANDOM_NAMES[randi() % RANDOM_NAMES.size()]))
	form.add_child(UIKit.section("2. Job classification (body type)"))
	form.add_child(_cycler("body", DB.appearance.get("bodies", [])))
	form.add_child(UIKit.section("3. Badge photo (face)"))
	form.add_child(_cycler("face", DB.appearance.get("faces", [])))
	form.add_child(UIKit.section("4. Grooming policy (hairstyle)"))
	form.add_child(_cycler("hair", DB.appearance.get("hair_styles", [])))
	form.add_child(UIKit.section("5. Uniform palette"))
	palette_box = HFlowContainer.new()
	palette_box.add_theme_constant_override("h_separation", 8)
	palette_box.add_theme_constant_override("v_separation", 8)
	form.add_child(palette_box)
	form.add_child(UIKit.section("6. Personnel file (save slot)"))
	slot_box = UIKit.vbox(4)
	form.add_child(slot_box)
	form.add_child(UIKit.spacer())
	error_label = UIKit.label("", 13, UIKit.C_DANGER, true)
	form.add_child(error_label)
	var btns := UIKit.hbox(10)
	form.add_child(btns)
	btns.add_child(UIKit.button("Back", func() -> void: GameState.ui.show_main_menu(), "default", 110))
	btns.add_child(UIKit.spacer())
	var sign := UIKit.button("Sign Contract & Clock In", _confirm, "primary", 260)
	sign.set_meta("default_focus", true)
	sign.custom_minimum_size.y = 46
	btns.add_child(sign)
	var right := UIKit.vbox(8)
	h.add_child(right)
	var pv := UIKit.panel(Color("#e6e3da"), 12, 6)
	right.add_child(pv)
	preview = CharacterPreview.new(Vector2(380, 500))
	pv.add_child(preview)
	right.add_child(UIKit.label("ID photo preview (rotating)", 12, UIKit.C_MUTED))
	_refresh()


func _first_free_slot() -> int:
	for i in GameState.SLOT_COUNT:
		if GameState.slot_summary(i).is_empty():
			return i
	return 0


func _cycler(key: String, list: Array) -> Control:
	var h := UIKit.hbox(8)
	var l := UIKit.label("", 15, UIKit.C_TEXT, true)
	l.custom_minimum_size.x = 220
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cycler_labels[key] = l
	h.add_child(UIKit.button("<", func() -> void:
		appearance[key] = posmod(int(appearance[key]) - 1, list.size())
		_refresh(), "default", 44))
	h.add_child(l)
	h.add_child(UIKit.button(">", func() -> void:
		appearance[key] = posmod(int(appearance[key]) + 1, list.size())
		_refresh(), "default", 44))
	return h


func _refresh_controls() -> void:
	for key in cycler_labels:
		var list: Array = DB.appearance.get({"body": "bodies", "hair": "hair_styles", "face": "faces"}[key], [])
		(cycler_labels[key] as Label).text = str(list[int(appearance[key])].get("name", "?")) if not list.is_empty() else "?"
	UIKit.clear(palette_box)
	var pals: Array = DB.appearance.get("palettes", [])
	for i in pals.size():
		var p: Dictionary = pals[i]
		var b := Button.new()
		b.focus_mode = Control.FOCUS_ALL
		b.custom_minimum_size = Vector2(52, 40)
		b.tooltip_text = str(p.get("name", ""))
		var sel := i == int(appearance.palette)
		b.add_theme_stylebox_override("normal", UIKit.sb(MeshFactory.col(p.get("suit", "#888")), 8, 3 if sel else 1, UIKit.C_ACCENT if sel else Color(0, 0, 0, 0.2), 0))
		b.add_theme_stylebox_override("hover", UIKit.sb(MeshFactory.col(p.get("suit", "#888")).lightened(0.15), 8, 3, UIKit.C_ACCENT_HI, 0))
		var acc := Panel.new()
		acc.add_theme_stylebox_override("panel", UIKit.sb(MeshFactory.col(p.get("accent", "#888")), 3, 0))
		acc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		UIKit.place(acc, 0.5, 0, 0.5, 1, -4, 6, 4, -6)
		b.add_child(acc)
		b.pressed.connect(func() -> void:
			appearance.palette = i
			Audio.play("ui_click", -6.0)
			_refresh())
		palette_box.add_child(b)
	var pal_name := UIKit.label(str(pals[int(appearance.palette)].get("name", "")), 12, UIKit.C_MUTED)
	palette_box.add_child(pal_name)
	UIKit.clear(slot_box)
	for s in GameState.SLOT_COUNT:
		var sum := GameState.slot_summary(s)
		var txt := "Slot %d  ·  %s" % [s + 1, "empty" if sum.is_empty() else "OVERWRITES %s (DATA Lv %d)" % [sum.name, int(sum.level)]]
		var b2 := UIKit.button(txt, func() -> void:
			slot = s
			_refresh(), "primary" if s == slot else "default")
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		slot_box.add_child(b2)


func _refresh() -> void:
	_refresh_controls()
	if preview:
		preview.set_appearance(appearance)
		# Just the starter sword: armor would recolour the uniform being picked.
		preview.set_equipment({"id": "intern_shortsword", "plus": 0}, {}, {})


func _confirm() -> void:
	var n := name_edit.text.strip_edges()
	if n.length() < 2:
		error_label.text = "Please enter a name (at least 2 characters)."
		Audio.play("deny")
		return
	GameState.new_profile(n, appearance, slot)
	GameState.notify("HR Automated Assistant", "Welcome aboard, %s! Visit the service desks, then take the elevator to Floor 7." % n, "success")
	GameState.main.start_game()
