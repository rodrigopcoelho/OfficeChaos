class_name GoldenComputer
extends Interactable
## Teleport checkpoint. Unlocks the moment the player walks up to it; interacting
## opens the corporate network map to travel between unlocked terminals.

const UNLOCK_RADIUS := 4.5

var computer_id := ""
var display_name := "Terminal"
var _gem: MeshInstance3D
var _beam: MeshInstance3D
var _light: OmniLight3D
var _t := 0.0


func _ready() -> void:
	super._ready()
	radius = 3.0
	prompt = "Access %s (Network Map)" % display_name
	var gold := Color("#d9a520")
	MeshFactory.box(self, Vector3(1.1, 0.8, 0.8), Vector3(0, 0.4, 0), gold.darkened(0.25), 0.15, 0.03)
	MeshFactory.box(self, Vector3(0.85, 0.65, 0.7), Vector3(0, 1.15, 0.0), gold, 0.35, 0.03)
	MeshFactory.box(self, Vector3(0.66, 0.46, 0.04), Vector3(0, 1.17, 0.36), Color("#ffe27a"), 3.0, 0.0)
	MeshFactory.box(self, Vector3(0.8, 0.05, 0.28), Vector3(0, 0.83, 0.42), gold.darkened(0.4), 0.0, 0.01)
	_gem = MeshFactory.shape(self, "gem", Vector3(0.45, 0.6, 0.45), Vector3(0, 2.3, 0), Color("#ffd75e"), 3.0)
	MeshBatcher.merge_children(self, [_gem])
	_beam = MeshInstance3D.new()
	_beam.mesh = MeshFactory.mesh_for("cyl", Vector3(0.5, 7.0, 0.5))
	_beam.material_override = MeshFactory.unlit(Color(1.0, 0.8, 0.3, 0.12), true)
	_beam.position.y = 3.5
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beam)
	_light = OmniLight3D.new()
	_light.light_color = Color("#ffcc55")
	_light.light_energy = 2.2
	_light.omni_range = 7.0
	_light.position.y = 2.0
	add_child(_light)
	Interactable.label3d(self, display_name.to_upper(), Vector3(0, 3.0, 0), Color("#ffe9a8"), 0.7)
	_refresh()


func _refresh() -> void:
	var unlocked := GameState.is_computer_unlocked(computer_id)
	_beam.visible = unlocked
	_light.light_energy = 2.4 if unlocked else 0.8


func _process(delta: float) -> void:
	_t += delta
	_gem.rotation.y += delta * 1.5
	_gem.position.y = 2.3 + sin(_t * 2.0) * 0.12
	var p = GameState.player
	if p != null and is_instance_valid(p) and not p.dead and not GameState.is_computer_unlocked(computer_id):
		if global_position.distance_to(p.global_position) < UNLOCK_RADIUS:
			_unlock()


func _unlock() -> void:
	if GameState.unlock_computer(computer_id):
		Audio.play("unlock")
		Fx.burst(global_position + Vector3(0, 2, 0), Color("#ffd75e"), 40, 7.0, 0.14, 0.9, -3.0)
		Fx.ring(global_position, 5.0, Color("#ffd75e"), 0.6)
		GameState.notify("IT Helpdesk", "Network node unlocked: %s. You can now transfer here from any golden terminal." % display_name, "unlock")
		_refresh()


func interact(_player) -> void:
	if not GameState.is_computer_unlocked(computer_id):
		_unlock()
	if GameState.ui:
		GameState.ui.open_app("network", {"from_computer": computer_id})
