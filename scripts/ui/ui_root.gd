class_name UIRoot
extends CanvasLayer
## Owns every screen: main menu, onboarding, HUD, app window, dialogs, pause,
## death screen, fades and the CRT post-processing layer.

const POST_SHADER := preload("res://shaders/post.gdshader")

var root: Control
var interact_block_until := 0  # msec; set when B (also Interact) closes a menu
var hud: HUD
var toasts: Toasts
var app: AppWindow
var icons: IconCache
var menu_layer: Control
var dialog_layer: Control
var pause_menu: Control
var death_screen: Control
var fade: ColorRect
var post_layer: CanvasLayer
var post_mat: ShaderMaterial
var mode := "menu"
var _glitch := 0.0
var _damage := 0.0
var _post_base: Dictionary = {}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.ui = self
	UIKit.init_fonts()
	post_layer = CanvasLayer.new()
	post_layer.layer = 5
	add_child(post_layer)
	var pr := ColorRect.new()
	pr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST_SHADER
	pr.material = post_mat
	post_layer.add_child(pr)
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.build_theme()
	add_child(root)
	icons = IconCache.new()
	add_child(icons)
	hud = HUD.new()
	root.add_child(hud)
	toasts = Toasts.new()
	root.add_child(toasts)
	app = AppWindow.new()
	root.add_child(app)
	dialog_layer = Control.new()
	dialog_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dialog_layer)
	pause_menu = _build_pause()
	root.add_child(pause_menu)
	death_screen = _build_death()
	root.add_child(death_screen)
	menu_layer = Control.new()
	menu_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(menu_layer)
	fade = ColorRect.new()
	fade.color = Color(0.02, 0.02, 0.03, 1.0)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade)
	fade.modulate.a = 0.0
	hud.visible = false
	toasts.visible = false
	Controls.device_changed.connect(_on_device_changed)


func _process(delta: float) -> void:
	_glitch = maxf(0.0, _glitch - delta * 1.5)
	_damage = maxf(0.0, _damage - delta * 1.8)
	post_mat.set_shader_parameter("glitch", float(_post_base.get("glitch", 0.0)) + _glitch)
	post_mat.set_shader_parameter("aberration", _glitch * 1.5 + _damage)
	post_mat.set_shader_parameter("damage", _damage)


func apply_post(p: Dictionary) -> void:
	_post_base = p
	post_mat.set_shader_parameter("vignette", float(p.get("vignette", 0.35)))
	# every level gets at least a gentle scanline and a little grain (art direction)
	post_mat.set_shader_parameter("scanline", maxf(0.025, float(p.get("scanline", 0.04))))
	post_mat.set_shader_parameter("grain", float(p.get("grain", 0.035)))
	post_mat.set_shader_parameter("tint", MeshFactory.col(p.get("tint", "#ffffff")))


func glitch_spike(amount: float) -> void:
	_glitch = maxf(_glitch, amount)


func damage_flash(amount: float) -> void:
	_damage = maxf(_damage, amount)


# ------------------------------------------------------------------ modes

func show_main_menu() -> void:
	mode = "menu"
	hud.visible = false
	toasts.visible = false
	app.visible = false
	pause_menu.visible = false
	death_screen.visible = false
	UIKit.clear(dialog_layer)
	UIKit.clear(menu_layer)
	menu_layer.add_child(MainMenu.new())
	refresh_pause()
	focus_default()


func show_char_create() -> void:
	UIKit.clear(menu_layer)
	menu_layer.add_child(CharCreate.new())
	focus_default()


func enter_play_mode() -> void:
	mode = "playing"
	UIKit.clear(menu_layer)
	hud.visible = true
	toasts.visible = true
	refresh_pause()


func on_level_loaded() -> void:
	var w = GameState.world
	if w == null:
		return
	hud.refresh()
	hud.show_banner(str(w.level.get("name", "")), str(w.level.get("subtitle", "")))


func is_blocking() -> bool:
	return app.visible or pause_menu.visible or death_screen.visible or dialog_layer.get_child_count() > 0


func refresh_pause() -> void:
	get_tree().paused = mode == "playing" and is_blocking()
	if mode == "playing" and is_blocking():
		hud.set_prompt("")  # the world is paused: hide "[E] ..." until the player scans again


func set_prompt(text: String) -> void:
	if hud.visible:
		hud.set_prompt(text)


func open_app(tab: String, ctx: Dictionary = {}) -> void:
	if mode != "playing" or death_screen.visible:
		return
	pause_menu.visible = false
	app.open(tab, ctx)
	refresh_pause()
	focus_default()


func toggle_pause() -> void:
	if mode != "playing" or death_screen.visible:
		return
	if app.visible:
		app.close_window()
		return
	if dialog_layer.get_child_count() > 0:
		UIKit.clear(dialog_layer)
		refresh_pause()
		return
	pause_menu.visible = not pause_menu.visible
	refresh_pause()
	focus_default()


