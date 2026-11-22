class_name Airplane
extends CharacterBody2D
## A flyable aircraft. It owns flight math, the take-off roll, damage stages,
## muzzle placement and the crash, but never reads input devices directly: it
## pulls a PlaneInput from whatever controller is attached to it.
##
## ORIENTATION
## The artwork is drawn nose-to-the-right. `rotation == 0` always means "nose
## pointing up on screen", for both players, so the flight math is identical.
## The Visual node carries a +-90 degree offset that turns the horizontal art
## into a climbing plane, and the opponent simply uses the same sheet mirrored
## on the Y axis (`visual_flip_h`) with the opposite offset. Turning therefore
## needs no per-player conversion: a left input always dips the nose to the left.
##
## ART
## The airframe is a low-poly 3D model rendered into a side-view texture by
## PlaneModel3D: the world, hitbox and all gameplay stay flat 2D, but the plane
## itself is genuinely 3D and always shows its side. The opponent flies the same
## model in a crimson livery, so the two pilots never look identical.
##
## WORLD
## The map wraps left to right: fly out of one side and the plane reappears at the
## same height and heading on the other side. The sky still has a floor (the flat
## surface) and a ceiling, so a 360-degree loop is possible without falling out of
## the world.
##
## DAMAGE
## A plane takes five normal hits. The first leaves scorch marks, the second makes
## it trail smoke, and the fifth knocks it out of the sky: it spins, falls under
## gravity and explodes when it hits the surface, which is when `destroyed` fires.

signal projectile_fired(
	origin: Vector2, direction: Vector2, owner_id: int, projectile: ProjectileConfig
)
## Fired when a crate round is loaded, and again when a shot spends it.
signal special_changed(round_kind: int)
signal health_changed(current: int, maximum: int)
signal damaged(amount: int)
signal launched(plane: Airplane)
signal destroyed(plane: Airplane)
## Fired when the throttle moves to another gear while flying.
signal gear_changed(gear: int)
## A bomb left the belly. The match spawns it and, in a LAN duel, tells the
## other device so both pilots watch the same thing fall.
signal bomb_dropped(origin: Vector2, velocity: Vector2, owner_id: int)
## Bombs left in the rack.
signal bombs_changed(count: int)
## How full the jet-boost tank is, 0..1.
signal boost_changed(ratio: float)
## A burst of defensive flares left the plane, thrown backwards.
signal flares_launched(origin: Vector2, direction: Vector2, owner_id: int)
## Flares left in the dispenser.
signal flares_changed(count: int)
## Shield charges left, and how long the running bubble has to go.
signal shield_changed(charges: int, remaining: float)
## A shield went up: the match mirrors it to the other device in a LAN duel.
signal shield_activated(owner_id: int, seconds: float)
## A bomb ran out and the rack is refilling: `ratio` is 1 when the reload starts
## and 0 when the rack is full again.
signal bomb_reload_changed(ratio: float)

enum FlightState { PARKED, TAXIING, AIRBORNE, CRASHING }

## A take-off runs through these in order: roll, rotate, climb out, level off.
enum TakeoffPhase { ROLL, ROTATE, CLIMB, LEVEL }

## Special rounds from supply crates. Only one is carried at a time, and the
## next shot spends it.
enum SpecialRound { NONE, KILLER, HOMING }

## Where the propeller and the muzzle sit, measured along the nose. The art is
## drawn nose-right, 190 px from spinner to tail.
const NOSE_OFFSET: float = 90.0
const MUZZLE_OFFSET: float = 100.0
## How far behind the centre the tail (and so the boost flame) sits, in art px.
const TAIL_OFFSET: float = 84.0
## Two bombs never leave the rack in the same instant, however hard the button
## is held.
const BOMB_DROP_COOLDOWN: float = 0.32

## Half the drawn airframe's length. Used to lift the plane while the nose comes
## up so the tail never sweeps through the grass.
const BODY_HALF_LENGTH: float = 95.0
## The airframe is drawn at this fraction of the tuned 190 px model, which leaves
## more sky to manoeuvre in. Everything placed from the art (nose, muzzle, hitbox,
## shadow positions) shrinks with it.
const MODEL_SCALE: float = 0.72
const CRASH_GRAVITY: float = 950.0
const CRASH_MAX_FALL_SPEED: float = 780.0
const CRASH_SPIN_SPEED: float = 5.5
## How far past the map edge a plane flies before it wraps to the other side.
const WRAP_MARGIN: float = 120.0
## How close the airframe may get to the flat surface while flying.
const GROUND_CLEARANCE: float = 20.0
## The nose has to be this far up before the tyres leave the strip.
const LIFTOFF_PITCH_DEGREES: float = 8.0
## How fast a dying plane noses over toward the ground, in rad/s.
const CRASH_NOSE_OVER_RATE: float = 2.8
## How fast the death spiral settles, in rad/s per second.
const CRASH_SPIN_DECAY: float = 3.0
## The airframe is drawn in side view, so a loop leaves it showing belly-up once
## it passes the vertical. A real pilot rolls out of that, so the model is rolled
## about its own fuselage axis instead: the nose keeps pointing exactly where it
## was pointing while the wings swing up through the profile and the plane comes
## out showing its other side. This is how long that half-roll takes - the plane
## never flips in a single frame.
const RIGHTING_SECONDS: float = 0.34
## How far off the vertical the plane has to be before it rolls the right way up,
## so a nose held near straight up does not flicker between the two sides.
const RIGHTING_DEADBAND: float = 0.06

## Crate rounds: one shot that finishes the job outright, and one that chases the
## enemy for three seconds before giving up.
const KILLER_ROUND: ProjectileConfig = preload("res://resources/configurations/projectile_killer.tres")
const HOMING_ROUND: ProjectileConfig = preload("res://resources/configurations/projectile_homing.tres")

