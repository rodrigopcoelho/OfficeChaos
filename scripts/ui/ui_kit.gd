class_name UIKit
extends RefCounted
## Shared look & widgets for the "CubeLink Workspace" corporate messenger UI, styled
## after Microsoft Teams (classic palette: slate app bar, purple title bar, #6264A7
## brand accent, Fluent greys and Teams presence colours).

const C_RAIL := Color("#33344a")
const C_RAIL_HI := Color("#464775")
const C_TITLEBAR := Color("#464775")
const C_BG := Color("#f5f5f5")
const C_PANEL := Color("#ffffff")
const C_PANEL_ALT := Color("#f0f0f0")
const C_BORDER := Color("#e1dfdd")
const C_TEXT := Color("#252423")
const C_MUTED := Color("#605e5c")
const C_ACCENT := Color("#6264a7")
const C_ACCENT_HI := Color("#8b8cc7")
const C_DATA := Color("#3fc4a2")
const C_HP := Color("#e0525a")
const C_GOLD := Color("#d99a1c")
const C_DANGER := Color("#c4314b")
const C_OK := Color("#92c353")
const C_AWAY := Color("#fdb913")
const C_DARK := Color("#292929")

static var font_ui: Font
static var font_bold: Font
static var font_mono: Font


static func init_fonts() -> void:
	if font_ui != null:
		return
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Helvetica Neue", "Inter", "Arial", "sans-serif"])
	f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font_ui = f
	var b := SystemFont.new()
	b.font_names = f.font_names
	b.font_weight = 700
	font_bold = b
	var m := SystemFont.new()
	m.font_names = PackedStringArray(["Menlo", "Consolas", "Courier New", "monospace"])
	font_mono = m


