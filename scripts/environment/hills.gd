class_name HillSilhouettes
extends Node2D
## Distant hill ridges behind the landscape. Three stacked layers, each one
## darker and closer than the one behind it, with warm haze pooling at the
## horizon, so the flat world reads as depth instead of one green wall.

@export var world_width: float = 3200.0
@export var ground_y: float = 0.0
@export var generation_seed: int = 4242

const STEP: float = 22.0

## Back to front: (color, height in px, wave frequency, phase, base depth below
## the ground line). Ridges are sampled from summed sines, so they roll instead
## of zig-zagging.
const LAYERS: Array[Dictionary] = [
	{
		"color": Color("b3c8cf"),
		"height": 360.0,
		"freq": 0.0024,
		"phase": 0.4,
		"depth": 150.0,
	},
	{
		"color": Color("8db3a9"),
		"height": 258.0,
		"freq": 0.0037,
		"phase": 2.1,
		"depth": 84.0,
	},
	{
		"color": Color("6f9f85"),
		"height": 182.0,
		"freq": 0.0051,
		"phase": 4.3,
		"depth": 30.0,
	},
]


var _haze: GradientTexture2D


func _ready() -> void:
	_haze = _build_haze()


func configure(width: float, ground_line: float) -> void:
	world_width = width
	ground_y = ground_line
	queue_redraw()


func _draw() -> void:
	for layer: Dictionary in LAYERS:
		_draw_ridge(layer)
	_draw_haze()


## One ridge: a smooth crest line with its valleys filled down past the ground
## line, so no sky can ever show through between hills and field.
func _draw_ridge(layer: Dictionary) -> void:
	var color: Color = layer["color"]
	var height: float = layer["height"]
	var freq: float = layer["freq"]
	var phase: float = layer["phase"]
	var base_y: float = ground_y + float(layer["depth"])

	var points := PackedVector2Array([Vector2(-420.0, ground_y + 520.0)])
	var x := -420.0
	while x <= world_width + 420.0:
		var wave := (
			0.52
			+ 0.30 * sin(x * freq + phase)
			+ 0.13 * sin(x * freq * 2.7 + phase * 1.6)
			+ 0.07 * sin(x * freq * 6.1 + phase * 2.2)
		)
		points.append(Vector2(x, base_y - height * wave))
		x += STEP
	points.append(Vector2(world_width + 420.0, ground_y + 520.0))
	draw_colored_polygon(points, color)


## Warm air settles into the valleys right above the horizon. A vertical
## gradient texture keeps the transition smooth (stacked bands showed seams).
func _draw_haze() -> void:
	if _haze == null:
		return
	draw_texture_rect(
		_haze,
		Rect2(-420.0, ground_y - 210.0, world_width + 840.0, 210.0),
		false
	)


func _build_haze() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray(
		[Color(1.0, 0.96, 0.88, 0.0), Color(1.0, 0.94, 0.84, 0.05), Color(1.0, 0.90, 0.76, 0.16)]
	)
	var texture_2d := GradientTexture2D.new()
	texture_2d.gradient = gradient
	texture_2d.width = 8
	texture_2d.height = 256
	texture_2d.fill_from = Vector2(0.0, 0.0)
	texture_2d.fill_to = Vector2(0.0, 1.0)
	return texture_2d
