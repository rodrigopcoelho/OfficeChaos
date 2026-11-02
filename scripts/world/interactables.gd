class_name Interactable
extends Node3D
## Base class for anything the player can use with the Interact key.

var prompt := "Interact"
var radius := 2.8
var enabled := true


func _ready() -> void:
	add_to_group("interactables")


func can_interact(_player) -> bool:
	return enabled


func get_prompt() -> String:
	return prompt


func interact(_player) -> void:
	pass


static func label3d(parent: Node3D, text: String, pos: Vector3, color: Color, size: float = 1.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.outline_size = 12
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.pixel_size = 0.0055 * size
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	l.position = pos
	parent.add_child(l)
	return l
