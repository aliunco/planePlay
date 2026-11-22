class_name SkyBackdrop
extends TextureRect
## Full-screen sky. It lives in a CanvasLayer, so it never scrolls with the
## camera: the sky is effectively infinitely far away.
##
## On its own (the title screen) it paints the fixed golden hour it was styled
## for. Given a DayCycle it becomes a living sky: the gradient follows the sun,
## stars come out, the moon rises, and the sun tracks its arc - all interpolated
## from the cycle's phase, so the light never jumps.

@export var top_color: Color = Color("26629c")
@export var mid_color: Color = Color("65a4d4")
@export var low_color: Color = Color("bfdff0")
@export var horizon_color: Color = Color("ffe2b4")
@export var sun_color: Color = Color("fff4d6")
## Sun position as a fraction of the screen (0,0 is the top-left corner).
@export var sun_at: Vector2 = Vector2(0.78, 0.31)
@export var sun_radius: float = 42.0
@export var show_sun: bool = true

## Horizontal bands the gradient is painted in. Enough that the ramp reads as
## smooth, few enough to stay cheap every frame.
const BANDS: int = 96
const STAR_SEED: int = 90210
const STAR_COUNT: int = 120
## Stop positions of the four sky colours.
const STOPS: float = 0.0

var day_cycle: DayCycle
## Weather pulls the gradient toward an overcast palette and hides the sun; the
## strength fades it in, so a change of weather never snaps.
var weather_kind: int = Weather.Kind.CLEAR
var weather_strength: float = 0.0

var _glow: GradientTexture2D
var _stars: Array[Vector3] = []
var _time: float = 0.0


func _ready() -> void:
	_glow = _build_glow()
	_build_stars()
	stretch_mode = TextureRect.STRETCH_SCALE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


## Hands the sky over to a running day. Without one it stays at golden hour.
func attach_cycle(cycle: DayCycle) -> void:
	day_cycle = cycle
	queue_redraw()


func set_weather(kind: int, strength: float) -> void:
	weather_kind = kind
	weather_strength = clampf(strength, 0.0, 1.0)
	if day_cycle != null:
		queue_redraw()


func _process(delta: float) -> void:
	if day_cycle == null:
		return
	_time += delta
	queue_redraw()


## Soft radial halo for the sun and the moon, reused every frame.
func _build_glow() -> GradientTexture2D:
	# Alpha reaches zero well inside the texture, so the halo never shows the
	# square edge of the quad it is drawn on.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.15, 0.3, 0.45, 0.6, 0.8, 1.0])
	gradient.colors = PackedColorArray(
		[
			Color(1.0, 0.98, 0.92, 0.42),
			Color(1.0, 0.96, 0.88, 0.26),
			Color(1.0, 0.95, 0.86, 0.11),
			Color(1.0, 0.95, 0.86, 0.055),
			Color(1.0, 0.95, 0.86, 0.022),
			Color(1.0, 0.95, 0.86, 0.006),
			Color(1.0, 0.95, 0.86, 0.0),
		]
	)
	var texture_2d := GradientTexture2D.new()
	texture_2d.gradient = gradient
	texture_2d.width = 256
	texture_2d.height = 256
	texture_2d.fill = GradientTexture2D.FILL_RADIAL
	texture_2d.fill_from = Vector2(0.5, 0.5)
	texture_2d.fill_to = Vector2(1.0, 1.0)
	return texture_2d


## Fixed star field: seeded, so the sky looks the same every time it comes out.
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = STAR_SEED
	for i in STAR_COUNT:
		_stars.append(
			Vector3(rng.randf(), rng.randf() * 0.66, rng.randf_range(0.6, 1.9))
		)


func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	if day_cycle == null:
		_paint_static()
		return
	_paint_cycle(day_cycle)


# --- The golden hour (title screen) -----------------------------------------

func _paint_static() -> void:
	_paint_gradient(PackedColorArray([top_color, mid_color, low_color, horizon_color]))

	if show_sun:
		var center := Vector2(size.x * sun_at.x, size.y * sun_at.y)
		# A radial gradient texture gives a perfectly smooth halo (stacked
		# circles showed as rings).
		var reach := sun_radius * 6.0
		if _glow != null:
			draw_texture_rect(
				_glow,
				Rect2(center - Vector2(reach, reach), Vector2(reach, reach) * 2.0),
				false
			)
		draw_circle(center, sun_radius, Color(1.0, 0.96, 0.83, 0.88))
		draw_circle(center, sun_radius * 0.58, Color(1.0, 1.0, 0.97, 0.92))

	_paint_haze(horizon_color)


# --- The living sky (match) --------------------------------------------------