# ------------------------------------------------------------------ controller focus

func _on_device_changed(gamepad: bool) -> void:
	UIKit.set_focus_visible(root.theme, gamepad)
	if gamepad:
		focus_default()
	else:
		get_viewport().gui_release_focus()


func focus_default() -> void:
	## With a controller, put focus on the most relevant button of whatever screen
	## is on top (deferred so freshly built menus exist first).
	if Controls.gamepad:
		_focus_top.call_deferred()


func _focus_top() -> void:
	var owner := get_viewport().gui_get_focus_owner()
	var top: Control = null
	if death_screen.visible:
		top = death_screen
	elif dialog_layer.get_child_count() > 0:
		top = dialog_layer
	elif pause_menu.visible:
		top = pause_menu
	elif app.visible:
		if owner == null or not app.is_ancestor_of(owner):
			app.focus_default()
		return
	elif menu_layer.get_child_count() > 0:
		top = menu_layer
	if top == null or (owner != null and top.is_ancestor_of(owner)):
		return
	var preferred: Control = null
	for n in top.find_children("*", "Button", true, false):
		if n.has_meta("default_focus") and (n as Control).is_visible_in_tree():
			preferred = n
			break
	if preferred:
		preferred.grab_focus()
	else:
		UIKit.focus_first(top)


func _is_dpad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]


func _unhandled_input(event: InputEvent) -> void:
	if mode == "playing" and event.is_action_pressed("ui_cancel") and event is InputEventJoypadButton:
		# B backs out of whatever is open (Esc keeps toggling the pause menu).
		if app.visible or dialog_layer.get_child_count() > 0 or pause_menu.visible:
			toggle_pause()
			get_viewport().set_input_as_handled()
			# B is also Interact: don't let the press that closed the menu reach the
			# player and reopen a terminal or desk they are standing next to.
			interact_block_until = Time.get_ticks_msec() + 250
			return
	if mode != "playing":
		return
	if (app.visible or pause_menu.visible or dialog_layer.get_child_count() > 0) and _is_dpad(event):
		return  # the D-pad navigates menus; it only opens the inventory during play
	if event.is_action_pressed("pause"):
		toggle_pause()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory") and not death_screen.visible:
		if app.visible and app.tab == "inventory":
			app.close_window()
		else:
			open_app("inventory")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("network_map") and not death_screen.visible:
		if app.visible and app.tab == "network":
			app.close_window()
		else:
			open_app("network")
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ transitions

func fade_out(t: float) -> void:
	fade.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 1.0, t)
	await tw.finished


func fade_in(t: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "modulate:a", 0.0, t)
	await tw.finished
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE


# ------------------------------------------------------------------ dialogs

func _modal(width: float, height: float) -> Array:
	UIKit.clear(dialog_layer)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog_layer.add_child(dim)
	var card := UIKit.panel(Color.WHITE, 12, 22)
	UIKit.place(card, 0.5, 0.5, 0.5, 0.5, -width * 0.5, -height * 0.5, width * 0.5, height * 0.5)
	dialog_layer.add_child(card)
	var v := UIKit.vbox(12)
	card.add_child(v)
	refresh_pause()
	return [card, v]


func close_dialog() -> void:
	UIKit.clear(dialog_layer)
	refresh_pause()


func show_dungeon_invite(dungeon_id: String) -> void:
	var d: Dictionary = DB.dungeons.get(dungeon_id, {})
	if d.is_empty():
		return
	var parts := _modal(620, 420)
	var v: VBoxContainer = parts[1]
	var head := UIKit.hbox(12)
	v.add_child(head)
	var cal := PanelContainer.new()
	cal.add_theme_stylebox_override("panel", UIKit.sb(Color("#c8343c"), 8, 0, Color.TRANSPARENT, 8))
	cal.custom_minimum_size = Vector2(64, 64)
	var cl := UIKit.vbox(0)
	cal.add_child(cl)
	var mon := UIKit.label("TODAY", 11, Color.WHITE, true)
	mon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.add_child(mon)
	var day := UIKit.label("NOW", 20, Color.WHITE, true)
	day.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cl.add_child(day)
	head.add_child(cal)
	var hv := UIKit.vbox(2)
	head.add_child(hv)
	hv.add_child(UIKit.label("Meeting invitation", 12, UIKit.C_MUTED, true))
	hv.add_child(UIKit.label(str(d.get("meeting_title", "Meeting")), 20, UIKit.C_TEXT, true))
	hv.add_child(UIKit.label("Organizer: %s" % str(d.get("organizer", "?")), 13, UIKit.C_DANGER, true))
	var info := UIKit.rich("[b]Location:[/b] %s\n[b]Recommended:[/b] DATA Level %d   [b]Threat:[/b] [color=#c8343c]%s[/color]   [b]Your clearance:[/b] Tier %d\n\n[color=#6e6b66]%s[/color]\n\n[color=#6e6b66]You can leave through the golden terminal at the entrance, and death simply sends you back to the Lobby with everything you own.[/color]" % [str(d.get("location", "")), int(d.get("recommended_level", 1)), str(d.get("threat", "HIGH")), GameState.clearance(), str(d.get("description", ""))])
	v.add_child(info)
	v.add_child(UIKit.spacer())
	var btns := UIKit.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btns)
	btns.add_child(UIKit.button("Decline", close_dialog, "default", 130))
	var accept := UIKit.button("Accept & Join", func() -> void:
		close_dialog()
		Audio.play("teleport")
		GameState.main.travel(str(d.get("level", "")), {"type": "start"}), "danger", 170)
	accept.set_meta("default_focus", true)
	btns.add_child(accept)
	focus_default()


