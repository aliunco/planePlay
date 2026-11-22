class_name GameManager
extends Node2D
## Owns one match: builds the world from configuration, spawns the airplanes with
## their controllers, pools projectiles, follows the camera and reports results.

enum Mode { SINGLE_PLAYER, LOCAL_VERSUS, LAN, SURVIVAL }
enum State { READY, FLYING, FINISHED }

signal match_finished(winner_id: int, mode: int)
signal quit_to_menu_requested

const AIRPLANE_SCENE: PackedScene = preload("res://scenes/airplane/airplane.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/projectile/projectile.tscn")
const EXPLOSION_SCENE: PackedScene = preload("res://scenes/effects/explosion.tscn")
## Slow, weak tracer the ground soldiers fire at both planes.
const SOLDIER_PROJECTILE: ProjectileConfig = preload("res://resources/configurations/projectile_soldier.tres")
const PROJECTILE_POOL_SIZE: int = 28

## The courier plane: how soon the first pass comes, how long between passes, and
## how high and how fast it crosses.
const COURIER_FIRST_DELAY: float = 2.5
const COURIER_INTERVAL_MIN: float = 24.0
const COURIER_INTERVAL_MAX: float = 36.0
const COURIER_ALTITUDE_MIN: float = 620.0
const COURIER_ALTITUDE_MAX: float = 1150.0
const COURIER_SPEED_MIN: float = 150.0
const COURIER_SPEED_MAX: float = 215.0
## Slow enough to be caught with a dive, quick enough that loitering underneath is
## not enough: a drop is only worth something if you go and get it.
const COIN_FALL_SPEED: float = 112.0
const CRATE_FALL_SPEED: float = 132.0
## Drop routes, the opening sky and the time of day are all drawn from one key per
## session, so two matches never play out the same. Both ends of a LAN match use
## the host's key, so they still drop the same pickup in the same place.
const PICKUP_MARGIN: float = 240.0
## How far the radar dial reaches; a little under a screen's width.
const RADAR_RANGE: float = 1200.0
## Survival: how long a replacement fighter takes to roll out onto the strip.
const SURVIVAL_RESPAWN_DELAY: float = 1.6
## Survival: how far from the player the replacement climbs out of the grass.
const SURVIVAL_SPAWN_DISTANCE: float = 900.0
## Multiplayer duels never end: after a crash the next round rolls the two
## fighters back onto their strips this many seconds later.
const DUEL_RESET_DELAY: float = 2.4
## Moonlight over the world at full dark. Dark enough to read as night, light
## enough that the field, the squad and the planes still show up.
const NIGHT_TINT: Color = Color(0.36, 0.44, 0.74)

@export var game_config: GameConfig
@export var player_plane_config: PlaneConfig
@export var opponent_plane_config: PlaneConfig

var mode: Mode = Mode.SINGLE_PLAYER
var difficulty: AIConfig.Difficulty = AIConfig.Difficulty.NORMAL
## Which fighter from PlaneRoster this match was launched with.
var plane_index: int = 0
## Rounds each pilot has taken in an endless duel. Index 0 is player 1.
var round_wins: Array[int] = [0, 0]
## True while a finished duel round is waiting to roll the next one out, so a
## second crash in the same blast cannot count twice.
var _round_resetting: bool = false
## What the sky is doing. Chosen on the title screen; survival changes it on its
## own every minute or so, fading one kind into the next.
var weather: int = Weather.Kind.CLEAR
var _start_weather: int = Weather.Kind.CLEAR
var _weather_strength: float = 1.0
var _weather_layer: WeatherLayer
var _weather_timer: float = 0.0
var _weather_tween: Tween
var state: State = State.READY
var player: Airplane
var opponent: Airplane

## Survival run: how many fighters this run has shot down, and the best run
## saved on this device. The current run raises the best as soon as it passes it.
var score: int = 0
var best_score: int = 0

var _record_to_beat: int = 0
var _record_announced: bool = false
## Bumped whenever a new run starts, so a pending respawn from the old run is
## dropped instead of dropping an enemy into a fresh match.
var _run_id: int = 0
var _survival_rng := RandomNumberGenerator.new()
var _day: DayCycle
var _night_tint: CanvasModulate

var _ai_config: AIConfig
var _projectile_pool: Array[Projectile] = []
## Last gear each pilot was heard at, so a shift knows which way it went.
var _gear_seen: Dictionary = {}
var _pool_cursor: int = 0
var _is_paused: bool = false
var _net_send_timer: float = 0.0
var _quality_timer: float = 0.0
## Hits this device landed on the other pilot that its device has not confirmed
## yet. While any are outstanding the heartbeat must not overwrite the damage.
var _pending_hits: int = 0
var _pending_age: float = 0.0
var _hit_seq: int = 0
var _courier_timer: float = COURIER_FIRST_DELAY
var _courier: CourierPlane
var _pickup_rng := RandomNumberGenerator.new()
## This session's key for the drops, the sky and the day cycle.
var _session_seed: int = 0
## False while a LAN guest is still waiting for the host's key: nothing drops
## until both screens share it.
var _pickup_seeded: bool = true

@onready var sky: SkyBackdrop = $SkyLayer/Sky
@onready var landscape: Landscape = $World/Landscape
@onready var soldiers: SoldierField = $World/Soldiers
@onready var hills: HillSilhouettes = $World/Hills
@onready var clouds: CloudField = $World/Clouds
@onready var ground_depth: GroundDepth = $World/GroundDepth
@onready var planes_root: Node2D = $World/Planes
@onready var projectiles_root: Node2D = $World/Projectiles
@onready var pickups_root: Node2D = $World/Pickups
@onready var world_root: Node2D = $World
@onready var effects_root: Node2D = $World/Effects
@onready var camera: CameraController = $Camera
@onready var hud: GameHUD = $HUD
@onready var mobile_controls: MobileControls = $MobileControls
@onready var audio: AudioManager = $Audio


## Called before the node enters the tree so _ready builds the right match.
func setup(
	match_mode: Mode,
	ai_difficulty: AIConfig.Difficulty,
	weather_kind: int = Weather.Kind.CLEAR,
	fighter_index: int = 0
) -> void:
	mode = match_mode
	difficulty = ai_difficulty
	weather = weather_kind
	_start_weather = weather_kind
	plane_index = clampi(fighter_index, 0, PlaneRoster.count() - 1)