@export var player_id: int = 1
@export var config: PlaneConfig
@export var world_rect: Rect2 = Rect2(0.0, -18000.0, 3200.0, 18280.0)
## Y of the flat surface the planes take off from (the floor of the sky).
@export var ground_y: float = 0.0

@onready var visual: Node2D = $Visual
@onready var body_sprite: Sprite2D = $Visual/Body
@onready var damage_marks: Node2D = $Visual/Damage
@onready var nose: Node2D = $Nose
@onready var muzzle: Node2D = $Muzzle
@onready var muzzle_flash: Sprite2D = $Nose/MuzzleFlash
@onready var smoke: CPUParticles2D = $Smoke
@onready var dust: CPUParticles2D = $Dust
@onready var health: AirplaneHealth = $Health
@onready var ground_shadow: PlaneGroundShadow = $GroundShadow

## Water thrown off the airframe while it flies through rain. Built in _ready so
## the scene stays free of one-off particle setups.
var _spray: CPUParticles2D
## Jet exhaust, lit while the boost burns.
var _afterburner: CPUParticles2D

## The rendered 3D airframe. Built in _ready so each plane carries its own model
## and livery.
var model: PlaneModel3D

var controller: AirplaneController
var flight_state: FlightState = FlightState.PARKED
var is_alive: bool = true
## True once the take-off roll has started (kept for AI and HUD logic).
var is_launched: bool = false
## How many hits this plane has taken this round (0-3).
var hits_taken: int = 0
## Engaged throttle gear: 1 is the slowest, PlaneConfig.GEAR_FACTORS.size() the
## fastest. Tapping up/down while flying shifts it one step at a time.
var throttle_gear: int = PlaneConfig.DEFAULT_GEAR
## Round loaded from a supply crate, if any. Spent by the next shot.
var special_round: int = SpecialRound.NONE

## Bombs in the rack. It holds `start_bombs`; once it is empty the ground crew
## reloads it, which takes a while.
var bombs: int = 0
## Shield charges carried: each one buys a short window where nothing the enemy
## fires can touch the airframe.
var shield_charges: int = 0
## Seconds left on the running shield, 0 when it is down.
var shield_time: float = 0.0
## Flares in the dispenser. Each one lights up a decoy that a homing round will
## chase instead of the plane.
var flares: int = 0
## Jet boost tank, 0..1. Burns while the boost is held, refills once it is let go.
var nitro: float = 1.0
## True while the boost is actually pushing the airframe.
var boosting: bool = false
## Rain on the airframe, 0..1. Drives the beads on the 3D model and the spray.
var rain: float = 0.0

## 0 in daylight, 1 after dark: how strongly the nose lamp is lit.
var night: float = 0.0

var _input := PlaneInput.new()
var _fire_timer: float = 0.0
var _bomb_timer: float = 0.0
var _flare_timer: float = 0.0
## Seconds left on a bomb reload, 0 when the rack is full or untouched.
var _bomb_reload: float = 0.0
var _bomb_reload_total: float = 0.0
## Last ratio sent for the reload, so the HUD is not spammed with the same value.
var _bomb_reload_sent: float = 0.0
## Length of the running shield, so the bubble can fade out on its tail end.
var _shield_total: float = 0.0
## Brightness punch when the shield swallows a hit.
var _shield_flash: float = 0.0
var _boost_hold: float = 0.0
## What the last frame drew, so the flame is erased the moment the boost cuts.
var _flame_drawn: bool = false
## Last ratio sent to the HUD, so a full tank does not spam the signal.
var _boost_sent: float = 1.0
var _spin_speed: float = 3.0
var _engine_time: float = 0.0
var _flash_tween: Tween
var _hit_tween: Tween

# Take-off roll state.
var _ground_rotation: float = PI * 0.5
var _ground_level_y: float = 0.0
var _taxi_speed: float = 0.0
var _taxi_travelled: float = 0.0
var _takeoff_phase: TakeoffPhase = TakeoffPhase.ROLL
var _climb_timer: float = 0.0
var _lifted_off: bool = false

# Crash state.
var _crash_ground_y: float = 0.0
var _crash_fall_speed: float = 0.0
var _crash_drift: float = 0.0
var _crash_spin: float = 0.0

# Which way up the airframe is drawn: 0 as it left the factory, 1 after the
# half-roll that puts it back on its belly.
var _righting: float = 0.0
var _righting_target: float = 0.0


func _ready() -> void:
	if config == null:
		config = PlaneConfig.new()

	_build_model()
	body_sprite.flip_h = config.visual_flip_h
	# Art is horizontal; ±90 degrees turns the nose up while rotation stays 0.
	visual.rotation = PI * 0.5 if config.visual_flip_h else -PI * 0.5
	visual.scale = Vector2.ONE * MODEL_SCALE
	# Damage decals ride on the airframe, mirrored with it.
	damage_marks.scale.x = -1.0 if config.visual_flip_h else 1.0
	# Parked, each plane points along the runway toward the middle of the map.
	_ground_rotation = -PI * 0.5 if config.visual_flip_h else PI * 0.5

	nose.position = Vector2(0.0, -NOSE_OFFSET * MODEL_SCALE)
	muzzle.position = Vector2(0.0, -MUZZLE_OFFSET * MODEL_SCALE)
	muzzle_flash.visible = false

	smoke.position = Vector2(0.0, 4.0 * MODEL_SCALE)
	dust.position = Vector2(0.0, 28.0 * MODEL_SCALE)
	smoke.scale_amount_min = 0.6
	smoke.scale_amount_max = 1.3
	ground_shadow.set_shape(58.0 * MODEL_SCALE)
	_apply_hitbox()

	health.setup(config.max_health)
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_build_flight_fx()
	_apply_visual_state()


## Builds (or rebuilds) the rendered airframe for the config's silhouette.
func _build_model() -> void:
	if model != null and is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = PlaneModel3D.new()
	add_child(model)
	model.build(
		config.livery_body, config.livery_accent, config.livery_belly, config.plane_silhouette
	)
	# The model renders at 2x for crisp edges; the sprite scales it back so one
	# model unit is one world pixel. Visual then applies MODEL_SCALE, so the whole
	# airframe is the smaller size the flight tuning assumes.
	body_sprite.texture = model.get_texture()
	body_sprite.scale = Vector2.ONE * model.sprite_scale()


