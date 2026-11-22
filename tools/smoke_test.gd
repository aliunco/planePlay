extends Node
## Headless smoke test scene. Drives real matches through the real input path and
## prints PASS/FAIL lines, so gameplay logic can be verified without a display.
##
##   godot --headless --fixed-fps 60 --path . res://tools/smoke_test.tscn

var _frame: int = 0
var _main: Node
var _game: GameManager
var _failures: int = 0
var _phase: String = "boot"
var _result := {}
var _start_rotation: float = 0.0
var _ground_x: float = 0.0
var _ground_y: float = 0.0
var _own_damage_health: int = -1
var _launch_sent := false
var _crash_y: float = 0.0
var _loop_from: float = 0.0
var _impact_checked := false
var _impact_frame: int = 0
var _cloud_start := Vector2.ZERO
var _cloud_frame_start: int = -1
var _soldier_shots_before: int = 0
var _pitch_x: float = 0.0
var _pitch_rotation: float = 0.0
var _gear_before: int = 0
var _speed_before: float = 0.0
var _engine_pitch_before: float = 0.0
var _enemy_health_before: int = 0
## Flare checks: the homing round and the bomb that the burning decoys are
## supposed to steal.
var _flare_round: Projectile = null
var _flare_test: Flare = null
var _flare_bomb: Bomb = null
## The player's health just before a survival kill, so the reward can be measured.
var _player_health_before: int = 0
## The saved survival record before this run, restored when the test ends so the
## developer's own best score is not overwritten.
var _record_backup: int = -1


func _ready() -> void:
	print("=== smoke test start ===")
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)


func _latest_game() -> GameManager:
	var host := _main.get_node("GameHost")
	for i in range(host.get_child_count() - 1, -1, -1):
		var child := host.get_child(i)
		if child is GameManager and not child.is_queued_for_deletion():
			return child as GameManager
	return null


