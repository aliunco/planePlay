class_name RemotePlaneController
extends AirplaneController
## Pilot driven by inputs that arrived over a multiplayer transport
## (Bluetooth today, anything else tomorrow).

## Stale inputs are dropped so a dropped connection cannot leave a plane
## turning forever.
const INPUT_TIMEOUT: float = 0.6

var _input := PlaneInput.new()
var _stale_time: float = 0.0


func push_input(state: PlaneInput) -> void:
	_input.copy_from(state)
	_stale_time = 0.0


func get_plane_input(delta: float) -> PlaneInput:
	_stale_time += delta
	if _stale_time > INPUT_TIMEOUT:
		_input.reset()
	return _input
