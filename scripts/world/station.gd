class_name Station
extends Interactable
## Hub service desks (Shop, Blacksmith, Upgrades) staffed by an NPC.

var tab := "shop"
var station_name := "Desk"
var title := "SERVICE"
var npc: Dictionary = {}
var _npc_visual: CharacterVisual
var _prop: Node3D
var _t := 0.0


func _ready() -> void:
	super._ready()
	radius = 3.2
	prompt = "Talk to %s (%s)" % [station_name, title.capitalize()]
	var desk_col := Color("#cfc3a2")
	MeshFactory.box(self, Vector3(1.9, 0.95, 0.8), Vector3(0, 0.475, 0.35), desk_col, 0.0, 0.03)
	MeshFactory.box(self, Vector3(2.0, 0.08, 0.95), Vector3(0, 0.98, 0.35), desk_col.darkened(0.3), 0.0, 0.02)
	MeshFactory.box(self, Vector3(1.6, 0.12, 0.04), Vector3(0, 0.6, 0.77), _accent(), 1.6, 0.0)
	# The chibi staff stand on a step behind the counter so they peek over it.
	MeshFactory.box(self, Vector3(1.3, 0.3, 0.7), Vector3(0, 0.15, -0.45), Color("#5b4a6e"), 0.0, 0.03)
	_npc_visual = CharacterVisual.new()
	add_child(_npc_visual)
	_npc_visual.build(npc)
	_npc_visual.position = Vector3(0, 0.3, -0.45)
	_npc_visual.rotation.y = PI
	_prop = Node3D.new()
	add_child(_prop)
	_build_prop()
	MeshBatcher.merge_children(self)
	MeshBatcher.merge_children(_prop)
	Interactable.label3d(self, title, Vector3(0, 3.1, 0), _accent().lightened(0.3), 1.2)
	Interactable.label3d(self, station_name, Vector3(0, 2.75, 0), Color(0.95, 0.93, 0.88), 0.6)
	var light := OmniLight3D.new()
	light.light_color = _accent()
	light.light_energy = 1.4
	light.omni_range = 5.0
	light.position = Vector3(0, 2.2, 1.0)
	add_child(light)


func _accent() -> Color:
	match tab:
		"shop": return Color("#e2aa2c")
		"forge": return Color("#ff7a1a")
		"enchant": return Color("#b24bff")
	return Color.WHITE


func _build_prop() -> void:
	match tab:
		"shop":
			var rack := Node3D.new()
			rack.position = Vector3(1.25, 0, -0.2)
			_prop.add_child(rack)
			MeshFactory.box(rack, Vector3(0.1, 1.8, 0.1), Vector3(0, 0.9, 0), Color("#5a3b26"))
			for i in 3:
				var w := Node3D.new()
				w.position = Vector3(0, 0.5 + i * 0.45, 0.1)
				w.rotation_degrees = Vector3(0, 0, 90)
				rack.add_child(w)
				var ids := ["longsword_patched", "battle_axe", "halberd_overclocked"]
				MeshFactory.build(DB.items.get(ids[i], {}).get("visual", {}).get("parts", []), w, {}, 0.01)
		"forge":
			var anvil := Node3D.new()
			anvil.position = Vector3(-1.3, 0, 0.2)
			_prop.add_child(anvil)
			MeshFactory.box(anvil, Vector3(0.7, 0.8, 0.6), Vector3(0, 0.4, 0), Color("#2a2b31"))
			MeshFactory.box(anvil, Vector3(0.9, 0.18, 0.4), Vector3(0, 0.9, 0), Color("#55575f"))
			MeshFactory.box(anvil, Vector3(0.5, 0.04, 0.3), Vector3(0, 1.0, 0), Color("#ff7a1a"), 3.0)
		"enchant":
			for i in 4:
				MeshFactory.shape(_prop, "gem", Vector3(0.2, 0.3, 0.2), Vector3(cos(i * PI / 2) * 0.9, 2.0, sin(i * PI / 2) * 0.5 - 0.3), Color("#b24bff"), 3.0)


func _process(delta: float) -> void:
	_t += delta
	_npc_visual.animate(0.0, delta)
	if tab == "enchant":
		_prop.rotation.y += delta * 0.8
	var p = GameState.player
	if p != null and is_instance_valid(p) and global_position.distance_to(p.global_position) < 6.0:
		var to: Vector3 = p.global_position - (global_position + _npc_visual.position)
		to.y = 0
		_npc_visual.face_smooth(to.normalized(), delta, 4.0)


func interact(_player) -> void:
	_npc_visual.express("happy", 1.6)
	if GameState.ui:
		Audio.play("notify", -6.0)
		GameState.ui.open_app(tab, {})
