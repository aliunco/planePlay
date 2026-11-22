class_name Flare
extends Node2D
## A defensive flare: a burning magnesium star kicked out behind the plane. It
## drifts, falls, gutters out after a couple of seconds, and drags any homing
## round that comes near it off the pilot who dropped it. A bomb passing close
## enough gets its fuse lit early as well, which is the point of the whole thing.
##
## Flares deal no damage and belong to nobody but the pilot who burned them: they
## only ever redirect things that are already hunting that pilot.

## How close a homing round has to be before the flare wins its attention.
const DECOY_RADIUS: float = 320.0
## And how close it has to get before the round spends itself on the flare.
const DECOY_HIT_RADIUS: float = 18.0
## A bomb this close goes off early, well away from the plane that dropped it.
const BOMB_RADIUS: float = 46.0
const BURN_SECONDS: float = 1.8
const FADE_SECONDS: float = 0.7
const GRAVITY: float = 460.0
const DRAG: float = 1.5

var owner_id: int = 0

var _velocity := Vector2.ZERO
var _age: float = 0.0
var _seed: float = 0.0


func _ready() -> void:
	# Homing rounds and bombs look for burning flares in this group.
	add_to_group(&"flares")
	z_index = 1
	queue_redraw()


func launch(at: Vector2, velocity: Vector2, id: int) -> void:
	global_position = at
	_velocity = velocity
	owner_id = id
	_seed = randf() * TAU


## True while the flare is still alight and worth chasing.
func is_burning() -> bool:
	return _age < BURN_SECONDS


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > BURN_SECONDS + FADE_SECONDS:
		queue_free()
		return
	_velocity.y += GRAVITY * delta
	_velocity = _velocity.lerp(Vector2.ZERO, minf(1.0, DRAG * delta))
	global_position += _velocity * delta
	queue_redraw()


func _draw() -> void:
	var fade := 1.0
	if _age > BURN_SECONDS:
		fade = maxf(0.0, 1.0 - (_age - BURN_SECONDS) / FADE_SECONDS)
	var flicker := 0.75 + 0.25 * sin(_age * 47.0 + _seed) + 0.1 * sin(_age * 91.0 + _seed * 2.0)
	var heat := clampf(flicker, 0.0, 1.0) * fade
	if heat <= 0.01:
		return

	# The glow, then the white-hot core: three discs of decreasing size.
	draw_circle(Vector2.ZERO, 26.0 * heat, Color(1.0, 0.55, 0.18, 0.10 * heat))
	draw_circle(Vector2.ZERO, 13.0 * heat, Color(1.0, 0.72, 0.3, 0.22 * heat))
	draw_circle(Vector2.ZERO, 6.0 * heat, Color(1.0, 0.88, 0.55, 0.85 * heat))
	draw_circle(Vector2.ZERO, 2.6 * heat, Color(1.0, 1.0, 0.94, 0.95 * heat))

	# Sparks guttering off it, thrown out along the drift.
	for i in 5:
		var angle := _seed + float(i) * 1.257 + _age * 3.0
		var reach := 8.0 + 14.0 * fposmod(_age * 1.4 + float(i) * 0.23, 1.0)
		var spark := Vector2(cos(angle), sin(angle)) * reach * (0.6 + 0.4 * heat)
		draw_circle(spark, 1.5 * heat, Color(1.0, 0.82, 0.45, 0.55 * heat))

	# A thin trail of smoke behind it, so a burst of flares reads as a curtain.
	var back := -_velocity.normalized() * 16.0 if _velocity.length() > 4.0 else Vector2(0.0, 12.0)
	for i in 4:
		var t := float(i) / 3.0
		draw_circle(
			back * (1.0 + t * 2.2),
			3.0 + t * 6.0,
			Color(0.72, 0.72, 0.74, (0.16 - t * 0.035) * fade)
		)
