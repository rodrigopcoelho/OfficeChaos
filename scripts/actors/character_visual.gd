class_name CharacterVisual
extends Node3D
## Procedural office worker in the Animal Crossing / Pocket Camp style: a big round
## head with a painted face, a small A-line blazer with the shirt, tie and lapels
## painted on (shaders/character.gdshader), stubby limbs, round mitten hands and
## chunky shoes. Used by the player, the hub NPCs and the UI previews.
## Bodies, hairstyles, faces and palettes come from data/appearance.json; equipment
## visuals from item data.

signal expression_changed(mood: String, hold: float)

const CHARACTER_SHADER: Shader = preload("res://shaders/character.gdshader")
const REST_Y := -0.6
const REST_X := -0.25
const HOLD_Z := -0.32       # weapon grip distance in front of the weapon pivot
const ARM_SPLAY := 0.22     # arms hang slightly away from the flared blazer (radians)
const ARM_LEN := 0.36
const HEAD_TILT := 0.15     # chin slightly up so faces read from the high game camera
const LINE := 0.024         # ink line width for character parts
const BLINK_TIME := 0.16
const MOODS := {"neutral": 0, "happy": 1, "hurt": 2, "ko": 3}
const MOUTHS := {"smile": 0, "cat": 1, "open": 2, "flat": 3, "grin": 4}
const GLASSES := {"none": 0, "round": 1, "square": 2}
## Face style keys copied straight into shader uniforms (see appearance.json "faces").
const FACE_FLOATS := ["sclera", "iris", "shine", "lid", "lash", "flick", "brow", "brow_y", "brow_tilt", "mouth_y", "mouth_w", "blush", "nose", "freckles", "bags"]

var body: Node3D
var torso: MeshInstance3D
var head: Node3D
var face_mesh: MeshInstance3D
var leg_l: Node3D
var leg_r: Node3D
var arm_l: Node3D
var arm_r: Node3D
var weapon_pivot: Node3D
var weapon_holder: Node3D
var armor_anchor: Node3D
var offhand: Node3D
var palette: Dictionary = {}
var body_def: Dictionary = {}
var face_def: Dictionary = {}
var walk_t := 0.0
var idle_t := 0.0
var mood := "neutral"
var _swing_tween: Tween
var _suit_color := Color.GRAY
var _face_mat: ShaderMaterial
var _suit_mat: ShaderMaterial
var _blink_in := 2.0   # seconds until the next blink
var _blink_t := -1.0   # time into the current blink, < 0 when the eyes are open
var _mood_t := 0.0     # seconds left on a temporary expression (0 = holds)