func _process(_delta: float) -> void:
	_frame += 1
	# Give the app a couple of frames to settle before driving the menu. Phase
	# resets restart the counter at 0, so this must only apply to the first phase.
	if _phase == "boot" and _frame < 3:
		return

	match _phase:
		"boot":
			_main.get_node("MenuLayer/MainMenu").play_requested.emit(
				GameManager.Mode.SINGLE_PLAYER, AIConfig.Difficulty.NORMAL
			)
			_phase = "spawned"

		"spawned":
			_game = _latest_game()
			if _game == null:
				return
			_check_spawn()
			_phase = "launch"
			_frame = 0

		"launch":
			if _frame == 6:
				_start_rotation = _game.player.rotation
				_ground_x = _game.player.global_position.x
				_ground_y = _game.player.global_position.y
				Input.action_press(&"p1_launch")
				_launch_sent = true
			elif _frame == 14 and _launch_sent:
				Input.action_release(&"p1_launch")
				_check("player started its take-off roll", _game.player.is_launched)
				_check("player is still on the ground while rolling", not _game.player.is_airborne())
			elif _frame == 45:
				_check("player slid forward along the surface", _game.player.global_position.x > _ground_x + 20.0)
				_check(
					"player stayed on the surface while rolling",
					absf(_game.player.global_position.y - _ground_y) < 1.0
				)
			elif _frame == 120:
				# Lift-off has just happened: the gear is folding, not gone.
				_check(
					"the gear folds away instead of vanishing",
					_game.player.model._gear_root.visible
					and absf((_game.player.model._gear_hinges[0] as Node3D).rotation.z) > 0.001
				)
			elif _frame == 132:
				_check(
					"the legs are still swinging halfway through the retraction",
					_game.player.model._gear_root.visible
					and absf((_game.player.model._gear_hinges[0] as Node3D).rotation.z) > deg_to_rad(5.0)
				)
			elif _frame == 175:
				_check(
					"the gear is hidden once it is inside the wing",
					not _game.player.model._gear_root.visible
				)
			elif _frame == 104:
				_pitch_x = _game.player.global_position.x
				_pitch_rotation = _game.player.rotation
			elif _frame == 114:
				_check(
					"the plane keeps rolling while it raises its nose",
					_game.player.global_position.x > _pitch_x + 4.0
				)
				_check(
					"the nose comes up during the take-off roll",
					absf(_game.player.rotation) < absf(_pitch_rotation) - 0.05
				)
				_check(
					"the airframe lifts clear of the grass as the nose comes up",
					_game.player.global_position.y < _ground_y - 8.0
				)
			elif _frame == 245:
				_check("player became airborne after the roll", _game.player.is_airborne())
				_check("player climbed after pitching up", _game.player.global_position.y < _ground_y - 20.0)
				_check(
					"the plane levels off into horizontal flight",
					absf(absf(_game.player.rotation) - PI * 0.5) < 0.05
				)
				_start_rotation = _game.player.rotation
				Input.action_press(&"p1_left")
			elif _frame == 265:
				Input.action_release(&"p1_left")
				Input.action_press(&"p1_fire")
				_check("turning left rotated the nose left", _game.player.rotation < _start_rotation - 0.01)
				_phase = "flying"
				_frame = 0

		"flying":
			if _frame % 12 == 0:
				Input.action_press(&"p1_fire")
			if _frame == 70:
				_gear_before = _game.player.throttle_gear
				_speed_before = _game.player.current_speed()
				_engine_pitch_before = _game.audio._engine_target_pitch
				Input.action_press(&"p1_launch")
			if _frame == 71:
				Input.action_release(&"p1_launch")
			if _frame == 75:
				_check(
					"a tap of up shifts the throttle up a gear",
					_game.player.throttle_gear == _gear_before + 1
				)
				_check(
					"a higher gear flies faster",
					_game.player.current_speed() > _speed_before + 1.0
				)
				_check(
					"the gears are spread wide enough to feel",
					PlaneConfig.GEAR_FACTORS[0] <= 0.6 and PlaneConfig.GEAR_FACTORS[3] >= 1.9
				)
				_check(
					"shifting up has its own engine blip",
					_game.audio._streams.has(&"gear_up") and _game.audio._streams.has(&"gear_down")
				)
			if _frame == 78:
				var drone: AudioStreamWAV = _game.audio._engine_player.stream
				_check("the engine drone is running", _game.audio._engine_player.playing)
				_check(
					"the engine loop repeats without a click",
					drone.loop_mode == AudioStreamWAV.LOOP_FORWARD
					and absi(
						drone.data.decode_s16(0) - drone.data.decode_s16(drone.data.size() - 2)
					) < 2000
				)
				_check(
					"a higher gear raises the engine note",
					_game.audio._engine_target_pitch > _engine_pitch_before
				)
			if _frame == 45:
				_check("the radar is up when you are hunting one opponent", _game.hud._radar.visible)
				_check("projectile pool spawned a bullet", _count_active_projectiles() > 0)
				_own_damage_health = _game.player.health.current_health
				_game._on_projectile_fired(
					_game.player.global_position, Vector2.UP, 1, _game.player.config.get_projectile_config()
				)
			if _frame == 55:
				_check("projectiles never damage their owner", _game.player.health.current_health == _own_damage_health)
				_check_clouds_moved()
			if _frame == 60:
				# Force one soldier's countdown to expire on the next tick; the shot
				# must travel through the real projectile pool.
				_soldier_shots_before = _soldier_shots()
				var squad: Array = _game.soldiers._soldiers
				if not squad.is_empty():
					(squad[0] as Soldier)._timer = 0.0
				else:
					_check("a squad is available to fire", false)
			if _frame == 70:
				_check("a soldier fired a tracer at the planes", _soldier_shots() > _soldier_shots_before)
			if _frame == 100:
				_check("AI took off after its launch delay", _game.opponent.is_launched)
			if _frame == 140:
				Input.action_release(&"p1_fire")
				_check_camera()
				_check(
					"both planes climbed above the ground",
					_game.player.global_position.y < 0.0 and _game.opponent.global_position.y < 0.0
				)
				_game.match_finished.connect(
					func(winner_id: int, mode: int) -> void: _result = {"winner": winner_id, "mode": mode}
				)
				_phase = "loop"
				_frame = 0

		"loop":
			if _frame == 2:
				_check("rotation is not capped at 80 degrees", _game.player.config.max_rotation >= 180.0)
				_loop_from = _game.player.rotation
				Input.action_press(&"p1_left")
			elif _frame == 90:
				# Half a second after the nose crossed the vertical the airframe has
				# rolled about its fuselage axis, so it flies belly-down instead of
				# upside down - with a roll, never a mirrored sprite.
				_check(
					"an inverted plane rolls onto its other side instead of flying upside down",
					_game.player.model.roll() > 2.8
				)
				_check(
					"the rolled airframe is not a mirrored sprite (the plane never flies backwards)",
					_game.player.visual.scale.x > 0.0
				)
			elif _frame == 100:
				Input.action_release(&"p1_left")
				var turned := absf(wrapf(_game.player.rotation - _loop_from, -PI, PI))
				_check("the nose can turn past 90 degrees", turned > deg_to_rad(100.0))
				_phase = "wrap"
				_frame = 0

		"wrap":
			if _frame == 2:
				_game.player.global_position.x = _game._world_rect().end.x + 140.0
			elif _frame == 4:
				_check(
					"flying off the right edge returns on the left",
					_game.player.global_position.x < 260.0
				)
				# The camera is clamped to the world limits, so a plane that wraps near
				# an edge cannot be centred: "snapped" means it jumped to that end of
				# the map instead of sweeping across it.
				_check(
					"the camera snaps to the wrapped plane",
					_game.camera.get_screen_center_position().x
					< float(_game.camera.limit_right) * 0.5
				)
				_game.player.global_position.x = _game._world_rect().position.x - 140.0
			elif _frame == 6:
				_check(
					"flying off the left edge returns on the right",
					_game.player.global_position.x > 2900.0
				)
				_phase = "damage"
				_frame = 0

		"damage":
			if _frame == 1:
				# A clean airframe for the scripted five-hit sequence: the dogfight
				# before it may already have put a round into the AI's fighter.
				_game.opponent.health.reset()
				_game.opponent.hits_taken = 0
				_game.opponent._update_damage_visuals()
			elif _frame == 2:
				_game.opponent.take_damage(34)
				_check("one shot only damages the plane", _game.opponent.is_alive)
				_check("first hit leaves the plane flying", _game.opponent.is_airborne())
				_check("first hit shows scorch marks", _game.opponent.damage_marks.visible)
				_check("first hit does not smoke yet", not _game.opponent.smoke.emitting)
				_check(
					"a hit costs exactly the bullet's damage",
					_game.opponent.health.current_health == _game.opponent.health.max_health - 34
				)
			elif _frame == 8:
				_game.opponent.take_damage(34)
				_check("second hit starts the smoke trail", _game.opponent.smoke.emitting)
				_check("plane still flying after two hits", _game.opponent.is_alive)
			elif _frame == 14:
				_game.opponent.take_damage(34)
				_check("three hits are no longer enough to bring a plane down", _game.opponent.is_alive)
				_check(
					"every airframe holds five normal hits before it dies",
					_game.opponent.health.max_health > 136 and _game.opponent.health.max_health <= 170
				)
			elif _frame == 20:
				_game.opponent.take_damage(34)
				_check("four hits leave it limping but flying", _game.opponent.is_alive and _game.opponent.is_airborne())
				_crash_y = _game.opponent.global_position.y
			elif _frame == 26:
				_game.opponent.take_damage(34)
				_check("the fifth hit knocks the plane out of the sky", _game.opponent.is_crashing())
				_check("destroyed plane stops being alive", not _game.opponent.is_alive)
				_check("crashed plane stays visible while falling", _game.opponent.visible)
			elif _frame == 36:
				_check("crashed plane is falling", _game.opponent.global_position.y > _crash_y + 1.0)
				_phase = "impact"
				_frame = 0

		"impact":
			if _game.state == GameManager.State.FINISHED and not _impact_checked:
				_impact_checked = true
				_impact_frame = _frame
				_check(
					"crash landed on the surface",
					absf(_game.opponent.global_position.y - (_ground_y + 10.0)) < 2.0
				)
				_check("explosion spawned at the crash site", _count_effects() > 0)
			elif _impact_checked and not _result.is_empty():
				_check("player 1 reported as winner", int(_result.get("winner", 0)) == 1)
				_check("game over overlay shown", _main.get_node("OverlayLayer/GameOver").visible)
				_main.get_node("OverlayLayer/GameOver").rematch_pressed.emit()
				_phase = "restarted"
				_frame = 0
			elif _frame > 420:
				_check("round ended after the crash", false)
				_finish()

		"restarted":
			var fresh := _latest_game()
			if fresh != null and fresh != _game:
				_game = fresh
				_check("rematch restores full health", _game.player.health.current_health == _game.player.health.max_health)
				_check("rematch parks the planes", not _game.player.is_launched)
				_main.get_node("MenuLayer/MainMenu").play_requested.emit(
					GameManager.Mode.LOCAL_VERSUS, AIConfig.Difficulty.NORMAL
				)
				_phase = "versus"
				_frame = 0

		"versus":
			var versus := _latest_game()
			if versus != null and versus != _game:
				_game = versus
				_check("local versus camera frames both planes", _game.camera.mode == CameraController.Mode.FRAME_BOTH)
				_check("no radar when both pilots share the screen", not _game.hud._radar.visible)
				_check("player 2 uses a human controller", _game.opponent.controller is PlayerPlaneController)
				InputManager.set_virtual_action(&"p2_launch", true)
				InputManager.set_virtual_action(&"p1_launch", true)
				_phase = "versus_launch"
				_frame = 0

		"versus_launch":
			if _frame == 6:
				InputManager.clear_virtual_actions()
				_check("virtual touch launched player 1", _game.player.is_launched)
				_check("virtual touch launched player 2", _game.opponent.is_launched)
				_main.get_node("MenuLayer/MainMenu").play_requested.emit(
					GameManager.Mode.SINGLE_PLAYER, AIConfig.Difficulty.NORMAL
				)
				_phase = "combat_ready"
				_frame = 0

		"combat_ready":
			var fresh := _latest_game()
			if fresh != null and fresh != _game:
				_game = fresh
				Input.action_press(&"p1_launch")
				_phase = "combat"
				_frame = 0

		"combat":
			# Player climbs straight and never fires: any damage must come from the AI.
			if _frame == 10:
				Input.action_release(&"p1_launch")
			if _frame % 120 == 0:
				var ai := _game.opponent.controller as AIController
				if ai != null:
					print(
						"combat t=%d dist=%.0f ai_rot=%.1f deg"
						% [
							_frame,
							_game.opponent.global_position.distance_to(_game.player.global_position),
							rad_to_deg(_game.opponent.rotation),
						]
					)
			if _game.player.health.current_health < _game.player.health.max_health:
				_check("AI landed a hit on the player", true)
				_check("camera stayed inside limits during combat", _camera_inside_limits())
				_check("AI projectiles came from the AI only", _game.player.health.current_health > 0)
				_phase = "ground_crash"
				_frame = 0
			elif _frame > 2600:
				_check("AI landed a hit on the player", false)
				_finish()

		"ground_crash":
			# The flat surface is solid: flying into it has to end the round.
			if _frame == 2:
				_game.opponent.global_position.y = _game.game_config.ground_y - 4.0
			elif _frame == 12:
				_check("flying into the ground destroys the plane", not _game.opponent.is_alive)
				_check("a ground crash ends the round", _game.state == GameManager.State.FINISHED)
				# Pickups and crate rounds get a fresh match of their own.
				_main.get_node("MenuLayer/MainMenu").play_requested.emit(
					GameManager.Mode.SINGLE_PLAYER, AIConfig.Difficulty.NORMAL
				)
				_phase = "pickups_ready"
				_frame = 0

		"pickups_ready":
			var pickup_game := _latest_game()
			if pickup_game == null or pickup_game == _game:
				return
			_game = pickup_game
			_prepare_pickup_test()
			_phase = "netcode"
			_frame = 0

		"netcode":
			if _frame == 2:
				_run_netcode_checks()
				_phase = "pickups"
				_frame = 0

		"pickups":
			if _frame == 10:
				_check(
					"the repair coin puts the plane back together",
					_game.player.health.current_health == _game.player.health.max_health
				)
				_check("a repair clears the hit count", _game.player.hits_taken == 0)
				_check("a repair takes the scorch marks away", not _game.player.damage_marks.visible)
				_check("a repaired plane stops smoking", not _game.player.smoke.emitting)
			elif _frame == 12:
				# A round fired 45 degrees off the target: it has to chase its way round.
				var forward := Vector2.UP.rotated(_game.player.rotation)
				_game.opponent.global_position = (
					_game.player.global_position + forward.rotated(deg_to_rad(45.0)) * 420.0
				)
				# No flares on the target: the AI's own answer to a homing round is
				# checked on its own, and down here the round is supposed to land.
				_game.opponent.flares = 0
				_game.player.give_special(Airplane.SpecialRound.HOMING)
				_check(
					"a crate round loads into the guns",
					_game.player.special_round == Airplane.SpecialRound.HOMING
				)
				_check(
					"the HUD names the loaded round",
					(_game.hud._special_labels[1] as Label).text == "HOMING ROUND READY"
				)
				_game.player.shoot()
				_check(
					"firing spends the crate round",
					_game.player.special_round == Airplane.SpecialRound.NONE
				)
				_check(
					"the HUD clears once the round is away",
					(_game.hud._special_labels[1] as Label).text == ""
				)
				_check("the homing round is in the air", _count_homing_projectiles() > 0)
			elif _frame == 96:
				_check(
					"the radar shows where the enemy is",
					_game.hud._radar.enemy_offset().distance_to(
						_game.opponent.global_position - _game.player.global_position
					) < 1.5
				)
			elif _frame == 100:
				_check("the homing round chased a target that started off its nose", _game.opponent.hits_taken == 1)
			elif _frame == 102:
				# Put the target across the wrap seam: the dial is a picture of the sky
				# around the plane, so the mark stays on the side the screen draws it.
				_game.opponent.global_position.x = (
					_game.player.global_position.x + _game.game_config.world_width - 300.0
				)
			elif _frame == 104:
				_check(
					"the radar keeps the enemy on the side the sky draws it",
					absf(_game.hud._radar.enemy_offset().x - 2900.0) < 1.5
				)
			elif _frame == 106:
				# Flares, mid-match where the plane is really flying: a burst costs a
				# charge, lights several decoys, steals a homing round and lights a
				# bomb's fuse early.
				var plane := _game.player
				plane.flares = maxi(plane.flares, 2)
				var flares_before := plane.flares
				plane.launch_flares()
				_check("a flare burst costs one charge", plane.flares == flares_before - 1)
				var live_flares := get_tree().get_nodes_in_group(&"flares")
				_check("a flare burst lights several decoys", live_flares.size() >= 3)
				_check(
					"the HUD counts the flare down",
					_game.hud._flare_labels[1].text.contains(str(plane.flares))
				)
				if not live_flares.is_empty():
					var decoy := live_flares[0] as Flare
					var round_config := ProjectileConfig.new()
					round_config.homing = true
					_flare_round = _game._next_projectile()
					_flare_round.spawn(
						round_config,
						decoy.global_position + Vector2(140.0, -70.0),
						Vector2.LEFT,
						2,
						160.0,
						_game._world_rect(),
						_game.opponent
					)
				var spot := plane.global_position + Vector2(0.0, -420.0)
				_flare_test = Flare.new()
				_game.effects_root.add_child(_flare_test)
				_flare_test.launch(spot, Vector2.ZERO, 1)
				_flare_bomb = _game._spawn_bomb(spot + Vector2(0.0, 26.0), Vector2.ZERO, 2, true)
				# And the AI reaches for its own dispenser when a round is fired at it.
				_game.opponent.flares = 1
				_game._try_ai_flares(_game.opponent)
			elif _frame == 108:
				_check(
					"a burning flare pulls a homing round off the fighter",
					_flare_round != null and _flare_round._nearest_decoy() != null
				)
			elif _frame == 136:
				_check(
					"a flare sets a bomb off early", not is_instance_valid(_flare_bomb)
				)
				_check(
					"the homing round never reached the fighter",
					_game.opponent.hits_taken == 1
				)
				_check("the AI burns a flare at a homing round", _game.opponent.flares == 0)
			elif _frame == 110:
				# The courier pass: let it go early, right beside the frozen plane, and
				# keep the plane out of the way so nothing can catch the load.
				_game.player.collision_layer = 0
				_game._send_courier()
				var courier := _game._courier
				_check("a courier plane crosses the sky", courier.visible and courier.is_flying())
				_check(
					"the courier plans a drop over the ground",
					courier.planned_drop().y < _game.game_config.ground_y - 200.0
				)
				_check(
					"the courier wears the badge of the load it carries",
					courier._badge.visible and courier._badge.kind == courier._kind
				)
				courier._drop_x = courier.position.x + courier._direction * 150.0
			elif _frame == 112:
				_check("the radar marks the courier", _game.hud._radar.has_courier_marker())
			elif _frame == 170:
				var dropped: SkyPickup = null
				for child in _game.pickups_root.get_children():
					var candidate := child as SkyPickup
					if candidate != null and not candidate.is_taken():
						dropped = candidate
				_check("the courier lets a pickup go", dropped != null)
				if dropped != null:
					_check(
						"the drop comes down on its parachute",
						dropped.global_position.y > dropped.spawn_origin.y
					)
					# Send it the rest of the way in a hurry: nothing catches it.
					dropped._fall_speed = 2400.0
					_check("the radar marks the falling drop", _game.hud._radar.has_drop_marker())
			elif _frame == 230:
				_check(
					"a drop nobody catches is lost on the ground",
					_game.pickups_root.get_child_count() == 0
				)
				_check(
					"the radar forgets a drop once it is lost",
					not _game.hud._radar.has_drop_marker()
				)
			elif _frame == 240:
				# Line the target up dead ahead and load the one-shot round.
				_game.player.collision_layer = 1
				_game.opponent.health.reset()
				_game.opponent.hits_taken = 0
				_game.opponent._update_damage_visuals()
				var forward := Vector2.UP.rotated(_game.player.rotation)
				_game.opponent.global_position = _game.player.global_position + forward * 420.0
				_game.player.give_special(Airplane.SpecialRound.KILLER)
				_check(
					"the instant round loads into the guns",
					_game.player.special_round == Airplane.SpecialRound.KILLER
				)
				_game.player.shoot()
			elif _frame == 290:
				_check("the instant round ends the fight in one hit", not _game.opponent.is_alive)
				_main.get_node("MenuLayer/MainMenu").play_requested.emit(
					GameManager.Mode.SURVIVAL, AIConfig.Difficulty.NORMAL
				)
				_phase = "survival"
				_frame = 0

		"survival":
			var run := _latest_game()
			if run == null or run == _game:
				return
			_game = run
			_check_boost()
			_check(
				"the ground squads work heavy cannon, not rifles",
				Soldier.RIFLE_REACH > 16.0 and SoldierModel3D.RIFLE_REACH == Soldier.RIFLE_REACH
			)
			_check(
				"the near ground layer is drawn in front of the planes",
				_game.ground_depth != null
				and _game.ground_depth.z_index > _game.planes_root.z_index
			)
			_check(
				"the foreground ground slides faster than the verge under it",
				(
					GroundDepth.slide_offset(
						100.0, GroundDepth.FOREGROUND_PARALLAX, GroundDepth.FOREGROUND_TILE
					)
					< GroundDepth.slide_offset(
						100.0, GroundDepth.VERGE_PARALLAX, GroundDepth.VERGE_TILE
					)
				)
			)
			# Every session rolls its own key: the day it opens at follows that key,
			# and an AUTO session can open in more than one sky.
			_check(
				"a session's day phase follows its key",
				(
					is_equal_approx(_game._day_phase_for(1234), _game._day_phase_for(1234))
					and absf(_game._day_phase_for(1234) - _game._day_phase_for(98765)) > 0.001
				)
			)
			var skies := {}
			for probe_seed in 24:
				var probe := RandomNumberGenerator.new()
				probe.seed = probe_seed * 7919 + 13
				skies[_game._roll_weather(probe)] = true
			_check("an AUTO session can open in more than one sky", skies.size() > 1)
			_check("a plane rolls out with three flares", _game.player.flares == 3)
			var rack_flares := _game.player.flares
			_game.player.give_flares(2)
			_check(
				"a supply crate tops the flare rack up", _game.player.flares == rack_flares + 2
			)
			_check(
				"the HUD carries the flare count",
				_game.hud._flare_labels[1].text.contains("FLARES")
			)
			_check("a plane rolls out with two bombs", _game.player.bombs == 2)
			_check(
				"the HUD carries the bomb count",
				_game.hud._bomb_labels[1].text.contains("BOMBS")
			)
			# Empty the rack without leaving the ground, then let the crew reload it.
			var parked_state := _game.player.flight_state
			_game.player.flight_state = Airplane.FlightState.AIRBORNE
			_game.player.drop_bomb()
			_game.player.drop_bomb()
			_game.player.flight_state = parked_state
			_check(
				"an empty rack starts a reload",
				_game.player.bombs == 0 and _game.player.is_reloading_bombs()
			)
			_check(
				"the HUD shows the reload", _game.hud._bomb_labels[1].text.contains("RELOAD")
			)
			_check("the bomb button draws the reload", _game.mobile_controls.bomb_button._progress > 0.9)
			_game.player._update_weapon(_game.player.config.bomb_reload_seconds + 0.5)
			_check(
				"the rack refills itself once the reload is done",
				_game.player.bombs == 2 and not _game.player.is_reloading_bombs()
			)
			_check(
				"the bomb button clears once the rack is full",
				_game.mobile_controls.bomb_button._progress == 0.0
			)
			# The shield: a crate hands over a charge, the bubble stops enemy fire
			# outright, and it runs out on its own.
			_check("a plane rolls out with no shield charge", _game.player.shield_charges == 0)
			_game.player.give_shield(_game.player.config.shield_per_crate)
			_check("a supply crate hands over a shield charge", _game.player.shield_charges == 1)
			_game.player.activate_shield()
			_check(
				"the shield goes up and spends the charge",
				_game.player.is_shielded() and _game.player.shield_charges == 0
			)
			_check(
				"the HUD counts the shield down",
				_game.hud._shield_labels[1].text.contains("SHIELD")
			)
			var shield_health := _game.player.health.current_health
			var shield_hits := _game.player.hits_taken
			_game.player.take_damage(40)
			_check(
				"nothing gets through the shield",
				(
					_game.player.health.current_health == shield_health
					and _game.player.hits_taken == shield_hits
				)
			)
			_game.player.shield_time = 0.0
			_game.player.take_damage(20)
			_check(
				"once the bubble is down, hits land again",
				_game.player.health.current_health < shield_health
			)
			_enemy_health_before = _game.opponent.health.current_health
			_game._spawn_bomb(_game.opponent.global_position + Vector2(0.0, -24.0), Vector2.ZERO, 1, true)
			_phase = "bomb_burst"
			_frame = 0

		"bomb_burst":
			# Weather first, while the bomb falls: rain, the wet airframe, snow, then
			# clear again.
			if _frame == 2:
				_game._apply_weather(Weather.Kind.RAIN, 1.0)
				_game._update_rain()
				_check("rain reaches the falling-precipitation layer", _game._weather_layer.visible)
				_check(
					"weather shows in the mode line",
					_game.hud.mode_label.text.contains("Rain")
				)
				_check(
					"rain wets the airframe",
					_game.player.rain > 0.95 and _game.player.model.wetness() > 0.95
				)
			elif _frame == 4:
				_game._apply_weather(Weather.Kind.SNOW, 1.0)
				_game._update_rain()
				_check(
					"snow falls instead of rain",
					_game._weather_layer.visible and _game._weather_layer.kind() == Weather.Kind.SNOW
				)
				_check("snow leaves the airframe dry", _game.player.model.wetness() < 0.05)
			elif _frame == 6:
				_game._apply_weather(Weather.Kind.CLEAR, 1.0)
				_check("clear weather has nothing falling", not _game._weather_layer.visible)
			elif _frame == 14:
				_check(
					"a bomb bursting under a fighter hurts it",
					_game.opponent.health.current_health < _enemy_health_before
				)
			elif _frame == 18:
				_phase = "survival_kill"
				_frame = 0

		"survival_kill":
			_record_backup = SurvivalRecord.load_best()
			# Hold the AI's trigger so only the scripted kill happens.
			var survival_ai := _game.opponent.controller as AIController
			if survival_ai != null and survival_ai.config != null:
				survival_ai.config.attack_range = 0.0
			_check("a survival run starts with nothing shot down", _game.score == 0)
			_check("survival shows the tally", _game.hud._score_label.visible)
			_check("survival starts with one enemy fighter", _game.opponent.is_alive)
			_game.player.take_off()
			# A wounded pilot, so the reward for the kill has something to repair.
			_game.player.heal(_game.player.health.max_health)
			_player_health_before = _game.player.health.current_health
			_game.player.take_damage(50)
			_player_health_before = _game.player.health.current_health
			_game.opponent.take_damage(_game.opponent.health.max_health)
			_phase = "survival_scored"
			_frame = 0

		"survival_scored":
			if _frame == 24:
				_check("a shot-down enemy is counted as a kill", _game.score == 1)
				_check(
					"survival does not end the round on an enemy kill",
					_game.state != GameManager.State.FINISHED
				)
				_check(
					"a survival kill patches the pilot up a little",
					_game.player.health.current_health > _player_health_before
				)
				_check("the best run follows the current run", _game.best_score >= 1)
				_check(
					"the tally names the kill",
					(_game.hud._score_label as Label).text.contains("1")
				)
			elif _frame == 150:
				_check(
					"a fresh enemy fighter replaces the one shot down",
					_game.opponent.is_alive and _game.opponent.is_launched
				)
				_check(
					"the replacement starts in one piece",
					_game.opponent.health.current_health == _game.opponent.health.max_health
				)
				_check("the run is still going", _game.state == GameManager.State.FLYING)
				_start_duel_check()

		"duel_ready":
			var duel := _latest_game()
			if duel == null or duel == _game:
				return
			_game = duel
			_check(
				"the fighter picked on the title screen reaches the match",
				_game.player.config.plane_silhouette == PlaneModel3D.Silhouette.SCIFI
			)
			_check(
				"the opponent flies a crimson copy of the same airframe",
				_game.opponent.config.plane_silhouette == _game.player.config.plane_silhouette
				and _game.opponent.config.livery_body != _game.player.config.livery_body
			)
			_check(
				"every fighter builds a full airframe",
				_all_airframes_build()
			)
			_check(
				"every fighter still takes five normal hits",
				_roster_health_in_window()
			)
			_check(
				"the picked fighter's numbers reach the match",
				_game.player.config.plane_speed == float(PlaneRoster.entry(9)["speed"])
				and _game.player.config.rotation_speed == float(PlaneRoster.entry(9)["turn"])
				and is_equal_approx(
					_game.player.config.fire_cooldown, float(PlaneRoster.entry(9)["cooldown"])
				)
			)
			_check(
				"a duel starts level",
				_game.round_wins[0] == 0 and _game.round_wins[1] == 0
			)
			_check(
				"a duel shows its scoreboard",
				_game.hud._score_label.visible
				and (_game.hud._score_label as Label).text.contains("P1 0")
			)
			_game.player.take_off()
			_game.opponent.take_off()
			_phase = "duel_kill"
			_frame = 0

		"duel_kill":
			if _frame == 10:
				_game.opponent.take_damage(_game.opponent.health.max_health)
				_game.opponent.global_position.y = _game.game_config.ground_y - 26.0
			elif _frame == 120:
				_check("a duel crash is a round for the other pilot", _game.round_wins[0] == 1)
				_check("a duel does not end on a crash", _game.state != GameManager.State.FINISHED)
				_check(
					"the round is announced",
					_game.hud.prompt_label.text.contains("PLAYER 1")
				)
				_check(
					"the scoreboard counts the round",
					(_game.hud._score_label as Label).text.contains("P1 1")
				)
			elif _frame == 250:
				_check(
					"both fighters roll out for the next round",
					_game.player.is_alive and _game.opponent.is_alive
				)
				_check(
					"a new round starts in one piece",
					_game.opponent.health.current_health == _game.opponent.health.max_health
				)
				_check(
					"the scoreboard moves on to the next round",
					(_game.hud._score_label as Label).text.contains("ROUND 2")
				)
				_game.player.take_damage(_game.player.health.max_health)
				_game.player.global_position.y = _game.game_config.ground_y - 26.0
			elif _frame == 480:
				_check("either side can take a round", _game.round_wins[1] == 1)
				_check("a tied duel plays on", _game.state != GameManager.State.FINISHED)
				_check(
					"the scoreboard shows both sides",
					_game.hud._score_label.text.contains("P1 1") and _game.hud._score_label.text.contains("P2")
				)
				_check_lan_airframe_adoption()
				_finish()