## Swaps in another fighter from the roster without disturbing the flight state.
## A LAN guest adopts the host's airframe as soon as its key arrives, so both
## screens simulate (and show) the same two aircraft.
func apply_airframe(index: int, own_livery: bool = false) -> void:
	if config == null:
		return
	# Already this fighter: rebuilding the 3D model here would stall the first
	# frames of a LAN match for no gain, and every stalled frame is input lag.
	if config.plane_silhouette == int(PlaneRoster.entry(index)["silhouette"]):
		return
	PlaneRoster.apply(config, index, own_livery)
	health.setup(config.max_health)
	health.reset()
	_build_model()


func is_airborne() -> bool:
	return flight_state == FlightState.AIRBORNE


func is_crashing() -> bool:
	return flight_state == FlightState.CRASHING


## The intent this airplane acted on during the last physics tick. Multiplayer
## sends this to the other device instead of positions.
func get_current_input() -> PlaneInput:
	return _input


## Resets everything for a fresh round. Position is set by the caller.
func reset_for_round(spawn_position: Vector2) -> void:
	is_alive = true
	is_launched = false
	hits_taken = 0
	flight_state = FlightState.PARKED
	rotation = _ground_rotation
	visible = true
	modulate = Color.WHITE
	collision_layer = 1
	global_position = spawn_position
	_ground_level_y = spawn_position.y
	_crash_ground_y = _ground_level_y + 10.0
	_taxi_speed = 0.0
	_taxi_travelled = 0.0
	_takeoff_phase = TakeoffPhase.ROLL
	_climb_timer = 0.0
	_lifted_off = false
	throttle_gear = PlaneConfig.DEFAULT_GEAR
	gear_changed.emit(throttle_gear)
	special_round = SpecialRound.NONE
	special_changed.emit(special_round)
	bombs = maxi(0, config.start_bombs)
	bombs_changed.emit(bombs)
	flares = maxi(0, config.start_flares)
	flares_changed.emit(flares)
	_flare_timer = 0.0
	shield_charges = maxi(0, config.start_shield)
	shield_time = 0.0
	_shield_total = 0.0
	_shield_flash = 0.0
	shield_changed.emit(shield_charges, shield_time)
	_bomb_reload = 0.0
	_bomb_reload_total = 0.0
	_bomb_reload_sent = 0.0
	bomb_reload_changed.emit(0.0)
	nitro = 1.0
	boosting = false
	_boost_hold = 0.0
	_bomb_timer = 0.0
	boost_changed.emit(nitro)
	_crash_fall_speed = 0.0
	_crash_drift = 0.0
	_crash_spin = 0.0
	_righting = 0.0
	_righting_target = 0.0
	if model != null:
		model.set_roll(0.0)
	_fire_timer = 0.0
	_input.reset()
	health.reset()
	_apply_visual_state()


func _physics_process(delta: float) -> void:
	_animate(delta)

	if flight_state == FlightState.CRASHING:
		_update_crash(delta)
		return

	if not is_alive:
		return

	if controller != null:
		_input = controller.get_plane_input(delta)

	_apply_throttle()
	_update_shield(delta)

	match flight_state:
		FlightState.PARKED:
			if _input.launch:
				take_off()
		FlightState.TAXIING:
			_update_takeoff_roll(delta)
		FlightState.AIRBORNE:
			_apply_rotation(delta)
			_update_boost(delta)
			_fly(delta)
			_update_weapon(delta)


# --- Take-off ----------------------------------------------------------------

func take_off() -> void:
	if not is_alive or flight_state != FlightState.PARKED:
		return
	flight_state = FlightState.TAXIING
	is_launched = true
	_taxi_speed = 0.0
	_taxi_travelled = 0.0
	_takeoff_phase = TakeoffPhase.ROLL
	_climb_timer = 0.0
	_lifted_off = false
	_set_gear(PlaneConfig.DEFAULT_GEAR)
	rotation = _ground_rotation
	launched.emit(self)


## The moment the tyres leave the strip: the gear tucks up and the dust stops.
func _lift_off() -> void:
	_lifted_off = true
	dust.emitting = false


## Rolls along the flat surface, rotates the nose up, climbs out and settles into
## horizontal flight. The plane never stops during the manoeuvre: it keeps
## rolling at taxi speed while it pitches, and the airframe stays high enough that
## neither the belly nor the rising tail cuts into the grass.
func _update_takeoff_roll(delta: float) -> void:
	_taxi_speed = minf(config.plane_speed, _taxi_speed + config.taxi_acceleration * delta)
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * _taxi_speed * delta

	match _takeoff_phase:
		TakeoffPhase.ROLL:
			# Wheels stay on the surface while the plane builds speed.
			global_position.y = _ground_level_y
			_taxi_travelled += _taxi_speed * delta
			dust.emitting = true
			if _taxi_travelled >= config.taxi_distance:
				_takeoff_phase = TakeoffPhase.ROTATE
		TakeoffPhase.ROTATE:
			var nose_up := _takeoff_nose_up_rotation()
			rotation = move_toward(rotation, nose_up, deg_to_rad(config.takeoff_rotate_rate) * delta)
			_hold_off_grass()
			if absf(rotation - nose_up) <= 0.002:
				rotation = nose_up
				_takeoff_phase = TakeoffPhase.CLIMB
		TakeoffPhase.CLIMB:
			rotation = _takeoff_nose_up_rotation()
			_hold_off_grass()
			_climb_timer += delta
			if _climb_timer >= config.takeoff_climb_seconds:
				_takeoff_phase = TakeoffPhase.LEVEL
		TakeoffPhase.LEVEL:
			# Back down to the runway heading, so the plane starts flying level.
			rotation = move_toward(
				rotation, _ground_rotation, deg_to_rad(config.takeoff_level_rate) * delta
			)
			_hold_off_grass()
			if absf(rotation - _ground_rotation) <= 0.002:
				rotation = _ground_rotation
				flight_state = FlightState.AIRBORNE
				dust.emitting = false
	_wrap_horizontal()


