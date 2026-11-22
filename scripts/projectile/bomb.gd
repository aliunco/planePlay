class_name Bomb
extends Node2D
## A bomb dropped from under a fighter's belly: it inherits a little of the
## plane's speed, falls under gravity, and bursts when it reaches the field or
## passes through another airplane.
##
## It applies no damage itself. The match owns that decision, because in a LAN
## duel exactly one device is allowed to decide a bomb hit - the one that dropped
## it - so the two copies of a pilot cannot disagree about losing health.

signal exploded(at: Vector2, owner_id: int, authoritative: bool)

const GRAVITY: float = 940.0
## Terminal velocity, so a bomb dropped from high up cannot tunnel through a plane.
const MAX_FALL_SPEED: float = 880.0
## Air drag on the horizontal component: the forward throw bleeds off as it falls.
const DRAG: float = 70.0
## How close a bomb has to pass an airframe to count as a hit.
const HIT_RADIUS: float = 40.0
## A bomb that misses everything is still gone when it hits the field.
const GROUND_MARGIN: float = 6.0

var owner_id: int = 0
var damage: int = 70
var blast_radius: float = 170.0
var is_live: bool = false
## False for the mirrored copy a LAN peer drops: it flies and bursts for show,
## but the device that dropped it decides who gets hurt.
var authoritative: bool = true

var _velocity := Vector2.ZERO
var _planes: Array[Airplane] = []
var _ground_y: float = 0.0
var _age: float = 0.0
var _trail_phase: float = 0.0


func launch(
	at: Vector2,
	velocity: Vector2,
	id: int,
	hit_damage: int,
	radius: float,
	planes: Array[Airplane],
	ground_y: float,
	bounds: Rect2
) -> void:
	global_position = at
	_velocity = velocity
	owner_id = id
	damage = hit_damage
	blast_radius = radius
	_planes = planes
	_ground_y = ground_y
	visible = true
	# A touch over-scale: a bomb is a threat worth seeing coming.
	scale = Vector2.ONE * 1.15
	is_live = true
	_trail_phase = float(id) * 1.7
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_live:
		return
	_age += delta
	_velocity.y = minf(MAX_FALL_SPEED, _velocity.y + GRAVITY * delta)
	_velocity.x = move_toward(_velocity.x, 0.0, DRAG * delta)
	global_position += _velocity * delta
	# The bomb noses over with its fall, so it reads as a falling object rather
	# than a sprite sliding down the screen.
	rotation = _velocity.angle() + PI * 0.5

	for plane in _planes:
		if plane == null or not is_instance_valid(plane):
			continue
		if plane.player_id == owner_id or not plane.is_alive:
			continue
		if plane.is_crashing():
			continue
		if global_position.distance_to(plane.global_position) <= HIT_RADIUS:
			_burst()
			return

	# A burning enemy flare close enough licks the fuse: the bomb goes off in the
	# air, away from the plane it is chasing.
	for node in get_tree().get_nodes_in_group(&"flares"):
		var flare := node as Flare
		if flare == null or not is_instance_valid(flare) or not flare.is_burning():
			continue
		if flare.owner_id == owner_id:
			continue
		if global_position.distance_to(flare.global_position) <= Flare.BOMB_RADIUS:
			_burst()
			return

	if global_position.y >= _ground_y - GROUND_MARGIN:
		global_position.y = _ground_y - GROUND_MARGIN
		_burst()


func _burst() -> void:
	is_live = false
	set_physics_process(false)
	visible = false
	exploded.emit(global_position, owner_id, authoritative)
	queue_free()


func _draw() -> void:
	# Body: a fat teardrop with a blunt tail, drawn nose-down in local space so the
	# node's rotation lines it up with the fall.
	var body := Color(0.28, 0.31, 0.24)
	var shade := Color(0.16, 0.18, 0.14)
	var light := Color(0.55, 0.58, 0.48)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, 15.0),
				Vector2(4.6, 8.0),
				Vector2(5.2, -6.0),
				Vector2(2.6, -13.0),
				Vector2(-2.6, -13.0),
				Vector2(-5.2, -6.0),
				Vector2(-4.6, 8.0),
			]
		),
		body
	)
	# Highlight down one flank.
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-2.0, 13.0),
				Vector2(-4.2, 6.0),
				Vector2(-4.4, -5.0),
				Vector2(-2.2, -11.0),
				Vector2(-1.2, -6.0),
				Vector2(-1.2, 6.0),
			]
		),
		Color(light, 0.45)
	)
	draw_line(Vector2(0.0, 12.0), Vector2(0.0, -12.0), Color(shade, 0.55), 1.2)
	# Tail fins, crossed so they read from the side whatever the spin.
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-5.4, -6.0),
				Vector2(-10.5, -14.0),
				Vector2(-2.4, -12.5),
			]
		),
		shade
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(5.4, -6.0),
				Vector2(10.5, -14.0),
				Vector2(2.4, -12.5),
			]
		),
		Color(shade, 0.85)
	)
	# A small yellow band around the middle.
	draw_rect(Rect2(-5.0, -1.0, 10.0, 3.0), Color(0.86, 0.72, 0.24, 0.9))
	# The fuse at the tail, blinking, and a faint vapour smear behind the fall.
	var blink := 0.5 + 0.5 * sin(_age * 18.0 + _trail_phase)
	draw_circle(Vector2(0.0, -13.5), 1.8 + blink, Color(1.0, 0.72, 0.32, 0.75))
	if _velocity.length() > 120.0:
		var back := -_velocity.normalized() * 20.0
		draw_line(Vector2.ZERO + back, Vector2.ZERO + back * 2.2, Color(1.0, 1.0, 1.0, 0.16), 2.0)