## Leaves the survival run for a same-screen duel flown with the last fighter in
## the roster, which is also the check that the picker's choice reaches a match.
func _start_duel_check() -> void:
	var menu := _main.get_node("MenuLayer/MainMenu") as MainMenu
	_check("the roster offers ten fighters", PlaneRoster.count() == 10)
	_check("every fighter has its own name", _roster_values_unique("name"))
	_check("every fighter has its own airframe", _roster_values_unique("silhouette"))
	_check(
		"speed, turn and fire rate spread across the roster",
		_roster_is_progressive()
	)
	_check("every property has a bar with a value", _roster_bars_are_sane())
	_check(
		"the list ends on the fighter that never flew",
		int(PlaneRoster.entry(PlaneRoster.count() - 1)["silhouette"])
		== PlaneModel3D.Silhouette.SCIFI
	)
	menu._set_plane(PlaneRoster.count() - 1)
	_check("the picker draws four bars", menu.plane_stats.row_count() == 4)
	_check(
		"the picker shows the chosen fighter",
		menu.selected_plane == PlaneRoster.count() - 1 and menu.plane_name_label.text.contains("Aurora")
	)
	menu.play_requested.emit(GameManager.Mode.LOCAL_VERSUS, AIConfig.Difficulty.NORMAL)
	_phase = "duel_ready"
	_frame = 0


