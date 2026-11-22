class_name PlayerPlaneController
extends AirplaneController
## Local human pilot. Reads the InputManager abstraction (keyboard + touch)
## and never talks to Input directly.

@export var turn_left_action: StringName = &"p1_left"
@export var turn_right_action: StringName = &"p1_right"
@export var fire_action: StringName = &"p1_fire"
@export var launch_action: StringName = &"p1_launch"
@export var throttle_down_action: StringName = &"p1_throttle_down"
@export var bomb_action: StringName = &"p1_bomb"
@export var boost_action: StringName = &"p1_boost"
@export var flare_action: StringName = &"p1_flare"
@export var shield_action: StringName = &"p1_shield"
## In single player, Player 1 also answers to the arrow keys.
@export var accept_alternate_keys: bool = false

var _input := PlaneInput.new()
var _up_was_held: bool = false
var _down_was_held: bool = false


func get_plane_input(_delta: float) -> PlaneInput:
	var left: Array[StringName] = [turn_left_action]
	var right: Array[StringName] = [turn_right_action]
	var fire: Array[StringName] = [fire_action]
	var launch: Array[StringName] = [launch_action]
	var throttle_down: Array[StringName] = [throttle_down_action]
	var bomb: Array[StringName] = [bomb_action]
	var boost: Array[StringName] = [boost_action]
	var flare: Array[StringName] = [flare_action]
	var shield: Array[StringName] = [shield_action]

	if accept_alternate_keys:
		left.append(&"p2_left")
		right.append(&"p2_right")
		fire.append(&"p2_fire")
		launch.append(&"p2_launch")
		throttle_down.append(&"p2_throttle_down")
		bomb.append(&"p2_bomb")
		boost.append(&"p2_boost")
		flare.append(&"p2_flare")
		shield.append(&"p2_shield")

	var up := InputManager.any_held(launch)
	var down := InputManager.any_held(throttle_down)

	_input.turn = InputManager.turn_axis(left, right)
	_input.fire = InputManager.any_held(fire)
	_input.launch = up
	_input.bomb = InputManager.any_held(bomb)
	_input.boost = InputManager.any_held(boost)
	_input.flare = InputManager.any_held(flare)
	_input.shield = InputManager.any_held(shield)

	# Up is both "take off" and "gear up", so the tap is sent on the frame the
	# button goes down; holding it to launch never changes gear by itself.
	_input.throttle = 0
	if up and not _up_was_held:
		_input.throttle += 1
	if down and not _down_was_held:
		_input.throttle -= 1
	_up_was_held = up
	_down_was_held = down
	return _input
