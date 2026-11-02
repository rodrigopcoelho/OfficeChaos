class_name RailIcon
extends Control
## Simple vector icons drawn in code for the app rail (no image assets needed).

var kind := "profile"
var color := Color.WHITE


func _init(k: String = "profile", c: Color = Color.WHITE) -> void:
	kind = k
	color = c
	custom_minimum_size = Vector2(24, 24)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var c := o + Vector2(s, s) * 0.5
	var w := maxf(1.5, s * 0.08)
	match kind:
		"profile":
			draw_circle(c + Vector2(0, -s * 0.15), s * 0.18, color)
			draw_arc(c + Vector2(0, s * 0.42), s * 0.34, PI, TAU, 16, color, w * 1.6)
		"items":
			draw_rect(Rect2(o + Vector2(s * 0.18, s * 0.35), Vector2(s * 0.64, s * 0.5)), color, false, w)
			draw_arc(c + Vector2(0, -s * 0.12), s * 0.17, PI, TAU, 12, color, w)
			draw_line(o + Vector2(s * 0.18, s * 0.55), o + Vector2(s * 0.82, s * 0.55), color, w)
		"map":
			var a := o + Vector2(s * 0.2, s * 0.75)
			var b := o + Vector2(s * 0.5, s * 0.25)
			var d := o + Vector2(s * 0.8, s * 0.7)
			draw_line(a, b, color, w)
			draw_line(b, d, color, w)
			draw_line(a, d, color, w)
			for p in [a, b, d]:
				draw_circle(p, s * 0.1, color)
		"shop":
			draw_circle(c, s * 0.34, color, false, w)
			draw_line(c + Vector2(0, -s * 0.2), c + Vector2(0, s * 0.2), color, w)
			draw_arc(c + Vector2(0, -s * 0.05), s * 0.1, PI * 0.5, PI * 1.6, 8, color, w)
			draw_arc(c + Vector2(0, s * 0.07), s * 0.1, -PI * 0.5, PI * 0.6, 8, color, w)
		"forge":
			draw_line(o + Vector2(s * 0.25, s * 0.85), o + Vector2(s * 0.62, s * 0.38), color, w * 1.4)
			draw_rect(Rect2(o + Vector2(s * 0.45, s * 0.12), Vector2(s * 0.4, s * 0.26)), color)
		"enchant":
			for i in 4:
				var ang := i * PI / 4.0
				var dir := Vector2(cos(ang), sin(ang)) * s * (0.38 if i % 2 == 0 else 0.24)
				draw_line(c - dir, c + dir, color, w)
			draw_circle(c, s * 0.08, color)
		"growth":
			for i in 3:
				var hgt := s * (0.25 + i * 0.2)
				draw_rect(Rect2(o + Vector2(s * (0.15 + i * 0.25), s * 0.85 - hgt), Vector2(s * 0.17, hgt)), color)
		"menu":
			for i in 3:
				draw_line(o + Vector2(s * 0.2, s * (0.3 + i * 0.2)), o + Vector2(s * 0.8, s * (0.3 + i * 0.2)), color, w)
		"settings":
			draw_circle(c, s * 0.3, color, false, w * 1.5)
			draw_circle(c, s * 0.1, color)
			for i in 6:
				var ang2 := i * TAU / 6.0
				draw_line(c + Vector2(cos(ang2), sin(ang2)) * s * 0.3, c + Vector2(cos(ang2), sin(ang2)) * s * 0.44, color, w * 1.5)
		"bell":
			draw_arc(c + Vector2(0, -s * 0.02), s * 0.26, PI, TAU, 12, color, w)
			draw_line(c + Vector2(-s * 0.26, -s * 0.02), c + Vector2(-s * 0.3, s * 0.25), color, w)
			draw_line(c + Vector2(s * 0.26, -s * 0.02), c + Vector2(s * 0.3, s * 0.25), color, w)
			draw_line(c + Vector2(-s * 0.36, s * 0.25), c + Vector2(s * 0.36, s * 0.25), color, w)
			draw_circle(c + Vector2(0, s * 0.36), s * 0.06, color)