## The heading held during the climb-out: a little nose-up above the runway, so
## the plane gains height but keeps most of its travel horizontal.
func _takeoff_nose_up_rotation() -> float:
	var toward_up := -signf(_ground_rotation)
	return _ground_rotation + toward_up * deg_to_rad(config.takeoff_pitch_degrees)


## Keeps the rotating airframe clear of the grass, and lifts the tyres off the
## strip once the nose is properly up. The clearance curve grows smoothly from
## the parked height, so nothing pops when the plane starts to rotate.
func _hold_off_grass() -> void:
	var pitch := absf(rotation - _ground_rotation)
	if not _lifted_off:
		if pitch < deg_to_rad(LIFTOFF_PITCH_DEGREES):
			global_position.y = _ground_level_y
			return
		_lift_off()
	global_position.y = minf(global_position.y, _ground_clear_center_y(rotation))


## Highest the plane's centre may sit without its lowest point going through the
## grass at a given nose angle: parked that point is the belly, nose-up it is the
## tail.
func _ground_clear_center_y(nose_angle: float) -> float:
	var belly := maxf(0.0, ground_y - _ground_level_y)
	var reach := BODY_HALF_LENGTH * MODEL_SCALE
	var lift := belly + (reach - belly) * cos(nose_angle)
	return ground_y - lift


# --- Flight ------------------------------------------------------------------

func _apply_rotation(delta: float) -> void:
	var turn := clampf(_input.turn, -1.0, 1.0)
	rotation += deg_to_rad(config.rotation_speed) * turn * delta
	if config.max_rotation < 180.0:
		var limit := deg_to_rad(config.max_rotation)
		rotation = clampf(rotation, -limit, limit)
	else:
		# Free flight: keep the angle in one turn so loops can go on forever.
		rotation = wrapf(rotation, -PI, PI)


