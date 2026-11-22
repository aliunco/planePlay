class_name PlaneInput
extends RefCounted
## One frame of intent for an airplane, whatever produced it:
## keyboard, touch, AI or a remote multiplayer transport.

## -1.0 turns left, 1.0 turns right.
var turn: float = 0.0
var fire: bool = false
## Only meaningful while the plane is parked on the ground.
var launch: bool = false
## Throttle tap for this tick: 1 shifts up a gear, -1 shifts down, 0 keeps the
## current one. Controllers send a tap on the frame the button goes down, so
## holding it keeps the gear instead of running through all four.
var throttle: int = 0
## Release a bomb from under the belly.
var bomb: bool = false
## Jet boost held down: burns the tank while it lasts.
var boost: bool = false
## Burn a defensive flare to shake off a homing round.
var flare: bool = false
## Spend a charge on the shield bubble.
var shield: bool = false


func copy_from(other: PlaneInput) -> void:
	turn = other.turn
	fire = other.fire
	launch = other.launch
	throttle = other.throttle
	bomb = other.bomb
	boost = other.boost
	flare = other.flare
	shield = other.shield


func reset() -> void:
	turn = 0.0
	fire = false
	launch = false
	throttle = 0
	bomb = false
	boost = false
	flare = false
	shield = false


func is_neutral() -> bool:
	return (
		is_zero_approx(turn)
		and not fire
		and not launch
		and throttle == 0
		and not bomb
		and not boost
		and not flare
		and not shield
	)


func to_dict() -> Dictionary:
	return {
		"turn": turn,
		"fire": fire,
		"launch": launch,
		"throttle": throttle,
		"bomb": bomb,
		"boost": boost,
		"flare": flare,
		"shield": shield,
	}


static func from_dict(data: Dictionary) -> PlaneInput:
	var input := PlaneInput.new()
	input.turn = clampf(float(data.get("turn", 0.0)), -1.0, 1.0)
	input.fire = bool(data.get("fire", false))
	input.launch = bool(data.get("launch", false))
	input.throttle = clampi(int(data.get("throttle", 0)), -1, 1)
	input.bomb = bool(data.get("bomb", false))
	input.boost = bool(data.get("boost", false))
	input.flare = bool(data.get("flare", false))
	input.shield = bool(data.get("shield", false))
	return input
