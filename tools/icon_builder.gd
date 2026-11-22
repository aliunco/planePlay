extends Node
## Renders the application icon from the game's own art: the aircraft is the real
## 3D model the match flies, over the same painted sky and hills the menu uses.
##
##   godot --path . res://tools/icon_builder.tscn
##
## Writes assets/icon/icon_1024.png plus the two Android adaptive layers, and a
## 512 px res://icon.png for the project and launcher icon. Rendering has to be
## real (not --headless), so this opens a window for a moment and then quits.

const OUT_DIR := "res://assets/icon"
const SIZE: int = 1024
const ADAPTIVE: int = 432
## Frames to let the 3D render and the composition settle before each capture.
const SETTLE_FRAMES: int = 5

var _plane: PlaneModel3D
var _viewport: SubViewport
var _art: IconArt
var _sprite: Sprite2D
var _step: int = 0
var _wait: int = 0
## The first capture waits long enough for the gear to finish folding away.
var _settle: int = 80


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# The real airframe, in a brightened version of the player's livery so it reads
	# at launcher sizes.
	_plane = PlaneModel3D.new()
	add_child(_plane)
	_plane.build(Color("6f8a4e"), Color("f2c94c"), Color("b9c4a5"))
	_plane.set_propeller_speed(0.0)
	# In flight: the gear is up.
	_plane.set_gear_down(false)
	# One extra key light for the icon: the game's lighting is tuned for a small
	# sprite in the sky, not for a 700 px hero shot.
	var boost := DirectionalLight3D.new()
	boost.light_energy = 0.85
	boost.light_color = Color(1.0, 0.96, 0.88)
	boost.rotation_degrees = Vector3(-38.0, 18.0, 0.0)
	boost.shadow_enabled = false
	_plane.add_child(boost)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(SIZE, SIZE)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_art = IconArt.new()
	_art.size = Vector2(SIZE, SIZE)
	_viewport.add_child(_art)

	_sprite = Sprite2D.new()
	_sprite.texture = _plane.get_texture()
	_sprite.position = Vector2(SIZE * 0.45, SIZE * 0.57)
	_sprite.rotation = deg_to_rad(-18.0)
	_sprite.scale = Vector2.ONE * 1.75
	_viewport.add_child(_sprite)


func _process(_delta: float) -> void:
	_wait += 1
	if _wait < _settle:
		return
	_wait = 0
	_settle = SETTLE_FRAMES
	match _step:
		0:
			_art.mode = IconArt.Mode.FULL
			_art.queue_redraw()
			_sprite.visible = true
			_sprite.scale = Vector2.ONE * 1.75
			_sprite.position = Vector2(SIZE * 0.45, SIZE * 0.57)
			_step = 1
		1:
			var full := _capture()
			_write(full, "icon_1024", SIZE)
			var small := full.duplicate() as Image
			small.resize(512, 512, Image.INTERPOLATE_LANCZOS)
			if small.save_png("res://icon.png") == OK:
				print("icon saved: res://icon.png ", small.get_size())
			# The adaptive foreground only carries the aircraft, inside the safe
			# circle Android keeps when it masks the icon.
			_art.mode = IconArt.Mode.FOREGROUND
			_art.queue_redraw()
			_sprite.scale = Vector2.ONE * 1.25
			_sprite.position = Vector2(SIZE * 0.5, SIZE * 0.54)
			_step = 2
		2:
			_write(_capture(), "adaptive_foreground_432", ADAPTIVE)
			_art.mode = IconArt.Mode.BACKGROUND
			_art.queue_redraw()
			_sprite.visible = false
			_step = 3
		3:
			_write(_capture(), "adaptive_background_432", ADAPTIVE)
			print("icon art done")
			get_tree().quit()


func _capture() -> Image:
	return _viewport.get_texture().get_image()


func _write(image: Image, name: String, target: int) -> void:
	if image.get_width() != target:
		image.resize(target, target, Image.INTERPOLATE_LANCZOS)
	var path := "%s/%s.png" % [OUT_DIR, name]
	if image.save_png(path) == OK:
		print("icon saved: ", path, " ", image.get_size())
	else:
		print("ICON FAILED ", path)


