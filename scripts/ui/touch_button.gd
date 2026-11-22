class_name TouchButton
extends Control
## Large on-screen button that supports holding and many simultaneous fingers.
##
## Godot's Button only tracks one pointer, so this draws its own control and
## tracks every touch index that landed on it. Presses are forwarded to the
## InputManager as virtual actions, which the plane controllers read exactly like
## keyboard input.
##
## The glyphs are drawn, not textured: a bold chevron for steering, a strip with a
## climbing chevron for take-off, a wheel with a chevron for the gear, and a
## gunsight for the trigger. Each one reads at a glance on a small phone screen.

signal press_changed(is_down: bool)

enum Icon { LEFT, RIGHT, TAKEOFF, GEAR_UP, GEAR_DOWN, FIRE, BOMB, BOOST, FLARE, SHIELD }

@export var icon: Icon = Icon.LEFT
@export var virtual_action: StringName = &"p1_left"
@export var idle_alpha: float = 0.24
@export var pressed_alpha: float = 0.52
@export var glyph_color: Color = Color(1.0, 1.0, 1.0, 0.92)

var _touch_indices: Dictionary = {}
var _mouse_down: bool = false
var _is_pressed: bool = false
## Reload running on this control: 1 just started, 0 ready. While it is running
## the glyph is dimmed and a ring fills round the button.
var _progress: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	resized.connect(queue_redraw)
	queue_redraw()


## Swaps the glyph without touching the press state (the take-off button becomes
## the gear-up button once the wheels leave the ground).
func set_icon(next: Icon) -> void:
	if icon == next:
		return
	icon = next
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not _touch_indices.has(event.index):
			_touch_indices[event.index] = true
			_refresh()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_mouse_down = true
			_refresh()
		accept_event()


## Releases are caught globally so letting go outside the circle still works.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if not event.pressed and _touch_indices.erase(event.index):
			_refresh()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed and _mouse_down:
			_mouse_down = false
			_refresh()


func _refresh() -> void:
	var now_down := not _touch_indices.is_empty() or _mouse_down
	if now_down == _is_pressed:
		return
	_is_pressed = now_down
	InputManager.set_virtual_action(virtual_action, _is_pressed)
	press_changed.emit(_is_pressed)
	queue_redraw()


## Clears the press without emitting (used when the game pauses).
func silent_release() -> void:
	_touch_indices.clear()
	_mouse_down = false
	if _is_pressed:
		_is_pressed = false
		InputManager.set_virtual_action(virtual_action, false)
		queue_redraw()


func is_down() -> bool:
	return _is_pressed


## Shows how far a reload has left to run: 0 is ready, 1 is just started.
func set_progress(ratio: float) -> void:
	var next := clampf(ratio, 0.0, 1.0)
	if is_equal_approx(next, _progress):
		return
	_progress = next
	queue_redraw()


func _draw() -> void:
	var radius := minf(size.x, size.y) * 0.5 - 4.0
	if radius <= 4.0:
		return
	var center := size * 0.5
	var fill_alpha := pressed_alpha if _is_pressed else idle_alpha
	draw_circle(center, radius, Color(1.0, 1.0, 1.0, fill_alpha))
	draw_arc(center, radius, 0.0, TAU, 64, Color(1.0, 1.0, 1.0, 0.55), 3.0, true)
	if _is_pressed:
		draw_arc(center, radius - 4.0, 0.0, TAU, 64, Color(1.0, 0.82, 0.4, 0.65), 4.0, true)

	match icon:
		Icon.LEFT:
			_draw_chevron(center, radius, PI, 10.0)
		Icon.RIGHT:
			_draw_chevron(center, radius, 0.0, 10.0)
		Icon.TAKEOFF:
			_draw_takeoff(center, radius)
		Icon.GEAR_UP:
			_draw_gear(center, radius, true)
		Icon.GEAR_DOWN:
			_draw_gear(center, radius, false)
		Icon.FIRE:
			_draw_gunsight(center, radius)
		Icon.BOMB:
			_draw_bomb(center, radius)
		Icon.BOOST:
			_draw_boost(center, radius)
		Icon.FLARE:
			_draw_flare(center, radius)
		Icon.SHIELD:
			_draw_shield(center, radius)

	# A reload covers the glyph with a scrim and fills a ring round the button, so
	# a dead control still says how long it is dead for.
	if _progress > 0.0:
		draw_circle(center, radius, Color(0.02, 0.05, 0.08, 0.5))
		draw_arc(center, radius + 5.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.16), 2.0, true)
		draw_arc(
			center,
			radius + 5.0,
			-PI * 0.5,
			-PI * 0.5 + TAU * (1.0 - _progress),
			48,
			Color(1.0, 0.84, 0.42, 0.92),
			5.0,
			true
		)


