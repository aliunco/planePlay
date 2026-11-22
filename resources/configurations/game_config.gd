class_name GameConfig
extends Resource
## World dimensions and spawn points. Landscape generation and the camera both
## read from here so the playable area stays consistent.

@export_group("World")
## Horizontal size of the landscape in pixels.
@export var world_width: float = 3200.0
## Top of the playable sky (negative Y is up).
@export var world_top: float = -18000.0
## Bottom of the visible ground band.
@export var world_bottom: float = 280.0
## Y coordinate of the flat ground surface the planes take off from.
@export var ground_y: float = 0.0
## How far the flat surface band extends below the horizon.
@export var ground_depth: float = 240.0

@export_group("Spawns")
@export var player_start_x: float = 560.0
@export var opponent_start_x: float = 2640.0
## Distance from the ground line to the airplane's center when parked.
@export var parked_height: float = 45.0

@export_group("Survival")
## Health handed back for every enemy shot down in a survival run, so a long run
## can be kept alive between repair coins instead of dying from attrition.
@export var survival_kill_heal: int = 45

@export_group("Camera")
@export var camera_zoom: float = 1.15
@export var camera_follow_speed: float = 5.0


func get_player_spawn() -> Vector2:
	return Vector2(player_start_x, ground_y - parked_height)


func get_opponent_spawn() -> Vector2:
	return Vector2(opponent_start_x, ground_y - parked_height)
