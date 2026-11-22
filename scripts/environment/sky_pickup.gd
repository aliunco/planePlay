class_name SkyPickup
extends Area2D
## Something the courier plane kicks out over the fields: repair gear (a coin) or a
## crate holding a special round, or a crate of bombs. It drifts down on a
## parachute, swinging a little, and only counts if a fighter catches it in the air
## — the ground loses it.
##
## Everything is drawn in code, so there is no art to ship: the coin fakes a 3D
## spin by squashing horizontally, the crate sways on its lines, and both hang from
## a canopy. The collision circle stays put while the drawing swings, so what you
## can collect is exactly where the pickup is.

signal collected(pickup: SkyPickup, plane: Airplane)

## REPAIR patches the airframe up; KILLER and HOMING load one special round;
## FLARES refills the dispenser that shakes homing rounds off; SHIELD hands over a
## charge of the bubble that stops enemy fire outright.
enum Kind { REPAIR, KILLER, HOMING, FLARES, SHIELD }

## How close a plane has to fly to take it.
const PICKUP_RADIUS: float = 34.0
const COIN_RADIUS: float = 21.0
const CRATE_HALF: float = 19.0
## The chute swings the load side to side: enough that catching one is a bit of
## flying, small enough that it stays predictable on the way down.
const SWAY_AMPLITUDE: float = 16.0
const SWAY_SPEED: float = 1.35
const GROUND_CLEARANCE: float = 8.0
const CANOPY_HEIGHT: float = 56.0

var kind: Kind = Kind.REPAIR
## Where the courier released it. Both devices of a LAN match agree on this, which
## is what the LAN test compares.
var spawn_origin: Vector2 = Vector2.ZERO

var _fall_speed: float = 112.0
var _ground_y: float = 0.0
var _age: float = 0.0
var _taken: bool = false


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	monitoring = true
	monitorable = false
	z_index = 1

	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = PICKUP_RADIUS
	shape.shape = circle
	add_child(shape)

	body_entered.connect(_on_body_entered)
	queue_redraw()


## Starts the descent from where the courier let it go.
func drop(at: Vector2, ground_y: float, fall_speed: float) -> void:
	position = at
	spawn_origin = at
	_ground_y = ground_y
	_fall_speed = fall_speed
	queue_redraw()


func is_taken() -> bool:
	return _taken


func _physics_process(delta: float) -> void:
	if _taken:
		return

	_age += delta
	position.y += _fall_speed * delta
	position.x = spawn_origin.x + sin(_age * SWAY_SPEED) * SWAY_AMPLITUDE
	if position.y >= _ground_y - GROUND_CLEARANCE:
		_lost()
		return
	queue_redraw()


func _on_body_entered(body: Node2D) -> void:
	if _taken or not (body is Airplane):
		return
	var plane := body as Airplane
	if not plane.is_alive:
		return
	_taken = true
	# Godot refuses physics changes inside an area signal, so switch the area off
	# on the next idle frame.
	set_deferred(&"monitoring", false)
	collected.emit(self, plane)
	_vanish()


## Collected: it pops and fades out in the pilot's hands.
func _vanish() -> void:
	_taken = true
	set_deferred(&"monitoring", false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ONE * 1.9, 0.25)
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.chain().tween_callback(queue_free)


## Ground contact: the chute folds, the load sinks into the field and is gone.
func _lost() -> void:
	_taken = true
	set_deferred(&"monitoring", false)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2(1.5, 0.18), 0.3)
	tween.tween_property(self, "modulate:a", 0.0, 0.35)
	tween.chain().tween_callback(queue_free)


func _draw() -> void:
	var tilt := sin(_age * SWAY_SPEED + 0.8) * 0.16
	if kind == Kind.REPAIR:
		_draw_parachute(Vector2(0.0, -COIN_RADIUS), COIN_RADIUS * 0.85)
		_draw_coin(tilt)
	else:
		_draw_parachute(Vector2(0.0, -CRATE_HALF), CRATE_HALF)
		_draw_crate(tilt)


## Canopy, shroud lines and the rigging that ties them to the load.
func _draw_parachute(top: Vector2, half_width: float) -> void:
	var canopy := top + Vector2(0.0, -CANOPY_HEIGHT)
	var line_color := Color(0.86, 0.89, 0.95, 0.85)
	draw_line(top + Vector2(-half_width, -2.0), canopy + Vector2(-half_width * 1.6, 0.0), line_color, 1.5)
	draw_line(top + Vector2(half_width, -2.0), canopy + Vector2(half_width * 1.6, 0.0), line_color, 1.5)
	draw_arc(canopy, half_width * 1.7, PI, TAU, 24, Color(0.96, 0.97, 1.0, 0.95), 4.0, true)
	draw_arc(canopy, half_width * 1.7, PI, TAU, 24, Color(0.55, 0.62, 0.72, 0.55), 1.5, true)