static func sb(bg: Color, radius: int = 6, border: int = 0, border_col: Color = Color.TRANSPARENT, pad: float = 8.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func build_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font_ui
	t.default_font_size = 15
	t.set_stylebox("normal", "Button", sb(C_PANEL, 4, 1, C_BORDER, 12))
	t.set_stylebox("hover", "Button", sb(C_PANEL_ALT, 4, 1, C_ACCENT_HI, 12))
	t.set_stylebox("pressed", "Button", sb(C_ACCENT, 4, 1, C_ACCENT, 12))
	t.set_stylebox("disabled", "Button", sb(Color("#f3f2f1"), 4, 1, C_BORDER, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_stylebox("focus", "CheckBox", StyleBoxEmpty.new())
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", C_TEXT)
	t.set_color("font_hover_color", "Button", C_TEXT)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", C_TEXT)
	t.set_color("font_disabled_color", "Button", Color("#a8a49c"))
	t.set_color("font_color", "Label", C_TEXT)
	t.set_stylebox("panel", "PanelContainer", sb(C_PANEL, 8, 1, C_BORDER, 12))
	t.set_stylebox("panel", "Panel", sb(C_PANEL, 8, 0))
	t.set_stylebox("normal", "LineEdit", sb(Color.WHITE, 6, 1, C_BORDER, 10))
	t.set_stylebox("focus", "LineEdit", sb(Color.WHITE, 6, 2, C_ACCENT, 10))
	t.set_color("font_color", "LineEdit", C_TEXT)
	t.set_color("caret_color", "LineEdit", C_ACCENT)
	t.set_stylebox("background", "ProgressBar", sb(Color(0, 0, 0, 0.12), 4, 0))
	t.set_stylebox("fill", "ProgressBar", sb(C_ACCENT, 4, 0))
	t.set_stylebox("panel", "TooltipPanel", sb(C_DARK, 6, 0, Color.TRANSPARENT, 10))
	t.set_color("font_color", "TooltipLabel", Color("#f2f1ed"))
	t.set_color("default_color", "RichTextLabel", C_TEXT)
	t.set_font("bold_font", "RichTextLabel", font_bold)
	t.set_font("normal_font", "RichTextLabel", font_ui)
	t.set_color("font_color", "CheckBox", C_TEXT)
	t.set_color("font_hover_color", "CheckBox", C_TEXT)
	t.set_color("font_pressed_color", "CheckBox", C_TEXT)
	t.set_stylebox("slider", "HSlider", sb(Color("#d8d5cc"), 3, 0, Color.TRANSPARENT, 2))
	t.set_stylebox("grabber_area", "HSlider", sb(C_ACCENT, 3, 0, Color.TRANSPARENT, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", sb(C_ACCENT_HI, 3, 0, Color.TRANSPARENT, 2))
	var sbar := sb(Color(0, 0, 0, 0.18), 4, 0, Color.TRANSPARENT, 2)
	t.set_stylebox("grabber", "VScrollBar", sbar)
	t.set_stylebox("grabber_highlight", "VScrollBar", sb(C_ACCENT, 4, 0, Color.TRANSPARENT, 2))
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.04), 4, 0, Color.TRANSPARENT, 2))
	return t


static func set_focus_visible(t: Theme, visible: bool) -> void:
	## Focus rings only show while a controller is in use (mouse users never see them).
	var ring: StyleBox = StyleBoxEmpty.new()
	if visible:
		var r := sb(Color(0, 0, 0, 0), 9, 3, Color("#ffb020"), 0)
		r.set_expand_margin_all(3)
		ring = r
	for cls in ["Button", "CheckBox", "HSlider"]:
		t.set_stylebox("focus", cls, ring)


static func label(text: String, size: int = 15, color: Color = C_TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func rich(bbcode: String, min_h: int = 0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.custom_minimum_size.y = min_h
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func button(text: String, cb: Callable, kind: String = "default", min_w: int = 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("focus_key", "btn:" + text)
	b.custom_minimum_size = Vector2(min_w, 36)
	match kind:
		"primary":
			b.add_theme_stylebox_override("normal", sb(C_ACCENT, 4, 0, Color.TRANSPARENT, 14))
			b.add_theme_stylebox_override("hover", sb(C_ACCENT_HI, 4, 0, Color.TRANSPARENT, 14))
			b.add_theme_stylebox_override("pressed", sb(C_ACCENT.darkened(0.2), 4, 0, Color.TRANSPARENT, 14))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
			b.add_theme_font_override("font", font_bold)
		"danger":
			b.add_theme_stylebox_override("normal", sb(C_DANGER, 4, 0, Color.TRANSPARENT, 14))
			b.add_theme_stylebox_override("hover", sb(C_DANGER.lightened(0.15), 4, 0, Color.TRANSPARENT, 14))
			b.add_theme_color_override("font_color", Color.WHITE)
			b.add_theme_color_override("font_hover_color", Color.WHITE)
		"ghost":
			b.add_theme_stylebox_override("normal", sb(Color(0, 0, 0, 0), 4, 0, Color.TRANSPARENT, 10))
			b.add_theme_stylebox_override("hover", sb(Color(0, 0, 0, 0.06), 4, 0, Color.TRANSPARENT, 10))
			b.add_theme_stylebox_override("pressed", sb(Color(0, 0, 0, 0.12), 4, 0, Color.TRANSPARENT, 10))
		"dark":
			b.add_theme_stylebox_override("normal", sb(Color(1, 1, 1, 0.06), 4, 1, Color(1, 1, 1, 0.12), 14))
			b.add_theme_stylebox_override("hover", sb(Color(1, 1, 1, 0.14), 4, 1, C_ACCENT_HI, 14))
			b.add_theme_stylebox_override("pressed", sb(C_ACCENT, 4, 1, C_ACCENT, 14))
			b.add_theme_stylebox_override("disabled", sb(Color(1, 1, 1, 0.02), 4, 1, Color(1, 1, 1, 0.05), 14))
			b.add_theme_color_override("font_color", Color("#f2f1ed"))
			b.add_theme_color_override("font_hover_color", Color.WHITE)
			b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			Audio.play("ui_click", -6.0, 0.05, 0.0)
			cb.call())
	return b


static func panel(bg: Color = C_PANEL, radius: int = 8, pad: float = 12.0, border: int = 1, border_col: Color = C_BORDER) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, radius, border, border_col, pad))
	return p


static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func spacer(expand: bool = true) -> Control:
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func bar(color: Color, h: int = 12, bg: Color = Color(0, 0, 0, 0.14)) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(0, h)
	p.add_theme_stylebox_override("fill", sb(color, 4, 0, Color.TRANSPARENT, 0))
	p.add_theme_stylebox_override("background", sb(bg, 4, 0, Color.TRANSPARENT, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func avatar(initials: String, color: Color, size: float = 40.0, status: Color = Color.TRANSPARENT) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(size, size)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var circle := Panel.new()
	circle.add_theme_stylebox_override("panel", sb(color, int(size / 2), 0))
	circle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	circle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(circle)
	var l := label(initials, int(size * 0.38), Color.WHITE, true)
	l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	root.add_child(l)
	if status.a > 0.0:
		var dot := Panel.new()
		dot.add_theme_stylebox_override("panel", sb(status, int(size * 0.15), 2, Color.WHITE, 0))
		dot.size = Vector2(size * 0.3, size * 0.3)
		dot.position = Vector2(size * 0.72, size * 0.72)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(dot)
	return root


static func initials(n: String) -> String:
	var parts := n.strip_edges().split(" ", false)
	if parts.is_empty():
		return "?"
	if parts.size() == 1:
		return parts[0].substr(0, 2).to_upper()
	return (parts[0].substr(0, 1) + parts[1].substr(0, 1)).to_upper()


static func focus_first(root: Node) -> bool:
	## Gives keyboard/controller focus to the first visible, enabled focusable control.
	if root == null or not root.is_inside_tree():
		return false
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if c.focus_mode == Control.FOCUS_ALL and c.is_visible_in_tree() and not (c is BaseButton and (c as BaseButton).disabled):
			c.grab_focus()
			return true
	return false


static func restore_focus(root: Node, key: String) -> bool:
	## Re-focuses the control tagged with meta "focus_key" == key after a rebuild.
	if root == null or not root.is_inside_tree() or key == "":
		return false
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if str(c.get_meta("focus_key", "")) == key and c.is_visible_in_tree() and c.focus_mode != Control.FOCUS_NONE:
			c.grab_focus()
			return true
	return false


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


static func section(text: String) -> Label:
	var l := label(text.to_upper(), 12, C_MUTED, true)
	return l


static func item_card(inst: Dictionary, selected: bool, cb: Callable, size: float = 84.0, badge: String = "") -> Button:
	var d := ItemUtil.def(inst)
	var rc := ItemUtil.rarity_color(str(d.get("rarity", "common")))
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.set_meta("focus_key", "item:%d" % int(inst.get("uid", -1)))
	b.custom_minimum_size = Vector2(size, size)
	b.tooltip_text = ItemUtil.display_name(inst)
	var bg := Color("#fbfaf7") if not selected else Color("#ece8ff")
	b.add_theme_stylebox_override("normal", sb(bg, 8, 2 if not selected else 3, rc if not selected else C_ACCENT, 4))
	b.add_theme_stylebox_override("hover", sb(Color("#f3f0ff"), 8, 3, C_ACCENT_HI, 4))
	b.add_theme_stylebox_override("pressed", sb(Color("#e4ddff"), 8, 3, C_ACCENT, 4))
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 6
	icon.offset_top = 6
	icon.offset_right = -6
	icon.offset_bottom = -6
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	var ui = GameState.ui
	if ui and ui.icons:
		var tex: Texture2D = ui.icons.get_icon(str(inst.id))
		if tex:
			icon.texture = tex
		else:
			var id := str(inst.id)
			var icon_ref: WeakRef = weakref(icon)
			var cache: Dictionary = ui.icons.cache
			var on_icon := func(ready_id: String) -> void:
				var tr = icon_ref.get_ref()
				if ready_id == id and tr != null:
					tr.texture = cache.get(id)
			ui.icons.icon_ready.connect(on_icon)
			icon.tree_exiting.connect(func() -> void:
				if ui.icons.icon_ready.is_connected(on_icon):
					ui.icons.icon_ready.disconnect(on_icon))
	var strip := Panel.new()
	strip.add_theme_stylebox_override("panel", sb(rc, 2, 0))
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place(strip, 0, 1, 1, 1, 8, -7, -8, -4)
	b.add_child(strip)
	var plus := int(inst.get("plus", 0))
	if plus > 0:
		var pl := label("+%d" % plus, 12, C_ACCENT, true)
		place(pl, 1, 0, 1, 0, -30, 2, -5, 20)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.add_child(pl)
	if not d.is_empty() and badge == "":
		# Power, Minecraft Dungeons style, in the top-left corner
		var pw := label(str(ItemUtil.power_of(inst)), 11, C_TEXT, true)
		place(pw, 0, 0, 0, 0, 6, 3, 40, 19)
		b.add_child(pw)
	if badge != "":
		var bp := PanelContainer.new()
		bp.add_theme_stylebox_override("panel", sb(C_ACCENT, 4, 0, Color.TRANSPARENT, 3))
		bp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl := label(badge, 10, Color.WHITE, true)
		bp.add_child(bl)
		bp.position = Vector2(4, 4)
		b.add_child(bp)
	if cb.is_valid():
		b.pressed.connect(func() -> void:
			Audio.play("ui_click", -8.0, 0.05, 0.0)
			cb.call())
	return b


static func empty_slot(size: float = 84.0, text: String = "") -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.add_theme_stylebox_override("panel", sb(Color(0, 0, 0, 0.035), 8, 1, Color(0, 0, 0, 0.06), 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if text != "":
		var l := label(text, 11, C_MUTED)
		l.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		p.add_child(l)
	return p


static func pill(text: String, bg: Color, fg: Color = Color.WHITE, size: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, 10, 0, Color.TRANSPARENT, 8))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(label(text, size, fg, true))
	return p


static func time_str(seconds: float) -> String:
	var s := int(seconds)
	return "%dh %02dm" % [s / 3600, (s % 3600) / 60]
