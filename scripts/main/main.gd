extends Node
## Application flow: main menu -> match -> result overlay -> menu.

const GAME_SCENE: PackedScene = preload("res://scenes/game/game.tscn")

@onready var menu: MainMenu = $MenuLayer/MainMenu
@onready var game_host: Node = $GameHost
@onready var game_over: GameOverScreen = $OverlayLayer/GameOver

var _current_mode: int = GameManager.Mode.SINGLE_PLAYER
var _current_difficulty: int = AIConfig.Difficulty.NORMAL
var _current_weather: int = Weather.Kind.CLEAR
## The fighter picked on the title screen, an index into PlaneRoster.
var _current_plane: int = 0
## The match in play, so a survival run's tally can be read when it ends.
var _active_game: GameManager

# LAN rematch handshake: both devices have to ask for the rematch.
var _rematch_local: bool = false
var _rematch_remote: bool = false
var _rematch_starting: bool = false


func _ready() -> void:
	game_over.hide_result()
	menu.play_requested.connect(_on_play_requested)
	menu.lan_host_requested.connect(_on_lan_host_requested)
	menu.lan_join_requested.connect(_on_lan_join_requested)
	game_over.rematch_pressed.connect(_on_rematch)
	game_over.menu_pressed.connect(_on_menu_requested)
	Lan.peer_joined.connect(_on_lan_peer_joined)
	Lan.failed.connect(_on_lan_failed)
	Lan.rematch_requested.connect(_on_lan_rematch_requested)
	Lan.peer_left.connect(func() -> void: menu.set_status("The other pilot left the match."))
	get_tree().paused = false


func _on_play_requested(mode: int, difficulty: int) -> void:
	Lan.close()
	_current_mode = mode
	_current_difficulty = difficulty
	_current_weather = menu.selected_weather
	_current_plane = menu.selected_plane
	_start_match()


# --- LAN lobby ---------------------------------------------------------------

func _on_lan_host_requested() -> void:
	menu.set_status("")
	if not Lan.host():
		menu.set_status(Lan.status_text())
		return
	menu.set_lan_waiting(true)
	menu.set_status(
		"Waiting for the other pilot...\nYour IP: %s  ·  port %d"
		% [Lan.local_address_hint(), Lan.DEFAULT_PORT]
	)


func _on_lan_join_requested(address: String) -> void:
	menu.set_status("")
	if not Lan.join(address):
		menu.set_status(Lan.status_text())
		return
	menu.set_lan_waiting(true)
	menu.set_status("Connecting...")


func _on_lan_peer_joined() -> void:
	menu.set_lan_waiting(false)
	menu.set_status("")
	_current_mode = GameManager.Mode.LAN
	_current_difficulty = AIConfig.Difficulty.NORMAL
	# Both devices have to fly the same sky, so a LAN duel is always clear: the
	# two pilots never chose together.
	_current_weather = Weather.Kind.CLEAR
	_current_plane = menu.selected_plane
	_start_match()


func _on_lan_failed(message: String) -> void:
	menu.set_lan_waiting(false)
	menu.set_status(message)


func _start_match() -> void:
	_clear_game()
	get_tree().paused = false
	_rematch_local = false
	_rematch_remote = false
	game_over.set_rematch_enabled(true)
	game_over.hide_result()
	menu.visible = false

	var game: GameManager = GAME_SCENE.instantiate()
	game.setup(_current_mode, _current_difficulty, _current_weather, _current_plane)
	game.match_finished.connect(_on_match_finished)
	game.quit_to_menu_requested.connect(_show_menu)
	game_host.add_child(game)
	_active_game = game


func _clear_game() -> void:
	for child in game_host.get_children():
		child.queue_free()


func _on_match_finished(winner_id: int, mode: int) -> void:
	if mode == GameManager.Mode.SURVIVAL:
		_finish_survival_run()
		return
	var title := "PLAYER %d WINS" % winner_id
	var subtitle := ""
	if mode == GameManager.Mode.SINGLE_PLAYER:
		if winner_id == 1:
			subtitle = "You shot down the AI pilot."
		else:
			subtitle = "The AI got you this time. Try an easier setting?"
	elif mode == GameManager.Mode.LOCAL_VERSUS:
		subtitle = "Player %d takes the round." % winner_id
	else:
		var local_id := 1 if Lan.is_host() else 2
		subtitle = (
			"You win the LAN duel." if winner_id == local_id else "The other pilot wins the LAN duel."
		)
	InputManager.clear_virtual_actions()
	_rematch_local = false
	_rematch_remote = false
	game_over.set_rematch_enabled(true)
	game_over.show_result(title, subtitle)


## A survival run is over when the player is shot down, so the result is the tally:
## how many fighters this run took down, against the best run on this device.
func _finish_survival_run() -> void:
	var score := 0
	var best := 0
	if _active_game != null and is_instance_valid(_active_game):
		score = _active_game.score
		best = _active_game.best_score
	InputManager.clear_virtual_actions()
	_rematch_local = false
	_rematch_remote = false
	game_over.set_rematch_enabled(true)

	var planes := "fighter" if score == 1 else "fighters"
	var subtitle := "You shot down %d %s  ·  best %d" % [score, planes, best]
	var title := "RUN OVER"
	if score > 0 and score >= best:
		title = "NEW RECORD"
		subtitle = "%d %s down  ·  best run yet" % [score, planes]
	game_over.show_result(title, subtitle)


func _on_rematch() -> void:
	if _current_mode != GameManager.Mode.LAN:
		_start_match()
		return

	# Both pilots have to agree, so the other device is not yanked into a round
	# it did not ask for.
	_rematch_local = true
	Lan.request_rematch()
	if _rematch_remote:
		_start_lan_rematch()
	else:
		game_over.set_status("Waiting for the other pilot to accept the rematch...")
		game_over.set_rematch_enabled(false)


func _on_lan_rematch_requested() -> void:
	if not game_over.visible:
		return
	_rematch_remote = true
	if _rematch_local:
		_start_lan_rematch()
	else:
		game_over.set_status("The other pilot wants a rematch. Press Rematch to accept.")


func _start_lan_rematch() -> void:
	if _rematch_starting:
		return
	_rematch_starting = true
	_start_match()
	_rematch_starting = false


func _on_menu_requested() -> void:
	_show_menu()


func _show_menu() -> void:
	get_tree().paused = false
	Lan.close()
	menu.set_lan_waiting(false)
	_clear_game()
	game_over.hide_result()
	menu.visible = true
	menu.refresh_record()
	# Look for a host again, in case this menu is opened on the joining device.
	menu.search_for_host()

