class_name AIConfig
extends Resource
## Difficulty knobs for the AI pilot.

enum Difficulty { EASY, NORMAL, HARD }

@export var difficulty: Difficulty = Difficulty.NORMAL
## Seconds between decisions. Higher = slower reactions.
@export var reaction_time: float = 0.4
## Random aim error in degrees applied when picking a heading.
@export var aim_error_degrees: float = 6.0
## Multiplier applied to the plane's fire cooldown. Higher = shoots less.
@export var fire_cooldown_scale: float = 1.15
## Only shoot when the opponent is closer than this (pixels). Planes only climb,
## so fights happen at range: keep this under about 1900 (bullet reach).
@export var attack_range: float = 1350.0
## Only shoot when the nose is within this many degrees of the target.
@export var fire_cone_degrees: float = 10.0
## Minimum seconds between steering direction changes (stops flapping).
@export var min_turn_interval: float = 0.45
## Seconds after the human takes off before the AI leaves the ground.
@export var launch_delay: float = 0.9

@export_group("Ground fire")
## Infantry standing on the ground, taking slow pot shots at both planes. They
## are scenery with teeth: the duel is between the aircraft, so a soldier should
## be a nuisance every few seconds, not a stream of tracers.
@export var soldier_count: int = 3
## Seconds between one soldier's shots.
@export var soldier_interval_min: float = 9.0
@export var soldier_interval_max: float = 15.0


static func preset(difficulty: Difficulty) -> AIConfig:
	var config := AIConfig.new()
	config.difficulty = difficulty
	match difficulty:
		Difficulty.EASY:
			config.reaction_time = 0.9
			config.aim_error_degrees = 15.0
			config.fire_cooldown_scale = 1.9
			config.attack_range = 950.0
			config.fire_cone_degrees = 17.0
			config.min_turn_interval = 0.75
			config.launch_delay = 1.7
			# No infantry: a clean one-on-one.
			config.soldier_count = 0
		Difficulty.HARD:
			config.reaction_time = 0.18
			config.aim_error_degrees = 2.5
			config.fire_cooldown_scale = 0.72
			config.attack_range = 1650.0
			config.fire_cone_degrees = 7.0
			config.min_turn_interval = 0.3
			config.launch_delay = 0.5
			config.soldier_count = 4
			config.soldier_interval_min = 6.0
			config.soldier_interval_max = 10.0
		_:
			config.reaction_time = 0.4
			config.aim_error_degrees = 6.0
			config.fire_cooldown_scale = 1.15
			config.attack_range = 1350.0
			config.fire_cone_degrees = 10.0
			config.min_turn_interval = 0.45
			config.launch_delay = 0.9
	return config