func build(appearance: Dictionary) -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	body_def = _pick("bodies", appearance, "body")
	palette = _pick("palettes", appearance, "palette")
	face_def = _pick("faces", appearance, "face")
	var hair := _pick("hair_styles", appearance, "hair")
	var ts := MeshFactory.vec3(body_def.get("torso", [0.64, 0.52, 0.46]))
	var hs := MeshFactory.vec3(body_def.get("head", [0.84, 0.76, 0.76]))
	var leg_len := float(body_def.get("leg_len", 0.3))
	_suit_color = _pc("suit")
	body = Node3D.new()
	add_child(body)
	# Legs: a trouser capsule on a chunky rounded shoe with a darker sole.
	leg_l = _pivot(body, Vector3(-ts.x * 0.2, leg_len, 0))
	leg_r = _pivot(body, Vector3(ts.x * 0.2, leg_len, 0))
	var shoe := _pc("shoes")
	for leg in [leg_l, leg_r]:
		var pant_bottom := -leg_len + 0.15
		_part(leg, "capsule", Vector3(0.2, 0.08 - pant_bottom, 0.21), Vector3(0, (0.08 + pant_bottom) * 0.5, 0), _pc("pants"))
		_part(leg, "dome", Vector3(0.24, 0.17, 0.33), Vector3(0, -leg_len + 0.125, -0.04), shoe)
		_part(leg, "box", Vector3(0.25, 0.05, 0.34), Vector3(0, -leg_len + 0.025, -0.04), shoe.darkened(0.45))
	# Blazer: one mesh whose shirt, tie, lapels and badge are painted by the shader.
	var top := leg_len + ts.y - 0.02
	torso = MeshFactory.kit_instance("blazer", ts)
	torso.position = Vector3(0, top - ts.y * 0.5, 0)
	_suit_mat = _paint_material(2, _suit_color, ts)
	_suit_mat.set_shader_parameter("shirt_color", _pc("shirt"))
	_suit_mat.set_shader_parameter("tie_color", _pc("accent"))
	_suit_mat.set_shader_parameter("badge", 1.0 if bool(body_def.get("badge", true)) else 0.0)
	torso.material_override = _suit_mat
	body.add_child(torso)
	# Armor art was authored for a ~0.7 x 0.42 torso; squeeze it onto this blazer.
	armor_anchor = _pivot(body, Vector3(0, top, 0))
	armor_anchor.scale = Vector3(ts.x / 0.7, 1.0, ts.z / 0.42)
	# Head: the face is painted on the mesh; hair and ears are authored in head units
	# (a 1 x 1 x 1 box around the head's centre, -z = face) and merged into one mesh.
	head = _pivot(body, Vector3(0, top - 0.05, 0))
	head.rotation.x = HEAD_TILT
	var head_shape := str(body_def.get("head_shape", "head"))
	face_mesh = MeshFactory.kit_instance(head_shape, hs)
	face_mesh.position = Vector3(0, hs.y * 0.5, 0)
	_face_mat = _paint_material(1, _pc("skin"), hs)
	_apply_face()
	face_mesh.material_override = _face_mat
	head.add_child(face_mesh)
	var hair_node := _pivot(head, face_mesh.position)
	hair_node.scale = hs
	var parts: Array = (hair.get("parts", []) as Array).duplicate()
	if not bool(hair.get("hide_ears", false)):
		for sx in [-1.0, 1.0]:
			parts.append({"shape": "sphere", "size": [0.14, 0.2, 0.13], "pos": [sx * 0.49, -0.06, 0.02], "color": "skin"})
	MeshFactory.build(parts, hair_node, palette, LINE, {}, true, true)
	# Arms hang from the shoulders, splayed a little; the hands are round mittens.
	var sh_y := top - 0.1
	var sh_x := ts.x * 0.39 + 0.05
	arm_l = _pivot(body, Vector3(-sh_x, sh_y, 0))
	arm_r = _pivot(body, Vector3(sh_x, sh_y, 0))
	for arm in [arm_l, arm_r]:
		var sx := -1.0 if arm == arm_l else 1.0
		var down := Vector3(sx * sin(ARM_SPLAY), -cos(ARM_SPLAY), 0)
		var tilt := Vector3(0, 0, rad_to_deg(sx * ARM_SPLAY))
		_part(arm, "capsule", Vector3(0.17, 0.3, 0.18), down * 0.12, _suit_color, tilt)
		_part(arm, "cyl", Vector3(0.15, 0.05, 0.15), down * 0.27, _pc("shirt"), tilt)
		_part(arm, "sphere", Vector3(0.18, 0.18, 0.18), down * ARM_LEN, _pc("skin"))
	offhand = _pivot(arm_l, Vector3(-sin(ARM_SPLAY), -cos(ARM_SPLAY), 0) * (ARM_LEN + 0.02) + Vector3(0, 0, -0.04))
	weapon_pivot = _pivot(body, Vector3(sh_x * 0.45, sh_y - 0.16, 0))
	weapon_holder = _pivot(weapon_pivot, Vector3(0, 0, HOLD_Z))
	# Each limb renders as one merged mesh; the head and blazer keep their painted materials.
	for limb in [leg_l, leg_r, arm_l, arm_r]:
		MeshBatcher.merge_children(limb)
	_rest_pose()
	mood = "neutral"
	_mood_t = 0.0
	_blink_t = -1.0
	_blink_in = randf_range(1.0, 4.0)
	scale = Vector3.ONE * float(body_def.get("scale", 1.0))


func _pick(list_key: String, appearance: Dictionary, key: String) -> Dictionary:
	var list: Array = DB.appearance.get(list_key, [])
	if list.is_empty():
		return {}
	return list[clampi(int(appearance.get(key, 0)), 0, list.size() - 1)]


