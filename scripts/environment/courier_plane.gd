class_name CourierPlane
extends Node2D
## A small cargo plane that crosses the sky now and then and kicks one pickup out
## over the fields. It is scenery with a purpose: smaller and hazier than the
## fighters, drawn behind them, and it cannot be shot at or collided with — the
## drop is the only thing that matters.
##
## The pass is planned up front (where it enters, where it lets go, where it
## leaves), so both ends of a LAN match can agree on the drop point exactly.

signal dropped(at: Vector2, kind: int)

const MODEL_SCALE: float = 0.48
const BODY: Color = Color("e3e8ef")
const ACCENT: Color = Color("d2a94c")
const BELLY: Color = Color("ccd4de")
## Dampened a little so it sits back in the haze instead of competing with the
## fighters for attention.
const HAZE: Color = Color(0.9, 0.94, 1.0, 0.96)
const PROP_SPEED: float = 26.0
## How far before the drop point the pass begins, and how much sky it covers
## afterwards. Long enough to see it coming.
const APPROACH: float = 700.0
const DEPARTURE: float = 1000.0

## The little plate on the fuselage: the same idea as the load it will let go, so
## you can tell a repair run from a special one before anything is released.
class PayloadBadge:
	extends Node2D

	var kind: int = SkyPickup.Kind.REPAIR

	func show_kind(new_kind: int) -> void:
		kind = new_kind
		queue_redraw()

	func _draw() -> void:
		var accent := Color("63c9ff")
		match kind:
			SkyPickup.Kind.REPAIR:
				accent = Color("6ee06a")
			SkyPickup.Kind.KILLER:
				accent = Color("ff6f5c")
			SkyPickup.Kind.FLARES:
				accent = Color("fff0b0")
			SkyPickup.Kind.SHIELD:
				accent = Color("b98cff")
		draw_circle(Vector2.ZERO, 9.5, Color(0.04, 0.09, 0.14, 0.88))
		draw_arc(Vector2.ZERO, 9.5, 0.0, TAU, 24, accent, 2.0, true)
		match kind:
			SkyPickup.Kind.REPAIR:
				draw_rect(Rect2(-1.5, -5.0, 3.0, 10.0), accent)
				draw_rect(Rect2(-5.0, -1.5, 10.0, 3.0), accent)
			SkyPickup.Kind.KILLER:
				draw_circle(Vector2.ZERO, 3.8, accent)
				# A cross through the dot: "this one finishes the fight".
				draw_line(Vector2(-5.2, -5.2), Vector2(5.2, 5.2), accent, 1.6)
				draw_line(Vector2(5.2, -5.2), Vector2(-5.2, 5.2), accent, 1.6)
			_:
				# A chasing arrow curled round the plate.
				draw_arc(Vector2.ZERO, 5.0, -0.5, PI * 1.15, 16, accent, 2.0, true)
				draw_colored_polygon(
					PackedVector2Array(
						[Vector2(-1.6, 4.2), Vector2(1.6, 5.0), Vector2(-1.4, 1.9)]
					),
					accent
				)


var _visual: Node2D
var _sprite: Sprite2D
var _badge: PayloadBadge
var _model: PlaneModel3D
var _flying: bool = false
var _speed: float = 180.0
var _direction: float = 1.0
var _end_x: float = 0.0
var _drop_x: float = 0.0
var _drop_y: float = 0.0
var _kind: int = SkyPickup.Kind.REPAIR
var _dropped: bool = false
var _time: float = 0.0


func _ready() -> void:
	z_index = 1
	modulate = HAZE
	_visual = Node2D.new()
	add_child(_visual)

	_model = PlaneModel3D.new()
	add_child(_model)
	_model.build(BODY, ACCENT, BELLY)
	_model.set_gear_down(false)
	_model.set_propeller_speed(PROP_SPEED)

	_sprite = Sprite2D.new()
	_sprite.texture = _model.get_texture()
	_sprite.scale = Vector2.ONE * _model.sprite_scale()
	_visual.add_child(_sprite)
	_visual.scale = Vector2.ONE * MODEL_SCALE

	# Drawn after the airframe, so the plate sits on the fuselage rather than
	# behind it.
	_badge = PayloadBadge.new()
	add_child(_badge)

	visible = false
	set_physics_process(false)


## Sends it across the sky. It enters from one side of `drop_x` and leaves on the
## other, releasing its load when it passes the drop point.
func launch(
	drop_x: float,
	altitude: float,
	ground_y: float,
	flight_speed: float,
	from_left: bool,
	kind: int
) -> void:
	_direction = 1.0 if from_left else -1.0
	_speed = flight_speed
	_drop_x = drop_x
	_drop_y = ground_y - altitude
	_kind = kind
	_dropped = false
	_time = 0.0
	_flying = true
	position = Vector2(drop_x - _direction * APPROACH, _drop_y)
	_end_x = drop_x + _direction * DEPARTURE
	rotation = _direction * PI * 0.5
	# Art is drawn nose-right; mirror it for a pass running the other way.
	_sprite.flip_h = _direction < 0.0
	_visual.rotation = PI * 0.5 if _direction < 0.0 else -PI * 0.5
	# The plate is painted on the side of the fuselage, but kept upright so the
	# icon stays readable while the airframe is turned along its heading.
	_badge.show_kind(kind)
	_badge.rotation = -rotation
	visible = true
	set_physics_process(true)


func is_flying() -> bool:
	return _flying


## The point and altitude it was told to drop at, whether or not it has yet.
func planned_drop() -> Vector2:
	return Vector2(_drop_x, _drop_y)


func stop() -> void:
	_flying = false
	_dropped = true
	visible = false
	set_physics_process(false)


func _physics_process(delta: float) -> void:
	if not _flying:
		return

	_time += delta
	position.x += _direction * _speed * delta
	_visual.position.y = sin(_time * 3.4) * 2.2

	var reached_drop := (
		(_direction > 0.0 and position.x >= _drop_x)
		or (_direction < 0.0 and position.x <= _drop_x)
	)
	if not _dropped and reached_drop:
		_dropped = true
		# The planned point, not the current frame's position: the load hangs out
		# of the hatch at the moment the pass is planned for, on every device.
		dropped.emit(Vector2(_drop_x, _drop_y + 10.0), _kind)

	var past_end := (
		(_direction > 0.0 and position.x >= _end_x)
		or (_direction < 0.0 and position.x <= _end_x)
	)
	if past_end:
		stop()
