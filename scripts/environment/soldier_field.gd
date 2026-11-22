class_name SoldierField
extends Node2D
## Places the ground soldiers along the flat surface and relays the shots they
## take. The count and the firing rhythm come from the difficulty preset, so
## Easy is a clean duel and Hard has a lively ground war.

signal shot_fired(origin: Vector2, direction: Vector2)

const SOLDIER_SCENE: PackedScene = preload("res://scenes/environment/soldier.tscn")
## Keep the take-off runs clear of infantry.
const CLEAR_RADIUS: float = 300.0
## Both peers of a LAN match must place and animate the same soldiers.
const PLACEMENT_SEED: int = 20261108

var _soldiers: Array[Soldier] = []
var _planes: Array[Airplane] = []


func set_planes(planes: Array[Airplane]) -> void:
	_planes = planes


## Rebuilds the squad. Called once per match from GameManager.
func configure(
	count: int,
	ground_y: float,
	world_width: float,
	avoid_x: Array[float],
	interval_min: float,
	interval_max: float
) -> void:
	for soldier in _soldiers:
		soldier.queue_free()
	_soldiers.clear()

	var rng := RandomNumberGenerator.new()
	rng.seed = PLACEMENT_SEED

	for i in count:
		var soldier: Soldier = SOLDIER_SCENE.instantiate()
		add_child(soldier)
		var x := _soldier_x(i, count, world_width, avoid_x, rng)
		soldier.position = Vector2(x, ground_y)
		var uniform := rng.randi() % Soldier.UNIFORMS.size()
		soldier.setup(
			uniform,
			PLACEMENT_SEED + i * 97 + uniform,
			_planes,
			interval_min,
			interval_max
		)
		soldier.shot_fired.connect(_on_shot_fired)
		_soldiers.append(soldier)


## Spreads the squad evenly around the map, then nudges anyone who landed on a
## take-off run. Placement is seeded, so a LAN match builds the same squad on
## both devices.
func _soldier_x(
	index: int,
	count: int,
	world_width: float,
	avoid_x: Array[float],
	rng: RandomNumberGenerator
) -> float:
	var spacing := world_width / float(maxi(count, 1))
	var x := spacing * (float(index) + 0.5) + rng.randf_range(-spacing * 0.28, spacing * 0.28)
	x = fposmod(x, world_width)

	for clear_x in avoid_x:
		if absf(x - clear_x) < CLEAR_RADIUS:
			x = fposmod(x + spacing * 0.5, world_width)
	return x


func reset_field() -> void:
	for soldier in _soldiers:
		soldier.reset_field()


func _on_shot_fired(origin: Vector2, direction: Vector2) -> void:
	shot_fired.emit(origin, direction)