func _paint_cycle(cycle: DayCycle) -> void:
	var cover := _cover_amount()
	var colors := cycle.sky_colors()
	if cover > 0.01:
		colors = _weathered(colors, cover)
	_paint_gradient(colors)

	var dark := cycle.night()
	var starlight := dark * (1.0 - cover * 0.85)
	if starlight > 0.01:
		_paint_stars(starlight)

	_paint_sun(cycle, 1.0 - cover * (1.0 - Weather.sun_visibility(weather_kind)))
	_paint_moon(cycle, dark * (1.0 - cover * 0.7))
	_paint_haze(colors[3])


## How much weather colour is laid over the sky right now.
func _cover_amount() -> float:
	if weather_kind == Weather.Kind.CLEAR:
		return 0.0
	return weather_strength


func _weathered(colors: PackedColorArray, cover: float) -> PackedColorArray:
	var target := Weather.sky_cover(weather_kind)
	var mix := cover * 0.88
	var out := PackedColorArray()
	for i in colors.size():
		out.append(colors[i].lerp(target[i], mix))
	return out


func _paint_gradient(colors: PackedColorArray) -> void:
	var band_height := size.y / float(BANDS)
	for i in BANDS:
		var t := (float(i) + 0.5) / float(BANDS)
		draw_rect(
			Rect2(0.0, float(i) * band_height, size.x, band_height + 1.0),
			_sample(colors, t)
		)


## A point on the four-stop sky ramp. The stops match the original gradient.
func _sample(colors: PackedColorArray, t: float) -> Color:
	var stops: Array[float] = [0.0, 0.46, 0.78, 1.0]
	if t <= stops[0]:
		return colors[0]
	for i in range(1, stops.size()):
		if t <= stops[i]:
			var span := maxf(0.0001, stops[i] - stops[i - 1])
			return colors[i - 1].lerp(colors[i], (t - stops[i - 1]) / span)
	return colors[colors.size() - 1]


func _paint_sun(cycle: DayCycle, visibility: float = 1.0) -> void:
	if visibility <= 0.02:
		return
	var point := cycle.sun_point()
	var center := Vector2(size.x * point.x, size.y * point.y)
	if point.y > 0.78:
		return
	# Fade it out as it touches the horizon instead of letting it pop away.
	var lift := clampf((0.78 - point.y) / 0.10, 0.0, 1.0) * visibility
	var warm := cycle.golden()
	var tint := Color(1.0, 0.97, 0.9).lerp(Color(1.0, 0.74, 0.46), warm)
	var radius := sun_radius * lerpf(1.14, 0.94, warm)

	var reach := radius * 6.0
	if _glow != null:
		draw_texture_rect(
			_glow,
			Rect2(center - Vector2(reach, reach), Vector2(reach, reach) * 2.0),
			false,
			Color(tint, lift)
		)
	draw_circle(center, radius, Color(tint, 0.88 * lift))
	draw_circle(center, radius * 0.58, Color(1.0, 1.0, 0.96, 0.92 * lift))


func _paint_moon(cycle: DayCycle, dark: float) -> void:
	if dark <= 0.02:
		return
	var point := cycle.moon_point()
	if point.y > 0.76:
		return
	var center := Vector2(size.x * point.x, size.y * point.y)
	var radius := 26.0
	var reach := radius * 5.0
	if _glow != null:
		draw_texture_rect(
			_glow,
			Rect2(center - Vector2(reach, reach), Vector2(reach, reach) * 2.0),
			false,
			Color(0.80, 0.87, 1.0, 0.34 * dark)
		)
	draw_circle(center, radius, Color(0.93, 0.95, 1.0, 0.95 * dark))
	# A few shallow craters give the disc some body.
	draw_circle(center + Vector2(-radius * 0.30, -radius * 0.22), radius * 0.20, Color(0.78, 0.82, 0.92, 0.42 * dark))
	draw_circle(center + Vector2(radius * 0.26, radius * 0.12), radius * 0.14, Color(0.78, 0.82, 0.92, 0.36 * dark))
	draw_circle(center + Vector2(-radius * 0.04, radius * 0.40), radius * 0.10, Color(0.78, 0.82, 0.92, 0.32 * dark))


func _paint_stars(dark: float) -> void:
	for i in _stars.size():
		var star := _stars[i]
		var twinkle := 0.72 + 0.28 * sin(_time * (0.7 + float(i % 7) * 0.13) + float(i))
		draw_circle(
			Vector2(star.x * size.x, star.y * size.y),
			star.z,
			Color(0.92, 0.95, 1.0, dark * twinkle * 0.9)
		)


## The air thickens toward the horizon.
func _paint_haze(color: Color) -> void:
	for i in 10:
		var t := float(i) / 9.0
		var band := Rect2(0.0, size.y * (0.60 + t * 0.40) - 12.0, size.x, 16.0)
		draw_rect(band, Color(color, 0.020))