## A LAN guest takes the host's fighter off the wire, so both devices simulate the
## same two aircraft even if the guest picked something else.
func _check_lan_airframe_adoption() -> void:
	_game.mode = GameManager.Mode.LAN
	_game._on_session_seed(424242, 3)
	_check("a LAN guest takes the host's session key", _game._session_seed == 424242)
	_check(
		"a LAN guest takes the host's fighter",
		_game.plane_index == 3
		and _game.player.config.plane_silhouette == int(PlaneRoster.entry(3)["silhouette"])
	)
	_check(
		"both LAN airframes agree after the swap",
		_game.opponent.config.plane_silhouette == _game.player.config.plane_silhouette
	)
	_check(
		"the adopted airframe is rebuilt and rendered",
		_game.player.model != null and _game.player.model.get_child_count() > 0
		and _game.player.body_sprite.texture != null
	)


## The later fighters have to be genuinely more advanced than the props, and the
## numbers have to be spread rather than a single stepping of one stat.
func _roster_is_progressive() -> bool:
	var first := PlaneRoster.entry(0)
	var last := PlaneRoster.entry(PlaneRoster.count() - 1)
	if float(last["speed"]) < float(first["speed"]) + 40.0:
		return false
	if float(last["turn"]) < float(first["turn"]) + 20.0:
		return false
	if float(last["cooldown"]) > float(first["cooldown"]) - 0.10:
		return false
	# At least one aircraft gives something up for what it gains, so the list is
	# distributed rather than a straight line.
	var dips := 0
	for i in range(1, PlaneRoster.count()):
		if float(PlaneRoster.entry(i)["speed"]) < float(PlaneRoster.entry(i - 1)["speed"]):
			dips += 1
	return dips >= 1


