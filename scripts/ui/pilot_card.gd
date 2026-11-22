class_name PilotCard
extends Control
## The glass card behind a pilot's name and health bar. Drawn rather than styled:
## a soft drop shadow, a deep navy body with a lit rim, a sheen across the top, a
## hairline under the header, an accent rail down the outer edge and a small badge
## with the aircraft's nose in it.
##
## The accent turns red - badge, rail and all - when that pilot's airframe is
## nearly gone, which reads from the corner of the eye.

const RADIUS: int = 18
const BADGE_RADIUS: float = 11.0

## Opponent cards mirror the layout, so the rail and badge sit on the outer edge.
@export var mirrored: bool = false
@export var accent: Color = UIStyle.ACCENT

var _ratio: float = 1.0
var _style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.anti_aliasing = true
	_style.corner_detail = 12
	resized.connect(queue_redraw)


func set_health_ratio(ratio: float) -> void:
	var next := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(next, _ratio):
		return
	_ratio = next
	queue_redraw()


func set_accent(color: Color) -> void:
	if color == accent:
		return
	accent = color
	queue_redraw()


func _draw() -> void:
	if size.x < 40.0 or size.y < 40.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var panel := rect.grow(-1.0)

	# The accent cools to ember red as the plane runs out of health.
	var alarm := clampf((0.30 - _ratio) / 0.30, 0.0, 1.0)
	var rail := accent.lerp(Color("ff5d4a"), alarm)

	# 1. Drop shadow, offset down so the card sits above the sky.
	_box(rect, RADIUS, Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), 0, 14, Color(0.01, 0.03, 0.06, 0.42), Vector2(0.0, 7.0))

	# 2. Glass body: deep navy, a lit rim, a whisper of colour from the pilot.
	var body := Color(0.035, 0.075, 0.12, 0.92).lerp(Color(0.10, 0.05, 0.06, 0.92), alarm * 0.5)
	_box(panel, RADIUS, body, Color(1.0, 1.0, 1.0, 0.11), 1)

	# 3. Sheen across the top third, and a warm tint from the accent.
	_box(
		Rect2(panel.position + Vector2(3.0, 3.0), Vector2(panel.size.x - 6.0, panel.size.y * 0.44)),
		RADIUS - 4,
		Color(1.0, 1.0, 1.0, 0.05),
		Color(0.0, 0.0, 0.0, 0.0),
		0
	)
	_box(
		Rect2(panel.position + Vector2(3.0, 3.0), Vector2(panel.size.x - 6.0, panel.size.y * 0.16)),
		RADIUS - 4,
		Color(rail, 0.07),
		Color(0.0, 0.0, 0.0, 0.0),
		0
	)

	# 4. Hairline between the header and the bar.
	var rule_y := size.y * 0.47
	draw_line(
		Vector2(16.0, rule_y),
		Vector2(size.x - 16.0, rule_y),
		Color(1.0, 1.0, 1.0, 0.10),
		1.0,
		true
	)

	# 5. Accent rail down the outer edge, with a soft glow behind it.
	var rail_x := 6.0 if not mirrored else size.x - 10.0
	_box(
		Rect2(Vector2(rail_x - 3.0, 14.0), Vector2(10.0, size.y - 28.0)),
		5,
		Color(rail, 0.16),
		Color(0.0, 0.0, 0.0, 0.0),
		0
	)
	_box(
		Rect2(Vector2(rail_x, 16.0), Vector2(4.0, size.y - 32.0)),
		2,
		rail,
		Color(0.0, 0.0, 0.0, 0.0),
		0
	)

	# 6. Badge: a ringed disc with the aircraft's nose in it.
	var centre := Vector2(26.0 if not mirrored else size.x - 26.0, size.y * 0.30)
	draw_circle(centre, BADGE_RADIUS, Color(rail, 0.16))
	draw_arc(centre, BADGE_RADIUS, 0.0, TAU, 28, Color(rail, 0.55), 1.5, true)
	var dir := -1.0 if mirrored else 1.0
	draw_colored_polygon(
		PackedVector2Array(
			[
				centre + Vector2(6.4 * dir, -4.6),
				centre + Vector2(7.8 * dir, 0.0),
				centre + Vector2(6.4 * dir, 4.6),
				centre + Vector2(-4.4 * dir, 1.4),
				centre + Vector2(-4.4 * dir, -1.4),
			]
		),
		Color(rail, 0.95)
	)


func _box(
	rect: Rect2,
	radius: int,
	color: Color,
	border: Color,
	border_width: int,
	shadow_size: int = 0,
	shadow_color: Color = Color(0.0, 0.0, 0.0, 0.0),
	shadow_offset: Vector2 = Vector2.ZERO
) -> void:
	_style.bg_color = color
	_style.border_color = border
	_style.set_border_width_all(border_width)
	_style.set_corner_radius_all(maxi(0, radius))
	_style.shadow_size = shadow_size
	_style.shadow_color = shadow_color
	_style.shadow_offset = shadow_offset
	draw_style_box(_style, rect)
