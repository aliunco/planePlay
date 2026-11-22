class_name Projectile
extends Node2D
## Pooled bullet. Collision uses a swept ray between the previous and the new
## position so fast bullets cannot tunnel through an airplane on a slow frame.

const PLANE_LAYER_MASK: int = 1  # physics layer 1 = airplanes
## A homing round will chase a burning flare the other pilot burned instead of
## the aircraft, if one is this close to it.
const DECOY_RANGE: float = 320.0
## And it spends itself on the flare once it is this close.
const DECOY_HIT_RANGE: float = 18.0

## Emitted instead of damaging the airplane directly: the match decides whether a
## hit lands here or has to travel to the other device first, so the two copies of
## a pilot can never disagree about who shot whom.
signal hit_plane(plane: Airplane, damage: int, owner_id: int)

@onready var sprite: Sprite2D = $Sprite
@onready var trail: Sprite2D = $Trail

var is_active: bool = false

var _config: ProjectileConfig
var _owner_id: int = 0
var _direction: Vector2 = Vector2.UP
var _speed: float = 0.0
var _damage: int = 0
var _life_left: float = 0.0
var _bounds: Rect2 = Rect2()
## Only homing rounds carry a target; they steer towards it until they expire.
var _homing_target: Airplane


func _ready() -> void:
	_deactivate()


func spawn(
	config: ProjectileConfig,
	origin: Vector2,
	direction: Vector2,
	owner_id: int,
	plane_speed: float,
	bounds: Rect2,
	homing_target: Airplane = null
) -> void:
	_config = config
	_homing_target = homing_target if config.homing else null
	_owner_id = owner_id
	_direction = direction.normalized()
	_speed = config.compute_speed(plane_speed)
	_damage = config.damage
	_life_left = config.lifetime
	_bounds = bounds

	global_position = origin
	rotation = _direction.angle() + PI * 0.5
	scale = Vector2.ONE * clampf(config.radius / 6.0, 0.6, 2.0)
	modulate = config.tint
	if config.texture != null:
		sprite.texture = config.texture
	trail.modulate = Color(1.0, 1.0, 1.0, 0.55)
	is_active = true
	visible = true
	set_physics_process(true)


func _physics_process(delta: float) -> void:
	if not is_active:
		return

	_steer(delta)
	var step := _speed * delta
	var target := global_position + _direction * step

	var query := PhysicsRayQueryParameters2D.create(global_position, target, PLANE_LAYER_MASK)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)

	if not hit.is_empty():
		var collider: Object = hit.get("collider")
		global_position = hit.get("position", target)
		if collider is Airplane:
			var plane := collider as Airplane
			if plane.player_id != _owner_id and plane.is_alive:
				hit_plane.emit(plane, _damage, _owner_id)
		_deactivate()
		return

	global_position = target
	_life_left -= delta
	if _life_left <= 0.0 or not _bounds.has_point(global_position):
		_deactivate()


## Homing rounds bend towards the target a little each tick, so a hard turn can
## out-turn them and full throttle can outrun them: they only get three seconds.
## A burning flare nearby wins that argument: the round turns onto it and is spent
## on the decoy instead of the aircraft.
func _steer(delta: float) -> void:
	if _config == null or not _config.homing:
		return
	var decoy := _nearest_decoy()
	if decoy != null:
		if global_position.distance_to(decoy.global_position) <= DECOY_HIT_RANGE:
			_deactivate()
			return
		_turn_towards(decoy.global_position, delta)
		return
	if _homing_target == null or not is_instance_valid(_homing_target):
		return
	if not _homing_target.is_alive:
		return
	_turn_towards(_homing_target.global_position, delta)


func _turn_towards(point: Vector2, delta: float) -> void:
	var to_point := point - global_position
	if to_point.length_squared() < 1.0:
		return
	var max_turn := deg_to_rad(_config.homing_turn_rate) * delta
	var wanted := to_point.angle()
	var turn := clampf(wrapf(wanted - _direction.angle(), -PI, PI), -max_turn, max_turn)
	_direction = _direction.rotated(turn)
	rotation = _direction.angle() + PI * 0.5


## The nearest burning flare thrown by the other pilot, if any is close enough to
## pull this round off its target. Only homing rounds ever look.
func _nearest_decoy() -> Flare:
	var best: Flare = null
	var best_distance := DECOY_RANGE
	for node in get_tree().get_nodes_in_group(&"flares"):
		var flare := node as Flare
		if flare == null or not is_instance_valid(flare) or not flare.is_burning():
			continue
		if flare.owner_id == _owner_id:
			continue
		var distance := global_position.distance_to(flare.global_position)
		if distance < best_distance:
			best_distance = distance
			best = flare
	return best


func _deactivate() -> void:
	is_active = false
	visible = false
	set_physics_process(false)


## Called by the pool owner when the projectile is recycled.
func deactivate() -> void:
	_deactivate()
