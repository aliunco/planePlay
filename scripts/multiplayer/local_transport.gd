class_name LocalTransport
extends MultiplayerTransport
## Loopback transport. Sends each input snapshot straight back as if it had
## arrived from a peer. Handy for verifying the remote-input path and for
## keyboard two-player testing without any platform plugin.

var _state: State = State.DISCONNECTED


func connect_to_peer(_config: Dictionary = {}) -> bool:
	_state = State.CONNECTED
	state_changed.emit(_state)
	peer_joined.emit("Local loopback")
	return true


func disconnect_from_peer() -> void:
	_state = State.DISCONNECTED
	state_changed.emit(_state)
	peer_left.emit()


func send_input(player_id: int, input: PlaneInput) -> void:
	if _state != State.CONNECTED:
		return
	var copy := PlaneInput.new()
	copy.copy_from(input)
	input_received.emit(player_id, copy)


func get_connection_state() -> State:
	return _state


func get_status_text() -> String:
	return "Loopback (testing only)"


func is_supported() -> bool:
	return true