## The painted part of the icon: sky, sun, clouds and the two hill ridges. Drawn
## at 1024 and scaled down, so every edge stays clean at launcher sizes.
class IconArt extends Node2D:
	enum Mode { FULL, FOREGROUND, BACKGROUND }

	var size: Vector2 = Vector2(1024.0, 1024.0)
	var mode: Mode = Mode.FULL

	const SKY_TOP := Color("0c2c4a")
	const SKY_MID := Color("1d6b9c")
	const SKY_LOW := Color("6fb6d6")
	const SKY_HORIZON := Color("ffcf8f")
	const SUN := Color("ffe6b0")
	const RIDGE_FAR := Color("2f7d74")
	const RIDGE_NEAR := Color("1d5a55")
	const GROUND := Color("17464a")

	func _draw() -> void:
		if mode == Mode.FOREGROUND:
			return
		_draw_sky()
		_draw_sun()
		_draw_clouds()
		_draw_ridges()

	func _draw_sky() -> void:
		var stops: Array[float] = [0.0, 0.38, 0.66, 0.86]
		var colors: Array[Color] = [SKY_TOP, SKY_MID, SKY_LOW, SKY_HORIZON]
		var bands := 128
		for i in bands:
			var t := (float(i) + 0.5) / float(bands)
			var color := _sample(stops, colors, minf(t, 0.86))
			draw_rect(
				Rect2(0.0, size.y * float(i) / float(bands), size.x, size.y / float(bands) + 1.0),
				color
			)

	func _sample(stops: Array[float], colors: Array[Color], t: float) -> Color:
		for i in range(1, stops.size()):
			if t <= stops[i]:
				var span := maxf(0.0001, stops[i] - stops[i - 1])
				return colors[i - 1].lerp(colors[i], (t - stops[i - 1]) / span)
		return colors[colors.size() - 1]

	## A big low sun, with a halo built from translucent discs.
	func _draw_sun() -> void:
		var centre := Vector2(size.x * 0.74, size.y * 0.28)
		for i in 5:
			var reach := size.x * (0.32 - float(i) * 0.05)
			draw_circle(centre, reach, Color(SUN, 0.032))
		draw_circle(centre, size.x * 0.135, Color(SUN, 0.85))
		draw_circle(centre, size.x * 0.092, Color(1.0, 0.98, 0.9, 0.95))

	func _draw_clouds() -> void:
		_cloud(Vector2(0.17, 0.24), 0.055, 0.10)
		_cloud(Vector2(0.50, 0.15), 0.045, 0.08)
		_cloud(Vector2(0.86, 0.62), 0.05, 0.12)
		_cloud(Vector2(0.26, 0.56), 0.04, 0.09)

	func _cloud(at: Vector2, scale: float, alpha: float) -> void:
		var centre := Vector2(size.x * at.x, size.y * at.y)
		var r := size.x * scale
		var color := Color(1.0, 0.98, 0.95, alpha)
		draw_circle(centre, r, color)
		draw_circle(centre + Vector2(r * 0.9, r * 0.18), r * 0.72, color)
		draw_circle(centre + Vector2(-r * 0.95, r * 0.22), r * 0.62, color)
		draw_circle(centre + Vector2(r * 0.2, -r * 0.45), r * 0.55, color)
		draw_rect(
			Rect2(centre.x - r * 1.55, centre.y - r * 0.1, r * 3.1, r * 0.4), color
		)

	## Two ridge lines and the dark ground they stand on.
	func _draw_ridges() -> void:
		_ridge(0.70, 0.030, 1.7, 0.4, RIDGE_FAR)
		_ridge(0.78, 0.038, 2.4, 1.1, RIDGE_NEAR)
		draw_rect(
			Rect2(0.0, size.y * 0.815, size.x, size.y * 0.19), GROUND
		)

	func _ridge(base: float, amplitude: float, frequency: float, phase: float, color: Color) -> void:
		var points := PackedVector2Array()
		points.append(Vector2(0.0, size.y))
		var steps := 48
		for i in steps + 1:
			var t := float(i) / float(steps)
			var y := base + sin(t * TAU * frequency + phase) * amplitude
			y += sin(t * TAU * frequency * 2.7 + phase * 2.0) * amplitude * 0.35
			points.append(Vector2(size.x * t, size.y * y))
		points.append(Vector2(size.x, size.y))
		draw_colored_polygon(points, color)
