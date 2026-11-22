extends Node
## Two-process LAN check. One process hosts, one joins, and both drive their own
## airplane; the assertions below only pass if the input really crossed the
## network (the remote plane is never touched by local input).
##
##   godot --headless --fixed-fps 60 --path . res://tools/lan_test.tscn -- --mode=host
##   godot --headless --fixed-fps 60 --path . res://tools/lan_test.tscn -- --mode=join --address=127.0.0.1
##
## Each process prints a final "LAN_RESULT ..." line; tools/run_lan_test.sh starts
## both and compares them to prove the two simulations agree.

var _main: Node
var _game: GameManager
var _mode: String = "host"
var _address: String = "127.0.0.1"
var _port: int = 27777
var _frame: int = 0
var _failures: int = 0
var _phase: String = "connect"
var _joined_frame: int = 0
var _started_ms: int = 0
var _done_frame: int = 0
var _match_instance_id: int = 0
var _climb_action: StringName = &"p1_left"
var _discovery_reported: bool = false
var _discovery_ok: bool = false
var _discovered_address: String = ""
var _discovery_started_ms: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Real-time pacing: a fast-forwarded loop would outrun the network.
	Engine.max_fps = 60
	_started_ms = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--mode="):
			_mode = argument.trim_prefix("--mode=")
		elif argument.begins_with("--address="):
			_address = argument.trim_prefix("--address=")
		elif argument.begins_with("--port="):
			_port = int(argument.trim_prefix("--port="))
	if _port <= 0:
		_port = Lan.DEFAULT_PORT

	print("LAN_TEST mode=", _mode, " port=", _port)

	_main = load("res://scenes/main/main.tscn").instantiate()
	add_child(_main)

	Lan.peer_joined.connect(_on_peer_joined)
	Lan.failed.connect(func(reason: String) -> void: _fail("connection: " + reason)) 

	if _mode == "join":
		# Find the host by broadcast first, the way the menu does, then join the
		# address it hands back.
		Lan.host_found.connect(_on_discovery_found)
		Lan.search_for_host(6.0)
		_discovery_started_ms = Time.get_ticks_msec()
		_phase = "discovery"
		return
	else:
		if not Lan.host(_port):
			_fail("host: " + Lan.status_text())


func _on_discovery_found(address: String) -> void:
	if _discovery_reported:
		return
	_discovery_reported = true
	_discovery_ok = not address.is_empty()
	_discovered_address = address
	_check("the menu finds the host by LAN discovery (%s)" % address, _discovery_ok)


func _on_peer_joined() -> void:
	if _phase != "connect":
		return
	print("LAN_TEST peer joined, waiting for the app to start the match")
	_phase = "waiting"


## The app starts the LAN match itself when a peer joins; pick up that game.
func _latest_game() -> GameManager:
	var host := _main.get_node("GameHost")
	for i in range(host.get_child_count() - 1, -1, -1):
		var child := host.get_child(i)
		if child is GameManager and not child.is_queued_for_deletion():
			return child as GameManager
	return null


func _process(_delta: float) -> void:
	_frame += 1

	if _phase == "discovery":
		if not _discovery_reported and Time.get_ticks_msec() - _discovery_started_ms > 6500:
			_discovery_reported = true
			_check("the menu finds the host by LAN discovery", false)
		if _discovery_reported:
			_phase = "connect"
			_started_ms = Time.get_ticks_msec()
			if not Lan.join(_discovered_address if _discovery_ok else _address, _port):
				_fail("join: " + Lan.status_text())
		return

	if _phase == "connect":
		if Time.get_ticks_msec() - _started_ms > 12000:
			_fail("no peer joined within 12 s (" + Lan.status_text() + ")")
			_finish()
		return

	if _phase == "waiting":
		_game = _latest_game()
		if _game == null:
			if Time.get_ticks_msec() - _started_ms > 15000:
				_fail("the LAN match never started")
				_finish()
			return
		print("LAN_TEST match running, local plane id=", _game.local_plane().player_id)
		_match_instance_id = _game.get_instance_id()
		_joined_frame = _frame
		_phase = "match"
		return

	if _phase == "done":
		_run_rematch_checks()
		return

	if not is_instance_valid(_game):
		_fail("the match ended before the checks finished")
		_finish()
		return

	match _phase:
		"match":
			# Both devices press their own launch control.
			if _frame > _joined_frame + 5 and _frame < _joined_frame + 30:
				Input.action_press(&"p1_launch")
			elif _frame == _joined_frame + 30:
				Input.action_release(&"p1_launch")
				_check("local airplane started its take-off roll", _game.local_plane().is_launched)
				_check("remote airplane got the other pilot's launch", _game.remote_plane().is_launched)
			elif _frame == _joined_frame + 285:
				_check("local airplane is airborne", _game.local_plane().is_airborne())
				_check("remote airplane is airborne", _game.remote_plane().is_airborne())
				# Climb away from the strip before turning. The left-facing plane has to
				# turn right to raise its nose, so each pilot presses its own key.
				_climb_action = &"p1_left" if _game.local_plane().player_id == 1 else &"p1_right"
				Input.action_press(_climb_action)
			elif _frame == _joined_frame + 315:
				Input.action_release(_climb_action)
				_check(
					"remote airplane turned from received input",
					absf(_game.remote_plane().rotation) > 0.15
				)
				_check("local airplane turned too", absf(_game.local_plane().rotation) > 0.15)
				_check("ping measured (%s)" % Lan.connection_quality_text(), Lan.rtt_ms > 0)
				var mode_text: String = _game.hud.mode_label.text
				_check(
					"HUD announces the LAN match and its ping (%s)" % mode_text,
					mode_text.begins_with("LAN match") and mode_text.contains(" ms")
				)
			elif _frame == _joined_frame + 300:
				# Silence the ground war so the only damage in play is the single hit
				# each device lands on the other pilot, which makes the health compare
				# below exact.
				for soldier in _game.soldiers._soldiers:
					var node := soldier as Node
					node.set_physics_process(false)
					node.set_process(false)
				for projectile in _game._projectile_pool:
					if projectile.is_active and projectile._owner_id == 0:
						projectile.deactivate()
			elif _frame == _joined_frame + 322:
				# A hit exactly as this device's own bullet would register it. The other
				# device has to apply it to the airplane it owns, so afterwards both
				# screens must show the same health for the same pilot.
				_game._on_projectile_hit_plane(
					_game.remote_plane(), 34, _game.local_plane().player_id
				)
			elif _frame == _joined_frame + 380:
				_check(
					"the hit landed on the other pilot's screen too (%d)"
					% _game.remote_plane().health.current_health,
					_game.remote_plane().health.current_health == _game.remote_plane().health.max_health - 34
				)
				_report()


