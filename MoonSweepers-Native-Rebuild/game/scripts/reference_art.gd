extends Control

var mode := "sidebar"
var value := 0.0
var angle := 0.0

func _draw():
	if mode == "sidebar":
		draw_rect(Rect2(Vector2.ZERO, size), Color("19181e"))
		for y in range(-50, ceili(size.y) + 50, 40):
			draw_colored_polygon(PackedVector2Array([Vector2(size.x - 28, y + 25), Vector2(size.x, y), Vector2(size.x, y + 21), Vector2(size.x - 28, y + 46)]), Color("ff8026"))
	elif mode == "coin":
		draw_circle(size / 2, size.x * 0.44, Color("ffb719"))
		draw_arc(size / 2, size.x * 0.38, 0, TAU, 48, Color("ff8a16"), 3)
	elif mode == "ring":
		draw_arc(size / 2, size.x * 0.44, 0, TAU, 64, Color(1, 1, 1, 0.35), 2)
		draw_arc(size / 2, size.x * 0.44, -PI / 2, -PI / 2 + maxf(value, 0.001) * TAU, 64, Color("ff8429"), 4)
	elif mode == "compass":
		draw_line(Vector2.ZERO, Vector2(size.x, 0), Color(1, 1, 1, 0.26), 2)
		for i in range(-24, 25):
			var x := size.x / 2 + i * 18 - fmod(angle * 150, 18.0)
			if x < 0 or x > size.x: continue
			draw_line(Vector2(x, 0), Vector2(x, -12 if i % 5 == 0 else -5), Color(1, 1, 1, 0.4), 2)
		draw_colored_polygon(PackedVector2Array([Vector2(size.x / 2 - 4, -22), Vector2(size.x / 2 + 4, -22), Vector2(size.x / 2, -13)]), Color("ffba3b"))
