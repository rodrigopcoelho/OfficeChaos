class_name CharacterPreview
extends SubViewportContainer
## Rotating 3D preview of a character (onboarding form and profile page).

var vp: SubViewport
var figure: CharacterVisual
var spin_speed := 0.6
var _t := 0.0
var _pending_app: Variant = null
var _pending_gear: Dictionary = {}


func _init(sz: Vector2 = Vector2(300, 380)) -> void:
	custom_minimum_size = sz
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(custom_minimum_size)
	add_child(vp)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#a58ed8")  # same lavender shadow tint as the Lobby
	env.ambient_light_energy = 0.62
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	we.environment = env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 0.5
	key.shadow_enabled = true
	vp.add_child(key)
	var rim := OmniLight3D.new()
	rim.position = Vector3(-1.5, 2.5, -1.5)
	rim.light_color = Color("#9a8cff")
	rim.light_energy = 2.0
	vp.add_child(rim)
	var floor_mi := MeshInstance3D.new()
	floor_mi.mesh = MeshFactory.mesh_for("cyl", Vector3(1.6, 0.08, 1.6))
	floor_mi.material_override = MeshFactory.clay(Color("#d6d2c4"), 0.0, 0.0)
	floor_mi.position.y = -0.04
	vp.add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 1.5, 4.3)
	cam.rotation_degrees.x = -9
	vp.add_child(cam)
	figure = CharacterVisual.new()
	vp.add_child(figure)
	# Callers may configure the preview before it enters the tree (or connect to
	# `ready` too late); apply whatever was requested so far.
	if _pending_app != null:
		set_appearance(_pending_app)
	if not _pending_gear.is_empty():
		set_gear(_pending_gear)


func set_appearance(app: Dictionary) -> void:
	_pending_app = app
	if figure == null:
		return
	figure.build(app)
	figure.rotation.y = PI + 0.4
	if not _pending_gear.is_empty():
		figure.set_gear(_pending_gear)


func set_gear(gear: Dictionary) -> void:
	## {slot: item instance}, see CharacterVisual.set_gear.
	_pending_gear = gear
	if figure == null or figure.body == null:
		return
	figure.set_gear(gear)


func set_equipment(w: Dictionary, a: Dictionary, c: Dictionary) -> void:
	set_gear({"weapon": w, "chest": a, "accessory": c})


func _process(delta: float) -> void:
	_t += delta
	if figure:
		figure.rotation.y += delta * spin_speed
		figure.animate(0.0, delta)
