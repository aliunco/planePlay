class_name BoostGauge
extends Control
## A slim energy strip tucked under a pilot's health bar: the jet-boost tank.
##
## It reads at a glance without competing with the health bar above it - a cool
## cyan line that drains when the boost is lit, refills while the pilot leaves it
## alone, and glows softly when the tank is full and the boost is ready to go.

const FULL_COLOR := Color("6fe3ff")
const LOW_COLOR := Color("ff8f5e")
## How fast the drawn level chases the real one. Slower than the fill of a health
## bar: the tank is a resource, and watching it trickle back is half the point.
const CHASE_RATE: float = 0.9

@export var mirrored: bool = false

var _ratio: float = 1.0
var _display: float = 1.0
var _time: float = 0.0
var _style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.anti_aliasing = true
	_style.corner_detail = 10
	resized.connect(queue_redraw)


func set_ratio(ratio: float) -> void:
	_ratio = clampf(ratio, 0.0, 1.0)


func ratio() -> float:
	return _ratio


func _process(delta: float) -> void:
	_time += delta
	_display = move_toward(_display, _ratio, CHASE_RATE * delta)
	queue_redraw()


func _draw() -> void:
	if size.x < 8.0 or size.y < 3.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var radius := int(size.y * 0.5)

	# Recessed track: barely there, so the strip reads as part of the card.
	_box(rect, radius, Color(0.02, 0.05, 0.09, 0.7), Color(1.0, 1.0, 1.0, 0.07), 1)

	if _display <= 0.001:
		return
	var width := rect.size.x * _display
	var start_x := rect.size.x - width if mirrored else 0.0
	var fill := Rect2(Vector2(start_x, 1.0), Vector2(width, rect.size.y - 2.0))
	var fill_radius := maxi(1, mini(radius - 1, int(width * 0.5)))

	var color := FULL_COLOR
	if _ratio < 0.18:
		color = LOW_COLOR
	elif _ratio < 0.6:
		color = FULL_COLOR.lerp(LOW_COLOR, 0.35)

	_box(fill, fill_radius, color, Color(0.0, 0.0, 0.0, 0.0), 0)
	# A lighter line along the top of the fill: the same glass as the health bar,
	# scaled down to a strip.
	if width > 4.0:
		_box(
			Rect2(fill.position + Vector2(1.0, 0.0), Vector2(width - 2.0, (rect.size.y - 2.0) * 0.45)),
			maxi(1, fill_radius - 1),
			Color(color.lightened(0.45), 0.75),
			Color(0.0, 0.0, 0.0, 0.0),
			0
		)
	# A bright tip so a draining tank has a moving edge.
	if _display < 0.995:
		var lip_x := start_x + 1.0 if mirrored else start_x + width - 2.0
		_box(
			Rect2(Vector2(lip_x, 1.0), Vector2(2.0, rect.size.y - 2.0)),
			maxi(1, int((rect.size.y - 2.0) * 0.5)),
			Color(1.0, 1.0, 1.0, 0.75),
			Color(0.0, 0.0, 0.0, 0.0),
			0
		)
	# Full tank: a soft travelling sheen, the visual equivalent of "ready".
	if _ratio >= 0.995:
		var sweep := fposmod(_time * 0.6, 1.0)
		var sheen_x := start_x + width * sweep
		_box(
			Rect2(Vector2(sheen_x, 0.0), Vector2(16.0, rect.size.y)),
			radius,
			Color(1.0, 1.0, 1.0, 0.16),
			Color(0.0, 0.0, 0.0, 0.0),
			0
		)


func _box(rect: Rect2, radius: int, color: Color, border: Color, border_width: int) -> void:
	_style.bg_color = color
	_style.border_color = border
	_style.set_border_width_all(border_width)
	_style.set_corner_radius_all(maxi(0, radius))
	draw_style_box(_style, rect)
