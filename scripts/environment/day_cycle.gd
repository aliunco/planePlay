class_name DayCycle
extends Node
## Drives the sun across the sky so a match can start in the morning, pass through
## a long dusk and end under the moon. The sky, the tint over the world and the
## aircraft landing lamps all read from here, so they change together.
##
## The phase is a fraction of one day: 0 is sunrise, 0.25 midday, 0.5 sunset and
## 0.75 midnight. Everything else is interpolated from it, and the phase advances
## smoothly, so the light never switches from day to night in one step.

## Seconds for one full day and night. Slow enough that dusk is watched rather
## than noticed.
@export var cycle_seconds: float = 220.0
## Where in the day a match starts: late morning, so dusk arrives during a run.
@export var start_phase: float = 0.16

## Where the painted horizon sits, as a fraction of the screen height. The
## landscape is laid out on the same line.
const HORIZON: float = 0.74

const DAY_TOP := Color("26629c")
const DAY_MID := Color("65a4d4")
const DAY_LOW := Color("bfdff0")
const DAY_HORIZON := Color("ffe2b4")

const GOLDEN_TOP := Color("3d5a85")
const GOLDEN_MID := Color("9487a8")
const GOLDEN_LOW := Color("f0b18f")
const GOLDEN_HORIZON := Color("ffcb95")

const NIGHT_TOP := Color("08102b")
const NIGHT_MID := Color("122044")
const NIGHT_LOW := Color("223a66")
const NIGHT_HORIZON := Color("445b84")

var phase: float = 0.0


func _ready() -> void:
	phase = fposmod(start_phase, 1.0)


func _process(delta: float) -> void:
	phase = fposmod(phase + delta / maxf(1.0, cycle_seconds), 1.0)


## -1 at midnight, 0 on the horizon, 1 at midday.
func elevation() -> float:
	return sin(phase * TAU)


## 0 after dark, 1 in full day.
func daylight() -> float:
	return smoothstep(-0.18, 0.20, elevation())


func night() -> float:
	return 1.0 - daylight()


## Warm light near the horizon: the golden hour at both ends of the day.
func golden() -> float:
	return clampf(1.0 - absf(elevation()) / 0.34, 0.0, 1.0)


## The aircraft lamps come on a little before the sky is fully dark.
func lamp() -> float:
	return smoothstep(0.42, 0.78, night())


## Where the sun sits, in fractions of the screen. It sinks below the horizon
## line as it sets.
func sun_point() -> Vector2:
	var angle := phase * TAU
	# Half an arc's width of travel, so the disc stays whole at both ends instead
	# of being clipped by the edge of the screen as it rises and sets.
	return Vector2(0.5 - 0.38 * cos(angle), HORIZON - 0.42 * sin(angle))


## The moon rides the opposite arc, so it is up while the sun is down.
func moon_point() -> Vector2:
	var angle := phase * TAU
	return Vector2(0.5 + 0.38 * cos(angle), HORIZON + 0.40 * sin(angle))


## The four sky stops for this moment: top, middle, low and horizon.
func sky_colors() -> PackedColorArray:
	var light := daylight()
	var warm := golden()
	return PackedColorArray(
		[
			NIGHT_TOP.lerp(DAY_TOP, light).lerp(GOLDEN_TOP, warm * 0.8),
			NIGHT_MID.lerp(DAY_MID, light).lerp(GOLDEN_MID, warm * 0.85),
			NIGHT_LOW.lerp(DAY_LOW, light).lerp(GOLDEN_LOW, warm * 0.9),
			NIGHT_HORIZON.lerp(DAY_HORIZON, light).lerp(GOLDEN_HORIZON, warm * 0.95),
		]
	)
