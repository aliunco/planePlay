class_name RadarDial
extends Control
## A small scanner under the player card. Your airplane sits in the middle pointing
## along its nose and the enemy is drawn at its real offset from you, so the dial
## answers "where is he?" when he is not on screen. The map wraps left to right, so
## the horizontal offset is taken the shorter way round; an enemy outside the dial's
## range sits on the rim with a hollow ring instead of vanishing.

const RING_RADIUS: float = 52.0
const SWEEP_SPEED: float = 1.5
const DIAL_SIZE: Vector2 = Vector2(RING_RADIUS * 2.0 + 24.0, RING_RADIUS * 2.0 + 24.0)

var _offset: Vector2 = Vector2.ZERO
var _range: float = 1200.0
var _heading: float = -PI * 0.5
var _has_enemy: bool = false
var _sweep: float = 0.0

# The courier and whatever it has let go, so a load can be found off screen.
var _courier_offset: Vector2 = Vector2.ZERO
var _has_courier: bool = false
var _drop_offset: Vector2 = Vector2.ZERO
var _drop_kind: int = -1
var _has_drop: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = DIAL_SIZE
	size = DIAL_SIZE


func _process(delta: float) -> void:
	_sweep = fmod(_sweep + delta * SWEEP_SPEED, TAU)
	queue_redraw()


## `offset` is the enemy minus the local airplane, in world pixels.
func set_target(offset: Vector2, range_px: float, heading: float, has_enemy: bool) -> void:
	_offset = offset
	_range = maxf(1.0, range_px)
	_heading = heading
	_has_enemy = has_enemy


func enemy_offset() -> Vector2:
	return _offset


func set_cargo(
	courier_offset: Vector2,
	has_courier: bool,
	drop_offset: Vector2,
	drop_kind: int,
	has_drop: bool
) -> void:
	_courier_offset = courier_offset
	_has_courier = has_courier
	_drop_offset = drop_offset
	_drop_kind = drop_kind
	_has_drop = has_drop


func has_courier_marker() -> bool:
	return _has_courier


func has_drop_marker() -> bool:
	return _has_drop


func drop_marker_kind() -> int:
	return _drop_kind


func radar_range() -> float:
	return _range


func _draw() -> void:
	var centre := size * 0.5
	draw_circle(centre, RING_RADIUS + 9.0, Color(0.02, 0.06, 0.11, 0.40))
	draw_circle(centre, RING_RADIUS, Color(0.04, 0.10, 0.16, 0.55))
	draw_arc(centre, RING_RADIUS, 0.0, TAU, 56, Color(1.0, 1.0, 1.0, 0.22), 1.5, true)
	draw_arc(centre, RING_RADIUS * 0.5, 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.09), 1.0, true)

	for i in 4:
		var angle := float(i) * PI * 0.5
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(
			centre + direction * (RING_RADIUS - 6.0),
			centre + direction * RING_RADIUS,
			Color(1.0, 1.0, 1.0, 0.24),
			1.5
		)

	# The sweep is only there to show the dial is live.
	var wedge := PackedVector2Array([centre])
	for i in 10:
		var angle := _sweep - float(i) * 0.05
		wedge.append(centre + Vector2(cos(angle), sin(angle)) * RING_RADIUS)
	draw_colored_polygon(wedge, Color(0.55, 0.95, 0.75, 0.06))
	draw_line(
		centre,
		centre + Vector2(cos(_sweep), sin(_sweep)) * RING_RADIUS,
		Color(0.62, 1.0, 0.82, 0.22),
		1.5
	)

	# Your airplane: a small arrowhead pointing where the nose points.
	var forward := Vector2.UP.rotated(_heading)
	var side := forward.orthogonal()
	draw_colored_polygon(
		PackedVector2Array([
			centre + forward * 9.0,
			centre - forward * 6.0 + side * 5.0,
			centre - forward * 6.0 - side * 5.0,
		]),
		Color("ffd166")
	)

	# Cargo first, so the enemy keeps the boldest mark on the dial.
	if _has_courier:
		_draw_courier_marker(centre)
	if _has_drop:
		_draw_drop_marker(centre)

	if _has_enemy:
		_draw_enemy(centre)


## An offset mapped onto the dial, pinned to the rim when it is out of range.
func _dial_point(centre: Vector2, offset: Vector2) -> Vector2:
	var scaled := offset / _range * RING_RADIUS
	var limit := RING_RADIUS - 6.0
	if scaled.length() > limit:
		scaled = scaled.normalized() * limit
	return centre + scaled


## The courier: a pale diamond, so it reads as "another aircraft", not a target.
func _draw_courier_marker(centre: Vector2) -> void:
	var at := _dial_point(centre, _courier_offset)
	draw_colored_polygon(
		PackedVector2Array([
			at + Vector2(0.0, -4.6),
			at + Vector2(4.6, 0.0),
			at + Vector2(0.0, 4.6),
			at + Vector2(-4.6, 0.0),
		]),
		Color(0.88, 0.94, 1.0, 0.92)
	)


## A falling load, coloured like the badge the courier is wearing.
func _draw_drop_marker(centre: Vector2) -> void:
	var accent := Color("6ee06a")
	if _drop_kind == SkyPickup.Kind.KILLER:
		accent = Color("ff6f5c")
	elif _drop_kind == SkyPickup.Kind.HOMING:
		accent = Color("63c9ff")
	elif _drop_kind == SkyPickup.Kind.FLARES:
		accent = Color("fff0b0")
	elif _drop_kind == SkyPickup.Kind.SHIELD:
		accent = Color("b98cff")
	var at := _dial_point(centre, _drop_offset)
	draw_circle(at, 3.0, accent)
	draw_arc(at, 5.2, 0.0, TAU, 16, Color(accent.r, accent.g, accent.b, 0.45), 1.0, true)


func _draw_enemy(centre: Vector2) -> void:
	var scaled := _offset / _range * RING_RADIUS
	var beyond_range := scaled.length() > RING_RADIUS - 5.0
	if beyond_range:
		scaled = scaled.normalized() * (RING_RADIUS - 5.0)

	var at := centre + scaled
	draw_circle(at, 8.5, Color(1.0, 0.42, 0.35, 0.18))
	draw_circle(at, 4.5 if not beyond_range else 3.6, Color("ff7a63"))
	if beyond_range:
		draw_arc(at, 5.8, 0.0, TAU, 16, Color(1.0, 0.55, 0.45, 0.55), 1.2, true)