func _ready() -> void:
	if game_config == null:
		game_config = GameConfig.new()
	if player_plane_config == null:
		player_plane_config = load("res://resources/configurations/plane_player.tres") as PlaneConfig
	if opponent_plane_config == null:
		opponent_plane_config = load("res://resources/configurations/plane_opponent.tres") as PlaneConfig

	_session_seed = _roll_session_seed()
	_prepare_aircraft()
	_settle_weather()
	_configure_world()
	_build_day_cycle()
	_build_weather()
	_build_projectile_pool()
	_spawn_aircraft()
	_configure_soldiers()
	_configure_camera()
	_survival_rng.randomize()
	_load_survival_record()
	_configure_hud()
	_pickup_rng.seed = _session_seed
	_build_courier()
	state = State.READY
	hud.set_prompt(_launch_prompt())
	mobile_controls.set_launch_highlight(true)


## Gives both fighters a roster airframe: the one picked on the title screen, and
## for an AI opponent a deliberately different one drawn from the session key.
func _prepare_aircraft() -> void:
	player_plane_config = player_plane_config.duplicate_for_instance()
	PlaneRoster.apply(player_plane_config, plane_index)
	var rival := plane_index
	if mode == Mode.SINGLE_PLAYER or mode == Mode.SURVIVAL:
		rival = PlaneRoster.rival_for(plane_index, _session_seed)
	# The opponent keeps its crimson paint whatever airframe it flies, so the two
	# pilots are never the same colour.
	opponent_plane_config = opponent_plane_config.duplicate_for_instance()
	PlaneRoster.apply(opponent_plane_config, rival, false)


## A fresh key for this session. The two random generators the match uses are kept
## apart from it, so nothing else can advance the drop sequence underneath it.
func _roll_session_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi()


## A session that asked for AUTO rolls its own opening sky. A chosen one is kept:
## the weather row on the title screen is a decision, not a hint.
func _settle_weather() -> void:
	if weather >= 0:
		_start_weather = weather
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = _session_seed
	weather = _roll_weather(rng)
	_start_weather = weather


## Mostly clear, often overcast, now and then a storm: a session that starts in
## AUTO should usually begin in good weather, not in the middle of a downpour.
func _roll_weather(rng: RandomNumberGenerator) -> int:
	var roll := rng.randf()
	if roll < 0.45:
		return Weather.Kind.CLEAR
	if roll < 0.72:
		return Weather.Kind.CLOUDY
	if roll < 0.90:
		return Weather.Kind.RAIN
	return Weather.Kind.SNOW


