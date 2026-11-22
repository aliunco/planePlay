extends Node
## Visual capture harness: plays a short scripted match and writes PNG frames to
## res://tools/shots/ so the rendered result can be inspected.
##
##   godot --path . --resolution 1280x720 res://tools/visual_check.tscn
##
## Captures are deferred by one frame instead of awaiting frame_post_draw, so a
## throttled or occluded window cannot stall the run.

const OUT_DIR := "res://tools/shots"

var _main: Node
var _game: GameManager
var _frame: int = 0
var _pending_shot: String = ""
var _auto: int = 0
var _auto_frame: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frame += 1

	if _pending_shot != "":
		_save_shot(_pending_shot)
		_pending_shot = ""

	match _frame:
		20:
			_request("01_menu")
		30:
			_main.get_node("MenuLayer/MainMenu").play_requested.emit(
				GameManager.Mode.LOCAL_VERSUS, AIConfig.Difficulty.NORMAL
			)
		32:
			# The two-plane camera lerps into place; hurry it up so the capture does
			# not happen while it is still flying across the map.
			var versus := _latest_game()
			# The match rolls its own opening sky and time of day; pin both, so a
			# capture run is comparable with the last one.
			if versus != null:
				versus._day.start_phase = 0.16
				versus._day.phase = 0.16
			if versus != null:
				versus.camera.follow_speed = 40.0
		70:
			_request("02_two_player_parked")
		85:
			_main.get_node("MenuLayer/MainMenu").play_requested.emit(
				GameManager.Mode.SINGLE_PLAYER, AIConfig.Difficulty.NORMAL
			)
		100:
			_game = _latest_game()
			_disable_ai_guns()
			_request("03_parked")
		115:
			Input.action_press(&"p1_launch")
		127:
			Input.action_release(&"p1_launch")
		150:
			_request("04_taxiing")
		200:
			_request("05a_pitch_start")
		235:
			_request("05b_pitching_up")
		280:
			_request("05c_pitch_end")
		315:
			_request("06_flight")
		300:
			Input.action_press(&"p1_right")
		320:
			Input.action_release(&"p1_right")
			Input.action_press(&"p1_fire")
		335:
			_request("07_firing")
		370:
			Input.action_release(&"p1_fire")
		385:
			_game.mobile_controls.toggle_forced()
		390:
			_request("08_mobile_controls")
		396:
			# The capture frames are process frames, and a throttled window runs more
			# of them than the simulation sees; make sure the plane is properly in
			# the air so the flame has something to burn behind.
			if _game.player.flight_state != Airplane.FlightState.AIRBORNE:
				_game.player.flight_state = Airplane.FlightState.AIRBORNE
			Input.action_press(&"p1_boost")
		418:
			_request("09a_boost")
		422:
			Input.action_release(&"p1_boost")
		395:
			_game.mobile_controls.toggle_forced()
		425:
			_game.hud.pause_pressed.emit()
		440:
			_request("09_paused")
		455:
			_game.hud.resume_pressed.emit()
		458:
			_spawn_pickups_demo()
		505:
			_request("10a_pickups")
		470:
			_request("10_high_altitude")
		506:
			# Dusk and then night, so the sun arc, the stars, the moon and the nose
			# lamp can be inspected. The cycle is held still for the capture.
			_game._day.cycle_seconds = 1000000.0
			_game._day.phase = 0.47
		512:
			_request("11b_dusk")
		518:
			_game._day.phase = 0.68
		524:
			_request("11c_night")
		530:
			_game._day.phase = 0.16
			_game._day.cycle_seconds = 220.0
		535:
			# Hold the airframe part-way through the righting roll, so the capture
			# shows the wings swung out of the profile and the other flank of the
			# aircraft - the nose still pointing where the plane is going.
			_game.player.rotation = -PI * 0.55
			_game.player._righting = 0.44
			_game.player.model.set_roll(PI * 0.44)
		536:
			_request("11a_roll")
		538:
			_game._apply_weather(Weather.Kind.RAIN, 1.0)
		544:
			_request("11d_rain")
		548:
			_game._apply_weather(Weather.Kind.SNOW, 1.0)
		554:
			_request("11e_snow")
		558:
			_game._apply_weather(Weather.Kind.CLOUDY, 1.0)
		564:
			_request("11f_cloudy")
		568:
			_game._apply_weather(Weather.Kind.CLEAR, 1.0)
		475:
			Input.action_press(&"p1_left")
		545:
			_request("11_looping")
			Input.action_release(&"p1_left")
		560:
			_game.player.take_damage(34)
		570:
			_request("12_first_hit")
		580:
			_game.player.take_damage(34)
		576:
			# A shield bubble round the airframe, caught mid-life.
			_game.player.give_shield(1)
			Input.action_press(&"p1_shield")
		584:
			_request("12c_shield")
			Input.action_release(&"p1_shield")
		586:
			# A burst of flares off the tail, caught while they are still alight.
			Input.action_press(&"p1_flare")
		592:
			_request("12b_flares")
		594:
			Input.action_release(&"p1_flare")
		600:
			_game.player.bombs = 2
			_game.player.drop_bomb()
		612:
			_request("12a_bomb")
		620:
			_request("13_smoking")
		635:
			_game.player.take_damage(34)
		655:
			_request("14_crashing")

	_auto_sequence()


