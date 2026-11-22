class_name MobileControls
extends CanvasLayer
## On-screen flight controls: turn left, turn right, take off / gear up, gear
## down and fire. Buttons are big, holdable and multi-touch aware; they drive
## virtual actions so the same plane controllers work with keyboard or touch.

@onready var left_button: TouchButton = $LeftButton
@onready var right_button: TouchButton = $RightButton
@onready var launch_button: TouchButton = $LaunchButton
@onready var throttle_down_button: TouchButton = $ThrottleDownButton
@onready var fire_button: TouchButton = $FireButton
@onready var bomb_button: TouchButton = $BombButton
@onready var boost_button: TouchButton = $BoostButton
@onready var flare_button: TouchButton = $FlareButton
@onready var shield_button: TouchButton = $ShieldButton

var _forced_visible: int = 0  # -1 hidden, 0 auto, 1 shown


func _ready() -> void:
	left_button.virtual_action = &"p1_left"
	right_button.virtual_action = &"p1_right"
	fire_button.virtual_action = &"p1_fire"
	bomb_button.virtual_action = &"p1_bomb"
	boost_button.virtual_action = &"p1_boost"
	flare_button.virtual_action = &"p1_flare"
	shield_button.virtual_action = &"p1_shield"
	launch_button.virtual_action = &"p1_launch"
	throttle_down_button.virtual_action = &"p1_throttle_down"
	_update_visibility()


func _update_visibility() -> void:
	if _forced_visible == 1:
		visible = true
		return
	if _forced_visible == -1:
		visible = false
		InputManager.clear_virtual_actions()
		return
	visible = DisplayServer.is_touchscreen_available() or bool(
		ProjectSettings.get_setting("input_settings/touch/force_virtual_controls", false)
	)


## Toggles the pad on desktop for testing (F1).
func toggle_forced() -> void:
	if visible:
		_forced_visible = -1
		release_all()
	else:
		_forced_visible = 1
	_update_visibility()


func release_all() -> void:
	left_button.silent_release()
	right_button.silent_release()
	launch_button.silent_release()
	throttle_down_button.silent_release()
	fire_button.silent_release()
	bomb_button.silent_release()
	boost_button.silent_release()
	flare_button.silent_release()
	shield_button.silent_release()


## The bomb rack's reload, drawn as a ring round the bomb button: 1 just started,
## 0 ready. The button itself stays dead while the rack is empty, so this is the
## only thing on screen that says how long the wait is.
func set_bomb_reload(ratio: float) -> void:
	bomb_button.set_progress(ratio)


## Keeps the take-off button visible only while it is useful, and swaps its glyph
## once flying: on the strip it is "take off", in the air the same button raises
## the gear, so the icon has to change with it.
func set_launch_highlight(enabled: bool) -> void:
	launch_button.modulate = Color.WHITE if enabled else Color(1.0, 1.0, 1.0, 0.45)
	launch_button.set_icon(TouchButton.Icon.TAKEOFF if enabled else TouchButton.Icon.GEAR_UP)