## Where in the day a session opens, from the same key. Both ends of a LAN match
## read this from the host's key, so the two screens fly the same sky.
func _day_phase_for(seed_value: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng.randf()


func _launch_prompt() -> String:
	if mode == Mode.LOCAL_VERSUS:
		return "Player 1: W    ·    Player 2: ↑    to take off"
	return "Press ▲  or  ↑ / W  to take off"


func _world_rect() -> Rect2:
	return Rect2(
		Vector2(0.0, game_config.world_top),
		Vector2(game_config.world_width, game_config.world_bottom - game_config.world_top)
	)


func _configure_world() -> void:
	var clears: Array[float] = [
		game_config.player_start_x,
		game_config.opponent_start_x,
	]
	landscape.configure(
		game_config.world_width,
		game_config.ground_y,
		game_config.ground_depth,
		clears
	)
	hills.configure(game_config.world_width, game_config.ground_y)
	clouds.world_width = game_config.world_width
	clouds.camera = camera
	ground_depth.configure(game_config.ground_y, game_config.world_width)


# --- Planes ------------------------------------------------------------------

func _spawn_aircraft() -> void:
	var second_config := opponent_plane_config
	if mode == Mode.SINGLE_PLAYER or mode == Mode.SURVIVAL:
		_ai_config = AIConfig.preset(difficulty)
		second_config = opponent_plane_config.duplicate_for_instance()
		second_config.fire_cooldown = maxf(0.08, second_config.fire_cooldown * _ai_config.fire_cooldown_scale)

	player = _create_airplane(player_plane_config, 1)
	opponent = _create_airplane(second_config, 2)

	player.reset_for_round(game_config.get_player_spawn())
	opponent.reset_for_round(game_config.get_opponent_spawn())

	match mode:
		Mode.SINGLE_PLAYER, Mode.SURVIVAL:
			_attach_controller(player, _make_human_controller(true))
			var ai := AIController.new()
			ai.config = _ai_config
			_attach_controller(opponent, ai)
			ai.setup(player, _world_rect(), _ai_config)
		Mode.LOCAL_VERSUS:
			_attach_controller(player, _make_human_controller(false))
			var second_controller := PlayerPlaneController.new()
			second_controller.turn_left_action = &"p2_left"
			second_controller.turn_right_action = &"p2_right"
			second_controller.fire_action = &"p2_fire"
			second_controller.launch_action = &"p2_launch"
			_attach_controller(opponent, second_controller)
		Mode.LAN:
			_setup_lan()


# --- Ground soldiers ---------------------------------------------------------

## Infantry are part of the difficulty: Easy has none, Hard has a lively ground
## war. Versus and LAN matches use the Normal squad so both screens agree.
func _configure_soldiers() -> void:
	var plan := AIConfig.preset(AIConfig.Difficulty.NORMAL)
	if _ai_config != null:
		plan = _ai_config

	soldiers.set_planes([player, opponent])
	soldiers.configure(
		plan.soldier_count,
		game_config.ground_y,
		game_config.world_width,
		[game_config.player_start_x, game_config.opponent_start_x],
		plan.soldier_interval_min,
		plan.soldier_interval_max
	)
	soldiers.shot_fired.connect(_on_soldier_fired)


## A soldier squeezed off a round: spawn it without touching plane cooldowns.
func _on_soldier_fired(origin: Vector2, direction: Vector2) -> void:
	if state == State.FINISHED:
		return
	var projectile := _next_projectile()
	# Owner id 0 matches neither pilot, so a soldier round can hit either plane.
	projectile.spawn(SOLDIER_PROJECTILE, origin, direction, 0, 0.0, _world_rect())


func _make_human_controller(allow_alternate_keys: bool) -> PlayerPlaneController:
	var controller := PlayerPlaneController.new()
	controller.turn_left_action = &"p1_left"
	controller.turn_right_action = &"p1_right"
	controller.fire_action = &"p1_fire"
	controller.launch_action = &"p1_launch"
	controller.accept_alternate_keys = allow_alternate_keys
	return controller


## The airplane this device drives. In a LAN match the host owns the left plane
## and the client owns the right one; every other mode is always player 1.
func local_plane() -> Airplane:
	if mode != Mode.LAN:
		return player
	return player if Lan.is_host() else opponent


## The airplane the other device drives.
func remote_plane() -> Airplane:
	if mode != Mode.LAN:
		return opponent
	return opponent if Lan.is_host() else player


func _setup_lan() -> void:
	# Each device keeps its own airplane under local control with the same key
	# set, and mirrors the other pilot's intent through the transport.
	_attach_controller(local_plane(), _make_human_controller(true))
	var remote_controller := RemotePlaneController.new()
	_attach_controller(remote_plane(), remote_controller)
	Lan.remote_input.connect(remote_controller.push_input)
	Lan.remote_state.connect(_on_remote_state)
	Lan.bomb_dropped.connect(_on_lan_bomb)
	Lan.flares_launched.connect(_on_lan_flares)
	Lan.shield_used.connect(_on_lan_shield)
	Lan.session_seeded.connect(_on_session_seed)
	# The host owns the session key and the shared airframe; the guest waits for
	# both before anything drops.
	if Lan.is_host():
		Lan.send_session_seed(_session_seed, plane_index)
	else:
		_pickup_seeded = false
	Lan.damage_received.connect(_on_lan_damage)
	Lan.hit_acknowledged.connect(_on_lan_hit_ack)
	Lan.peer_left.connect(_on_lan_peer_left)


func _create_airplane(config: PlaneConfig, id: int) -> Airplane:
	var plane: Airplane = AIRPLANE_SCENE.instantiate()
	plane.player_id = id
	plane.config = config
	plane.world_rect = _world_rect()
	plane.ground_y = game_config.ground_y
	planes_root.add_child(plane)
	return plane


func _attach_controller(plane: Airplane, controller: AirplaneController) -> void:
	plane.add_child(controller)
	controller.bind(plane)
	plane.controller = controller


func _connect_plane_signals(plane: Airplane) -> void:
	plane.projectile_fired.connect(_on_projectile_fired)
	plane.destroyed.connect(_on_plane_destroyed)
	plane.launched.connect(_on_plane_launched)
	plane.damaged.connect(_on_plane_damaged)
	plane.special_changed.connect(
		func(round_kind: int) -> void:
			hud.set_special(plane.player_id, round_kind)
	)
	plane.bomb_dropped.connect(_on_plane_bomb_dropped)
	plane.bombs_changed.connect(
		func(count: int) -> void:
			hud.set_bombs(plane.player_id, count)
	)
	plane.boost_changed.connect(
		func(ratio: float) -> void:
			hud.set_boost(plane.player_id, ratio)
	)
	plane.flares_launched.connect(_on_plane_flares)
	plane.flares_changed.connect(
		func(count: int) -> void:
			hud.set_flares(plane.player_id, count)
	)
	plane.shield_activated.connect(_on_plane_shield)
	plane.shield_changed.connect(
		func(charges: int, remaining: float) -> void:
			hud.set_shield(plane.player_id, charges, remaining)
	)
	plane.bomb_reload_changed.connect(
		func(_ratio: float) -> void:
			var seconds := plane.bomb_reload_seconds()
			hud.set_bomb_reload(plane.player_id, seconds)
			if plane == local_plane():
				mobile_controls.set_bomb_reload(plane.bomb_reload_ratio())
	)
	plane.health_changed.connect(
		func(current: int, maximum: int) -> void:
			hud.set_health(plane.player_id, current, maximum)
	)
	_gear_seen[plane.player_id] = plane.throttle_gear
	plane.gear_changed.connect(
		func(gear: int) -> void:
			hud.set_gear(plane.player_id, gear, PlaneConfig.GEAR_FACTORS.size())
			if plane == local_plane() and plane.is_airborne():
				_play_gear_shift(plane.player_id, gear)
	)


## The engine note jumps a step when the throttle moves: a short blip upward for
## a shift up, the same sweep downward for a shift down, a little higher the
## further up the box you are.
func _play_gear_shift(player_id: int, gear: int) -> void:
	var previous: int = int(_gear_seen.get(player_id, gear))
	_gear_seen[player_id] = gear
	if gear == previous:
		return
	var pitch := 1.0 + float(gear - 1) * 0.06
	audio.play(&"gear_up" if gear > previous else &"gear_down", pitch)


# --- Camera / HUD ------------------------------------------------------------

func _configure_camera() -> void:
	camera.configure(_world_rect(), game_config.camera_zoom, game_config.camera_follow_speed)
	camera.mode = (
		CameraController.Mode.FRAME_BOTH
		if mode == Mode.LOCAL_VERSUS
		else CameraController.Mode.FOLLOW
	)
	camera.set_target(local_plane())
	camera.set_second_target(opponent if mode == Mode.LOCAL_VERSUS else null)
	camera.snap_to_target()


func _configure_hud() -> void:
	_connect_plane_signals(player)
	_connect_plane_signals(opponent)

	hud.setup_names(_name_for_player(1), _name_for_player(2), _mode_text())
	hud.set_health(1, player.health.current_health, player.health.max_health)
	hud.set_health(2, opponent.health.current_health, opponent.health.max_health)
	hud.set_gear(1, player.throttle_gear, PlaneConfig.GEAR_FACTORS.size())
	hud.set_gear(2, opponent.throttle_gear, PlaneConfig.GEAR_FACTORS.size())
	hud.set_bombs(1, player.bombs)
	hud.set_bombs(2, opponent.bombs)
	hud.set_boost(1, player.nitro)
	hud.set_boost(2, opponent.nitro)
	hud.set_flares(1, player.flares)
	hud.set_flares(2, opponent.flares)
	hud.set_shield(1, player.shield_charges, player.shield_time)
	hud.set_shield(2, opponent.shield_charges, opponent.shield_time)
	hud.set_bomb_reload(1, player.bomb_reload_seconds())
	hud.set_bomb_reload(2, opponent.bomb_reload_seconds())
	mobile_controls.set_bomb_reload(player.bomb_reload_ratio())
	hud.set_radar_visible(mode != Mode.LOCAL_VERSUS)
	hud.set_score_visible(mode == Mode.SURVIVAL)
	hud.set_score(score, best_score)
	if _is_duel():
		_update_tally()
	hud.pause_pressed.connect(_pause_match)
	hud.resume_pressed.connect(_resume_match)
	hud.restart_pressed.connect(restart_match)
	hud.menu_pressed.connect(_return_to_menu)


func _name_for_player(id: int) -> String:
	if mode == Mode.LAN:
		return "You" if id == local_plane().player_id else "Opponent"
	if id == 1:
		return player_plane_config.display_name
	if (mode == Mode.SINGLE_PLAYER or mode == Mode.SURVIVAL) and _ai_config != null:
		return "AI (%s)" % _difficulty_name(difficulty)
	return opponent_plane_config.display_name


func _difficulty_name(value: AIConfig.Difficulty) -> String:
	match value:
		AIConfig.Difficulty.EASY:
			return "Easy"
		AIConfig.Difficulty.HARD:
			return "Hard"
		_:
			return "Normal"


func _mode_text() -> String:
	var text := _base_mode_text()
	if weather != Weather.Kind.CLEAR:
		text += "  ·  %s" % Weather.label(weather)
	return text


func _base_mode_text() -> String:
	match mode:
		Mode.SINGLE_PLAYER:
			return "Single player  ·  %s" % _difficulty_name(difficulty)
		Mode.LOCAL_VERSUS:
			return "Two players  ·  same screen"
		Mode.SURVIVAL:
			return "Survival  ·  %s" % _difficulty_name(difficulty)
		_:
			var role := "host" if Lan.is_host() else "joined"
			var quality := Lan.connection_quality_text()
			if quality.is_empty():
				return "LAN match  ·  %s" % role
			return "LAN match  ·  %s  ·  %s" % [role, quality]


# --- Network -----------------------------------------------------------------

func _process(delta: float) -> void:
	_update_engine_sound()
	_update_radar()
	_update_night(delta)
	_update_rain()


## Drives the water on both airframes straight from the weather, so a shower that
## fades in also wets the planes gradually and dries them off the same way.
func _update_rain() -> void:
	var amount := _weather_strength if weather == Weather.Kind.RAIN else 0.0
	if player != null and is_instance_valid(player):
		player.set_rain(amount)
	if opponent != null and is_instance_valid(opponent):
		opponent.set_rain(amount)


## The scanner under the pilot card: where the enemy is relative to the pilot at
## this device, plus the courier and whatever it has dropped, so a load can be
## found off screen.
##
## The dial is a picture of the sky around the plane, so the marks are measured
## the way the screen draws them, not the short way round the wrapping map. That
## is what makes the enemy dot agree with the arrow at the start of a match: the
## two planes begin more than half a map apart, and the short way round would put
## an enemy you can see ahead of you behind the dial.
func _update_radar() -> void:
	var me := local_plane()
	var enemy := remote_plane()
	if me == null or enemy == null or not is_instance_valid(enemy):
		return
	hud.set_radar(
		_offset_from(me, enemy.global_position), RADAR_RANGE, me.rotation, enemy.is_alive
	)

	var courier_offset := Vector2.ZERO
	var has_courier := _courier != null and _courier.is_flying()
	if has_courier:
		courier_offset = _offset_from(me, _courier.global_position)

	var drop_offset := Vector2.ZERO
	var drop_kind := -1
	var has_drop := false
	for child in pickups_root.get_children():
		var pickup := child as SkyPickup
		if pickup != null and not pickup.is_taken():
			drop_offset = _offset_from(me, pickup.global_position)
			drop_kind = pickup.kind
			has_drop = true
			break
	hud.set_radar_cargo(courier_offset, has_courier, drop_offset, drop_kind, has_drop)


## A world point as the camera draws it relative to a plane: no wrapping, so a
## mark on the dial is always in the direction the player would fly to reach it
## on screen.
func _offset_from(origin: Airplane, world_point: Vector2) -> Vector2:
	return world_point - origin.global_position


## The engine note follows the local airplane: a low idle while it waits on the
## strip, a heavier note as it rolls, and then one step of pitch and volume per
## throttle gear. It dies with the engine and goes quiet on the result screen.
func _update_engine_sound() -> void:
	if state == State.FINISHED:
		audio.set_engine(false)
		return
	var plane := local_plane()
	if plane == null or not is_instance_valid(plane) or not plane.is_alive:
		audio.set_engine(false)
		return
	match plane.flight_state:
		Airplane.FlightState.PARKED:
			audio.set_engine(true, 0.74, -28.0)
		Airplane.FlightState.TAXIING:
			audio.set_engine(true, 0.92, -24.0)
		Airplane.FlightState.CRASHING:
			audio.set_engine(false)
		_:
			var gear := clampi(plane.throttle_gear, 1, PlaneConfig.GEAR_FACTORS.size())
			audio.set_engine(true, 0.84 + 0.19 * float(gear - 1), -26.0 + 3.0 * float(gear))


func _physics_process(delta: float) -> void:
	# Pickups tick on physics frames in every mode, so a LAN match spawns them at
	# the same moments on both devices.
	_update_pickups(delta)
	_update_weather(delta)

	if mode != Mode.LAN or state == State.FINISHED:
		return
	if _pending_hits > 0:
		_pending_age += delta
		if _pending_age > 2.0:
			# The confirmation never arrived (a peer that dropped mid-hit): let the
			# heartbeat reconcile again instead of freezing the bar forever.
			_pending_hits = 0
			_pending_age = 0.0
	var local := local_plane()
	if local == null:
		return

	# Lockstep: both devices run the same simulation, so only the intent of this
	# device's own airplane has to travel.
	Lan.send_input(local.get_current_input())

	_net_send_timer += delta
	if _net_send_timer >= 0.25:
		_net_send_timer = 0.0
		Lan.send_state(
			local.global_position, local.rotation, local.flight_state, local.health.current_health, local.is_alive
		)

	# Keep the ping/loss readout in the mode label current.
	_quality_timer += delta
	if _quality_timer >= 1.0:
		_quality_timer = 0.0
		hud.set_mode_text(_mode_text())


## The other pilot's heartbeat: only used to heal a drifting simulation, the
## local prediction is what the player sees frame to frame.
func _on_remote_state(state_data: Dictionary) -> void:
	var remote := remote_plane()
	if remote == null or not remote.is_alive or remote.is_crashing():
		return

	var position: Vector2 = state_data.get("position", remote.global_position)
	var error := position.distance_to(remote.global_position)
	if error > 140.0:
		remote.global_position = position
	elif error > 3.0:
		remote.global_position = remote.global_position.lerp(position, 0.3)
	remote.rotation = float(state_data.get("rotation", remote.rotation))

	var health_value := int(state_data.get("health", remote.health.current_health))
	if _pending_hits > 0:
		# This heartbeat was sampled before the hit we already show landed on his
		# device, so adopting its older number is exactly what used to bounce the
		# bar backwards (and leave one screen showing a live pilot the other had
		# already shot down).
		return
	remote.health.sync_current(health_value)


func _on_lan_peer_left() -> void:
	if mode != Mode.LAN:
		return
	get_tree().paused = false
	_is_paused = false
	InputManager.clear_virtual_actions()
	quit_to_menu_requested.emit()


# --- Projectiles / effects ---------------------------------------------------

func _build_projectile_pool() -> void:
	for i in PROJECTILE_POOL_SIZE:
		var projectile: Projectile = PROJECTILE_SCENE.instantiate()
		projectiles_root.add_child(projectile)
		projectile.hit_plane.connect(_on_projectile_hit_plane)
		_projectile_pool.append(projectile)


## Every bullet hit lands here. Offline it is a plain damage call. In a LAN match
## the device that fired the bullet decides the hit and the airplane's own device
## applies the same amount, so both copies of a pilot always lose the same health
## and cannot end up with one dead and the other alive.
func _on_projectile_hit_plane(plane: Airplane, damage: int, owner_id: int) -> void:
	if plane == null or not plane.is_alive:
		return
	if mode != Mode.LAN:
		plane.take_damage(damage)
		return
	var local := local_plane()
	if local == null:
		plane.take_damage(damage)
		return
	var my_id := local.player_id

	if owner_id == 0:
		# Ground fire is simulated on both devices. Only the airplane's own device
		# applies it; its heartbeat carries the result to the other one, so a
		# soldier round is never counted twice.
		if plane.player_id == my_id:
			plane.take_damage(damage)
		return

	if owner_id != my_id:
		# Somebody else's bullet: the device that fired it is the authority and is
		# already sending the hit to its victim. Applying it here as well would
		# double the damage.
		return

	plane.take_damage(damage)
	if plane.player_id != my_id:
		_hit_seq += 1
		_pending_hits += 1
		_pending_age = 0.0
		Lan.send_damage(plane.player_id, damage, _hit_seq)


## Our airplane was hit: apply exactly what the other pilot's device decided, then
## confirm it so its copy can trust the heartbeat again.
func _on_lan_damage(victim_id: int, amount: int, hit_id: int) -> void:
	var local := local_plane()
	if local == null or local.player_id != victim_id or not local.is_alive:
		return
	local.take_damage(amount)
	Lan.send_hit_ack(victim_id, hit_id)


func _on_lan_hit_ack(_victim_id: int, _hit_id: int) -> void:
	if _pending_hits > 0:
		_pending_hits -= 1
		_pending_age = 0.0


func _next_projectile() -> Projectile:
	for i in _projectile_pool.size():
		var index := (_pool_cursor + i) % _projectile_pool.size()
		if not _projectile_pool[index].is_active:
			_pool_cursor = (index + 1) % _projectile_pool.size()
			return _projectile_pool[index]
	# Everything is in flight: recycle the oldest slot.
	var fallback := _projectile_pool[_pool_cursor]
	_pool_cursor = (_pool_cursor + 1) % _projectile_pool.size()
	fallback.deactivate()
	return fallback


func _on_projectile_fired(
	origin: Vector2, direction: Vector2, owner_id: int, round_config: ProjectileConfig
) -> void:
	var shooter := player if player != null and owner_id == player.player_id else opponent
	if shooter == null or shooter.config == null or round_config == null:
		return
	var target := opponent if shooter == player else player
	var projectile := _next_projectile()
	projectile.spawn(
		round_config,
		origin,
		direction,
		owner_id,
		shooter.config.plane_speed,
		_world_rect(),
		target if round_config.homing else null
	)
	var is_special := round_config.homing or round_config.lethal
	audio.play("special_shot" if is_special else "shoot")
	# A homing round on its way to an AI pilot is what flares are for: it answers
	# with a burst, a beat late, exactly as a human would reach for the button.
	if round_config.homing:
		_try_ai_flares(target)


## The AI's answer to a homing round. The short delay is the point: a flare that
## lit the instant the trigger was pulled would read as immunity rather than a
## reaction, and a round already close enough will still land.
func _try_ai_flares(plane: Airplane) -> void:
	if plane == null or not is_instance_valid(plane) or not plane.is_alive:
		return
	if not (plane.controller is AIController) or plane.flares <= 0:
		return
	await get_tree().create_timer(0.4).timeout
	if state == State.FINISHED:
		return
	if plane == null or not is_instance_valid(plane) or not plane.is_alive:
		return
	plane.launch_flares()


# --- Bombs -------------------------------------------------------------------

## A pilot let a bomb go: spawn it, and in a LAN duel tell the other device so
## both screens watch the same thing fall.
func _on_plane_bomb_dropped(origin: Vector2, velocity: Vector2, owner_id: int) -> void:
	if state == State.FINISHED:
		return
	_spawn_bomb(origin, velocity, owner_id, true)
	audio.play("bomb")
	if mode == Mode.LAN:
		Lan.send_bomb(origin, velocity, owner_id)


## The other pilot's bomb, mirrored here for the picture only: the blast itself
## is decided on the device that dropped it.
func _on_lan_bomb(origin: Vector2, velocity: Vector2, owner_id: int) -> void:
	if state == State.FINISHED:
		return
	_spawn_bomb(origin, velocity, owner_id, false)


func _spawn_bomb(origin: Vector2, velocity: Vector2, owner_id: int, authoritative: bool) -> Bomb:
	var owner_plane := player if player != null and owner_id == player.player_id else opponent
	if owner_plane == null or owner_plane.config == null:
		return null
	var bomb := Bomb.new()
	bomb.authoritative = authoritative
	projectiles_root.add_child(bomb)
	bomb.exploded.connect(_on_bomb_exploded)
	bomb.launch(
		origin,
		velocity,
		owner_id,
		owner_plane.config.bomb_damage,
		owner_plane.config.bomb_blast_radius,
		[player, opponent],
		game_config.ground_y,
		_world_rect()
	)
	return bomb


## The host's key has arrived: take its drop sequence, its sky, its time of day
## and its fighter, then let the courier start its rounds. Both ends of a LAN
## duel fly the same airframe, so the guest adopts the host's pick.
func _on_session_seed(seed_value: int, host_plane: int) -> void:
	if mode != Mode.LAN:
		return
	_session_seed = seed_value
	_pickup_rng.seed = _session_seed
	_pickup_seeded = true
	if _day != null:
		_day.phase = _day_phase_for(_session_seed)
	plane_index = clampi(host_plane, 0, PlaneRoster.count() - 1)
	for plane: Airplane in [player, opponent]:
		if plane != null and is_instance_valid(plane):
			plane.apply_airframe(plane_index, false)
	mobile_controls.set_bomb_reload(player.bomb_reload_ratio())
	if _is_duel():
		_update_tally()


# --- Shield ------------------------------------------------------------------

func _on_plane_shield(owner_id: int, seconds: float) -> void:
	audio.play("shield")
	if mode == Mode.LAN:
		Lan.send_shield(owner_id, seconds)


## The other pilot's bubble, drawn here too: the damage itself is already decided
## on the device that owns the plane, so this is only the picture.
func _on_lan_shield(owner_id: int, seconds: float) -> void:
	var plane := player if player != null and owner_id == player.player_id else opponent
	if plane == null or not is_instance_valid(plane):
		return
	plane.show_shield(seconds)
	audio.play("shield")


# --- Flares ------------------------------------------------------------------

## A pilot burned a burst of flares. Everyone sees and hears it; in a LAN duel the
## other device is told as well, because its homing rounds are the ones that have
## to be fooled.
func _on_plane_flares(origin: Vector2, direction: Vector2, owner_id: int) -> void:
	if state == State.FINISHED:
		return
	_spawn_flares(origin, direction, owner_id)
	audio.play("flare")
	if mode == Mode.LAN:
		Lan.send_flares(origin, direction, owner_id)


func _on_lan_flares(origin: Vector2, direction: Vector2, owner_id: int) -> void:
	if state == State.FINISHED:
		return
	_spawn_flares(origin, direction, owner_id)


## A handful of burning decoys fanned out behind the plane, each with its own
## speed and spread so they scatter into a curtain instead of moving as a block.
func _spawn_flares(origin: Vector2, direction: Vector2, owner_id: int) -> void:
	var owner_plane := player if player != null and owner_id == player.player_id else opponent
	if owner_plane == null or owner_plane.config == null:
		return
	var base := direction.angle() if direction.length_squared() > 0.0001 else -PI * 0.5
	for i in maxi(1, owner_plane.config.flares_per_burst):
		var flare := Flare.new()
		effects_root.add_child(flare)
		var angle := base + deg_to_rad(randf_range(-34.0, 34.0))
		flare.launch(origin, Vector2.RIGHT.rotated(angle) * randf_range(110.0, 230.0), owner_id)


## A bomb burst. Everyone sees and hears it; only the device that dropped it works
## out who was inside the blast (the radius damage goes through the same
## authority path as a bullet, so a LAN hit is still decided exactly once).
func _on_bomb_exploded(at: Vector2, owner_id: int, authoritative: bool) -> void:
	_spawn_explosion(at, 1.2)
	audio.play("explode")
	if authoritative:
		camera.shake(11.0, 0.35)
	if not authoritative:
		return
	var owner_plane := player if player != null and owner_id == player.player_id else opponent
	if owner_plane == null or owner_plane.config == null:
		return
	var radius := owner_plane.config.bomb_blast_radius
	var damage := owner_plane.config.bomb_damage
	if radius <= 0.0 or damage <= 0:
		return
	for plane: Airplane in [player, opponent]:
		if plane == null or not is_instance_valid(plane) or not plane.is_alive:
			continue
		# The pilot who dropped it is never caught in his own blast.
		if plane.player_id == owner_id:
			continue
		var distance := at.distance_to(plane.global_position)
		if distance > radius:
			continue
		var falloff := 1.0 - 0.7 * clampf(distance / radius, 0.0, 1.0)
		var dealt := maxi(8, int(round(float(damage) * falloff)))
		_on_projectile_hit_plane(plane, dealt, owner_id)


func _clear_bombs() -> void:
	for child in projectiles_root.get_children():
		if child is Bomb:
			child.queue_free()


# --- Courier and pickups -----------------------------------------------------

func _build_courier() -> void:
	_courier = CourierPlane.new()
	world_root.add_child(_courier)
	_courier.dropped.connect(_on_courier_dropped)


## One pass at a time, and only once the sky is clear of the last drop.
func _update_pickups(delta: float) -> void:
	if state != State.FLYING:
		return
	# A LAN guest holds the first pass until the host's key is in: a drop that
	# differs between screens is worse than one that is late.
	if not _pickup_seeded:
		return
	_courier_timer -= delta
	if _courier_timer > 0.0:
		return
	if _courier.is_flying() or _pickup_in_the_air():
		_courier_timer = 2.0
		return
	_send_courier()


## Where the pass goes and what it carries come from the seeded generator, so a
## LAN match drops the same thing in the same place on both devices. Aiming the
## pass at the screen only happens when there is no second device to agree with.
func _send_courier() -> void:
	var altitude := _pickup_rng.randf_range(COURIER_ALTITUDE_MIN, COURIER_ALTITUDE_MAX)
	var from_left := _pickup_rng.randf() < 0.5
	var flight_speed := _pickup_rng.randf_range(COURIER_SPEED_MIN, COURIER_SPEED_MAX)
	var roll := _pickup_rng.randf()
	# Repair gear is the most common load by some distance: a run ends from
	# attrition more often than from a clean hit, and the sky is a big place to
	# go looking for a coin.
	var kind := SkyPickup.Kind.REPAIR
	if roll >= 0.55:
		if roll < 0.68:
			kind = SkyPickup.Kind.HOMING
		elif roll < 0.80:
			kind = SkyPickup.Kind.SHIELD
		elif roll < 0.90:
			kind = SkyPickup.Kind.FLARES
		else:
			kind = SkyPickup.Kind.KILLER

	var drop_x: float
	if mode == Mode.LAN:
		drop_x = _pickup_rng.randf_range(PICKUP_MARGIN, game_config.world_width - PICKUP_MARGIN)
	else:
		var view_x := camera.get_screen_center_position().x
		drop_x = clampf(
			view_x + _pickup_rng.randf_range(-300.0, 300.0),
			PICKUP_MARGIN,
			game_config.world_width - PICKUP_MARGIN
		)
	_courier.launch(drop_x, altitude, game_config.ground_y, flight_speed, from_left, kind)
	_courier_timer = _pickup_rng.randf_range(COURIER_INTERVAL_MIN, COURIER_INTERVAL_MAX)


func _on_courier_dropped(at: Vector2, kind: int) -> void:
	if state != State.FLYING:
		return
	var pickup := SkyPickup.new()
	pickup.kind = kind
	_track_pickup(pickup)
	pickup.drop(
		at,
		game_config.ground_y,
		COIN_FALL_SPEED if kind == SkyPickup.Kind.REPAIR else CRATE_FALL_SPEED
	)


func _pickup_in_the_air() -> bool:
	for child in pickups_root.get_children():
		var pickup := child as SkyPickup
		if pickup != null and not pickup.is_taken():
			return true
	return false


func _track_pickup(pickup: SkyPickup) -> void:
	pickups_root.add_child(pickup)
	pickup.collected.connect(_on_pickup_collected)


func _on_pickup_collected(pickup: SkyPickup, plane: Airplane) -> void:
	match pickup.kind:
		SkyPickup.Kind.REPAIR:
			plane.repair()
			audio.play("repair")
		SkyPickup.Kind.KILLER:
			plane.give_special(Airplane.SpecialRound.KILLER)
			audio.play("special")
		SkyPickup.Kind.SHIELD:
			plane.give_shield(plane.config.shield_per_crate)
			audio.play("shield")
		SkyPickup.Kind.FLARES:
			plane.give_flares(plane.config.flares_per_crate)
			audio.play("special")
		_:
			plane.give_special(Airplane.SpecialRound.HOMING)
			audio.play("special")
	if plane == local_plane():
		camera.shake(4.0, 0.2)


func _clear_pickups() -> void:
	for child in pickups_root.get_children():
		child.queue_free()
	_courier_timer = COURIER_FIRST_DELAY
	if _courier != null:
		_courier.stop()


func _spawn_explosion(at: Vector2, size_scale: float = 1.0) -> void:
	var explosion: Node2D = EXPLOSION_SCENE.instantiate()
	explosion.position = at
	explosion.scale = Vector2.ONE * size_scale
	effects_root.add_child(explosion)


func _clear_effects() -> void:
	for child in effects_root.get_children():
		child.queue_free()


# --- Match flow --------------------------------------------------------------

func _on_plane_launched(plane: Airplane) -> void:
	audio.play("launch")
	if plane == local_plane():
		hud.set_prompt("")
		mobile_controls.set_launch_highlight(false)
		state = State.FLYING


func _on_plane_damaged(_amount: int) -> void:
	audio.play("hit")
	camera.shake(7.0, 0.3)


func _on_plane_destroyed(plane: Airplane) -> void:
	# Survival never ends on the enemy's crash: it is the next one's cue.
	if mode == Mode.SURVIVAL and plane == opponent:
		_register_survival_kill()
		return
	# A duel is endless: every crash is a round for the other pilot.
	if _is_duel():
		_register_duel_round(plane.player_id)
		return
	if state == State.FINISHED:
		return
	state = State.FINISHED
	hud.set_prompt("")
	_spawn_explosion(plane.global_position, 1.6)
	camera.shake(18.0, 0.65)
	audio.play("explode")
	var winner_id := 2 if plane.player_id == 1 else 1
	await get_tree().create_timer(1.5).timeout
	if not is_inside_tree():
		return
	match_finished.emit(winner_id, mode)


## An endless duel on one screen or over LAN: the two pilots never stop flying,
## and the scoreboard is how many rounds each side has taken.
func _is_duel() -> bool:
	return mode == Mode.LOCAL_VERSUS or mode == Mode.LAN


func restart_match() -> void:
	get_tree().paused = false
	_is_paused = false
	hud.set_paused(false)
	_run_id += 1
	_round_resetting = false
	if _is_duel():
		round_wins[0] = 0
		round_wins[1] = 0
		_update_tally()
	if mode == Mode.SURVIVAL:
		score = 0
		_load_survival_record()
		hud.set_score(score, best_score)
		_apply_weather(_start_weather, 1.0)
		_weather_timer = 55.0
		hud.set_mode_text(_mode_text())

	for projectile in _projectile_pool:
		projectile.deactivate()
	_clear_bombs()
	_clear_effects()
	_clear_pickups()

	_pending_hits = 0
	_pending_age = 0.0
	player.reset_for_round(game_config.get_player_spawn())
	opponent.reset_for_round(game_config.get_opponent_spawn())
	if opponent.controller is AIController:
		(opponent.controller as AIController).reset_state()
	soldiers.reset_field()

	hud.set_health(1, player.health.current_health, player.health.max_health)
	hud.set_health(2, opponent.health.current_health, opponent.health.max_health)
	hud.set_prompt(_launch_prompt())
	mobile_controls.set_launch_highlight(true)
	state = State.READY
	camera.snap_to_target()


func _pause_match() -> void:
	if state == State.FINISHED or _is_paused:
		return
	_is_paused = true
	get_tree().paused = true
	hud.set_paused(true)
	mobile_controls.release_all()
	# Duck the engine while paused; it comes back by itself on resume.
	audio.set_engine(false)


func _resume_match() -> void:
	_is_paused = false
	get_tree().paused = false
	hud.set_paused(false)


func _return_to_menu() -> void:
	get_tree().paused = false
	_is_paused = false
	InputManager.clear_virtual_actions()
	quit_to_menu_requested.emit()


# --- Endless duel ------------------------------------------------------------

## One pilot went down: the other takes the round, the tally moves, and both
## fighters roll out again a moment later. There is no final score to hand to an
## overlay, which is the point of a duel you can stay in all evening.
func _register_duel_round(loser_id: int) -> void:
	if _round_resetting or state == State.FINISHED:
		return
	_round_resetting = true
	var winner_id := 2 if loser_id == 1 else 1
	round_wins[winner_id - 1] += 1
	var loser := player if loser_id == 1 else opponent
	if loser != null and is_instance_valid(loser):
		_spawn_explosion(loser.global_position, 1.6)
	camera.shake(16.0, 0.6)
	audio.play("explode")
	_update_tally(true)
	var round_number := round_wins[0] + round_wins[1]
	hud.set_prompt("%s TAKES ROUND %d" % [_duel_side_name(winner_id), round_number])
	mobile_controls.set_launch_highlight(false)

	var run := _run_id
	await get_tree().create_timer(DUEL_RESET_DELAY).timeout
	if not is_inside_tree() or run != _run_id:
		return
	_round_resetting = false
	if state == State.FINISHED or not _is_duel():
		return
	_reset_duel_round()


## Both fighters back on their strips, nothing in the air, the same scoreboard.
func _reset_duel_round() -> void:
	for projectile in _projectile_pool:
		projectile.deactivate()
	_clear_bombs()
	_clear_effects()
	_clear_pickups()
	_pending_hits = 0
	_pending_age = 0.0
	player.reset_for_round(game_config.get_player_spawn())
	opponent.reset_for_round(game_config.get_opponent_spawn())
	if opponent.controller is AIController:
		(opponent.controller as AIController).reset_state()
	soldiers.reset_field()
	hud.set_prompt(_launch_prompt())
	mobile_controls.set_launch_highlight(true)
	state = State.READY
	camera.snap_to_target()


func _duel_side_name(player_id: int) -> String:
	if mode == Mode.LAN:
		return "YOU" if player_id == local_plane().player_id else "THE OTHER PILOT"
	return "PLAYER %d" % player_id


## "ROUND 4  ·  YOU 2  —  1 THEM" from this device's point of view in a LAN
## match, and straight pilot numbers when both share one screen.
func _tally_text() -> String:
	var round_number := round_wins[0] + round_wins[1] + 1
	if mode == Mode.LAN:
		var local_id := 1 if Lan.is_host() else 2
		return "ROUND %d  ·  YOU %d  —  %d THEM" % [
			round_number, round_wins[local_id - 1], round_wins[2 - local_id]
		]
	return "ROUND %d  ·  P1 %d  —  %d P2" % [round_number, round_wins[0], round_wins[1]]


func _update_tally(flash: bool = false) -> void:
	if hud == null or not _is_duel():
		return
	hud.set_tally(_tally_text(), flash)


# --- Survival ----------------------------------------------------------------

func _load_survival_record() -> void:
	_record_to_beat = SurvivalRecord.load_best()
	best_score = _record_to_beat
	_record_announced = false


## One enemy down: count it, save the run if it is a new best, and roll the next
## fighter out onto the strip. The player's own crash is handled by the wipeout
## path, which ends the run.
func _register_survival_kill() -> void:
	score += 1
	_spawn_explosion(opponent.global_position, 1.6)
	camera.shake(14.0, 0.5)
	audio.play("explode")

	# A kill patches the pilot up a little: a long run should be survivable by
	# flying well, not only by finding a repair coin every ninety seconds.
	if player != null and is_instance_valid(player) and player.is_alive:
		var heal := game_config.survival_kill_heal
		if heal > 0:
			player.heal(heal)

	if score > best_score:
		best_score = score
		SurvivalRecord.save_best(best_score)
		if not _record_announced and score > _record_to_beat:
			_record_announced = true
			_announce_record()
	hud.set_score(score, best_score)

	var run := _run_id
	await get_tree().create_timer(SURVIVAL_RESPAWN_DELAY).timeout
	if not is_inside_tree() or run != _run_id:
		return
	if state == State.FINISHED or mode != Mode.SURVIVAL:
		return
	_respawn_opponent()


## The record banner is a prompt, so it borrows the prompt line and then clears
## itself instead of sitting there over the fight.
func _announce_record() -> void:
	hud.set_prompt("NEW RECORD  ·  %d" % score)
	await get_tree().create_timer(2.2).timeout
	if not is_inside_tree() or hud == null:
		return
	if hud.prompt_label.text.begins_with("NEW RECORD"):
		hud.set_prompt("")


## A fresh enemy fighter waits on the strip a little way down the map, then takes
## off by itself.
func _respawn_opponent() -> void:
	if opponent == null or not is_instance_valid(opponent):
		return
	opponent.reset_for_round(_survival_spawn())
	var ai := opponent.controller as AIController
	if ai != null:
		ai.reset_state()
	opponent.take_off()
	hud.set_health(2, opponent.health.current_health, opponent.health.max_health)
	camera.shake(6.0, 0.2)


func _survival_spawn() -> Vector2:
	var width := game_config.world_width
	var side := -1.0 if _survival_rng.randf() < 0.5 else 1.0
	var x := fposmod(player.global_position.x + side * SURVIVAL_SPAWN_DISTANCE, width)
	x = clampf(x, 280.0, width - 280.0)
	return Vector2(x, game_config.ground_y - game_config.parked_height)


# --- Weather -----------------------------------------------------------------

func _build_weather() -> void:
	_weather_layer = WeatherLayer.new()
	# Its own canvas, above the world and below the vignette: the weather falls in
	# front of the planes but never over the interface.
	var canvas := CanvasLayer.new()
	canvas.layer = 6
	add_child(canvas)
	canvas.add_child(_weather_layer)
	_weather_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_apply_weather(weather, 1.0)
	_weather_timer = 55.0


## One place that tells the sky, the clouds, the world tint and the falling
## precipitation what the weather is, so they can never disagree.
func _apply_weather(kind: int, strength: float) -> void:
	var changed := kind != weather
	weather = kind
	_weather_strength = clampf(strength, 0.0, 1.0)
	if _weather_layer != null:
		_weather_layer.set_weather(kind, _weather_strength)
	if sky != null:
		sky.set_weather(kind, _weather_strength)
	if clouds != null:
		clouds.set_weather(kind, _weather_strength)
	# The mode line carries the weather, so it follows every change rather than
	# only the ones survival rolls.
	if changed and hud != null:
		hud.set_mode_text(_mode_text())


## Survival weather: mostly clear, sometimes overcast, now and then a rainstorm.
## Other modes keep the weather chosen on the title screen.
func _update_weather(delta: float) -> void:
	if mode != Mode.SURVIVAL or state != State.FLYING:
		return
	_weather_timer -= delta
	if _weather_timer > 0.0:
		return
	_weather_timer = _survival_rng.randf_range(55.0, 95.0)
	var roll := _survival_rng.randf()
	var next := Weather.Kind.CLEAR
	if roll >= 0.55:
		next = Weather.Kind.CLOUDY if roll < 0.80 else Weather.Kind.RAIN
	_change_weather(next)


## Fades the current weather out, switches, and fades the new one in, so a
## survival run watches the sky close in rather than snap.
func _change_weather(kind: int) -> void:
	if kind == weather:
		return
	if _weather_tween != null and _weather_tween.is_valid():
		_weather_tween.kill()
	_weather_tween = create_tween()
	_weather_tween.tween_method(_set_weather_strength, _weather_strength, 0.0, 1.6)
	_weather_tween.tween_callback(_switch_weather.bind(kind))
	_weather_tween.tween_method(_set_weather_strength, 0.0, 1.0, 2.4)


func _switch_weather(kind: int) -> void:
	_apply_weather(kind, 0.0)


func _set_weather_strength(strength: float) -> void:
	_apply_weather(weather, strength)


# --- Day and night -----------------------------------------------------------

func _build_day_cycle() -> void:
	_day = DayCycle.new()
	# A session can open at dawn, at midday or in the dark: the key decides, and
	# the sun then runs its usual arc from there.
	_day.start_phase = _day_phase_for(_session_seed)
	add_child(_day)
	# The world is one canvas, so a single tint over it turns the whole scene from
	# daylight to moonlight. The sky and the HUD live on their own layers and are
	# untouched by it.
	_night_tint = CanvasModulate.new()
	add_child(_night_tint)
	sky.attach_cycle(_day)


func _update_night(_delta: float) -> void:
	if _day == null or _night_tint == null:
		return
	# Night and weather both dim the world, and they multiply: a rainy night is
	# darker than a clear one, but never pitch black.
	var night := Color.WHITE.lerp(NIGHT_TINT, _day.night())
	var cover := Color.WHITE.lerp(Weather.world_tint(weather), _weather_strength)
	_night_tint.color = Color(night.r * cover.r, night.g * cover.g, night.b * cover.b, 1.0)
	var lamp := _day.lamp()
	if player != null and is_instance_valid(player):
		player.set_night(lamp)
	if opponent != null and is_instance_valid(opponent):
		opponent.set_night(lamp)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action(&"toggle_mobile_controls"):
		mobile_controls.toggle_forced()
	elif event.is_action(&"restart"):
		restart_match()
