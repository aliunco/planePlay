class_name PlaneConfig
extends Resource
## Everything that makes one airplane fly and fight. The gameplay code never
## hard-codes these numbers, so balance changes are data changes.

## Four throttle gears. Forward speed is plane_speed times one of these, so gear
## 2 is the speed the game was balanced around: gear 1 crawls, gear 4 nearly
## doubles it, and the gap between neighbours is meant to be felt immediately.
const GEAR_FACTORS: Array[float] = [0.55, 1.0, 1.45, 2.0]
## Gear every plane starts, and leaves the strip, in.
const DEFAULT_GEAR: int = 2

@export_group("Flight")
## Forward speed in pixels per second at gear 2. The plane always moves along its
## nose; the engaged gear scales this.
@export var plane_speed: float = 160.0
## Degrees per second the nose can rotate.
@export var rotation_speed: float = 100.0
## Maximum absolute nose angle from straight up, in degrees. 360 = free flight:
## the pilot can loop, dive and turn all the way around (down is allowed).
## Values below 180 clamp the nose angle, e.g. 80 keeps the plane climbing.
@export var max_rotation: float = 360.0

@export_group("Combat")
## How many standard bullet hits bring a plane down. The health bar is ticked once
## per hit, so this is the number to keep in step with max_health and the bullet
## damage (150 health against a 34-damage bullet is five hits).
const HITS_TO_KILL: int = 5

## Five hits from a 34-damage bullet: long enough that a dogfight has room to
## breathe, short enough that trades still decide the round.
@export var max_health: int = 150
@export var fire_cooldown: float = 0.34
@export var projectile_config: ProjectileConfig

@export_group("Bombs and boost")
## Bombs a plane leaves the strip with. The rack refills itself once it is empty:
## there is no bomb in the courier's load any more.
@export var start_bombs: int = 2
## Seconds the ground crew take to winch two fresh bombs into an empty rack.
@export var bomb_reload_seconds: float = 15.0## Damage at the centre of a blast, falling off to a third of it at the rim.
@export var bomb_damage: int = 70
## How far the blast reaches, in pixels.
@export var bomb_blast_radius: float = 170.0
## Top speed while the jet boost is lit, as a multiple of the engaged gear.
@export var boost_multiplier: float = 1.75
## How many seconds a full boost tank lasts, and how long an empty one takes to
## refill. Leaving a little in the tank is worth it: the tank only refills once
## the pilot lets go for a moment.
@export var boost_seconds: float = 3.0
@export var boost_recharge_seconds: float = 13.0
@export var boost_recharge_delay: float = 0.9

@export_group("Shield")
## Shield charges a plane rolls out with, and how many one crate adds.
@export var start_shield: int = 0
@export var shield_per_crate: int = 1
## How long one charge keeps the bubble up. Everything the enemy fires is stopped
## for that long; flying into the ground is not.
@export var shield_seconds: float = 15.0

@export_group("Flares")
## Flares a plane rolls out with, and how many one crate adds. A flare burst is a
## hard counter to a homing round, so the rack is deliberately small.
@export var start_flares: int = 3
@export var flares_per_crate: int = 2
## How many flares one press throws out, and how long before another burst.
@export var flares_per_burst: int = 5
@export var flare_cooldown: float = 0.55

@export_group("Take-off")
## Ground roll before the nose comes up, in pixels.
@export var taxi_distance: float = 190.0
## Ground acceleration during the roll, pixels per second squared.
@export var taxi_acceleration: float = 230.0
## Nose-up angle held during the climb-out, in degrees above the runway.
@export var takeoff_pitch_degrees: float = 30.0
## How fast the nose rotates up to that angle, degrees per second.
@export var takeoff_rotate_rate: float = 62.0
## How long the plane climbs out before it levels off, in seconds.
@export var takeoff_climb_seconds: float = 1.1
## How fast it levels back to horizontal flight, degrees per second.
@export var takeoff_level_rate: float = 40.0

@export_group("Presentation")
## Which airframe to build (see PlaneRoster and PlaneModel3D.Silhouette): 0 is
## the classic prop fighter, 5-8 the jets, 9 the experimental Aurora.
@export var plane_silhouette: int = 0
## Name of the fighter from the roster, so the menu and the HUD agree on it.
@export var plane_name: String = "Kestrel Mk I"
## Livery of the rendered 3D airframe: fuselage, nose/wingtips and underside.
## Every plane builds its own model from these three colours.
@export var livery_body: Color = Color("4c5c36")
@export var livery_accent: Color = Color("e6b93f")
@export var livery_belly: Color = Color("9aa49c")
## Opponents use the same model mirrored on the Y axis (nose to the left).
@export var visual_flip_h: bool = false
@export var display_name: String = "Player"


func get_projectile_config() -> ProjectileConfig:
	if projectile_config == null:
		projectile_config = ProjectileConfig.new()
	return projectile_config


## Forward speed with a gear engaged, gear 1 being the slowest.
static func gear_speed(base_speed: float, gear: int) -> float:
	var index := clampi(gear, 1, GEAR_FACTORS.size()) - 1
	return base_speed * GEAR_FACTORS[index]


## Returns a copy safe to tweak per-instance (e.g. AI difficulty cooldowns).
func duplicate_for_instance() -> PlaneConfig:
	var copy: PlaneConfig = duplicate()
	copy.projectile_config = get_projectile_config().duplicate()
	return copy
