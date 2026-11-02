class_name SettingsPanel
extends ScrollContainer
## Audio, graphics/performance, feedback toggles and rebindable controls for both
## keyboard & mouse and controller.

var _waiting_action := ""
var _waiting_pad := false
var _rows: Dictionary = {}


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true
	_build()


func _build() -> void:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var focus_key := str(focused.get_meta("focus_key", "")) if focused != null and is_ancestor_of(focused) else ""
	UIKit.clear(self)
	_rows.clear()
	var h := UIKit.hbox(40)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(h)
	var left := UIKit.vbox(10)
	left.custom_minimum_size.x = 380
	h.add_child(left)
	left.add_child(UIKit.section("Audio"))
	left.add_child(_slider("Master volume", Settings.master_volume, func(v: float) -> void: Settings.master_volume = v))
	left.add_child(_slider("Effects volume", Settings.sfx_volume, func(v: float) -> void: Settings.sfx_volume = v))
	left.add_child(_slider("Ambience volume", Settings.ambient_volume, func(v: float) -> void: Settings.ambient_volume = v))
	left.add_child(UIKit.section("Graphics & performance"))
	left.add_child(_choice("Graphics quality", [["High", "high"], ["Medium", "medium"], ["Low", "low"]], Settings.quality, func(v) -> void: Settings.quality = str(v)))
	var qhint := UIKit.label("High = full shadows · Medium = lighter shadows · Low = no shadows/glow (best FPS on older Macs).", 11, UIKit.C_MUTED)
	qhint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(qhint)
	left.add_child(_choice("Frame-rate cap", [["Off", 0], ["30", 30], ["60", 60], ["120", 120]], Settings.max_fps, func(v) -> void: Settings.max_fps = int(v)))
	left.add_child(_check("VSync (no tearing)", Settings.vsync, func(v: bool) -> void: Settings.vsync = v))
	left.add_child(_check("Fullscreen", Settings.fullscreen, func(v: bool) -> void: Settings.fullscreen = v))
	left.add_child(UIKit.section("Feedback"))
	left.add_child(_check("Screen shake", Settings.screen_shake, func(v: bool) -> void: Settings.screen_shake = v))
	left.add_child(_check("Damage numbers", Settings.damage_numbers, func(v: bool) -> void: Settings.damage_numbers = v))
	left.add_child(_check("Controller vibration", Settings.vibration, func(v: bool) -> void: Settings.vibration = v))
	left.add_child(_check("Controller aim assist", Settings.aim_assist, func(v: bool) -> void: Settings.aim_assist = v))
	var right := UIKit.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(right)
	right.add_child(UIKit.section("Controls  ·  select a binding, then press the new key / button"))
	var table := GridContainer.new()
	table.columns = 3
	table.add_theme_constant_override("h_separation", 10)
	table.add_theme_constant_override("v_separation", 6)
	right.add_child(table)
	table.add_child(UIKit.label("Action", 12, UIKit.C_MUTED, true))
	table.add_child(UIKit.label("Keyboard & mouse", 12, UIKit.C_MUTED, true))
	table.add_child(UIKit.label("Controller", 12, UIKit.C_MUTED, true))
	for a in Settings.ACTION_ORDER:
		var l := UIKit.label(str(Settings.ACTIONS[a].label), 14)
		l.custom_minimum_size.x = 150
		table.add_child(l)
		var kb := UIKit.button(Settings.binding_text(a), _start_rebind.bind(a, false), "default", 160)
		kb.set_meta("focus_key", "kb:" + a)
		_rows["kb:" + a] = kb
		table.add_child(kb)
		if Settings.PAD_ACTIONS.has(a):
			var pb := UIKit.button(Controls.pad_text(a), _start_rebind.bind(a, true), "default", 140)
			pb.set_meta("focus_key", "pad:" + a)
			_rows["pad:" + a] = pb
			table.add_child(pb)
		else:
			table.add_child(UIKit.label("Left stick" if a.begins_with("move") else "-", 13, UIKit.C_MUTED))
	var hint := UIKit.label("Arrow keys always move too. Controller layout follows Minecraft Dungeons II: right-stick flick also dodges, LB/RB switch tabs in menus, B goes back.", 12, UIKit.C_MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(hint)
	right.add_child(UIKit.button("Reset controls to defaults", func() -> void:
		Settings.reset_bindings()
		Settings.apply_bindings()
		Settings.save_settings()
		_build.call_deferred()))
	if focus_key != "":
		(func() -> void: UIKit.restore_focus(self, focus_key)).call_deferred()


func _apply_and_save() -> void:
	Settings.apply()
	Settings.save_settings()


func _slider(text: String, value: float, setter: Callable) -> Control:
	var v := UIKit.vbox(2)
	v.add_child(UIKit.label(text, 13, UIKit.C_MUTED))
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = value
	s.custom_minimum_size = Vector2(320, 24)
	s.focus_mode = Control.FOCUS_ALL
	s.set_meta("focus_key", "slider:" + text)
	s.value_changed.connect(func(x: float) -> void:
		setter.call(x)
		_apply_and_save())
	v.add_child(s)
	return v


func _check(text: String, value: bool, setter: Callable) -> Control:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_ALL
	c.set_meta("focus_key", "check:" + text)
	c.toggled.connect(func(x: bool) -> void:
		setter.call(x)
		_apply_and_save())
	return c


func _choice(text: String, options: Array, current: Variant, setter: Callable) -> Control:
	var v := UIKit.vbox(4)
	v.add_child(UIKit.label(text, 13, UIKit.C_MUTED))
	var row := UIKit.hbox(6)
	v.add_child(row)
	for o in options:
		var value: Variant = o[1]
		var b := UIKit.button(str(o[0]), func() -> void:
			setter.call(value)
			_apply_and_save()
			_build.call_deferred(), "primary" if str(value) == str(current) else "default", 64)
		b.set_meta("focus_key", "choice:%s:%s" % [text, str(value)])
		row.add_child(b)
	return v


func _start_rebind(action: String, pad: bool) -> void:
	_waiting_action = action
	_waiting_pad = pad
	var b: Button = _rows.get(("pad:" if pad else "kb:") + action)
	if b:
		b.text = "Press a button..." if pad else "Press a key..."


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not is_visible_in_tree():
		return
	var ok := false
	if _waiting_pad:
		if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_waiting_action = ""
			_build.call_deferred()
			return
		if event is InputEventJoypadButton and event.pressed:
			ok = Settings.rebind_pad(_waiting_action, event)
		elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.6:
			ok = Settings.rebind_pad(_waiting_action, event)
	else:
		if event is InputEventKey and event.pressed and not event.echo:
			ok = Settings.rebind(_waiting_action, event)
		elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_XBUTTON1, MOUSE_BUTTON_XBUTTON2]:
			ok = Settings.rebind(_waiting_action, event)
	if not ok:
		return
	get_viewport().set_input_as_handled()
	_waiting_action = ""
	_build.call_deferred()