func _fly(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	velocity = forward * current_speed()
	global_position += velocity * delta
	_keep_inside_world()


## Airspeed for the engaged throttle gear, with the jet boost on top while it is
## lit.
func current_speed() -> float:
	var speed := PlaneConfig.gear_speed(config.plane_speed, throttle_gear)
	if boosting:
		speed *= config.boost_multiplier
	return speed


## One gear per tap, and only in the air: on the strip the throttle belongs to the
## take-off run.
func _apply_throttle() -> void:
	if _input.throttle == 0 or flight_state != FlightState.AIRBORNE:
		return
	_set_gear(throttle_gear + _input.throttle)
	_input.throttle = 0


func _set_gear(gear: int) -> void:
	var next := clampi(gear, 1, PlaneConfig.GEAR_FACTORS.size())
	if next == throttle_gear:
		return
	throttle_gear = next
	gear_changed.emit(throttle_gear)


## Keeps the plane in the sky and wraps it around the sides of the map. The flat
## surface is solid: a dive that reaches it ends the flight where it hits.
func _keep_inside_world() -> void:
	var next := global_position
	next.y = clampf(next.y, world_rect.position.y + 80.0, ground_y - GROUND_CLEARANCE)
	if next.y >= ground_y - GROUND_CLEARANCE - 0.5:
		global_position = Vector2(next.x, ground_y - GROUND_CLEARANCE)
		_crash_into_ground()
		return
	global_position = next
	_wrap_horizontal()


## Flying into the field is fatal: the airframe explodes on contact instead of
## skimming along the surface.
func _crash_into_ground() -> void:
	if not is_alive or flight_state != FlightState.AIRBORNE:
		return
	if health.current_health > 0:
		health.take_damage(health.current_health)
	if is_alive:
		_on_died()
	_crash_ground_y = global_position.y
	_finish_crash()


## Exiting one side of the map brings the plane back on the other side at the
## same height and heading (the map is a horizontal loop).
func _wrap_horizontal() -> void:
	var width := world_rect.size.x
	if width <= 0.0:
		return
	var span := width + WRAP_MARGIN * 2.0
	var left := world_rect.position.x - WRAP_MARGIN
	var right := world_rect.end.x + WRAP_MARGIN
	if global_position.x < left:
		global_position.x += span
	elif global_position.x > right:
		global_position.x -= span


## Shortest horizontal offset to another X on the wrapping map, so aiming and
## chasing can pick the side that is actually closer.
static func wrapped_delta_x(from_x: float, to_x: float, bounds: Rect2) -> float:
	var width := bounds.size.x
	var delta := to_x - from_x
	if width <= 0.0:
		return delta
	if delta > width * 0.5:
		delta -= width
	elif delta < -width * 0.5:
		delta += width
	return delta


# --- Weapons -----------------------------------------------------------------

func _update_weapon(delta: float) -> void:
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_bomb_timer = maxf(0.0, _bomb_timer - delta)
	_flare_timer = maxf(0.0, _flare_timer - delta)
	_update_bomb_reload(delta)
	if _input.fire and _fire_timer <= 0.0:
		shoot()
	if _input.bomb and _bomb_timer <= 0.0:
		drop_bomb()
	if _input.flare and _flare_timer <= 0.0:
		launch_flares()


# --- Jet boost ---------------------------------------------------------------

## Burns the tank while the boost is held and refills it once the pilot lets go
## for a moment. An empty tank cannot be lit until it has some charge again, so a
## pilot who drains it has to fly a while on the engine alone.
func _update_boost(delta: float) -> void:
	var wants := _input.boost and nitro > 0.0
	boosting = wants and flight_state == FlightState.AIRBORNE and is_alive
	if boosting:
		nitro = maxf(0.0, nitro - delta / maxf(0.1, config.boost_seconds))
		_boost_hold = config.boost_recharge_delay
		if nitro <= 0.0:
			boosting = false
	elif is_alive and flight_state == FlightState.AIRBORNE:
		_boost_hold = maxf(0.0, _boost_hold - delta)
		if _boost_hold <= 0.0:
			nitro = minf(1.0, nitro + delta / maxf(0.1, config.boost_recharge_seconds))
	if absf(nitro - _boost_sent) >= 0.006 or (nitro >= 1.0) != (_boost_sent >= 1.0):
		_boost_sent = nitro
		boost_changed.emit(nitro)


# --- Bombs -------------------------------------------------------------------

## A bomb leaves the belly: it keeps a little of the plane's forward speed, falls,
## and the match takes care of the blast. The rack is finite.
func drop_bomb() -> void:
	if not is_alive or flight_state != FlightState.AIRBORNE or bombs <= 0:
		return
	bombs -= 1
	_bomb_timer = BOMB_DROP_COOLDOWN
	bombs_changed.emit(bombs)
	if bombs <= 0:
		_start_bomb_reload()
	var forward := Vector2.UP.rotated(rotation)
	var belly := forward.orthogonal()
	var origin := global_position + belly * 16.0 * MODEL_SCALE - forward * 10.0
	var launch_velocity := velocity * 0.32 + belly * 46.0
	bomb_dropped.emit(origin, launch_velocity, player_id)
	_kick_recoil()


## The rack emptied: the ground crew starts winching two fresh bombs up into it.
## Until they are aboard the bomb button is dead, and the wait is shown on it.
func _start_bomb_reload() -> void:
	_bomb_reload_total = maxf(0.1, config.bomb_reload_seconds)
	_bomb_reload = _bomb_reload_total
	_bomb_reload_sent = 1.0
	bomb_reload_changed.emit(1.0)


func _update_bomb_reload(delta: float) -> void:
	if _bomb_reload <= 0.0:
		return
	_bomb_reload = maxf(0.0, _bomb_reload - delta)
	var ratio := _bomb_reload / maxf(0.1, _bomb_reload_total)
	if _bomb_reload <= 0.0:
		bombs = maxi(1, config.start_bombs)
		bombs_changed.emit(bombs)
		_bomb_reload_total = 0.0
		ratio = 0.0
	if not is_equal_approx(ratio, _bomb_reload_sent):
		_bomb_reload_sent = ratio
		bomb_reload_changed.emit(ratio)


## 1 while the rack is empty and filling, 0 when it is ready.
func bomb_reload_ratio() -> float:
	if _bomb_reload <= 0.0 or _bomb_reload_total <= 0.0:
		return 0.0
	return clampf(_bomb_reload / _bomb_reload_total, 0.0, 1.0)


func is_reloading_bombs() -> bool:
	return _bomb_reload > 0.0


## Seconds left on a running reload, for the readout.
func bomb_reload_seconds() -> float:
	return maxf(0.0, _bomb_reload)


# --- Shield ------------------------------------------------------------------

## Spend a charge on a bubble that swallows everything the enemy throws for a few
## seconds. Bullets, shells and blasts all go through `take_damage`, so they are
## stopped in one place; flying into the ground is not.
func activate_shield() -> void:
	if not is_alive or shield_charges <= 0 or shield_time > 0.0:
		return
	shield_charges -= 1
	_start_shield(config.shield_seconds)


## A supply crate hands over more shield charges.
func give_shield(amount: int) -> void:
	if not is_alive or amount <= 0:
		return
	shield_charges += amount
	shield_changed.emit(shield_charges, shield_time)


## Lights the bubble without touching the rack: used for the mirrored copy of the
## other pilot's shield in a LAN duel, which is a picture and nothing more.
func show_shield(seconds: float) -> void:
	shield_time = maxf(shield_time, seconds)
	_shield_total = maxf(_shield_total, seconds)
	shield_changed.emit(shield_charges, shield_time)
	queue_redraw()


func is_shielded() -> bool:
	return shield_time > 0.0


func _start_shield(seconds: float) -> void:
	shield_time = maxf(0.1, seconds)
	_shield_total = shield_time
	shield_changed.emit(shield_charges, shield_time)
	shield_activated.emit(player_id, shield_time)
	queue_redraw()


func _update_shield(delta: float) -> void:
	if _input.shield:
		activate_shield()
	if _shield_flash > 0.0:
		_shield_flash = maxf(0.0, _shield_flash - delta * 3.4)
		queue_redraw()
	if shield_time <= 0.0:
		return
	shield_time = maxf(0.0, shield_time - delta)
	shield_changed.emit(shield_charges, shield_time)
	queue_redraw()


## A bright ripple across the bubble where a round was eaten.
func _play_shield_deflect() -> void:
	_shield_flash = 1.0
	queue_redraw()


## One burst of flares out the back: a handful of burning decoys that a homing
## round will follow instead of the plane, and that will set off a passing bomb
## early. The dispenser is finite and each burst costs one charge.
func launch_flares() -> void:
	if not is_alive or flight_state != FlightState.AIRBORNE or flares <= 0:
		return
	if _flare_timer > 0.0:
		return
	flares -= 1
	_flare_timer = config.flare_cooldown
	flares_changed.emit(flares)
	var forward := Vector2.UP.rotated(rotation)
	var belly := forward.orthogonal()
	var origin := global_position - forward * 14.0 * MODEL_SCALE + belly * 8.0
	flares_launched.emit(origin, -forward, player_id)
	_kick_recoil()


## A supply crate hands over more flares.
func give_flares(amount: int) -> void:
	if not is_alive or amount <= 0:
		return
	flares += amount
	flares_changed.emit(flares)


## Rain on the airframe. Beads slide along the model and water whips off the nose
## in the airstream, which is what makes flying through a shower read as weather
## rather than a screen effect.
func set_rain(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if is_equal_approx(next, rain):
		return
	rain = next
	if model != null:
		model.set_wetness(next)
	if _spray != null:
		_spray.emitting = (next > 0.12 and flight_state == FlightState.AIRBORNE) or (
			next > 0.12 and flight_state == FlightState.TAXIING
		)
		_spray.modulate.a = clampf(next * 1.2, 0.0, 1.0)


func shoot() -> void:
	if not is_alive or flight_state != FlightState.AIRBORNE:
		return
	_fire_timer = config.fire_cooldown
	var forward := Vector2.UP.rotated(rotation)
	var projectile := config.get_projectile_config()
	if special_round != SpecialRound.NONE:
		# A crate round is a single shot: it leaves the muzzle now and the guns go
		# back to ordinary bullets.
		projectile = HOMING_ROUND if special_round == SpecialRound.HOMING else KILLER_ROUND
		special_round = SpecialRound.NONE
		special_changed.emit(special_round)
	projectile_fired.emit(muzzle.global_position, forward, player_id, projectile)
	_play_muzzle_flash()
	_kick_recoil()


## A short flash at the nose, plus a brief backward nudge so firing is felt.
func _play_muzzle_flash() -> void:
	muzzle_flash.visible = true
	muzzle_flash.modulate.a = 1.0
	muzzle_flash.scale = Vector2.ONE * 0.85 * MODEL_SCALE
	muzzle_flash.rotation = randf_range(-0.4, 0.4)
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = create_tween()
	_flash_tween.set_parallel(true)
	_flash_tween.tween_property(muzzle_flash, "scale", Vector2.ONE * 1.35 * MODEL_SCALE, 0.1)
	_flash_tween.tween_property(muzzle_flash, "modulate:a", 0.0, 0.12)
	_flash_tween.chain().tween_callback(func() -> void: muzzle_flash.visible = false)


func _kick_recoil() -> void:
	var tween := create_tween()
	tween.tween_property(visual, "position", Vector2(0.0, 3.5), 0.04)
	tween.tween_property(visual, "position", Vector2.ZERO, 0.09)


# --- Damage ------------------------------------------------------------------

func take_damage(amount: int) -> void:
	if not is_alive:
		return
	if is_shielded():
		_play_shield_deflect()
		return
	hits_taken += 1
	health.take_damage(amount)
	damaged.emit(amount)
	_update_damage_visuals()
	_play_hit_flash()


## Hit one: scorch marks. Hit two: a constant smoke trail. Hit three: the crash.
func _update_damage_visuals() -> void:
	damage_marks.visible = hits_taken >= 1
	smoke.emitting = hits_taken >= 2


func _play_hit_flash() -> void:
	body_sprite.modulate = Color(2.4, 2.2, 2.2)
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.18)


# --- Pickups -----------------------------------------------------------------

## Loads one crate round; the next shot fires it instead of a normal bullet.
func give_special(round_kind: int) -> void:
	if not is_alive or round_kind == SpecialRound.NONE:
		return
	special_round = round_kind
	special_changed.emit(special_round)


func has_special() -> bool:
	return special_round != SpecialRound.NONE


## A repair coin patches the airframe up: full health, no scorch marks and no
## smoke trail, as if it had just rolled off the strip.
func repair() -> void:
	if not is_alive or flight_state == FlightState.CRASHING:
		return
	hits_taken = 0
	health.reset()
	_update_damage_visuals()
	body_sprite.modulate = Color(0.75, 2.2, 0.95)
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.35)