## A thick arrowhead. `angle` is the way it points (0 = right).
func _draw_chevron(center: Vector2, radius: float, angle: float, width: float) -> void:
	var direction := Vector2.RIGHT.rotated(angle)
	var side := direction.orthogonal()
	var tip := center + direction * radius * 0.44
	var back := center - direction * radius * 0.26
	draw_polyline(
		PackedVector2Array(
			[back + side * radius * 0.30, tip, back - side * radius * 0.30]
		),
		glyph_color,
		width,
		true
	)


## Take-off: a strip along the bottom with the plane climbing away from it.
func _draw_takeoff(center: Vector2, radius: float) -> void:
	var strip_y := center.y + radius * 0.50
	draw_line(
		Vector2(center.x - radius * 0.54, strip_y),
		Vector2(center.x + radius * 0.54, strip_y),
		Color(glyph_color, 0.55),
		3.0,
		true
	)
	# Runway dashes, so the line reads as a strip rather than a rule.
	draw_line(
		Vector2(center.x - radius * 0.20, strip_y - 9.0),
		Vector2(center.x + radius * 0.14, strip_y - 9.0),
		Color(glyph_color, 0.32),
		2.5,
		true
	)
	_draw_chevron(center + Vector2(0.0, -radius * 0.12), radius, -PI * 0.5, 9.0)


## Gear: a wheel and the way it is travelling. Retracting, the wheel sits low and
## the chevron above it points up; extending, it is the other way round.
func _draw_gear(center: Vector2, radius: float, retracting: bool) -> void:
	var going := -1.0 if retracting else 1.0
	var wheel_center := center + Vector2(0.0, radius * 0.20 * going * -1.0)
	var wheel_radius := radius * 0.22
	draw_arc(wheel_center, wheel_radius, 0.0, TAU, 32, glyph_color, 4.5, true)
	draw_circle(wheel_center, wheel_radius * 0.34, glyph_color)
	# Strut running back toward the airframe.
	draw_line(
		wheel_center,
		wheel_center + Vector2(0.0, radius * 0.24 * going * -1.0),
		glyph_color,
		3.5,
		true
	)
	var tip := Vector2(center.x, center.y + radius * 0.66 * going)
	var arm_y := center.y + radius * 0.36 * going
	draw_polyline(
		PackedVector2Array(
			[Vector2(center.x - radius * 0.22, arm_y), tip, Vector2(center.x + radius * 0.22, arm_y)]
		),
		glyph_color,
		6.0,
		true
	)


## Bomb: a fat little bomb with fins, and the mark it makes on the way down.
func _draw_bomb(center: Vector2, radius: float) -> void:
	var top := center.y - radius * 0.34
	var body := PackedVector2Array(
		[
			Vector2(center.x, center.y + radius * 0.34),
			Vector2(center.x + radius * 0.20, center.y + radius * 0.10),
			Vector2(center.x + radius * 0.22, center.y - radius * 0.18),
			Vector2(center.x + radius * 0.10, top),
			Vector2(center.x - radius * 0.10, top),
			Vector2(center.x - radius * 0.22, center.y - radius * 0.18),
			Vector2(center.x - radius * 0.20, center.y + radius * 0.10),
		]
	)
	draw_colored_polygon(body, glyph_color)
	# Tail fins either side of the nose cap.
	draw_line(
		Vector2(center.x - radius * 0.10, top + 1.0),
		Vector2(center.x - radius * 0.34, top - radius * 0.16),
		glyph_color,
		5.0,
		true
	)
	draw_line(
		Vector2(center.x + radius * 0.10, top + 1.0),
		Vector2(center.x + radius * 0.34, top - radius * 0.16),
		glyph_color,
		5.0,
		true
	)
	# Fall lines under it.
	for i in 2:
		var x := center.x + (float(i) - 0.5) * radius * 0.34
		draw_line(
			Vector2(x, center.y + radius * 0.48),
			Vector2(x, center.y + radius * 0.66),
			Color(glyph_color, 0.55),
			2.5,
			true
		)


