class_name ProjectileConfig
extends Resource
## Tunable values for a bullet. Attached to a PlaneConfig so every airplane can
## carry its own projectile setup (speed, damage, lifetime, look).

## Projectile speed is derived from the shooter's plane speed so a faster plane
## always shoots proportionally faster bullets.
@export var speed_multiplier: float = 5.0
## Optional absolute speed override. 0.0 means "use plane_speed * multiplier".
@export var absolute_speed: float = 0.0
@export var lifetime: float = 2.4
@export var damage: int = 34
## Finishes the target outright whatever its health is, so raising max_health
## never turns the crate round into a dud.
@export var lethal: bool = false
@export var radius: float = 6.0
## Homing rounds steer towards the enemy airplane for their whole lifetime; when
## it runs out they are disposed of, so a well-flown dodge works.
@export var homing: bool = false
@export var homing_turn_rate: float = 130.0
@export var tint: Color = Color("ffcf5c")
@export var texture: Texture2D


func compute_speed(plane_speed: float) -> float:
	if absolute_speed > 0.0:
		return absolute_speed
	return plane_speed * speed_multiplier
