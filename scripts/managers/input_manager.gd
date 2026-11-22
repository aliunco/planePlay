extends Node
## Single place where physical actions and on-screen touch controls meet.
##
## Gameplay code never reads Input directly: it asks this autoload for held
## actions, and the touch buttons simply push virtual presses here. That keeps
## the plane logic independent of keyboard, touch or remote (Bluetooth) sources.

const ACTION_KEYS := {
	&"p1_left": [KEY_A],
	&"p1_right": [KEY_D],
	&"p1_launch": [KEY_W],
	&"p1_throttle_down": [KEY_S],
	&"p1_fire": [KEY_SPACE],
	&"p1_bomb": [KEY_B],
	&"p1_boost": [KEY_SHIFT],
	&"p1_flare": [KEY_F],
	&"p1_shield": [KEY_G],
	&"p2_left": [KEY_LEFT],
	&"p2_right": [KEY_RIGHT],
	&"p2_launch": [KEY_UP],
	&"p2_throttle_down": [KEY_DOWN],
	&"p2_fire": [KEY_ENTER],
	&"p2_bomb": [KEY_SLASH],
	&"p2_boost": [KEY_CTRL],
	&"p2_flare": [KEY_PERIOD],
	&"p2_shield": [KEY_COMMA],
	&"pause": [KEY_ESCAPE],
	&"restart": [KEY_R],
	&"toggle_mobile_controls": [KEY_F1],
}

## Actions currently held down through on-screen buttons.
var _virtual_actions: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_actions()


func _register_actions() -> void:
	for action: StringName in ACTION_KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode: int in ACTION_KEYS[action]:
			if _action_has_key(action, keycode):
				continue
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)


func _action_has_key(action: StringName, keycode: int) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and event.physical_keycode == keycode:
			return true
	return false


# --- Virtual (touch) input ---------------------------------------------------

func set_virtual_action(action: StringName, pressed: bool) -> void:
	if pressed:
		_virtual_actions[action] = true
	else:
		_virtual_actions.erase(action)


func clear_virtual_actions() -> void:
	_virtual_actions.clear()


# --- Queries -----------------------------------------------------------------

func is_held(action: StringName) -> bool:
	return _virtual_actions.has(action) or Input.is_action_pressed(action)


## True while either a real binding or a virtual button is down.
func any_held(actions: Array[StringName]) -> bool:
	for action: StringName in actions:
		if is_held(action):
			return true
	return false


## -1.0 = left, 1.0 = right, 0.0 = neutral. Opposing presses cancel out.
func turn_axis(left_actions: Array[StringName], right_actions: Array[StringName]) -> float:
	var left := 1.0 if any_held(left_actions) else 0.0
	var right := 1.0 if any_held(right_actions) else 0.0
	return right - left


func is_pause_just_pressed() -> bool:
	return Input.is_action_just_pressed(&"pause")