func _pc(key: String) -> Color:
	return MeshFactory.col(palette.get(key, "#888888"))


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _part(parent: Node3D, shape: String, size: Vector3, pos: Vector3, color: Color, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshFactory.kit_instance(shape, size)
	mi.material_override = MeshFactory.clay(color, 0.0, MeshFactory.line_width(size, LINE))
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi


func _paint_material(mode: int, color: Color, size: Vector3) -> ShaderMaterial:
	## Per-character material: painted details animate (blink, mood) or recolour (armor).
	var m := ShaderMaterial.new()
	m.shader = CHARACTER_SHADER
	m.set_shader_parameter("paint_mode", mode)
	m.set_shader_parameter("albedo", color)
	m.set_shader_parameter("aspect", size.y / maxf(size.x, 0.01))
	m.set_shader_parameter("ink", MeshFactory.INK)
	# Faces stay readable under the high sun: the shadow edge wraps around under the chin.
	m.set_shader_parameter("light_wrap", 0.6 if mode == 1 else 0.2)
	m.next_pass = MeshFactory.outline_pass(LINE)
	return m


func _apply_face() -> void:
	var f := face_def
	_face_mat.set_shader_parameter("eye_pos", _vec2(f.get("eye_pos", [0.17, -0.02])))
	_face_mat.set_shader_parameter("eye_size", _vec2(f.get("eye_size", [0.066, 0.088])))
	for k in FACE_FLOATS:
		if f.has(k):
			_face_mat.set_shader_parameter(k, float(f[k]))
	_face_mat.set_shader_parameter("mouth", int(MOUTHS.get(str(f.get("mouth", "smile")), 0)))
	_face_mat.set_shader_parameter("glasses", int(GLASSES.get(str(f.get("glasses", "none")), 0)))
	_face_mat.set_shader_parameter("iris_color", MeshFactory.col(f.get("iris_color", palette.get("eyes", "#2a1c18"))))
	_face_mat.set_shader_parameter("glasses_color", MeshFactory.col(f.get("glasses_color", "#2a2236")))
	_face_mat.set_shader_parameter("mouth_color", MeshFactory.col(f.get("mouth_color", "#9c2f3a")))
	_face_mat.set_shader_parameter("blush_color", MeshFactory.col(f.get("blush_color", "#ff7f8a")))


static func _vec2(v: Variant) -> Vector2:
	if v is Array and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2.ZERO


func _rest_pose() -> void:
	if weapon_pivot == null:
		return
	weapon_pivot.rotation = Vector3(REST_X, REST_Y, 0)
	weapon_holder.position = Vector3(0, 0, HOLD_Z)
	arm_r.rotation = Vector3(deg_to_rad(35), REST_Y, 0)


func set_equipment(weapon: Dictionary, armor: Dictionary, accessory: Dictionary) -> void:
	if weapon_holder == null:
		return
	for slot_node in [weapon_holder, armor_anchor, offhand]:
		for c in slot_node.get_children():
			slot_node.remove_child(c)
			c.queue_free()
	if not weapon.is_empty():
		var wd := ItemUtil.def(weapon)
		MeshFactory.build(wd.get("visual", {}).get("parts", []), weapon_holder, {}, 0.01, {}, true, true)
	var suit := _suit_color
	if not armor.is_empty():
		var ad := ItemUtil.def(armor)
		var av: Dictionary = ad.get("visual", {})
		if av.has("torso_color"):
			suit = MeshFactory.col(av.torso_color)
		MeshFactory.build(av.get("parts", []), armor_anchor, {}, 0.015, {}, true, true)
	_suit_mat.set_shader_parameter("albedo", suit)
	if not accessory.is_empty():
		var cd := ItemUtil.def(accessory)
		MeshFactory.build(cd.get("visual", {}).get("parts", []), offhand, {}, 0.01, {}, true, true)


# ------------------------------------------------------------------ face

func express(mood_name: String, hold: float = 0.0) -> void:
	## Shows an expression: "happy", "hurt", "ko" or "neutral". With hold > 0 the face
	## returns to neutral after `hold` seconds; otherwise it stays until changed.
	if not MOODS.has(mood_name):
		mood_name = "neutral"
	mood = mood_name
	_mood_t = hold
	if _face_mat:
		_face_mat.set_shader_parameter("mood", int(MOODS[mood_name]))
		_face_mat.set_shader_parameter("blink", 0.0)
	_blink_t = -1.0
	expression_changed.emit(mood_name, hold)


func _update_face(delta: float) -> void:
	if _mood_t > 0.0:
		_mood_t -= delta
		if _mood_t <= 0.0:
			express("neutral")
	if _face_mat == null or mood != "neutral":
		return
	if _blink_t >= 0.0:
		_blink_t += delta
		var k := clampf(_blink_t / BLINK_TIME, 0.0, 1.0)
		_face_mat.set_shader_parameter("blink", sin(k * PI))
		if k >= 1.0:
			_blink_t = -1.0
			_blink_in = 0.12 if randf() < 0.15 else randf_range(2.0, 5.0)
	else:
		_blink_in -= delta
		if _blink_in <= 0.0:
			_blink_t = 0.0


# ------------------------------------------------------------------ animation

func face(dir: Vector3) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = atan2(-dir.x, -dir.z)


func face_smooth(dir: Vector3, delta: float, speed: float = 16.0) -> void:
	if dir.length_squared() < 0.0001:
		return
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 1.0 - exp(-speed * delta))


