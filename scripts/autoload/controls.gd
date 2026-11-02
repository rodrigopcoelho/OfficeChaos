extends Node
## Tracks which device the player is using (mouse & keyboard vs controller) and
## provides controller helpers: right-stick flick detection (dodge, as in
## Minecraft Dungeons II), button-prompt labels for the HUD, and rumble.

signal device_changed(gamepad: bool)

const PAD_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "View", JOY_BUTTON_GUIDE: "Guide", JOY_BUTTON_START: "Menu",
	JOY_BUTTON_LEFT_STICK: "LS", JOY_BUTTON_RIGHT_STICK: "RS",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_DPAD_UP: "D-pad Up", JOY_BUTTON_DPAD_DOWN: "D-pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-pad Left", JOY_BUTTON_DPAD_RIGHT: "D-pad Right",
}
const FLICK_ON := 0.8
const FLICK_OFF := 0.35

var gamepad := false
var device := 0
var right_stick := Vector2.ZERO
var _flick_armed := true
var _pending_flick := Vector2.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		var m := event as InputEventJoypadMotion
		device = m.device
		if m.axis == JOY_AXIS_RIGHT_X:
			right_stick.x = m.axis_value
		elif m.axis == JOY_AXIS_RIGHT_Y:
			right_stick.y = m.axis_value
		if absf(m.axis_value) > 0.5:
			_set_gamepad(true)
		_track_flick()
	elif event is InputEventJoypadButton:
		if event.pressed:
			device = event.device
			_set_gamepad(true)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 3.0:
			_set_gamepad(false)
	elif event is InputEventMouseButton or event is InputEventKey:
		if event.is_pressed():
			_set_gamepad(false)


func _set_gamepad(v: bool) -> void:
	if v == gamepad:
		return
	gamepad = v
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if v else Input.MOUSE_MODE_VISIBLE
	device_changed.emit(v)


func _track_flick() -> void:
	## A quick push of the right stick past FLICK_ON queues one dodge in that direction;
	## it re-arms once the stick returns near the centre.
	var mag := right_stick.length()
	if _flick_armed and mag >= FLICK_ON:
		_flick_armed = false
		_pending_flick = right_stick.normalized()
	elif mag <= FLICK_OFF:
		_flick_armed = true


func consume_flick() -> Vector2:
	var f := _pending_flick
	_pending_flick = Vector2.ZERO
	return f


func prompt(action: String) -> String:
	## Label of the button bound to `action` on the device currently in use.
	return pad_text(action) if gamepad else Settings.binding_text(action)


func pad_text(action: String) -> String:
	var b: Dictionary = Settings.pad_bindings.get(action, {})
	if b.is_empty():
		return "-"
	if str(b.get("type", "")) == "pad_axis":
		match int(b.code):
			JOY_AXIS_TRIGGER_LEFT: return "LT"
			JOY_AXIS_TRIGGER_RIGHT: return "RT"
		return "Axis %d" % int(b.code)
	return str(PAD_NAMES.get(int(b.code), "Button %d" % int(b.code)))


func rumble(weak: float, strong: float, duration: float) -> void:
	if gamepad and Settings.vibration and Input.get_connected_joypads().has(device):
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)
