class_name AvatarPortrait
extends Control
## Messenger-style round profile picture rendered from the character model. The
## SubViewport only re-renders when the look or the expression changes, so the
## portrait costs nothing per frame while still pulling faces when you get hit.

const RENDER_PX := 128
const MASK_SHADER: Shader = preload("res://shaders/avatar_mask.gdshader")

var vp: SubViewport
var figure: CharacterVisual
var _cam: Camera3D
var _env: Environment
var _pending: Array = []  # [appearance, armor] requested before _ready


func _init(px: float = 56.0) -> void:
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	vp = SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.size = Vector2i(RENDER_PX, RENDER_PX)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color("#b9b0dd")
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color("#a58ed8")
	_env.ambient_light_energy = 0.62
	_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = _env
	vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -20, 0)
	key.light_energy = 0.5
	vp.add_child(key)
	_cam = Camera3D.new()
	_cam.fov = 26.0
	vp.add_child(_cam)
	figure = CharacterVisual.new()
	vp.add_child(figure)
	var tex := TextureRect.new()
	tex.texture = vp.get_texture()
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = MASK_SHADER
	tex.material = mat
	add_child(tex)
	if not _pending.is_empty():
		show_profile(_pending[0], _pending[1])


func show_profile(appearance: Dictionary, armor: Dictionary = {}) -> void:
	_pending = [appearance, armor]
	if figure == null:
		return
	figure.build(appearance)
	figure.set_equipment({}, armor, {})
	figure.rotation.y = PI + 0.3
	var pal: Dictionary = figure.palette
	_env.background_color = MeshFactory.col(pal.get("suit", "#6656c9")).lerp(Color("#e8e4f4"), 0.55)
	# Frame head and shoulders: the head's centre in the figure's space.
	var head_c := (figure.head.position + figure.face_mesh.position) * figure.scale.x
	_cam.position = Vector3(0, head_c.y + 0.05, 2.6)
	_cam.look_at(Vector3(0, head_c.y - 0.1, 0), Vector3.UP)
	redraw()


func express(mood: String) -> void:
	if figure == null or figure.body == null:
		return
	figure.express(mood)
	redraw()


func redraw() -> void:
	if vp:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
