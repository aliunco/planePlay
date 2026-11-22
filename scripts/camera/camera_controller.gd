class_name CameraController
extends Camera2D
## Follows the local airplane and never leaves the landscape.
##
## TWO modes:
##  FOLLOW      - smooth chase of one plane (single player, Bluetooth).
##  FRAME_BOTH  - both planes on one screen (local two player on a shared screen).

enum Mode { FOLLOW, FRAME_BOTH }

const MIN_FRAMING_ZOOM: float = 0.42
const FRAMING_PADDING: float = 400.0

var mode: Mode = Mode.FOLLOW
var target: Node2D
var second_target: Node2D
var follow_speed: float = 5.0
var base_zoom: float = 1.15
var world_width: float = 0.0
var _desired_position := Vector2.ZERO
var _desired_zoom: float = 1.15
var _shake_strength: float = 0.0
var _shake_time: float = 0.0
var _last_target_x: float = 0.0
var _has_last_target: bool = false


func configure(bounds: Rect2, zoom_level: float, speed: float) -> void:
	limit_left = int(bounds.position.x)
	limit_top = int(bounds.position.y)
	limit_right = int(bounds.end.x)
	limit_bottom = int(bounds.end.y)
	base_zoom = zoom_level
	follow_speed = speed
	world_width = bounds.size.x
	_desired_zoom = base_zoom
	zoom = Vector2(base_zoom, base_zoom)
	if target != null:
		global_position = target.global_position
		snap_to_target()


func set_target(plane: Node2D) -> void:
	target = plane
	if mode == Mode.FOLLOW and target != null:
		global_position = target.global_position
		snap_to_target()


func set_second_target(plane: Node2D) -> void:
	second_target = plane


func snap_to_target() -> void:
	if target == null:
		return
	global_position = _clamp_to_limits(target.global_position, zoom)
	force_update_scroll()


## Kicks the frame around for a moment: hits and explosions feel heavier.
func shake(strength: float, duration: float) -> void:
	_shake_strength = maxf(_shake_strength, strength)
	_shake_time = maxf(_shake_time, duration)


func _physics_process(delta: float) -> void:
	_apply_shake(delta)
	if target == null:
		return

	if mode == Mode.FRAME_BOTH and second_target != null:
		_update_frame_both(delta)
	else:
		_update_follow(delta)

	# A wrap teleports the plane a whole map width sideways. Measure the jump on
	# the plane itself, because clamping the goal to the world limits can shrink
	# it to less than half a map on wide screens.
	var target_step := absf(target.global_position.x - _last_target_x) if _has_last_target else 0.0
	_last_target_x = target.global_position.x
	_has_last_target = true

	var goal := _clamp_to_limits(_desired_position, Vector2(_desired_zoom, _desired_zoom))
	var wrapped := world_width > 0.0 and target_step > world_width * 0.5
	if wrapped or (world_width > 0.0 and absf(goal.x - global_position.x) > world_width * 0.5):
		# The target wrapped around the map: follow it instantly instead of
		# sweeping the camera across the whole world.
		global_position = goal
		zoom = Vector2(_desired_zoom, _desired_zoom)
		force_update_scroll()
		return

	global_position = global_position.lerp(goal, clampf(delta * follow_speed, 0.0, 1.0))
	zoom = zoom.lerp(Vector2(_desired_zoom, _desired_zoom), clampf(delta * follow_speed, 0.0, 1.0))


## Shake lives in `offset`, so it never fights the followed position.
func _apply_shake(delta: float) -> void:
	if _shake_time <= 0.0:
		offset = offset.lerp(Vector2.ZERO, clampf(delta * 9.0, 0.0, 1.0))
		_shake_strength = 0.0
		return
	_shake_time -= delta
	var falloff := clampf(_shake_time * 2.4, 0.0, 1.0)
	var reach := _shake_strength * falloff
	offset = Vector2(randf_range(-reach, reach), randf_range(-reach, reach))


func _update_follow(_delta: float) -> void:
	_desired_position = target.global_position
	_desired_zoom = base_zoom


func _update_frame_both(_delta: float) -> void:
	var a := target.global_position
	var b := second_target.global_position
	var center := (a + b) * 0.5
	var view := get_viewport_rect().size

	var span := (b - a).abs()
	var needed_width := maxf(span.x + FRAMING_PADDING, view.x / base_zoom)
	var needed_height := maxf(span.y + FRAMING_PADDING, view.y / base_zoom)

	var zoom_for_width := view.x / needed_width
	var zoom_for_height := view.y / needed_height
	_desired_zoom = clampf(minf(zoom_for_width, zoom_for_height), MIN_FRAMING_ZOOM, base_zoom)
	_desired_position = center


## Keeps the camera inside the world even when the viewport is wider or taller
## than the landscape at the current zoom.
func _clamp_to_limits(position: Vector2, current_zoom: Vector2) -> Vector2:
	var half_view := get_viewport_rect().size * 0.5 / current_zoom
	var result := position

	var min_x := float(limit_left) + half_view.x
	var max_x := float(limit_right) - half_view.x
	if min_x > max_x:
		result.x = (float(limit_left) + float(limit_right)) * 0.5
	else:
		result.x = clampf(result.x, min_x, max_x)

	var min_y := float(limit_top) + half_view.y
	var max_y := float(limit_bottom) - half_view.y
	if min_y > max_y:
		result.y = (float(limit_top) + float(limit_bottom)) * 0.5
	else:
		result.y = clampf(result.y, min_y, max_y)

	return result