## A partial repair, for the reward on a survival kill: the airframe keeps its
## damage but gets some of its health back, and a knocked-out stage (smoke, then
## scorch marks) comes back with it.
func heal(amount: int) -> void:
	if not is_alive or amount <= 0 or flight_state == FlightState.CRASHING:
		return
	var before := health.current_health
	if before >= health.max_health:
		return
	health.sync_current(mini(health.max_health, before + amount))
	if health.current_health <= before:
		return
	# The three damage stages follow the health bar back up.
	var ratio := health.get_ratio()
	hits_taken = clampi(int(round((1.0 - ratio) * float(PlaneConfig.HITS_TO_KILL))), 0, 3)
	_update_damage_visuals()
	_play_heal_flash()


func _play_heal_flash() -> void:
	body_sprite.modulate = Color(0.75, 2.2, 0.95)
	if _hit_tween != null and _hit_tween.is_valid():
		_hit_tween.kill()
	_hit_tween = create_tween()
	_hit_tween.tween_property(body_sprite, "modulate", Color.WHITE, 0.3)


func _on_health_changed(current: int, maximum: int) -> void:
	health_changed.emit(current, maximum)


## Out of health: stop flying, start falling. The round only ends on impact.
func _on_died() -> void:
	if flight_state == FlightState.CRASHING:
		return
	is_alive = false
	is_launched = false
	flight_state = FlightState.CRASHING
	collision_layer = 0
	_input.reset()
	velocity = Vector2.ZERO
	_crash_fall_speed = 90.0
	_crash_drift = clampf(Vector2.UP.rotated(rotation).x * config.plane_speed * 0.45, -70.0, 70.0)
	_crash_spin = CRASH_SPIN_SPEED * 0.55 * (-1.0 if rotation > 0.0 else 1.0)
	smoke.emitting = true


func _update_crash(delta: float) -> void:
	_crash_fall_speed = minf(CRASH_MAX_FALL_SPEED, _crash_fall_speed + CRASH_GRAVITY * delta)
	# The wreck keeps a little forward momentum, then it bleeds off as it drops.
	_crash_drift = move_toward(_crash_drift, 0.0, 45.0 * delta)
	var next := global_position
	next.y += _crash_fall_speed * delta
	next.x = clampf(next.x + _crash_drift * delta, world_rect.position.x + 30.0, world_rect.end.x - 30.0)
	global_position = next

	# It noses over toward the ground and tumbles, the spin easing off as the dive
	# steepens - a stall into a spiral rather than a spinning top.
	var nose_down := PI if rotation >= 0.0 else -PI
	rotation = move_toward(rotation, nose_down, CRASH_NOSE_OVER_RATE * delta)
	_crash_spin = move_toward(_crash_spin, 0.0, CRASH_SPIN_DECAY * delta)
	rotation = wrapf(rotation + _crash_spin * delta, -PI, PI)

	if global_position.y >= _crash_ground_y:
		_finish_crash()