## Boost: a bolt with two speed lines, so it reads as "go faster" rather than
## "fire" or "gear".
func _draw_boost(center: Vector2, radius: float) -> void:
	var bolt := PackedVector2Array(
		[
			Vector2(center.x + radius * 0.10, center.y - radius * 0.46),
			Vector2(center.x - radius * 0.22, center.y + radius * 0.06),
			Vector2(center.x - radius * 0.02, center.y + radius * 0.06),
			Vector2(center.x - radius * 0.12, center.y + radius * 0.46),
			Vector2(center.x + radius * 0.24, center.y - radius * 0.08),
			Vector2(center.x + radius * 0.02, center.y - radius * 0.08),
		]
	)
	draw_colored_polygon(bolt, glyph_color)
	for i in 2:
		var y := center.y + (float(i) - 0.5) * radius * 0.34
		draw_line(
			Vector2(center.x - radius * 0.46, y),
			Vector2(center.x - radius * 0.30, y),
			Color(glyph_color, 0.6),
			3.0,
			true
		)


## Flares: a burning decoy thrown off, drawn as a spitting star with sparks
## falling away from it.
func _draw_flare(center: Vector2, radius: float) -> void:
	var core := radius * 0.16
	draw_circle(center, core * 1.8, Color(glyph_color, 0.55))
	draw_circle(center, core, glyph_color)
	for i in 8:
		var angle := float(i) * TAU / 8.0 + 0.2
		var direction := Vector2.RIGHT.rotated(angle)
		var reach := radius * (0.62 if i % 2 == 0 else 0.44)
		draw_line(center + direction * (core + 2.0), center + direction * reach, glyph_color, 3.0, true)
	# Sparks guttering off the star, falling behind it.
	for i in 3:
		var spark := center + Vector2(0.0, radius * (0.5 + float(i) * 0.16))
		draw_circle(spark, 2.2 - float(i) * 0.4, Color(glyph_color, 0.6 - float(i) * 0.14))


## Shield: a heraldic shield outline with a highlight down one side.
func _draw_shield(center: Vector2, radius: float) -> void:
	var top := center.y - radius * 0.46
	var bottom := center.y + radius * 0.48
	var half := radius * 0.40
	var outline := PackedVector2Array(
		[
			Vector2(center.x, top),
			Vector2(center.x + half, top + radius * 0.16),
			Vector2(center.x + half * 0.84, center.y + radius * 0.14),
			Vector2(center.x, bottom),
			Vector2(center.x - half * 0.84, center.y + radius * 0.14),
			Vector2(center.x - half, top + radius * 0.16),
		]
	)
	draw_polyline(outline, glyph_color, 4.0, true)
	draw_line(
		Vector2(center.x, top + radius * 0.16),
		Vector2(center.x, bottom - radius * 0.16),
		Color(glyph_color, 0.65),
		2.5,
		true
	)
	draw_line(
		Vector2(center.x - half * 0.55, top + radius * 0.3),
		Vector2(center.x + half * 0.55, top + radius * 0.3),
		Color(glyph_color, 0.65),
		2.5,
		true
	)


## Fire: a gunsight, the one symbol every pilot already reads as "shoot".
func _draw_gunsight(center: Vector2, radius: float) -> void:
	var ring := radius * 0.44
	draw_arc(center, ring, 0.0, TAU, 48, glyph_color, 4.0, true)
	for i in 4:
		var direction := Vector2.RIGHT.rotated(float(i) * PI * 0.5)
		draw_line(
			center + direction * (ring + 2.0),
			center + direction * (ring + 12.0),
			glyph_color,
			4.0,
			true
		)
	draw_circle(center, radius * 0.075, glyph_color)
