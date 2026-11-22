class_name AirplaneHealth
extends Node
## Health bookkeeping for a single airplane. Kept separate from the plane node so
## damage rules can be tested or replaced without touching movement code.

signal health_changed(current: int, maximum: int)
signal damage_taken(amount: int)
signal died

var max_health: int = 150
var current_health: int = 150
var is_dead: bool = false


func setup(maximum: int) -> void:
	max_health = maxi(1, maximum)
	current_health = max_health
	is_dead = false
	health_changed.emit(current_health, max_health)


func take_damage(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current_health = maxi(0, current_health - amount)
	damage_taken.emit(amount)
	health_changed.emit(current_health, max_health)
	if current_health == 0:
		is_dead = true
		died.emit()


## Adopts a value from the network without re-running damage rules. Used by the
## owner's heartbeat when a prediction drifted.
func sync_current(value: int) -> void:
	var clamped := clampi(value, 0, max_health)
	if clamped == current_health:
		return
	current_health = clamped
	health_changed.emit(current_health, max_health)


func reset() -> void:
	is_dead = false
	current_health = max_health
	health_changed.emit(current_health, max_health)


func get_ratio() -> float:
	return float(current_health) / float(max_health)