## Hits the surface: the wreck is replaced by the explosion and the round ends.
func _finish_crash() -> void:
	global_position.y = _crash_ground_y
	flight_state = FlightState.PARKED
	velocity = Vector2.ZERO
	visible = false
	smoke.emitting = false
	destroyed.emit(self)


# --- Presentation ------------------------------------------------------------

func _animate(delta: float) -> void:
	_engine_time += delta
	_update_ground_shadow()
	_update_righting(delta)
	var target_spin := 34.0 if is_alive else 6.0
	if flight_state == FlightState.CRASHING:
		target_spin = 10.0
	_spin_speed = lerpf(_spin_speed, target_spin, minf(1.0, delta * 4.0))
	if model != null:
		model.set_propeller_speed(_spin_speed)
		# Wheels roll with the take-off run and stop once the gear leaves the
		# strip.
		var ground_speed := _taxi_speed if flight_state == FlightState.TAXIING else 0.0
		model.set_wheel_speed(ground_speed / PlaneModel3D.WHEEL_RADIUS)
		# Gear is out on the strip and tucked away as soon as it lifts off.
		var on_wheels := flight_state == FlightState.PARKED \
			or (flight_state == FlightState.TAXIING and not _lifted_off)
		model.set_gear_down(on_wheels)

	if _afterburner != null:
		_afterburner.emitting = boosting and is_alive
	if _spray != null:
		var wet := rain > 0.12 and is_alive
		_spray.emitting = wet and (
			flight_state == FlightState.AIRBORNE or flight_state == FlightState.TAXIING
		)
		_spray.modulate.a = clampf(rain * 1.1, 0.0, 0.7)

	# The jet flame is drawn on the airframe itself, so it is always visible at the
	# tail even when the particles are hidden behind a wing.
	if boosting != _flame_drawn:
		_flame_drawn = boosting
		queue_redraw()
	elif boosting:
		# It flickers, so it redraws every frame while it burns.
		queue_redraw()

	if flight_state == FlightState.AIRBORNE or flight_state == FlightState.CRASHING:
		# Engine vibration; it gets rougher as the airframe takes damage.
		var shake := 0.7 + float(hits_taken) * 1.2
		visual.position = Vector2(sin(_engine_time * 42.0) * shake, cos(_engine_time * 37.0) * shake * 0.7)
	elif flight_state == FlightState.TAXIING:
		# Rolling over the grass: a light rumble instead of a dead-still airframe.
		visual.position = Vector2(0.0, sin(_engine_time * 34.0) * 0.9)
	else:
		visual.position = visual.position.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))


## Keeps the cast shadow on the field: it spreads and fades as the plane climbs,
## which is the only cue for altitude in a flat side view.
func _update_ground_shadow() -> void:
	if ground_shadow == null:
		return
	ground_shadow.visible = visible
	ground_shadow.global_position = Vector2(global_position.x, ground_y + 9.0)
	var altitude := clampf(ground_y - global_position.y, 0.0, 1800.0)
	var t := altitude / 1800.0
	ground_shadow.scale = Vector2.ONE * lerpf(0.85, 1.7, t)
	ground_shadow.modulate.a = lerpf(0.95, 0.16, t)


## The hitbox is authored for the full-size airframe, so scale a per-instance copy
## to match the smaller model (scene shapes are shared between instances).
func _apply_hitbox() -> void:
	var shape_node := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if shape_node == null or not (shape_node.shape is CapsuleShape2D):
		return
	var capsule := shape_node.shape.duplicate() as CapsuleShape2D
	capsule.radius *= MODEL_SCALE
	capsule.height *= MODEL_SCALE
	shape_node.shape = capsule


## Keeps the airframe the right way up through a loop. Past the vertical the side
## view would show the plane on its back, so the model rolls half a turn about its
## own fuselage axis: the nose keeps its heading while a wing sweeps up through
## the profile and the aircraft comes out the other side, belly down. Nothing is
## mirrored, so the plane never appears to fly backwards, and the roll is animated
## over RIGHTING_SECONDS rather than snapped.
func _update_righting(delta: float) -> void:
	# Which way the belly points: the model is built nose-right with the belly down,
	# and the opponent flies the same model drawn mirrored.
	var belly := sin(rotation)
	if config != null and config.visual_flip_h:
		belly = -belly
	if belly > RIGHTING_DEADBAND:
		_righting_target = 0.0
	elif belly < -RIGHTING_DEADBAND:
		_righting_target = 1.0

	_righting = move_toward(_righting, _righting_target, delta / RIGHTING_SECONDS)
	if model != null:
		model.set_roll(_righting * PI)


