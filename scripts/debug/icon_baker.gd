extends Node
## Bakes the 2D inventory icon art for every item and quits (needs a window):
##   godot --path . -- --icons
## Each item's 3D model is rendered with ink lines at 256 px, then turned into a flat
## sticker-style icon: a thick ink outline around the silhouette and a soft drop
## shadow. Saved to res://assets/icons/<id>.png (run --import afterwards so Godot
## picks them up), plus a contact sheet of all icons at user://icon_sheet.png.

const PX := 256
const OUTLINE_PX := 4
const SHADOW_OFFSET := Vector2i(5, 6)
const INK := Color("#1f1726")
const SHEET_COLS := 12
const SHEET_CELL := 96


func _ready() -> void:
	GameState.main.ui.visible = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(IconCache.ICON_DIR))
	await get_tree().process_frame
	var icons: IconCache = GameState.main.ui.icons
	var ids: Array = DB.items.keys()
	ids.sort_custom(func(a, b) -> bool:
		var da: Dictionary = DB.items[a]
		var db: Dictionary = DB.items[b]
		if str(da.slot) != str(db.slot):
			return GameState.SLOTS.find(str(da.slot)) < GameState.SLOTS.find(str(db.slot))
		return str(a) < str(b))
	var sheet := Image.create(SHEET_COLS * SHEET_CELL, ceili(ids.size() / float(SHEET_COLS)) * SHEET_CELL, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#f5f5f5"))
	var i := 0
	for id in ids:
		var raw: Image = await icons.render_image(str(id), PX, 0.03)
		if raw == null or raw.is_empty():
			push_warning("[ICONS] could not render " + str(id))
			continue
		var art := stylize(raw)
		art.save_png(ProjectSettings.globalize_path(IconCache.ICON_DIR + str(id) + ".png"))
		var thumb := art.duplicate() as Image
		thumb.resize(SHEET_CELL - 8, SHEET_CELL - 8, Image.INTERPOLATE_LANCZOS)
		var cell := Vector2i((i % SHEET_COLS) * SHEET_CELL + 4, (i / SHEET_COLS) * SHEET_CELL + 4)
		var bg := Image.create(SHEET_CELL - 8, SHEET_CELL - 8, false, Image.FORMAT_RGBA8)
		bg.fill(ItemUtil.rarity_color(str(DB.items[id].get("rarity", "common"))).lerp(Color.WHITE, 0.75))
		sheet.blit_rect(bg, Rect2i(Vector2i.ZERO, bg.get_size()), cell)
		sheet.blend_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), cell)
		i += 1
	sheet.save_png("user://icon_sheet.png")
	print("[ICONS] baked %d icons into %s" % [i, ProjectSettings.globalize_path(IconCache.ICON_DIR)])
	print("[ICONS] contact sheet ", ProjectSettings.globalize_path("user://icon_sheet.png"))
	get_tree().quit()


static func stylize(src: Image) -> Image:
	## Silhouette -> dilated ink outline + offset soft shadow, with the render on top.
	var img := src.duplicate() as Image
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in h:
		for x in w:
			mask[y * w + x] = 1 if img.get_pixel(x, y).a > 0.35 else 0
	var grown := _dilate(mask, w, h, OUTLINE_PX)
	var out := Image.create(w, h, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			var sx := x - SHADOW_OFFSET.x
			var sy := y - SHADOW_OFFSET.y
			if sx >= 0 and sy >= 0 and grown[sy * w + sx] == 1:
				out.set_pixel(x, y, Color(0.12, 0.09, 0.16, 0.22))
	for y in h:
		for x in w:
			if grown[y * w + x] == 1:
				out.set_pixel(x, y, INK)
	out.blend_rect(img, Rect2i(0, 0, w, h), Vector2i.ZERO)
	return out


static func _dilate(mask: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	## Square max filter, separable: rows then columns.
	var tmp := PackedByteArray()
	tmp.resize(w * h)
	for y in h:
		var row := y * w
		for x in w:
			var v := 0
			for k in range(maxi(0, x - r), mini(w, x + r + 1)):
				if mask[row + k] == 1:
					v = 1
					break
			tmp[row + x] = v
	var out := PackedByteArray()
	out.resize(w * h)
	for x in w:
		for y in h:
			var v2 := 0
			for k in range(maxi(0, y - r), mini(h, y + r + 1)):
				if tmp[k * w + x] == 1:
					v2 = 1
					break
			out[y * w + x] = v2
	return out