## Every fighter's bars cover 0..1 and name a real number, and the last fighter
## fills more of the speed, turn and fire bars than the first.
func _roster_bars_are_sane() -> bool:
	for i in PlaneRoster.count():
		var rows := PlaneRoster.stat_rows(i)
		if rows.size() != 4:
			return false
		for row in rows:
			var ratio := float(row["ratio"])
			if ratio < 0.0 or ratio > 1.0 or str(row["value"]).is_empty():
				return false
	var first := PlaneRoster.stat_rows(0)
	var last := PlaneRoster.stat_rows(PlaneRoster.count() - 1)
	for i in 3:
		if float(last[i]["ratio"]) <= float(first[i]["ratio"]):
			return false
	return true


func _roster_values_unique(key: String) -> bool:
	var seen := {}
	for plane in PlaneRoster.all():
		if seen.has(plane[key]):
			return false
		seen[plane[key]] = true
	return true


## The roster may not break the five-hit rule: every health total has to stay
## above four bullets (136) and at or below five (170).
func _roster_health_in_window() -> bool:
	for i in PlaneRoster.count():
		var config := PlaneConfig.new()
		PlaneRoster.apply(config, i)
		if config.max_health <= 136 or config.max_health > 170:
			return false
	return true


func _all_airframes_build() -> bool:
	for i in PlaneRoster.count():
		var model := PlaneModel3D.new()
		add_child(model)
		var plane := PlaneRoster.entry(i)
		model.build(plane["body"], plane["accent"], plane["belly"], int(plane["silhouette"]))
		var built := (
			model._gear_root != null
			and model._airframe.get_child_count() > 4
			and model.get_texture() != null
		)
		remove_child(model)
		model.queue_free()
		if not built:
			return false
	return true



