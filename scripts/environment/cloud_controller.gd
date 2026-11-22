class_name CloudSprite
extends AnimatedSprite2D
## A single animated cloud. It plays one frame of the cloud sheet at a time and
## wanders on its own: it picks a random point nearby, drifts there at its own
## speed, then picks another. The field around it only recycles clouds that the
## camera has left behind.

const FRAME_SIZE := Vector2i(320, 200)

var wrap_left: float = -260.0
var wrap_right: float = 3460.0
## How far from the chosen point the cloud considers itself "arrived".
var arrival_distance: float = 18.0

var _speed: float = 14.0
## The alpha the cloud was placed with; weather tints and thickens it from here.
var _base_alpha: float = 0.9
var _target := Vector2.ZERO
var _wander_radius := Vector2(240.0, 110.0)
var _rng := RandomNumberGenerator.new()


func setup(
	frames: SpriteFrames,
	uniform_scale: float,
	alpha: float,
	left_edge: float,
	right_edge: float,
	seed_value: int
) -> void:
	sprite_frames = frames
	scale = Vector2.ONE * uniform_scale
	modulate = Color(1.0, 1.0, 1.0, alpha)
	_base_alpha = alpha
	wrap_left = left_edge
	wrap_right = right_edge
	_rng.seed = seed_value
	_speed = _rng.randf_range(8.0, 26.0)
	# Different clouds start on different animation frames so the sky does not
	# breathe in unison.
	if frames != null and frames.has_animation(&"drift"):
		var count := frames.get_frame_count(&"drift")
		if count > 0:
			frame = _rng.randi() % count
			play(&"drift")
	speed_scale = _rng.randf_range(0.18, 0.42)
	_choose_target()


## Weather colour: an overcast greys the clouds out, a storm darkens and thickens
## them, snow keeps them bright.
func set_weather(tint: Color, alpha_scale: float) -> void:
	modulate = Color(tint.r, tint.g, tint.b, clampf(_base_alpha * alpha_scale, 0.0, 1.0))


## Called by the field after it teleports a cloud: start wandering from the new
## position instead of drifting back toward the old one.
func reset_wander() -> void:
	_choose_target()


func _choose_target() -> void:
	_target = position + Vector2(
		_rng.randf_range(-_wander_radius.x, _wander_radius.x),
		_rng.randf_range(-_wander_radius.y, _wander_radius.y)
	)


func _process(delta: float) -> void:
	var to_target := _target - position
	if to_target.length() < arrival_distance:
		_choose_target()
	else:
		position += to_target.normalized() * _speed * delta

	if position.x > wrap_right:
		position.x = wrap_left
		reset_wander()
	elif position.x < wrap_left:
		position.x = wrap_right
		reset_wander()
