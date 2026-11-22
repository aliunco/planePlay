class_name AIController
extends AirplaneController
## AI pilot. Produces PlaneInput exactly like a human controller does, so the AI
## uses the same movement, projectile and damage systems as the player.

var config: AIConfig
var target: Airplane
var world_rect: Rect2 = Rect2(0.0, -18000.0, 3200.0, 18280.0)

var _input := PlaneInput.new()
var _aim_angle: float = 0.0
var _reaction_timer: float = 0.0
var _turn_hold: float = 0.0
var _last_turn_dir: float = 0.0
var _launch_wait: float = 0.0
## Seconds until the AI will consider another bomb run, so it does not empty the
## rack the moment it gets above the player.
var _bomb_wait: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if config == null:
		config = AIConfig.preset(AIConfig.Difficulty.NORMAL)


func setup(opponent: Airplane, bounds: Rect2, ai_config: AIConfig) -> void:
	target = opponent
	world_rect = bounds
	config = ai_config
	_input.reset()


## Clears timers so a restart behaves like a fresh match.
func reset_state() -> void:
	_launch_wait = 0.0
	_bomb_wait = 0.0
	_reaction_timer = 0.0
	_turn_hold = 0.0
	_last_turn_dir = 0.0
	_aim_angle = 0.0
	_input.reset()


func get_plane_input(delta: float) -> PlaneInput:
	_input.reset()
	if plane == null or target == null or not plane.is_alive:
		return _input

	if not plane.is_launched:
		_launch_wait += delta
		_input.launch = target.is_launched and _launch_wait >= config.launch_delay
		return _input

	if not target.is_alive:
		_input.turn = 0.0
		return _input

	_reaction_timer -= delta
	_turn_hold = maxf(0.0, _turn_hold - delta)
	if _reaction_timer <= 0.0:
		_reaction_timer = maxf(0.05, config.reaction_time)
		_decide_heading()

	var diff := wrapf(_aim_angle - plane.rotation, -PI, PI)
	_input.turn = _steer(diff)
	_input.fire = _wants_to_fire()
	_input.bomb = _wants_to_bomb(delta)
	# The boost is for closing a gap or breaking off, never for the final
	# approach: overshooting a target two hundred pixels away is worse than slow.
	_input.boost = plane.nitro > 0.45 and _target_offset().length() > 900.0
	# The bubble is for the moment the fight has already gone wrong: below half
	# health, with a charge in hand, and not one already up.
	_input.shield = (
		plane.shield_charges > 0
		and not plane.is_shielded()
		and plane.health.get_ratio() < 0.5
	)
	return _input


## Bombs only come out when the AI is above the player and reasonably close, so
## they land instead of sailing past underneath.
func _wants_to_bomb(delta: float) -> bool:
	_bomb_wait = maxf(0.0, _bomb_wait - delta)
	if plane == null or target == null or plane.bombs <= 0 or _bomb_wait > 0.0:
		return false
	if not plane.is_airborne() or not target.is_alive:
		return false
	var offset := _target_offset()
	if offset.y < 180.0:
		return false
	if absf(offset.x) > 320.0:
		return false
	_bomb_wait = 4.5
	return true


## Offset from us to the target, taking the shorter way around the wrapping map.
func _target_offset() -> Vector2:
	var delta := target.global_position - plane.global_position
	delta.x = Airplane.wrapped_delta_x(plane.global_position.x, target.global_position.x, world_rect)
	return delta


## Where the target will be, relative to us, when our bullets get there. Without
## this the AI would always shoot behind a moving opponent.
func _predicted_target_offset() -> Vector2:
	var bullet_speed := 800.0
	if plane.config != null:
		bullet_speed = plane.config.get_projectile_config().compute_speed(plane.config.plane_speed)
	# Lead a target that is itself faster or slower than our gear-2 cruise speed.
	if target != null:
		bullet_speed += maxf(0.0, target.velocity.length())
	bullet_speed = maxf(1.0, bullet_speed)

	# Iterate the intercept: a target flying away takes longer to reach than a
	# stationary one, so the first straight-line estimate under-leads.
	var travel_time := _target_offset().length() / bullet_speed
	var predicted := _target_offset()
	for i in 3:
		predicted = _target_offset() + target.velocity * travel_time
		travel_time = predicted.length() / bullet_speed
	return predicted


## Picks (and holds) a heading for the next reaction window.
func _decide_heading() -> void:
	if plane == null or target == null:
		return
	var to_target := _predicted_target_offset()
	var desired := Vector2.UP.angle_to(to_target.normalized())
	var max_rad := deg_to_rad(plane.config.max_rotation) if plane.config else deg_to_rad(360.0)

	# The map wraps, so there are no side walls to avoid, but there is still a
	# floor, and touching it now ends the flight: pull up harder the lower it gets.
	var clearance := plane.ground_y - plane.global_position.y
	if clearance < 420.0:
		var level := deg_to_rad(48.0 if clearance > 220.0 else 20.0)
		desired = clampf(desired, -level, level)

	var error := deg_to_rad(_rng.randf_range(-1.0, 1.0) * config.aim_error_degrees)
	_aim_angle = clampf(desired + error, -max_rad, max_rad)
	_input.throttle = _throttle_tap()


## Works the four gears: full power to close a gap, cruises once it is on the
## target's tail, and idles down when it is right on top of it.
func _throttle_tap() -> int:
	var wanted := PlaneConfig.GEAR_FACTORS.size()
	var distance := _target_offset().length()
	if distance < 340.0:
		wanted = 2
	elif distance < 760.0:
		wanted = 3
	if plane.throttle_gear < wanted:
		return 1
	if plane.throttle_gear > wanted:
		return -1
	return 0


func _steer(diff: float) -> float:
	var want := clampf(diff * 3.0, -1.0, 1.0)
	if absf(want) < 0.05:
		return 0.0
	var direction := signf(want)
	if _last_turn_dir != 0.0 and direction != _last_turn_dir and _turn_hold > 0.0:
		# Hold the current turn briefly so the AI does not flap left/right.
		return 0.0
	if direction != _last_turn_dir:
		_last_turn_dir = direction
		_turn_hold = config.min_turn_interval
	return want


func _wants_to_fire() -> bool:
	if plane == null or target == null or not target.is_alive:
		return false
	if not plane.is_airborne():
		return false
	var to_target := _predicted_target_offset()
	var distance := _target_offset().length()
	if distance > config.attack_range:
		return false
	var nose := Vector2.UP.rotated(plane.rotation)
	var angle_error := rad_to_deg(absf(nose.angle_to(to_target.normalized())))
	return angle_error <= config.fire_cone_degrees
