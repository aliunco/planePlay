class_name HealthBar
extends Control
## A capsule health bar drawn by hand instead of styled: a dark glass track, a
## glossy fill that drains smoothly, a warm "ghost" that lags a moment behind a
## hit so the size of the damage is visible, one groove per hit it takes to shoot
## a plane down, and a pulsing warning ring when the airframe is nearly gone.
##
## The bar owns its own animation: callers only report health.

## How fast the fill runs down (bar widths per second) and how fast the lagging
## damage ghost catches up after its short hold.
const DRAIN_RATE: float = 2.4
const GHOST_RATE: float = 0.55
const GHOST_HOLD: float = 0.28
## Below this the bar pulses: the pilot is in trouble.
const DANGER_RATIO: float = 0.25

var max_health: int = 150
var health: int = 150
## Guide grooves, one per hit. PlaneConfig.HITS_TO_KILL.
var segments: int = 5
## The opponent's bar fills from the right, mirroring the card.
@export var mirrored: bool = false

var _ratio: float = 1.0
var _display: float = 1.0
var _ghost: float = 1.0
var _ghost_hold: float = 0.0
var _time: float = 0.0
var _style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.anti_aliasing = true
	_style.corner_detail = 10
	resized.connect(queue_redraw)


func set_health(current: int, maximum: int) -> void:
	maximum = maxi(1, maximum)
	current = clampi(current, 0, maximum)
	var next := float(current) / float(maximum)
	if next < _ratio:
		# A hit: the ghost stays where the bar was, then drains after a beat.
		_ghost = maxf(_ghost, _ratio)
		_ghost_hold = GHOST_HOLD
	elif next > _ratio:
		# Repaired, or a fresh round: the fill rises to meet it, no stale ghost.
		_ghost = next
	health = current
	max_health = maximum
	_ratio = next


func ratio() -> float:
	return _ratio


func _process(delta: float) -> void:
	_time += delta
	_display = move_toward(_display, _ratio, DRAIN_RATE * delta)
	if _ghost_hold > 0.0:
		_ghost_hold -= delta
	else:
		_ghost = move_toward(_ghost, _display, GHOST_RATE * delta)
	queue_redraw()


func _draw() -> void:
	if size.x < 6.0 or size.y < 4.0:
		return
	var rect := Rect2(Vector2.ZERO, size)
	var radius := int(minf(size.y * 0.5, 14.0))

	# Track: recessed dark glass with a lit top edge.
	_box(rect, radius, Color(0.018, 0.05, 0.082, 0.96), Color(1.0, 1.0, 1.0, 0.10), 1)
	_box(
		Rect2(rect.position + Vector2(2.0, 2.0), Vector2(rect.size.x - 4.0, rect.size.y * 0.46)),
		maxi(1, radius - 2),
		Color(0.0, 0.0, 0.0, 0.20),
		Color(0.0, 0.0, 0.0, 0.0),
		0
	)

	# The chunk just lost, still hanging on for a beat.
	if _ghost > _display + 0.002:
		_bar_fill(rect, radius, _ghost, Color(1.0, 0.74, 0.50, 0.60))

	if _display > 0.002:
		var color := UIStyle.health_color(_display)
		_bar_fill(rect, radius, _display, color)
		# Gloss over the top half, shade along the bottom: a glass tube.
		var width := size.x * _display
		var start_x := size.x - width if mirrored else 0.0
		var fill_rect := Rect2(Vector2(start_x, 1.0), Vector2(width, size.y - 2.0))
		var inner_radius := maxi(1, mini(radius - 1, int(width * 0.5)))
		_box(
			Rect2(fill_rect.position, Vector2(width, fill_rect.size.y * 0.50)),
			inner_radius,
			Color(color.lightened(0.42), 0.62),
			Color(0.0, 0.0, 0.0, 0.0),
			0
		)
		_box(
			Rect2(
				Vector2(fill_rect.position.x, fill_rect.end.y - fill_rect.size.y * 0.32),
				Vector2(width, fill_rect.size.y * 0.32)
			),
			inner_radius,
			Color(color.darkened(0.46), 0.52),
			Color(0.0, 0.0, 0.0, 0.0),
			0
		)
		# A hairline of pure light along the very top: the glass tube's shine.
		if width > 8.0:
			_box(
				Rect2(Vector2(fill_rect.position.x + 2.0, 2.4), Vector2(width - 4.0, 1.6)),
				1,
				Color(1.0, 1.0, 1.0, 0.22),
				Color(0.0, 0.0, 0.0, 0.0),
				0
			)
		# A bright lip on the leading edge, so a draining bar has a moving point.
		if _display < 0.995 and width > 6.0:
			var edge_x := start_x + 1.0 if mirrored else start_x + width - 3.0
			_box(
				Rect2(Vector2(edge_x, 2.0), Vector2(2.5, size.y - 4.0)),
				maxi(1, int((size.y - 4.0) * 0.5)),
				Color(color.lightened(0.55), 0.85),
				Color(0.0, 0.0, 0.0, 0.0),
				0
			)

	# Guide grooves: one per hit.
	if segments > 1:
		for i in range(1, segments):
			var x := size.x * float(i) / float(segments)
			draw_line(
				Vector2(x, 2.0), Vector2(x, size.y - 2.0), Color(0.0, 0.02, 0.04, 0.55), 2.0, true
			)
			draw_line(
				Vector2(x + 2.0, 3.0),
				Vector2(x + 2.0, size.y - 3.0),
				Color(1.0, 1.0, 1.0, 0.06),
				1.0,
				true
			)

	# Nearly gone: a soft warning ring pulsing around the bar.
	if _ratio <= DANGER_RATIO:
		var pulse := 0.30 + 0.22 * sin(_time * 5.0)
		_box(
			rect.grow(1.5),
			radius + 1,
			Color(0.0, 0.0, 0.0, 0.0),
			Color(1.0, 0.36, 0.28, pulse),
			2
		)


func _bar_fill(rect: Rect2, radius: int, ratio: float, color: Color) -> void:
	var width := rect.size.x * clampf(ratio, 0.0, 1.0)
	if width < 1.0:
		return
	var start_x := rect.size.x - width if mirrored else 0.0
	_box(
		Rect2(rect.position + Vector2(start_x, 0.0), Vector2(width, rect.size.y)),
		maxi(1, mini(radius, int(width * 0.5))),
		color,
		Color(0.0, 0.0, 0.0, 0.0),
		0
	)


func _box(rect: Rect2, radius: int, color: Color, border: Color, border_width: int) -> void:
	_style.bg_color = color
	_style.border_color = border
	_style.set_border_width_all(border_width)
	_style.set_corner_radius_all(maxi(0, radius))
	_style.shadow_size = 0
	_style.shadow_color = Color(0.0, 0.0, 0.0, 0.0)
	draw_style_box(_style, rect)
