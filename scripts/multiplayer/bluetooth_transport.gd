class_name BluetoothTransport
extends MultiplayerTransport
## Bluetooth transport placeholder.
##
## This class is intentionally honest: until a native plugin is present it
## reports "not supported" and never pretends a match is connected. It defines
## exactly what a native bridge has to provide so the rest of the game does not
## change when one is added. Full plan: docs/BLUETOOTH_INTEGRATION.md
##
## Expected bridge shape (see docs for Kotlin/Swift signatures):
##   discover()            -> starts scanning, callback on_device_found(name, id)
##   host(name)            -> opens a listen socket
##   connect_to(id)        -> opens an RFCOMM / L2CAP channel to a device
##   send(bytes)           -> writes one framed packet
##   close()               -> tears everything down

const ANDROID_PLUGIN_NAME := "BluetoothLink"
const IOS_PLUGIN_METHOD_PREFIX := "bluetooth_"

## Packet framing for PlaneInput snapshots: 1 byte magic + 1 byte flags + 1 byte
## turn (0..255 mapped to -1..1) + 1 byte sequence.
const FRAME_MAGIC: int = 0xA5
const FRAME_SIZE: int = 4

var _state: State = State.DISCONNECTED
var _status: String = "Bluetooth plugin not installed"
var _sequence: int = 0


func is_supported() -> bool:
	return Engine.has_singleton(ANDROID_PLUGIN_NAME) or OS.has_feature("ios_plugin")


func connect_to_peer(_config: Dictionary = {}) -> bool:
	if not is_supported():
		_state = State.FAILED
		_status = "Bluetooth needs a native plugin (docs/BLUETOOTH_INTEGRATION.md)"
		state_changed.emit(_state)
		transport_error.emit(_status)
		return false

	# --- Integration point ---------------------------------------------------
	# On Android:  var plugin = Engine.get_singleton(ANDROID_PLUGIN_NAME)
	#              plugin.discover(); plugin.connect("device_found", ...)
	# On iOS:      Engine.get_singleton("BluetoothLink").call("discover")
	# Only after a channel is open should _state become State.CONNECTED.
	# -------------------------------------------------------------------------
	_state = State.SEARCHING
	_status = "Searching for nearby pilots..."
	state_changed.emit(_state)
	return true


func disconnect_from_peer() -> void:
	# Integration point: plugin.close() on both platforms.
	_state = State.DISCONNECTED
	_status = "Disconnected"
	state_changed.emit(_state)
	peer_left.emit()


func send_input(player_id: int, input: PlaneInput) -> void:
	if _state != State.CONNECTED:
		return
	# Integration point: plugin.send(encode_frame(input)) once the native bridge
	# exists. encode_frame/decode_frame below are platform independent.
	var _bytes := encode_frame(input)


func get_connection_state() -> State:
	return _state


func get_status_text() -> String:
	return _status


# --- Shared, testable packet helpers ----------------------------------------

func encode_frame(input: PlaneInput) -> PackedByteArray:
	_sequence = (_sequence + 1) % 256
	var flags := 0
	if input.fire:
		flags |= 1
	if input.launch:
		flags |= 2
	var turn_byte := int(round((clampf(input.turn, -1.0, 1.0) + 1.0) * 127.5))
	return PackedByteArray([FRAME_MAGIC, flags, turn_byte, _sequence])


func decode_frame(bytes: PackedByteArray) -> PlaneInput:
	var input := PlaneInput.new()
	if bytes.size() < FRAME_SIZE or bytes[0] != FRAME_MAGIC:
		return input
	var flags := bytes[1]
	input.fire = (flags & 1) != 0
	input.launch = (flags & 2) != 0
	input.turn = clampf(float(bytes[2]) / 127.5 - 1.0, -1.0, 1.0)
	return input