func animate(speed_ratio: float, delta: float) -> void:
	if body == null:
		return
	idle_t += delta
	_update_face(delta)
	if speed_ratio > 0.05:
		# A bouncy waddle: short legs swing fast, the big head bobs and sways.
		walk_t += delta * (7.0 + 7.0 * speed_ratio)
		var s := sin(walk_t) * 0.7 * clampf(speed_ratio, 0.0, 1.0)
		leg_l.rotation.x = s
		leg_r.rotation.x = -s
		arm_l.rotation.x = -s * 0.8
		body.position.y = absf(sin(walk_t)) * 0.08 * speed_ratio
		body.rotation.z = sin(walk_t) * 0.06 * speed_ratio
		head.rotation.z = -sin(walk_t) * 0.05 * speed_ratio
	else:
		var k := minf(10.0 * delta, 1.0)
		leg_l.rotation.x = lerpf(leg_l.rotation.x, 0.0, k)
		leg_r.rotation.x = lerpf(leg_r.rotation.x, 0.0, k)
		arm_l.rotation.x = lerpf(arm_l.rotation.x, 0.0, k)
		body.position.y = sin(idle_t * 2.0) * 0.012
		body.rotation.z = lerpf(body.rotation.z, 0.0, k)
		head.rotation.z = lerpf(head.rotation.z, sin(idle_t * 0.9) * 0.035, k)
	head.rotation.x = HEAD_TILT + sin(idle_t * 1.3) * 0.03


func swing(sign_dir: float, arc_deg: float, dur: float, style: String) -> void:
	if weapon_pivot == null:
		return
	if _swing_tween:
		_swing_tween.kill()
	_swing_tween = create_tween()
	match style:
		"chop":
			weapon_pivot.rotation = Vector3(deg_to_rad(80), 0, 0)
			arm_r.rotation = Vector3(deg_to_rad(150), 0, 0)
			_swing_tween.set_parallel(true)
			_swing_tween.tween_property(weapon_pivot, "rotation:x", deg_to_rad(-55), dur * 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			_swing_tween.tween_property(arm_r, "rotation:x", deg_to_rad(40), dur * 0.3).set_ease(Tween.EASE_IN)
			_swing_tween.tween_property(body, "rotation:x", deg_to_rad(-12), dur * 0.3)
		"thrust":
			weapon_pivot.rotation = Vector3(0, 0, 0)
			arm_r.rotation = Vector3(deg_to_rad(80), 0, 0)
			weapon_holder.position = Vector3(0, 0, 0.1)
			_swing_tween.set_parallel(true)
			_swing_tween.tween_property(weapon_holder, "position:z", -1.0, dur * 0.25).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			_swing_tween.tween_property(body, "rotation:x", deg_to_rad(-10), dur * 0.25)
		_:
			var a := deg_to_rad(arc_deg * 0.5)
			weapon_pivot.rotation = Vector3(0, a * sign_dir, 0)
			arm_r.rotation = Vector3(deg_to_rad(80), a * sign_dir, 0)
			_swing_tween.set_parallel(true)
			_swing_tween.tween_property(weapon_pivot, "rotation:y", -a * sign_dir, dur * 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_swing_tween.tween_property(arm_r, "rotation:y", -a * sign_dir, dur * 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			_swing_tween.tween_property(body, "rotation:y", -0.25 * sign_dir, dur * 0.32)
	_swing_tween.chain().tween_interval(dur * 0.18)
	_swing_tween.chain().set_parallel(true)
	_swing_tween.tween_property(weapon_pivot, "rotation", Vector3(REST_X, REST_Y, 0), dur * 0.45)
	_swing_tween.tween_property(weapon_holder, "position", Vector3(0, 0, HOLD_Z), dur * 0.45)
	_swing_tween.tween_property(arm_r, "rotation", Vector3(deg_to_rad(35), REST_Y, 0), dur * 0.45)
	_swing_tween.tween_property(body, "rotation", Vector3.ZERO, dur * 0.45)


func spin(dur: float) -> void:
	if _swing_tween:
		_swing_tween.kill()
	weapon_pivot.rotation = Vector3(0, deg_to_rad(90), 0)
	arm_r.rotation = Vector3(deg_to_rad(85), deg_to_rad(90), 0)
	_swing_tween = create_tween()
	_swing_tween.tween_property(body, "rotation:y", -TAU, dur).from(0.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_swing_tween.tween_callback(func() -> void:
		body.rotation = Vector3.ZERO
		_rest_pose())


func roll(dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(body, "rotation:x", -TAU, dur).from(0.0)
	tw.tween_callback(func() -> void: body.rotation.x = 0.0)


func die() -> void:
	if _swing_tween:
		_swing_tween.kill()
	express("ko")
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(body, "rotation:x", deg_to_rad(85), 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "position:y", 0.15, 0.6)


func revive() -> void:
	if body:
		body.rotation = Vector3.ZERO
		body.position = Vector3.ZERO
	express("neutral")
	_rest_pose()
