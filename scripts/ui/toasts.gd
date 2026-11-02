class_name Toasts
extends VBoxContainer
## Chat-style notification toasts that slide in at the bottom-right.

const SENDER_COLORS := {
	"HR Automated Assistant": Color("#3fc4a2"),
	"Asset Management": Color("#3f9cf0"),
	"IT Helpdesk": Color("#d99a1c"),
	"Facilities Bot": Color("#6656c9"),
	"Procurement": Color("#e2aa2c"),
	"Security": Color("#c8343c"),
}
const MAX_TOASTS := 4

var history: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 8)
	UIKit.place(self, 1, 1, 1, 1, -400, -560, -16, -16)
	GameState.notified.connect(push)


func push(sender: String, message: String, kind: String = "info") -> void:
	history.push_front({"sender": sender, "message": message, "kind": kind, "time": Time.get_time_string_from_system().substr(0, 5)})
	if history.size() > 40:
		history.pop_back()
	var col: Color = SENDER_COLORS.get(sender, Color("#ff2a4a") if kind == "boss" else UIKit.C_ACCENT)
	var accent := col
	match kind:
		"loot_special": accent = ItemUtil.rarity_color("special")
		"loot_unique": accent = ItemUtil.rarity_color("unique")
		"warn": accent = UIKit.C_DANGER
		"boss": accent = Color("#ff2a4a")
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", UIKit.sb(Color(1, 1, 1, 0.97) if kind != "boss" else Color("#1f0f16"), 10, 0, Color.TRANSPARENT, 12))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer := UIKit.hbox(10)
	card.add_child(outer)
	var strip := Panel.new()
	strip.custom_minimum_size = Vector2(4, 0)
	strip.add_theme_stylebox_override("panel", UIKit.sb(accent, 2, 0))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_child(strip)
	outer.add_child(UIKit.avatar(UIKit.initials(sender), col, 34, UIKit.C_OK if kind != "boss" else Color("#ff2a4a")))
	var v := UIKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)
	var head := UIKit.hbox(6)
	v.add_child(head)
	var text_col := UIKit.C_TEXT if kind != "boss" else Color("#ffd0d6")
	head.add_child(UIKit.label(sender, 13, text_col, true))
	head.add_child(UIKit.label(history[0].time, 11, UIKit.C_MUTED))
	var msg := UIKit.label(message, 13, text_col)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = 290
	v.add_child(msg)
	add_child(card)
	card.modulate.a = 0.0
	card.position.x = 60
	var tw := card.create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.chain().tween_interval(5.0 if kind != "boss" else 6.5)
	tw.chain().tween_property(card, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(card.queue_free)
	if kind in ["boss", "levelup", "unlock", "success", "loot_unique"]:
		Audio.play("notify", -4.0)
	while get_child_count() > MAX_TOASTS:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