## 0 in daylight, 1 in the dark. Drives the lamp at the nose.
func set_night(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if is_equal_approx(next, night):
		return
	night = next
	queue_redraw()


## The lamp under the nose and the jet flame at the tail, both drawn under the
## airframe so they light the sky instead of painting over the wings.
func _draw() -> void:
	if shield_time > 0.0:
		_draw_shield()
	if boosting:
		_draw_boost_flame()
	if night <= 0.02:
		return
	var lamp_origin := Vector2(0.0, -NOSE_OFFSET * MODEL_SCALE)
	var warm := Color(1.0, 0.95, 0.78)
	# Nested wedges instead of a shader: three cones stacked give the falloff.
	_draw_beam(lamp_origin, 0.36, 620.0, Color(warm, 0.045 * night))
	_draw_beam(lamp_origin, 0.22, 520.0, Color(warm, 0.055 * night))
	_draw_beam(lamp_origin, 0.11, 390.0, Color(warm, 0.070 * night))
	# The lamp itself, and the halo bleeding around it.
	draw_circle(lamp_origin, 30.0, Color(warm, 0.09 * night))
	draw_circle(lamp_origin, 14.0, Color(1.0, 0.98, 0.9, 0.20 * night))
	draw_circle(lamp_origin, 4.6, Color(1.0, 1.0, 0.94, 0.75 * night))


## The shield bubble: a tall ellipse of light around the airframe, with a rim, an
## inner ring and two arcs sweeping round it, punched brighter wherever it just
## swallowed a hit. Drawn before the model, so the bubble sits behind the plane.
func _draw_shield() -> void:
	var fade := clampf(shield_time / 1.2, 0.15, 1.0)
	var pulse := 0.86 + 0.14 * sin(_engine_time * 5.5)
	var flash := _shield_flash
	var tint := Color(0.55, 0.74, 1.0)
	var rim_alpha := (0.68 + 0.3 * flash) * fade
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 1.3))
	draw_circle(Vector2.ZERO, 82.0, Color(tint, (0.14 + 0.14 * flash) * fade))
	draw_circle(Vector2.ZERO, 74.0, Color(tint.lightened(0.2), (0.06 + 0.12 * flash) * fade))
	draw_arc(Vector2.ZERO, 82.0, 0.0, TAU, 72, Color(tint, rim_alpha * pulse), 3.0, true)
	draw_arc(Vector2.ZERO, 72.0, 0.0, TAU, 72, Color(tint, rim_alpha * 0.34), 1.6, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Two arcs running round the bubble, so it reads as energy rather than a decal.
	var sweep := fmod(_engine_time * 1.5, TAU)
	draw_arc(Vector2.ZERO, 76.0, sweep, sweep + 1.1, 20, Color(1.0, 1.0, 1.0, 0.46 * fade), 3.4, true)
	draw_arc(
		Vector2.ZERO, 91.0, sweep + PI, sweep + PI + 0.8, 16, Color(1.0, 1.0, 1.0, 0.22 * fade), 2.2, true
	)


## Three nested cones of blue-white fire streaming off the tail, flickering with
## the engine so it reads as a lit jet rather than a static wedge.
func _draw_boost_flame() -> void:
	var tail := Vector2(0.0, TAIL_OFFSET * MODEL_SCALE)
	var flicker := 0.8 + 0.2 * sin(_engine_time * 52.0) + 0.06 * sin(_engine_time * 91.0)
	_draw_flame_cone(tail, 9.5, 66.0 * flicker, Color(0.35, 0.7, 1.0, 0.26))
	_draw_flame_cone(tail, 6.0, 46.0 * flicker, Color(0.62, 0.9, 1.0, 0.42))
	_draw_flame_cone(tail, 3.0, 27.0 * flicker, Color(1.0, 1.0, 1.0, 0.72))


func _draw_flame_cone(
	apex: Vector2, half_width: float, length: float, color: Color
) -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				apex + Vector2(-half_width, 0.0),
				apex + Vector2(half_width, 0.0),
				apex + Vector2(0.0, length),
			]
		),
		color
	)


func _draw_beam(apex: Vector2, spread: float, reach: float, color: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				apex,
				apex + Vector2.UP.rotated(-spread) * reach,
				apex + Vector2.UP.rotated(spread) * reach,
			]
		),
		color
	)


## The two trails a plane can wear: a jet flame behind the tail while the boost is
## lit, and water whipping off the nose in the rain. Built here so each plane owns
## its own particles.
func _build_flight_fx() -> void:
	var puff: Texture2D = preload("res://assets/effects/smoke_puff.svg")

	_afterburner = CPUParticles2D.new()
	_afterburner.position = Vector2(0.0, TAIL_OFFSET * MODEL_SCALE)
	_afterburner.emitting = false
	_afterburner.amount = 30
	_afterburner.lifetime = 0.3
	_afterburner.local_coords = false
	_afterburner.texture = puff
	_afterburner.direction = Vector2(0.0, 1.0)
	_afterburner.spread = 10.0
	_afterburner.gravity = Vector2.ZERO
	_afterburner.initial_velocity_min = 90.0
	_afterburner.initial_velocity_max = 230.0
	_afterburner.scale_amount_min = 0.22
	_afterburner.scale_amount_max = 0.5
	var flame := Gradient.new()
	flame.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	flame.colors = PackedColorArray(
		[
			Color(0.85, 0.97, 1.0, 0.95),
			Color(0.42, 0.68, 1.0, 0.6),
			Color(0.2, 0.35, 0.9, 0.0),
		]
	)
	_afterburner.color_ramp = flame
	_afterburner.z_index = -1
	add_child(_afterburner)

	_spray = CPUParticles2D.new()
	_spray.position = Vector2(0.0, -NOSE_OFFSET * MODEL_SCALE * 0.55)
	_spray.emitting = false
	_spray.amount = 22
	_spray.lifetime = 0.26
	_spray.local_coords = false
	_spray.texture = puff
	_spray.direction = Vector2(0.0, 1.0)
	_spray.spread = 62.0
	_spray.gravity = Vector2(0.0, 120.0)
	_spray.initial_velocity_min = 50.0
	_spray.initial_velocity_max = 140.0
	_spray.scale_amount_min = 0.04
	_spray.scale_amount_max = 0.10
	var water := Gradient.new()
	water.offsets = PackedFloat32Array([0.0, 1.0])
	water.colors = PackedColorArray([Color(0.94, 0.98, 1.0, 0.8), Color(0.8, 0.92, 1.0, 0.0)])
	_spray.color_ramp = water
	add_child(_spray)


func _apply_visual_state() -> void:
	dust.emitting = false
	muzzle_flash.visible = false
	body_sprite.modulate = Color.WHITE
	visual.position = Vector2.ZERO
	damage_marks.visible = false
	smoke.emitting = false
	boosting = false
	if _afterburner != null:
		_afterburner.emitting = false
	if _spray != null:
		_spray.emitting = false