func _draw_coin(tilt: float) -> void:
	var offset := Vector2.ZERO
	draw_circle(offset, COIN_RADIUS * 1.55, Color(1.0, 0.86, 0.38, 0.10))

	# Never fully edge-on: a coin that thins to a line reads as a smudge instead
	# of something worth diving for.
	var spin := maxf(0.38, absf(cos(_age * 1.15)))
	draw_set_transform(offset, tilt, Vector2(spin, 1.0))
	draw_circle(Vector2.ZERO, COIN_RADIUS, Color("f7d45c"))
	draw_circle(Vector2.ZERO, COIN_RADIUS * 0.8, Color("f0b437"))
	# A bold medical cross: the one pickup that gives health says so.
	var bar := COIN_RADIUS * 0.62
	var arm := COIN_RADIUS * 0.24
	draw_rect(Rect2(-arm, -bar, arm * 2.0, bar * 2.0), Color(0.09, 0.36, 0.18, 0.55))
	draw_rect(Rect2(-bar, -arm, bar * 2.0, arm * 2.0), Color(0.09, 0.36, 0.18, 0.55))
	draw_rect(Rect2(-arm * 0.86, -bar * 0.9, arm * 1.72, bar * 1.8), Color("2f9c53"))
	draw_rect(Rect2(-bar * 0.9, -arm * 0.86, bar * 1.8, arm * 1.72), Color("2f9c53"))
	draw_line(
		Vector2(-arm * 0.5, -bar * 0.55), Vector2(-arm * 0.5, bar * 0.55), Color(1, 1, 1, 0.5), 2.0
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_arc(offset, COIN_RADIUS, 0.0, TAU, 32, Color(1.0, 1.0, 1.0, 0.55), 2.0, true)


func _draw_crate(tilt: float) -> void:
	var accent := Color("63c9ff")
	if kind == Kind.KILLER:
		accent = Color("ff7a63")
	elif kind == Kind.FLARES:
		accent = Color("fff0b0")
	elif kind == Kind.SHIELD:
		accent = Color("b98cff")
	draw_circle(Vector2.ZERO, CRATE_HALF * 2.0, Color(accent.r, accent.g, accent.b, 0.10))

	draw_set_transform(Vector2.ZERO, tilt, Vector2.ONE)
	draw_rect(Rect2(-CRATE_HALF, -CRATE_HALF, CRATE_HALF * 2.0, CRATE_HALF * 2.0), Color("b98a56"))
	draw_rect(
		Rect2(-CRATE_HALF, -CRATE_HALF, CRATE_HALF * 2.0, CRATE_HALF * 2.0),
		Color("6d4a28"),
		false,
		2.5
	)
	draw_line(Vector2(-CRATE_HALF, -CRATE_HALF), Vector2(CRATE_HALF, CRATE_HALF), Color("6d4a28"), 2.0)
	draw_line(Vector2(CRATE_HALF, -CRATE_HALF), Vector2(-CRATE_HALF, CRATE_HALF), Color("6d4a28"), 2.0)
	draw_circle(Vector2.ZERO, CRATE_HALF * 0.52, accent)
	if kind == Kind.FLARES:
		_draw_flare_glyph(CRATE_HALF * 0.52)
	elif kind == Kind.SHIELD:
		_draw_shield_glyph(CRATE_HALF * 0.46)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The star stamped on a flare crate: a spitting burst, the one glyph that reads
## as "countermeasure" rather than "another round".
func _draw_flare_glyph(size_px: float) -> void:
	var ink := Color(0.24, 0.20, 0.10, 0.92)
	draw_circle(Vector2.ZERO, size_px * 0.28, ink)
	for i in 8:
		var direction := Vector2.RIGHT.rotated(float(i) * TAU / 8.0 + 0.2)
		var reach := size_px * (0.95 if i % 2 == 0 else 0.66)
		draw_line(direction * size_px * 0.34, direction * reach, ink, 1.8, true)


## The shield stamped on a shield crate: a heraldic outline, the one glyph nobody
## mistakes for a round.
func _draw_shield_glyph(scale_value: float) -> void:
	var ink := Color(0.24, 0.16, 0.34, 0.92)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, -scale_value),
				Vector2(scale_value * 0.86, -scale_value * 0.58),
				Vector2(scale_value * 0.72, scale_value * 0.24),
				Vector2(0.0, scale_value),
				Vector2(-scale_value * 0.72, scale_value * 0.24),
				Vector2(-scale_value * 0.86, -scale_value * 0.58),
			]
		),
		ink
	)
	draw_line(
		Vector2(0.0, -scale_value * 0.5),
		Vector2(0.0, scale_value * 0.5),
		Color(0.85, 0.75, 1.0, 0.85),
		1.6
	)
	draw_line(
		Vector2(-scale_value * 0.5, -scale_value * 0.1),
		Vector2(scale_value * 0.5, -scale_value * 0.1),
		Color(0.85, 0.75, 1.0, 0.85),
		1.6
	)
