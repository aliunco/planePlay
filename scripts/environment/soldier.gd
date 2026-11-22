class_name Soldier
extends Node2D
## An infantryman standing on the flat surface, drawn as a low-poly 3D figure seen
## from the side - the same 2.5D trick the airplanes use. He works a pintle-mounted
## heavy cannon, swinging it round to follow the nearest plane overhead and putting
## a single slow shell up at it; he never leads his target, so the squad is a
## nuisance rather than a threat.

signal shot_fired(origin: Vector2, direction: Vector2)

## Uniform colours, one per soldier, so a squad is not one flat block.
const UNIFORMS: Array[Color] = [Color("6f7a48"), Color("7d6a4a")]
## Where the rifle rests between targets, one per idle stance: held level, angled
## up and shouldered. Matches the stance list in SoldierModel3D.
const REST_AIMS: Array[float] = [-0.25, 0.3, 0.92]
## Where the heavy gun pivots, in screen pixels from the soldier's feet, and how
## far the muzzle sits from it. Must match SoldierModel3D: the shells are born at
## the muzzle, so the two numbers have to agree.
const SHOULDER := Vector2(1.5, -19.0)
const RIFLE_REACH: float = 18.0
## The rifle never points below the horizon or past straight up.
const AIM_MIN: float = -0.25
const AIM_MAX: float = 1.45
## How fast the rifle swings onto a new aim, in radians per second.
const AIM_TURN_RATE: float = 2.6
## Shots only come from roughly below the plane, so the battlefield reads as one.
const MAX_TARGET_HEIGHT: float = 900.0

var planes: Array[Airplane] = []
var range_px: float = 1500.0
var interval_min: float = 3.5
var interval_max: float = 7.0
var aim_spread_degrees: float = 8.0
## The rendered 3D figure; built in setup() because the uniform varies.
var model: SoldierModel3D

var _rng := RandomNumberGenerator.new()
var _timer: float = 0.0
var _time: float = 0.0
var _aim: float = AIM_MIN
var _rest_aim: float = AIM_MIN
var _facing: float = 1.0
var _bob_phase: float = 0.0
var _bob_speed: float = 1.7

@onready var body: Sprite2D = $Body


func setup(
	uniform: int,
	seed_value: int,
	targets: Array[Airplane],
	interval_from: float,
	interval_to: float
) -> void:
	_rng.seed = seed_value
	planes = targets
	interval_min = interval_from
	interval_max = interval_to
	# Stagger the first shot so a group never fires as one volley.
	_timer = _rng.randf_range(1.2, interval_max)

	# Every soldier gets his own stance, breathing cycle and sway, so the squad
	# reads as a line of individuals.
	var stance := _rng.randi() % REST_AIMS.size()
	_rest_aim = REST_AIMS[stance]
	_aim = _rest_aim
	_bob_phase = _rng.randf_range(0.0, TAU)
	_bob_speed = _rng.randf_range(1.4, 2.2)

	model = SoldierModel3D.new()
	add_child(model)
	model.build(UNIFORMS[uniform % UNIFORMS.size()])
	model.set_stance(stance)
	model.set_breath_phase(_rng.randf_range(0.0, TAU))
	model.set_aim(_rest_aim)
	body.texture = model.get_texture()
	body.scale = Vector2.ONE * model.sprite_scale()
	body.position = Vector2(0.0, -SoldierModel3D.ART_HEIGHT * 0.5)


## New round: forget the current countdown, keep the staggered feel.
func reset_field() -> void:
	_timer = _rng.randf_range(1.0, interval_max)


func _process(delta: float) -> void:
	_time += delta
	# A touch of idle sway, so a standing soldier is never dead still.
	body.position.y = -SoldierModel3D.ART_HEIGHT * 0.5 + sin(_time * _bob_speed + _bob_phase) * 0.3

	var target := _nearest_target()
	_track(target, delta)

	_timer -= delta
	if _timer > 0.0 or target == null:
		return
	_timer = _rng.randf_range(interval_min, interval_max)
	_fire_at(target)


## Swings the rifle onto the target (and turns the whole figure to face it).
func _track(target: Airplane, delta: float) -> void:
	var desired := _rest_aim
	if target != null:
		var shoulder := global_position + Vector2(SHOULDER.x * _facing, SHOULDER.y)
		var to_target := target.global_position - shoulder
		_facing = 1.0 if to_target.x >= 0.0 else -1.0
		desired = clampf(atan2(-to_target.y, absf(to_target.x)), AIM_MIN, AIM_MAX)

	_aim = move_toward(_aim, desired, AIM_TURN_RATE * delta)
	body.flip_h = _facing < 0.0
	if model != null:
		model.set_aim(_aim)


func _fire_at(target: Airplane) -> void:
	var muzzle := _muzzle_position()
	var to_target := target.global_position - muzzle
	if to_target.length() < 1.0:
		return
	var direction := to_target.normalized().rotated(
		deg_to_rad(_rng.randf_range(-1.0, 1.0) * aim_spread_degrees)
	)
	if model != null:
		model.flash_muzzle()
	shot_fired.emit(muzzle, direction)


## The rifle tip in world space, following the current aim and facing.
func _muzzle_position() -> Vector2:
	var along := Vector2(cos(_aim), -sin(_aim)) * RIFLE_REACH
	return global_position + Vector2(
		(SHOULDER.x + along.x) * _facing,
		SHOULDER.y + along.y
	)


## The closest plane this soldier can actually see: airborne, above him and
## within range.
func _nearest_target() -> Airplane:
	var best: Airplane = null
	var best_distance := INF
	for plane in planes:
		if plane == null or not is_instance_valid(plane):
			continue
		if not plane.is_alive or not plane.is_airborne():
			continue
		var offset := plane.global_position - global_position
		if offset.y > -120.0:
			continue
		if absf(offset.y) > MAX_TARGET_HEIGHT or offset.length() > range_px:
			continue
		if offset.length() < best_distance:
			best_distance = offset.length()
			best = plane
	return best