## The LAN damage rules, exercised without a peer: the device that fires decides a
## hit, the airplane's own device applies what it is told, and a heartbeat that
## predates the hit must not undo it.
## The jet boost: burned by holding it, felt as speed, and refilled by letting
## go. Driven through the same code the flight loop runs, on an airborne plane.
func _check_boost() -> void:
	var plane := _game.player
	var parked := plane.flight_state
	plane.flight_state = Airplane.FlightState.AIRBORNE
	plane.nitro = 1.0
	plane._input.reset()
	plane._input.boost = true
	var cruise := PlaneConfig.gear_speed(plane.config.plane_speed, plane.throttle_gear)
	plane._update_boost(0.6)
	_check("the jet boost is faster than the engine alone", plane.current_speed() > cruise + 1.0)
	_check("holding the boost burns the tank", plane.nitro < 0.9)
	var burnt := plane.nitro
	plane._input.reset()
	plane._update_boost(2.0)
	_check("the boost tank refills once it is let go", plane.nitro > burnt)
	_check(
		"the HUD shows the boost tank filling",
		_game.hud._boost_gauges[1].ratio() > burnt
	)
	plane.nitro = 1.0
	plane.boosting = false
	plane.flight_state = parked
	plane._input.reset()


func _run_netcode_checks() -> void:
	var real_mode := _game.mode
	_game.mode = GameManager.Mode.LAN
	var local := _game.local_plane()
	var remote := _game.remote_plane()
	remote.health.reset()
	remote.hits_taken = 0
	remote._update_damage_visuals()
	var full := remote.health.current_health

	_game._on_projectile_hit_plane(remote, 34, local.player_id)
	_check(
		"a hit you land shows on the other pilot at once",
		remote.health.current_health == full - 34
	)
	_check("the hit is on its way to his device", _game._pending_hits == 1)

	_game._on_remote_state(
		{"health": full, "position": remote.global_position, "rotation": remote.rotation}
	)
	_check(
		"a heartbeat older than the hit cannot heal it back",
		remote.health.current_health == full - 34
	)

	_game._on_lan_hit_ack(remote.player_id, 1)
	_game._on_remote_state(
		{"health": full - 34, "position": remote.global_position, "rotation": remote.rotation}
	)
	_check(
		"once he confirms it, his number is trusted again",
		remote.health.current_health == full - 34 and _game._pending_hits == 0
	)

	# Ground fire belongs to the airplane's own device only.
	_game._on_projectile_hit_plane(remote, 8, 0)
	_check(
		"tracers on the other pilot wait for his own device",
		remote.health.current_health == full - 34
	)
	var mine := local.health.current_health
	_game._on_projectile_hit_plane(local, 8, 0)
	_check("tracers on your own airplane land here", local.health.current_health == mine - 8)

	# His bullet reaching us: he decides, so we must not also apply it.
	mine = local.health.current_health
	_game._on_projectile_hit_plane(local, 34, remote.player_id)
	_check("the other pilot's bullet is not counted twice", local.health.current_health == mine)
	_game._on_lan_damage(local.player_id, 34, 1)
	_check("his hit lands when his device says it did", local.health.current_health == mine - 34)

	_game.mode = real_mode
	_game._pending_hits = 0
	local.health.reset()
	local.hits_taken = 0
	local._update_damage_visuals()
	remote.health.reset()
	remote.hits_taken = 0
	remote._update_damage_visuals()


