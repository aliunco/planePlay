class_name Weather
extends RefCounted
## What the sky is doing, and how the rest of the world should answer. The sky,
## the clouds, the tint over the map and the precipitation layer all read from
## here, so one choice of weather changes everything consistently.

enum Kind { CLEAR, CLOUDY, RAIN, SNOW }


static func label(kind: int) -> String:
	match kind:
		Kind.CLOUDY:
			return "Cloudy"
		Kind.RAIN:
			return "Rain"
		Kind.SNOW:
			return "Snow"
		_:
			return "Clear"


static func precipitation(kind: int) -> bool:
	return kind == Kind.RAIN or kind == Kind.SNOW


## The four sky stops an overcast, a rainstorm or a snowfall pulls the gradient
## toward. Clear weather uses the day cycle's own colours.
static func sky_cover(kind: int) -> PackedColorArray:
	match kind:
		Kind.CLOUDY:
			return PackedColorArray(
				[
					Color("5b7794"),
					Color("86a0b4"),
					Color("b3c3ce"),
					Color("cfd7db"),
				]
			)
		Kind.RAIN:
			return PackedColorArray(
				[
					Color("33485c"),
					Color("54697c"),
					Color("758794"),
					Color("8b98a1"),
				]
			)
		Kind.SNOW:
			return PackedColorArray(
				[
					Color("8aa2b8"),
					Color("b3c6d4"),
					Color("dbe6ee"),
					Color("eef3f6"),
				]
			)
		_:
			return PackedColorArray(
				[Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]
			)


## How much light the world keeps under this weather. Multiplied with the night
## tint, so a rainy night is darker than a clear one but still flyable.
static func world_tint(kind: int) -> Color:
	match kind:
		Kind.CLOUDY:
			return Color(0.86, 0.89, 0.93)
		Kind.RAIN:
			return Color(0.70, 0.75, 0.83)
		Kind.SNOW:
			return Color(0.93, 0.95, 1.0)
		_:
			return Color.WHITE


static func cloud_tint(kind: int) -> Color:
	match kind:
		Kind.CLOUDY:
			return Color(0.84, 0.87, 0.90)
		Kind.RAIN:
			return Color(0.58, 0.64, 0.72)
		Kind.SNOW:
			return Color(0.95, 0.97, 1.0)
		_:
			return Color.WHITE


## Cloud cover gets heavier as the weather closes in.
static func cloud_alpha_scale(kind: int) -> float:
	match kind:
		Kind.CLOUDY:
			return 1.2
		Kind.RAIN:
			return 1.3
		Kind.SNOW:
			return 1.15
		_:
			return 1.0


## How much of the sun and stars still show through: 1 in clear air, almost
## nothing in a downpour.
static func sun_visibility(kind: int) -> float:
	match kind:
		Kind.CLOUDY:
			return 0.32
		Kind.RAIN:
			return 0.10
		Kind.SNOW:
			return 0.38
		_:
			return 1.0