func show_confirm(title: String, text: String, yes_text: String, on_yes: Callable) -> void:
	var parts := _modal(520, 240)
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label(title, 20, UIKit.C_TEXT, true))
	var l := UIKit.label(text, 14, UIKit.C_MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	v.add_child(UIKit.spacer())
	var btns := UIKit.hbox(10)
	btns.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(btns)
	btns.add_child(UIKit.button("Cancel", close_dialog, "default", 120))
	var yes := UIKit.button(yes_text, func() -> void:
		close_dialog()
		on_yes.call(), "primary", 160)
	yes.set_meta("default_focus", true)
	btns.add_child(yes)
	focus_default()


# ------------------------------------------------------------------ pause & death

func _build_pause() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.02, 0.06, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(dim)
	var card := UIKit.panel(Color.WHITE, 14, 26)
	UIKit.place(card, 0.5, 0.5, 0.5, 0.5, -220, -270, 220, 270)
	c.add_child(card)
	var v := UIKit.vbox(10)
	card.add_child(v)
	var head := UIKit.hbox(10)
	v.add_child(head)
	head.add_child(UIKit.avatar("||", Color("#d99a1c"), 40, Color("#d99a1c")))
	var hv := UIKit.vbox(0)
	head.add_child(hv)
	hv.add_child(UIKit.label("You appear to be away", 18, UIKit.C_TEXT, true))
	hv.add_child(UIKit.label("Status: Be right back", 12, Color("#d99a1c"), true))
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	v.add_child(sp)
	v.add_child(UIKit.button("Resume", toggle_pause, "primary"))
	v.add_child(UIKit.button("Inventory & Equipment", func() -> void: open_app("inventory")))
	v.add_child(UIKit.button("Save Game", func() -> void:
		if GameState.save_game():
			GameState.notify("IT Helpdesk", "Progress saved to slot %d." % (int(GameState.profile.slot) + 1), "success")))
	v.add_child(UIKit.button("Settings", func() -> void: open_app("settings")))
	v.add_child(UIKit.button("Return to the Lobby", func() -> void:
		pause_menu.visible = false
		refresh_pause()
		GameState.main.travel(str(DB.manifest.get("hub_level", "hub")), {"type": "start"})))
	v.add_child(UIKit.button("Save & Quit to Title", func() -> void:
		GameState.save_game()
		pause_menu.visible = false
		GameState.main.go_to_menu()))
	v.add_child(UIKit.button("Save & Quit to Desktop", func() -> void:
		GameState.save_game()
		get_tree().quit(), "danger"))
	c.visible = false
	return c


func _build_death() -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.12, 0.0, 0.03, 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.add_child(dim)
	var v := UIKit.vbox(14)
	UIKit.place(v, 0.5, 0.5, 0.5, 0.5, -360, -150, 360, 150)
	c.add_child(v)
	var t := UIKit.label("SESSION TERMINATED", 46, Color("#ff5a6a"), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UIKit.label("Your connection to the simulation was lost.\nIT has preserved all of your DATA, Gold, Corrupted Gold, equipment and unlocked terminals.", 16, Color(1, 0.9, 0.92))
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	var b := UIKit.button("Reconnect at the Lobby", respawn, "primary", 260)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	c.visible = false
	return c


func show_death() -> void:
	app.visible = false
	pause_menu.visible = false
	UIKit.clear(dialog_layer)
	death_screen.visible = true
	focus_default()
	death_screen.modulate.a = 0.0
	create_tween().tween_property(death_screen, "modulate:a", 1.0, 0.6)
	glitch_spike(1.5)
	refresh_pause()


func respawn() -> void:
	death_screen.visible = false
	refresh_pause()
	GameState.main.travel(str(DB.manifest.get("hub_level", "hub")), {"type": "start"})