## An isolated sky for the pickup work: both planes flying in place with their
## physics switched off, so the scripted shots have a still target.
func _prepare_pickup_test() -> void:
	var mid := _game.game_config.world_width * 0.5
	var sky := _game.game_config.ground_y - 900.0
	for plane: Airplane in [_game.player, _game.opponent]:
		plane.flight_state = Airplane.FlightState.AIRBORNE
		plane.set_physics_process(false)
		plane.global_position = Vector2(mid, sky)
		plane.rotation = -PI * 0.5
	# Far enough apart that the coin can only be collected by the player.
	_game.opponent.global_position = Vector2(mid + 700.0, sky)
	_game.state = GameManager.State.FLYING
	# Nothing arrives on its own: the courier pass is driven by the test.
	_game._courier_timer = 999.0

	_game.player.take_damage(34)
	_check(
		"a hit leaves the plane damaged and marked",
		_game.player.health.current_health < _game.player.health.max_health
		and _game.player.hits_taken == 1
	)

	# A repair coin hanging right where the plane is, so the pickup path runs.
	var coin := SkyPickup.new()
	coin.kind = SkyPickup.Kind.REPAIR
	_game._track_pickup(coin)
	coin.drop(_game.player.global_position, _game.game_config.ground_y, 0.0)


func _count_homing_projectiles() -> int:
	var count := 0
	for projectile in _game._projectile_pool:
		if projectile.is_active and projectile._config != null and projectile._config.homing:
			count += 1
	return count


