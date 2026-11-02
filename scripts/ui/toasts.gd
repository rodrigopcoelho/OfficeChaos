class_name Toasts
extends VBoxContainer
## Microsoft Teams-style desktop notifications, stacked at the bottom-right:
## an app header ("CubeLink" + close), the sender's avatar with a presence dot,
## bold sender name and time, the message, and a faux "Reply" box. Cards slide in
## from the right edge and slide back out; a coloured top rule marks loot rarity,
## warnings and boss messages.

const SENDER_COLORS := {
	"HR Automated Assistant": Color("#3fc4a2"),
	"Asset Management": Color("#3f9cf0"),
	"IT Helpdesk": Color("#d99a1c"),
	"Facilities Bot": Color("#6264a7"),
	"Procurement": Color("#e2aa2c"),
	"Security": Color("#c4314b"),
}
const MAX_TOASTS := 4
const WIDTH := 372.0
const SHOW_TIME := 5.0
const REPLY_KINDS := ["info", "boss", "shop", "levelup"]

var history: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 10)
	UIKit.place(self, 1, 1, 1, 1, -WIDTH - 18, -620, -18, -18)
	GameState.notified.connect(push)


func push(sender: String, message: String, kind: String = "info") -> void:
	history.push_front({"sender": sender, "message": message, "kind": kind, "time": Time.get_time_string_from_system().substr(0, 5)})
	if history.size() > 40:
		history.pop_back()
	var boss := kind == "boss"
	var col: Color = SENDER_COLORS.get(sender, Color("#c4314b") if boss else UIKit.C_ACCENT)
	var accent := Color.TRANSPARENT
	match kind:
		"loot_rare": accent = ItemUtil.rarity_color("rare")
		"loot_special": accent = ItemUtil.rarity_color("special")
		"loot_unique": accent = ItemUtil.rarity_color("unique")
		"warn": accent = UIKit.C_DANGER
		"boss": accent = Color("#c4314b")
		"levelup", "success", "unlock": accent = UIKit.C_ACCENT
	var bg := Color("#292929") if boss else Color.WHITE
	var text_col := Color("#ffffff") if boss else UIKit.C_TEXT
	var muted := Color("#c8c6c4") if boss else UIKit.C_MUTED
	# Outer wrapper keeps the slide animation independent of the VBox layout.
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(WIDTH, 0)
	var card := PanelContainer.new()
	var style := UIKit.sb(bg, 4, 1, Color(0, 0, 0, 0.12) if not boss else Color("#3b3a39"), 0)
	style.shadow_color = Color(0, 0, 0, 0.28)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 3)
	card.add_theme_stylebox_override("panel", style)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.custom_minimum_size.x = WIDTH
	slot.add_child(card)
	var v := UIKit.vbox(0)
	card.add_child(v)
	if accent.a > 0.0:
		var rule := ColorRect.new()
		rule.color = accent
		rule.custom_minimum_size.y = 3
		rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(rule)
	# App header row: tiny app tile + "CubeLink" + close glyph
	var head := MarginContainer.new()
	for side in ["left", "right"]:
		head.add_theme_constant_override("margin_" + side, 12)
	head.add_theme_constant_override("margin_top", 8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var hh := UIKit.hbox(6)
	head.add_child(hh)
	var tile := PanelContainer.new()
	tile.add_theme_stylebox_override("panel", UIKit.sb(UIKit.C_ACCENT, 3, 0, Color.TRANSPARENT, 0))
	tile.custom_minimum_size = Vector2(16, 16)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := UIKit.label("C", 10, Color.WHITE, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tile.add_child(tl)
	hh.add_child(tile)
	hh.add_child(UIKit.label("CubeLink", 12, muted))
	hh.add_child(UIKit.spacer())
	hh.add_child(UIKit.label("···", 12, muted, true))
	hh.add_child(UIKit.label("✕", 12, muted))
	# Body: avatar with presence + sender/time + message
	var body := MarginContainer.new()
	body.add_theme_constant_override("margin_left", 12)
	body.add_theme_constant_override("margin_right", 14)
	body.add_theme_constant_override("margin_top", 8)
	body.add_theme_constant_override("margin_bottom", 12)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(body)
	var row := UIKit.hbox(12)
	body.add_child(row)
	var av := UIKit.avatar(UIKit.initials(sender), col, 40, Color("#c4314b") if boss else UIKit.C_OK)
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(av)
	var tv := UIKit.vbox(2)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tv)
	var nh := UIKit.hbox(8)
	tv.add_child(nh)
	nh.add_child(UIKit.label(sender, 14, text_col, true))
	nh.add_child(UIKit.spacer())
	nh.add_child(UIKit.label(history[0].time, 11, muted))
	var msg := UIKit.label(message, 13, text_col)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.custom_minimum_size.x = WIDTH - 90
	tv.add_child(msg)
	if kind in REPLY_KINDS:
		var reply := PanelContainer.new()
		reply.add_theme_stylebox_override("panel", UIKit.sb(Color("#f5f5f5") if not boss else Color("#3b3a39"), 4, 1, Color(0, 0, 0, 0.08), 8))
		reply.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reply.add_child(UIKit.label("Reply", 12, muted))
		var rm := MarginContainer.new()
		rm.add_theme_constant_override("margin_top", 6)
		rm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rm.add_child(reply)
		tv.add_child(rm)
	add_child(slot)
	# The wrapper takes the card's height once laid out; the card slides inside it.
	slot.custom_minimum_size.y = card.get_combined_minimum_size().y
	card.position.x = WIDTH + 40
	var tw := card.create_tween()
	tw.tween_property(card, "position:x", 0.0, 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(SHOW_TIME if not boss else SHOW_TIME + 1.5)
	tw.tween_property(card, "position:x", WIDTH + 40, 0.28).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(slot, "custom_minimum_size:y", 0.0, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(slot.queue_free)
	Audio.play("notify", -4.0 if kind in ["boss", "levelup", "unlock", "success", "loot_unique"] else -14.0)
	while get_child_count() > MAX_TOASTS:
		var old := get_child(0)
		remove_child(old)
		old.queue_free()
