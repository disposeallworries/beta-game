extends Control
class_name ExpeditionRadar
## North-up XZ map; model yaw is +Z-forward, matching the actual blob rotation.

const CYAN := Color("65d8e8")
const GOLD := Color("e9bd78")
const PURPLE := Color("bc91eb")
const RED := Color("f27c78")
const MUTED := Color("9cabb8")

var phase: String = "explore"
var player_position := Vector3.ZERO
var player_yaw: float = PI
var world_bounds: Array[AABB] = []
var pool_positions: Array[Vector3] = []
var sword_positions: Array[Vector3] = []
var enemy_positions: Array[Vector3] = []
var portal_position := Vector3.ZERO
var radius: float = 90.0
var _card_style: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func update_data(data: Dictionary) -> void:
	phase = str(data.get("phase", "explore"))
	player_position = data.get("radar_player", Vector3.ZERO)
	player_yaw = float(data.get("radar_yaw", PI))
	world_bounds.assign(data.get("radar_bounds", []))
	pool_positions.assign(data.get("radar_pools", []))
	sword_positions.assign(data.get("radar_swords", []))
	enemy_positions.assign(data.get("radar_enemies", []))
	portal_position = data.get("radar_portal", Vector3.ZERO)
	radius = maxf(float(data.get("radar_radius", 90.0)), 1.0)
	queue_redraw()


func map_rect() -> Rect2:
	var side: float = maxf(minf(size.x - 24.0, size.y - 58.0), 40.0)
	return Rect2(Vector2((size.x - side) * 0.5, 30.0), Vector2.ONE * side)


func world_to_map(at: Vector3, clamp_to_edge: bool = false) -> Vector2:
	var area := map_rect()
	var point: Vector2 = area.get_center() + Vector2(at.x - player_position.x, at.z - player_position.z) * area.size.x / (radius * 2.0)
	if clamp_to_edge:
		point.x = clampf(point.x, area.position.x + 5.0, area.end.x - 5.0)
		point.y = clampf(point.y, area.position.y + 5.0, area.end.y - 5.0)
	return point


func heading_polygon() -> PackedVector2Array:
	var center := map_rect().get_center()
	var triangle := PackedVector2Array()
	for point in [Vector2(0, -6.0), Vector2(-4.2, 4.5), Vector2(0, 2.5), Vector2(4.2, 4.5)]:
		triangle.append(center + point.rotated(PI - player_yaw))
	return triangle


func _draw() -> void:
	if size.x < 1.0 or size.y < 1.0:
		return
	if _card_style == null:
		_card_style = StyleBoxFlat.new()
		_card_style.bg_color = Color(0.026, 0.043, 0.061, 0.90)
		_card_style.border_color = Color("355061")
		_card_style.set_border_width_all(1)
		_card_style.set_corner_radius_all(8)
	draw_style_box(_card_style, Rect2(Vector2.ZERO, size))
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(12, 19), "THREATS" if phase == "defend" else "FIELD MAP", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
	var area := map_rect()
	draw_rect(area, Color("0c1923"), true)
	var center := area.get_center()
	draw_line(Vector2(center.x, area.position.y), Vector2(center.x, area.end.y), Color(0.24, 0.33, 0.39, 0.18), 1)
	draw_line(Vector2(area.position.x, center.y), Vector2(area.end.x, center.y), Color(0.24, 0.33, 0.39, 0.18), 1)
	for bounds in world_bounds:
		var start: Vector2 = world_to_map(bounds.position)
		var end: Vector2 = world_to_map(bounds.end)
		var projection := Rect2(start, end - start)
		if not projection.intersects(area):
			continue
		var clipped: Rect2 = projection.intersection(area)
		var shade := Color(0.26, 0.35, 0.39, 0.62)
		if bounds.end.y > player_position.y + 2.0:
			shade = Color(0.37, 0.41, 0.44, 0.66)
		draw_rect(clipped, shade, true)
		draw_rect(clipped, Color(0.52, 0.65, 0.66, 0.45), false, 1)
	if phase == "defend":
		_draw_tower(world_to_map(Vector3.ZERO, true))
		for at in enemy_positions:
			var point := world_to_map(at, true)
			draw_circle(point, 5.0, Color(0.95, 0.26, 0.22, 0.16))
			draw_circle(point, 2.8, RED)
	else:
		for at in pool_positions:
			var point := world_to_map(at, true)
			draw_circle(point, 5.5, Color(0.28, 0.85, 0.95, 0.15))
			draw_circle(point, 3.0, CYAN)
		for at in sword_positions:
			_draw_sword(world_to_map(at, true))
		var portal := world_to_map(portal_position, true)
		draw_circle(portal, 4.5, Color(0.19, 0.11, 0.29, 1))
		draw_arc(portal, 4.5, 0, TAU, 20, PURPLE, 1.5, true)
		draw_circle(portal, 1.4, PURPLE)
	draw_circle(center, 7.2, Color(0.02, 0.05, 0.08, 0.9))
	draw_colored_polygon(heading_polygon(), Color("f0f6f8"))
	draw_rect(area, Color(0.43, 0.57, 0.65, 0.6), false, 1)
	var footer_y: float = area.end.y + 17.0
	draw_string(font, Vector2(area.position.x, footer_y), "N ↑   E →", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)
	var scale_text := "%dm" % int(radius)
	var width: float = font.get_string_size(scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(area.end.x - width, footer_y), scale_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, MUTED)


func _draw_tower(at: Vector2) -> void:
	draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), Color("342d23"), true)
	draw_rect(Rect2(at - Vector2(4, 4), Vector2(8, 8)), GOLD, false, 1.5)
	draw_line(at + Vector2(-4, -5), at + Vector2(-4, -7), GOLD, 1.5)
	draw_line(at + Vector2(0, -5), at + Vector2(0, -7), GOLD, 1.5)
	draw_line(at + Vector2(4, -5), at + Vector2(4, -7), GOLD, 1.5)


func _draw_sword(at: Vector2) -> void:
	draw_line(at + Vector2(-3, 3), at + Vector2(4, -4), GOLD, 2.0, true)
	draw_line(at + Vector2(-3, -1), at + Vector2(1, 3), GOLD, 1.5, true)
	draw_line(at + Vector2(-4.5, 4.5), at + Vector2(-2.5, 2.5), GOLD, 2.0, true)
