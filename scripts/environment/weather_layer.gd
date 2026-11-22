class_name WeatherLayer
extends Control
## Screen-space precipitation: rain streaks or drifting snow, drawn over the
## whole viewport. It lives on its own canvas layer, so it falls in front of the
## world without being part of it - the planes fly through the weather instead of
## dragging it around.
##
## The drops are a fixed pool of fractions of the screen, wrapped as they leave
## it, so a downpour costs the same every frame and never allocates.

const RAIN_COUNT: int = 260
const SNOW_COUNT: int = 170
## Fixed seed: the pattern is the same on both devices of a LAN match.
const DROP_SEED: int = 77123

var _kind: int = Weather.Kind.CLEAR
var _strength: float = 0.0
## x fraction, y fraction, speed (screens per second) per drop.
var _rain: Array[Vector3] = []
var _snow: Array[Vector3] = []
var _snow_phase: Array[float] = []
var _time: float = 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_drops()
	visible = false
	set_process(false)


func _build_drops() -> void:
	_rng.seed = DROP_SEED
	for i in RAIN_COUNT:
		_rain.append(
			Vector3(_rng.randf(), _rng.randf(), _rng.randf_range(1.5, 2.6))
		)
	for i in SNOW_COUNT:
		_snow.append(
			Vector3(_rng.randf(), _rng.randf(), _rng.randf_range(0.09, 0.22))
		)
		_snow_phase.append(_rng.randf_range(0.0, TAU))


## `strength` fades the weather in and out, which is what lets survival change
## the sky without a hard cut.
func set_weather(kind: int, strength: float) -> void:
	_kind = kind
	_strength = clampf(strength, 0.0, 1.0)
	var active := _strength > 0.01 and Weather.precipitation(kind)
	visible = active
	set_process(active)
	queue_redraw()


func kind() -> int:
	return _kind


func strength() -> float:
	return _strength


func _process(delta: float) -> void:
	_time += delta
	if _kind == Weather.Kind.RAIN:
		for i in _rain.size():
			var drop := _rain[i]
			drop.y += drop.z * delta
			drop.x += drop.z * 0.16 * delta
			if drop.y > 1.05:
				drop.y -= 1.1
			if drop.x > 1.05:
				drop.x -= 1.1
			_rain[i] = drop
	else:
		for i in _snow.size():
			var flake := _snow[i]
			flake.y += flake.z * delta
			flake.x += sin(_time * 0.7 + _snow_phase[i]) * 0.02 * delta
			if flake.y > 1.04:
				flake.y -= 1.08
			if flake.x > 1.05:
				flake.x -= 1.1
			elif flake.x < -0.05:
				flake.x += 1.1
			_snow[i] = flake
	queue_redraw()


func _draw() -> void:
	if _strength <= 0.01 or size.x <= 0.0:
		return
	if _kind == Weather.Kind.RAIN:
		_draw_rain()
	else:
		_draw_snow()
	# A veil over the whole scene: weather flattens the light.
	var veil := (
		Color(0.05, 0.10, 0.16, 0.10 * _strength)
		if _kind == Weather.Kind.RAIN
		else Color(0.75, 0.82, 0.90, 0.07 * _strength)
	)
	draw_rect(Rect2(Vector2.ZERO, size), veil)


func _draw_rain() -> void:
	var color := Color(0.72, 0.82, 0.96, 0.42 * _strength)
	for drop in _rain:
		var head := Vector2(drop.x * size.x, drop.y * size.y)
		var length := 22.0 + drop.z * 10.0
		draw_line(head, head + Vector2(-length * 0.18, -length), color, 1.6, true)


func _draw_snow() -> void:
	var color := Color(0.95, 0.97, 1.0, 0.80 * _strength)
	for i in _snow.size():
		var flake := _snow[i]
		draw_circle(
			Vector2(flake.x * size.x, flake.y * size.y),
			1.2 + flake.z * 9.0,
			color
		)