func _finish() -> void:
	Input.action_release(&"p1_fire")
	Input.action_release(&"p1_launch")
	if _record_backup >= 0:
		SurvivalRecord.save_best(_record_backup)
		_record_backup = -1
	print("=== smoke test finished: %d failure(s) ===" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _count_effects() -> int:
	return _game.effects_root.get_child_count()


func _count_active_projectiles() -> int:
	var count := 0
	for child in _game.projectiles_root.get_children():
		var projectile := child as Projectile
		if projectile != null and projectile.is_active:
			count += 1
	return count


func _check_spawn() -> void:
	print("world rect: ", _game._world_rect())
	print("player spawn: ", _game.player.global_position, "  opponent: ", _game.opponent.global_position)
	var view_half_width: float = _game.get_viewport().get_visible_rect().size.x * 0.5 / _game.camera.zoom.x
	var gap := absf(_game.player.global_position.x - _game.opponent.global_position.x)
	_check("opponent starts outside the player's view", gap > view_half_width * 2.0)
	_check("planes start parked on the ground", not _game.player.is_launched and not _game.opponent.is_launched)
	_check("planes are still while parked", _game.player.velocity == Vector2.ZERO)
	_check("camera starts inside the world limits", _camera_inside_limits())
	_check("player uses the unmirrored own-plane art", not _game.player.body_sprite.flip_h)
	_check("opponent mirrors its art on the Y axis", _game.opponent.body_sprite.flip_h)
	_check(
		"the two pilots fly different liveries",
		_game.player.config.livery_body != _game.opponent.config.livery_body
	)
	_check(
		"both airframes are rendered 3D models with a spinning propeller",
		_game.player.model != null
		and _game.opponent.model != null
		and _game.player.body_sprite.texture != null
		and _game.opponent.body_sprite.texture != null
		and _game.player.muzzle_flash.texture != null
	)
	_check("the hitbox is thinner than the artwork is tall", _plane_capsule_radius() <= 12.0)
	_check(
		"parked planes face along the runway toward the middle",
		absf(_game.player.rotation - PI * 0.5) < 0.01 and absf(_game.opponent.rotation + PI * 0.5) < 0.01
	)
	# Ground infantry: Normal difficulty fields a squad.
	var squad: Array = _game.soldiers._soldiers
	_check("a squad stands on the ground on Normal", squad.size() == 3)
	# The opening sky is settled before the first frame: AUTO rolls one of the four
	# from the session key, and a chosen one is kept as it is.
	_check(
		"a match starts in one settled sky",
		(
			_game.weather >= Weather.Kind.CLEAR
			and _game.weather <= Weather.Kind.SNOW
			and _game.weather == _game._start_weather
		)
	)
	var squad_on_ground := true
	for soldier in squad:
		if absf((soldier as Node2D).global_position.y - _game.game_config.ground_y) > 1.0:
			squad_on_ground = false
	_check("every soldier stands on the surface", squad_on_ground)

	# Animated cloud sheet.
	var clouds: Array = _game.clouds._clouds
	_check("the sky has clouds", clouds.size() > 0)
	var animated := clouds[0] as AnimatedSprite2D
	_check(
		"clouds come from an animated sheet",
		animated != null and animated.sprite_frames != null and animated.sprite_frames.has_animation(&"drift")
	)
	_cloud_start = (clouds[0] as Node2D).position
	_cloud_frame_start = animated.frame if animated != null else -1
	# This match exercises take-off, looping, wrapping and crashes; keep AI gunfire
	# out of it so the scripted damage sequence is deterministic.
	var ai := _game.opponent.controller as AIController
	if ai != null and ai.config != null:
		ai.config.attack_range = 0.0


func _check_camera() -> void:
	_check("camera stays inside the world limits", _camera_inside_limits())
	var cam := _game.camera
	var center := cam.get_screen_center_position()
	_check("camera followed the player upward", center.y < -100.0)
	var half := _game.get_viewport().get_visible_rect().size * 0.5 / cam.zoom
	_check(
		"camera view never leaves the landscape",
		center.x - half.x >= float(cam.limit_left) - 1.0 and center.x + half.x <= float(cam.limit_right) + 1.0
	)


func _check_clouds_moved() -> void:
	var clouds: Array = _game.clouds._clouds
	if clouds.is_empty():
		return
	var cloud := clouds[0] as Node2D
	var animated := clouds[0] as AnimatedSprite2D
	_check("clouds wander from where they started", cloud.position.distance_to(_cloud_start) > 0.5)
	_check(
		"clouds are animating through the sheet",
		animated.is_playing() and animated.sprite_frames.get_frame_count(&"drift") > 1
	)


func _soldier_shots() -> int:
	var count := 0
	for projectile in _game._projectile_pool:
		if projectile.is_active and projectile._owner_id == 0:
			count += 1
	return count


func _plane_capsule_radius() -> float:
	var shape_node := _game.player.get_node("CollisionShape2D") as CollisionShape2D
	var capsule := shape_node.shape as CapsuleShape2D
	return capsule.radius if capsule != null else 999.0


func _camera_inside_limits() -> bool:
	var cam := _game.camera
	var center := cam.get_screen_center_position()
	return (
		center.x >= float(cam.limit_left) - 1.0
		and center.x <= float(cam.limit_right) + 1.0
		and center.y >= float(cam.limit_top) - 1.0
		and center.y <= float(cam.limit_bottom) + 1.0
	)
