extends Node
## Player preferences: rebindable controls (keyboard/mouse and controller),
## audio volumes, video, graphics quality and frame-rate options.
## Stored in user://settings.json.

const PATH := "user://settings.json"

const ACTIONS := {
	"move_up": {"label": "Move Up", "type": "key", "code": KEY_W},
	"move_down": {"label": "Move Down", "type": "key", "code": KEY_S},
	"move_left": {"label": "Move Left", "type": "key", "code": KEY_A},
	"move_right": {"label": "Move Right", "type": "key", "code": KEY_D},
	"attack": {"label": "Attack", "type": "mouse", "code": MOUSE_BUTTON_LEFT},
	"dodge": {"label": "Dodge Roll", "type": "mouse", "code": MOUSE_BUTTON_RIGHT},
	"special": {"label": "Special Ability", "type": "key", "code": KEY_Q},
	"interact": {"label": "Interact", "type": "key", "code": KEY_E},
	"inventory": {"label": "Inventory", "type": "key", "code": KEY_I},
	"network_map": {"label": "Network Map", "type": "key", "code": KEY_M},
	"pause": {"label": "Pause Menu", "type": "key", "code": KEY_ESCAPE},
}
const ACTION_ORDER := ["move_up", "move_down", "move_left", "move_right", "attack", "dodge", "special", "interact", "inventory", "network_map", "pause"]

## Controller defaults follow Minecraft Dungeons II (left stick move, X melee,
## LB / right-stick flick dodge, Y artifact, A interact, D-pad Up inventory,
## View map, Menu pause). Movement on the left stick is fixed.
const PAD_ACTIONS := {
	"attack": {"label": "Melee Attack", "type": "pad_button", "code": JOY_BUTTON_X},
	"dodge": {"label": "Dodge Roll", "type": "pad_button", "code": JOY_BUTTON_LEFT_SHOULDER},
	"special": {"label": "Special (Artifact)", "type": "pad_button", "code": JOY_BUTTON_Y},
	"interact": {"label": "Interact", "type": "pad_button", "code": JOY_BUTTON_A},
	"inventory": {"label": "Inventory", "type": "pad_button", "code": JOY_BUTTON_DPAD_UP},
	"network_map": {"label": "Network Map", "type": "pad_button", "code": JOY_BUTTON_BACK},
	"pause": {"label": "Pause Menu", "type": "pad_button", "code": JOY_BUTTON_START},
}
const PAD_ORDER := ["attack", "dodge", "special", "interact", "inventory", "network_map", "pause"]
const QUALITY_LEVELS := ["high", "medium", "low"]
const FPS_CAPS := [0, 30, 60, 120]

var bindings: Dictionary = {}
var pad_bindings: Dictionary = {}
var master_volume := 0.8
var sfx_volume := 0.8
var ambient_volume := 0.6
var fullscreen := false
var vsync := true
var max_fps := 0
var quality := "high"
var screen_shake := true
var damage_numbers := true
var vibration := true
var aim_assist := true
var last_slot := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	reset_bindings()
	load_settings()
	apply()


func _ensure_buses() -> void:
	for bus_name in ["SFX", "Ambient"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")


func reset_bindings() -> void:
	bindings.clear()
	for a in ACTIONS:
		bindings[a] = {"type": ACTIONS[a].type, "code": int(ACTIONS[a].code)}
	pad_bindings.clear()
	for a in PAD_ACTIONS:
		pad_bindings[a] = {"type": PAD_ACTIONS[a].type, "code": int(PAD_ACTIONS[a].code)}


func apply() -> void:
	apply_bindings()
	_set_bus("Master", master_volume)
	_set_bus("SFX", sfx_volume)
	_set_bus("Ambient", ambient_volume)
	Engine.max_fps = max_fps
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	if vp:
		vp.msaa_3d = Viewport.MSAA_DISABLED if quality == "low" else Viewport.MSAA_2X
	var w = GameState.world if get_node_or_null("/root/GameState") else null
	if w != null and is_instance_valid(w):
		w.apply_quality()


func _set_bus(bus_name: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func apply_bindings() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.2)
		InputMap.action_erase_events(a)
		InputMap.action_add_event(a, make_event(bindings[a]))
		if pad_bindings.has(a):
			InputMap.action_add_event(a, make_event(pad_bindings[a]))
	# Fixed secondary bindings: arrow keys and the left stick always move.
	var arrows := {"move_up": KEY_UP, "move_down": KEY_DOWN, "move_left": KEY_LEFT, "move_right": KEY_RIGHT}
	for a in arrows:
		InputMap.action_add_event(a, make_event({"type": "key", "code": arrows[a]}))
	var stick := {"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0], "move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0]}
	for a in stick:
		var m := InputEventJoypadMotion.new()
		m.axis = stick[a][0]
		m.axis_value = stick[a][1]
		InputMap.action_add_event(a, m)
	_ensure_ui_actions()