func _latest_game() -> GameManager:
	var host := _main.get_node("GameHost")
	for i in range(host.get_child_count() - 1, -1, -1):
		var child := host.get_child(i)
		if child is GameManager and not child.is_queued_for_deletion():
			return child as GameManager
	return null


## Puts a repair coin and a supply crate beside the demo plane, so the capture
## shows what both look like in the sky.
func _spawn_pickups_demo() -> void:
	if _game == null:
		return
	var here := _game.player.global_position
	# The courier crossing behind the fighters, mid-pass, about to let go.
	_game._send_courier()
	var courier := _game._courier
	courier.position = Vector2(here.x - 430.0, here.y - 90.0)
	courier._drop_x = here.x + 60.0
	# A known load, so the capture shows a specific fuselage badge.
	courier._kind = SkyPickup.Kind.REPAIR
	courier._badge.show_kind(SkyPickup.Kind.REPAIR)
	print("courier at ", courier.global_position, " flying=", courier.is_flying())

	var coin := SkyPickup.new()
	coin.kind = SkyPickup.Kind.REPAIR
	_game._track_pickup(coin)
	coin.drop(here + Vector2(-190.0, -30.0), _game.game_config.ground_y, 0.0)

	var crate := SkyPickup.new()
	crate.kind = SkyPickup.Kind.HOMING
	_game._track_pickup(crate)
	crate.drop(here + Vector2(215.0, -110.0), _game.game_config.ground_y, 0.0)


## Keeps the AI from shooting the demo plane so the damage stages happen in the
## order this script drives them.
func _disable_ai_guns() -> void:
	if _game == null:
		return
	var ai := _game.opponent.controller as AIController
	if ai != null and ai.config != null:
		ai.config.attack_range = 0.0


## The crash, its explosion and the result screen happen at data-dependent times,
## so the last shots follow the match state instead of fixed frame numbers.
func _auto_sequence() -> void:
	if _game == null:
		return

	match _auto:
		0:
			if _game.state == GameManager.State.FINISHED:
				_auto = 1
				_auto_frame = _frame
				_request("15_crash_impact")
		1:
			if _main.get_node("OverlayLayer/GameOver").visible:
				var over: Control = _main.get_node("OverlayLayer/GameOver")
				print(
					"over rect=", over.get_global_rect(),
					" panel=", over.get_node("Panel").get_global_rect(),
					" viewport=", get_viewport().get_visible_rect(),
					" scale=", over.scale
				)
				_auto = 2
				_auto_frame = _frame
		2:
			# Let the result panel finish sliding in before capturing it.
			if _frame > _auto_frame + 25:
				_auto = 3
				_auto_frame = _frame
				_request("16_game_over")
		3:
			if _frame > _auto_frame + 40:
				print("visual check done")
				get_tree().quit()


func _request(shot_name: String) -> void:
	_pending_shot = shot_name


func _save_shot(shot_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, shot_name]
	var error := image.save_png(path)
	if error != OK:
		print("SHOT FAILED ", path, " err=", error)
	else:
		print("shot saved: ", path, " ", image.get_size())
