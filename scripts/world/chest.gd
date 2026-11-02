class_name RewardChest
extends Interactable
## "Performance Bonus" crate at the end of a dungeon. Locked until the boss falls.

var locked := true
var opened := false
var table := "chest"
var gold_range: Array = [50, 100]
var _lid: Node3D
var _light: OmniLight3D
var _label: Label3D


func _ready() -> void:
	super._ready()
	radius = 2.6
	MeshFactory.box(self, Vector3(1.3, 0.75, 0.85), Vector3(0, 0.375, 0), Color("#6b4a2e"), 0.0, 0.03)
	MeshFactory.box(self, Vector3(1.36, 0.1, 0.9), Vector3(0, 0.2, 0), Color("#c9a24a"), 0.4, 0.01)
	_lid = Node3D.new()
	_lid.position = Vector3(0, 0.75, -0.43)
	add_child(_lid)
	MeshFactory.box(_lid, Vector3(1.36, 0.25, 0.9), Vector3(0, 0.12, 0.43), Color("#7a5636"), 0.0, 0.03)
	MeshFactory.box(_lid, Vector3(0.2, 0.2, 0.05), Vector3(0, 0.0, 0.89), Color("#ffd75e"), 1.5, 0.0)
	MeshBatcher.merge_children(self)
	MeshBatcher.merge_children(_lid)
	_light = OmniLight3D.new()
	_light.light_color = Color("#ffcc55")
	_light.omni_range = 4.0
	_light.position.y = 1.5
	add_child(_light)
	_label = Interactable.label3d(self, "PERFORMANCE BONUS", Vector3(0, 1.9, 0), Color("#ffd75e"), 0.6)
	_update()


func _update() -> void:
	enabled = not locked and not opened
	_light.light_energy = 0.0 if locked or opened else 2.5
	_label.visible = not opened
	_label.modulate = Color("#ff6070") if locked else Color("#ffd75e")
	_label.text = "LOCKED BONUS" if locked else "PERFORMANCE BONUS"
	prompt = "Claim your Performance Bonus"


func unlock() -> void:
	locked = false
	_update()


func interact(_player) -> void:
	if not enabled:
		return
	opened = true
	_update()
	Audio.play("chest")
	var tw := create_tween()
	tw.tween_property(_lid, "rotation:x", deg_to_rad(-110), 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.burst(global_position + Vector3(0, 1, 0), Color("#ffd75e"), 40, 7.0, 0.14, 0.9, -6.0)
	var w = GameState.world
	var gold := randi_range(int(gold_range[0]), int(gold_range[-1]))
	w.drop_rewards(global_position + Vector3(0, 0, 1.2), 30.0, gold, table)