func _ensure_ui_actions() -> void:
	## Menu navigation on a controller: D-pad or left stick move focus, A confirms,
	## B goes back, LB/RB switch app tabs.
	var extra := {
		"ui_accept": [_pad(JOY_BUTTON_A)],
		"ui_cancel": [_pad(JOY_BUTTON_B)],
		"ui_up": [_pad(JOY_BUTTON_DPAD_UP), _axis(JOY_AXIS_LEFT_Y, -1.0)],
		"ui_down": [_pad(JOY_BUTTON_DPAD_DOWN), _axis(JOY_AXIS_LEFT_Y, 1.0)],
		"ui_left": [_pad(JOY_BUTTON_DPAD_LEFT), _axis(JOY_AXIS_LEFT_X, -1.0)],
		"ui_right": [_pad(JOY_BUTTON_DPAD_RIGHT), _axis(JOY_AXIS_LEFT_X, 1.0)],
		"ui_tab_prev": [_pad(JOY_BUTTON_LEFT_SHOULDER)],
		"ui_tab_next": [_pad(JOY_BUTTON_RIGHT_SHOULDER)],
	}
	for a in extra:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.5)
		for ev in extra[a]:
			if not InputMap.action_has_event(a, ev):
				InputMap.action_add_event(a, ev)


func _pad(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button as JoyButton
	return e


func _axis(axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.axis = axis as JoyAxis
	e.axis_value = value
	return e


func make_event(b: Dictionary) -> InputEvent:
	match str(b.get("type", "key")):
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(b.code) as MouseButton
			return m
		"pad_button":
			return _pad(int(b.code))
		"pad_axis":
			return _axis(int(b.code), float(b.get("value", 1.0)))
	var k := InputEventKey.new()
	k.physical_keycode = int(b.code) as Key
	return k


func binding_text(action: String) -> String:
	var b: Dictionary = bindings.get(action, {})
	if b.is_empty():
		return "-"
	if str(b.type) == "mouse":
		match int(b.code):
			MOUSE_BUTTON_LEFT: return "Left Mouse"
			MOUSE_BUTTON_RIGHT: return "Right Mouse"
			MOUSE_BUTTON_MIDDLE: return "Middle Mouse"
			_: return "Mouse %d" % int(b.code)
	return OS.get_keycode_string(int(b.code))


func rebind(action: String, event: InputEvent) -> bool:
	## Keyboard/mouse binding (InputEventKey / InputEventMouseButton).
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := int(k.physical_keycode) if k.physical_keycode != 0 else int(k.keycode)
		bindings[action] = {"type": "key", "code": code}
	elif event is InputEventMouseButton:
		bindings[action] = {"type": "mouse", "code": int((event as InputEventMouseButton).button_index)}
	else:
		return false
	apply_bindings()
	save_settings()
	return true


func rebind_pad(action: String, event: InputEvent) -> bool:
	## Controller binding: a face/shoulder/D-pad button or a trigger.
	if event is InputEventJoypadButton:
		pad_bindings[action] = {"type": "pad_button", "code": int((event as InputEventJoypadButton).button_index)}
	elif event is InputEventJoypadMotion and (event as InputEventJoypadMotion).axis in [JOY_AXIS_TRIGGER_LEFT, JOY_AXIS_TRIGGER_RIGHT]:
		pad_bindings[action] = {"type": "pad_axis", "code": int((event as InputEventJoypadMotion).axis), "value": 1.0}
	else:
		return false
	apply_bindings()
	save_settings()
	return true


func save_settings() -> void:
	var data := {
		"bindings": bindings, "pad_bindings": pad_bindings, "master_volume": master_volume, "sfx_volume": sfx_volume,
		"ambient_volume": ambient_volume, "fullscreen": fullscreen, "vsync": vsync, "max_fps": max_fps, "quality": quality,
		"screen_shake": screen_shake, "damage_numbers": damage_numbers, "vibration": vibration, "aim_assist": aim_assist,
		"last_slot": last_slot,
	}
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not parsed is Dictionary:
		return
	var d: Dictionary = parsed
	var saved: Dictionary = d.get("bindings", {})
	for a in saved:
		if ACTIONS.has(a) and saved[a] is Dictionary:
			bindings[a] = {"type": str(saved[a].get("type", "key")), "code": int(saved[a].get("code", 0))}
	var saved_pad: Dictionary = d.get("pad_bindings", {})
	for a in saved_pad:
		if PAD_ACTIONS.has(a) and saved_pad[a] is Dictionary:
			pad_bindings[a] = {"type": str(saved_pad[a].get("type", "pad_button")), "code": int(saved_pad[a].get("code", 0)), "value": float(saved_pad[a].get("value", 1.0))}
	master_volume = float(d.get("master_volume", master_volume))
	sfx_volume = float(d.get("sfx_volume", sfx_volume))
	ambient_volume = float(d.get("ambient_volume", ambient_volume))
	fullscreen = bool(d.get("fullscreen", fullscreen))
	vsync = bool(d.get("vsync", vsync))
	max_fps = int(d.get("max_fps", max_fps))
	quality = str(d.get("quality", quality)) if str(d.get("quality", quality)) in QUALITY_LEVELS else "high"
	screen_shake = bool(d.get("screen_shake", screen_shake))
	damage_numbers = bool(d.get("damage_numbers", damage_numbers))
	vibration = bool(d.get("vibration", vibration))
	aim_assist = bool(d.get("aim_assist", aim_assist))
	last_slot = int(d.get("last_slot", last_slot))
