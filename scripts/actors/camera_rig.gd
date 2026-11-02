class_name CameraRig
extends Node3D
## Fixed-angle 2.5D follow camera with aim lead, trauma-based shake and a
## tilt-shift depth of field for the HD-2D diorama look.

const OFFSET := Vector3(0, 15.0, 10.2)
const PITCH := -0.9733  # atan2(15.0, 10.2): the camera's downward angle

var target: Node3D
var camera: Camera3D
var shake := 0.0
var orbit := false
var orbit_center := Vector3.ZERO
var orbit_t := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 40.0
	camera.near = 0.5
	camera.far = 200.0
	add_child(camera)
	camera.position = OFFSET
	camera.rotation.x = -atan2(OFFSET.y, OFFSET.z)
	var attrs := CameraAttributesPractical.new()
	attrs.dof_blur_far_enabled = true
	attrs.dof_blur_far_distance = 24.0
	attrs.dof_blur_far_transition = 14.0
	attrs.dof_blur_near_enabled = true
	attrs.dof_blur_near_distance = 9.0
	attrs.dof_blur_near_transition = 4.0
	attrs.dof_blur_amount = 0.045
	camera.attributes = attrs
	camera.current = true


func snap() -> void:
	if target and is_instance_valid(target):
		global_position = target.global_position


func _process(delta: float) -> void:
	if orbit:
		orbit_t += delta * 0.06
		global_position = orbit_center
		rotation.y = orbit_t
		camera.position = OFFSET * 1.6
	elif target and is_instance_valid(target):
		var goal := target.global_position
		if target is Player:
			var lead: Vector3 = (target.aim_point - target.global_position)
			lead.y = 0
			goal += lead.limit_length(8.0) * 0.18
		global_position = global_position.lerp(goal, 1.0 - exp(-7.0 * delta))
	shake = maxf(0.0, shake - delta * 1.6)
	var s := shake * shake if Settings.screen_shake else 0.0
	camera.h_offset = randf_range(-1, 1) * s * 0.6
	camera.v_offset = randf_range(-1, 1) * s * 0.6