func _report() -> void:
	var local := _game.local_plane()
	var remote := _game.remote_plane()
	var planned := _game._courier.planned_drop() if _game._courier != null else Vector2.ZERO
	var first_pickup := _first_pickup()
	var pickup_at := first_pickup.spawn_origin if first_pickup != null else Vector2.ZERO
	var pickup_kind := first_pickup.kind if first_pickup != null else -1
	print(
		("LAN_RESULT role=%s local=(%.1f, %.1f) remote=(%.1f, %.1f) remote_rot=%.3f "
		+ "local_rot=%.3f health=%d/%d local_health=%d courier=(%.1f, %.1f) "
		+ "pickups=%d pickup0=(%.1f, %.1f) kind=%d")
		% [
			_mode,
			local.global_position.x,
			local.global_position.y,
			remote.global_position.x,
			remote.global_position.y,
			remote.rotation,
			local.rotation,
			remote.health.current_health,
			remote.health.max_health,
			local.health.current_health,
			planned.x,
			planned.y,
			_pickup_count(),
			pickup_at.x,
			pickup_at.y,
			pickup_kind,
		]
	)
	_phase = "done"
	_done_frame = _frame


## The courier pass and its drop come from a fixed seed, so both devices must
## agree on where the load lands: if they disagree, the simulations are drifting.
func _pickup_count() -> int:
	var count := 0
	for child in _game.pickups_root.get_children():
		var pickup := child as SkyPickup
		if pickup != null and not pickup.is_taken():
			count += 1
	return count


func _first_pickup() -> SkyPickup:
	for child in _game.pickups_root.get_children():
		var pickup := child as SkyPickup
		if pickup != null and not pickup.is_taken():
			return pickup
	return null


## Ends the round on both devices and checks that a rematch asked for by both
## pilots really starts a fresh round on both screens.
func _run_rematch_checks() -> void:
	var rel := _frame - _done_frame
	var overlay := _main.get_node_or_null("OverlayLayer/GameOver") as GameOverScreen
	if rel == 20:
		if is_instance_valid(_game) and overlay != null:
			_game.match_finished.emit(_game.local_plane().player_id, GameManager.Mode.LAN)
	elif rel == 50 and _mode == "host":
		_press_rematch(overlay)
	elif rel == 80 and _mode == "join":
		_press_rematch(overlay)
	elif rel == 140:
		var restarted := _latest_game()
		_check(
			"a rematch from both pilots started a new round",
			restarted != null and restarted.get_instance_id() != _match_instance_id
		)
	elif rel >= 220:
		_finish()


func _press_rematch(overlay: GameOverScreen) -> void:
	if overlay == null or not overlay.visible:
		_fail("the rematch button was not offered")
		return
	overlay.rematch_button.pressed.emit()


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS  ", label)
	else:
		_failures += 1
		print("FAIL  ", label)


func _fail(label: String) -> void:
	_failures += 1
	print("FAIL  ", label)


func _finish() -> void:
	Lan.close()
	print("=== lan test finished (%s): %d failure(s) ===" % [_mode, _failures])
	get_tree().quit(1 if _failures > 0 else 0)
