class_name MultiplayerTransport
extends RefCounted
## Abstract link between two players.
##
## The gameplay layer only ever sees PlaneInput snapshots coming from a
## controller, so a transport never touches airplane code. Implementations own
## discovery, connection state, framing and reliability; the game owns rules.
##
## NOTE: Godot's MultiplayerAPI (ENet/WebSocket peers) is deliberately NOT used
## here. Bluetooth needs explicit device discovery and RFCOMM/GATT connection
## management that MultiplayerAPI does not provide, so transport is explicit.
## See docs/BLUETOOTH_INTEGRATION.md.

signal state_changed(state: State)
signal input_received(player_id: int, input: PlaneInput)
signal peer_joined(peer_name: String)
signal peer_left
signal transport_error(message: String)

enum State { DISCONNECTED, SEARCHING, CONNECTING, CONNECTED, FAILED }


## Starts advertising + discovery. Returns false when the transport cannot run
## on this platform/build (e.g. no native plugin installed).
func connect_to_peer(_config: Dictionary = {}) -> bool:
	state_changed.emit(State.FAILED)
	transport_error.emit("Transport not implemented")
	return false


func disconnect_from_peer() -> void:
	state_changed.emit(State.DISCONNECTED)


## Sends one frame of local intent to the remote player.
func send_input(_player_id: int, _input: PlaneInput) -> void:
	pass


## Convenience: push received input into the remote-controlled airplane, if any.
func deliver_to(controller: RemotePlaneController) -> void:
	if controller == null:
		return
	input_received.connect(
		func(_player_id: int, input: PlaneInput) -> void: controller.push_input(input)
	)


func get_connection_state() -> State:
	return State.DISCONNECTED


func get_status_text() -> String:
	return "Not connected"


func is_supported() -> bool:
	return false
