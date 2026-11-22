class_name SceneryProp
extends Node2D
## Small procedural countryside props - hay bales, bushes and rocks - drawn from
## primitives so the fields have life without shipping more textures. Each prop
## paints its own contact shadow.

enum Kind { HAY, BUSH, ROCK }

@export var kind: Kind = Kind.HAY
@export var size_scale: float = 1.0
@export var tint: Color = Color.WHITE


func _draw() -> void:
	scale = Vector2.ONE * size_scale
	match kind:
		Kind.HAY:
			_draw_hay()
		Kind.BUSH:
			_draw_bush()
		Kind.ROCK:
			_draw_rock()


func _draw_shadow(width: float, alpha: float = 0.22) -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(width * 0.5, 1.0))
	draw_circle(Vector2(0.0, 0.0), width * 0.11, Color(0.09, 0.17, 0.09, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A round bale lying on the grass: warm straw with two binding bands.
func _draw_hay() -> void:
	_draw_shadow(52.0)
	var straw := Color("dcc07b").lerp(tint, 0.15)
	var shade := Color("bd9d5c")
	draw_rect(Rect2(-24.0, -22.0, 48.0, 22.0), straw)
	draw_circle(Vector2(-24.0, -11.0), 11.0, straw)
	draw_circle(Vector2(24.0, -11.0), 11.0, straw)
	draw_rect(Rect2(-24.0, -3.0, 48.0, 3.0), shade)
	draw_circle(Vector2(-24.0, -11.0), 7.0, shade.lightened(0.10))
	draw_circle(Vector2(24.0, -11.0), 7.0, shade.lightened(0.10))
	for band_x in [-9.0, 9.0]:
		draw_rect(Rect2(band_x, -22.0, 2.5, 22.0), Color("a98b4f"))


## A low leafy bush: a few overlapping lobes in two greens.
func _draw_bush() -> void:
	_draw_shadow(46.0)
	var dark := Color("4d7f3e")
	var light := Color("6b9d51")
	draw_circle(Vector2(-11.0, -10.0), 12.0, dark)
	draw_circle(Vector2(9.0, -9.0), 13.0, dark)
	draw_circle(Vector2(-1.0, -16.0), 12.0, light)
	draw_circle(Vector2(-14.0, -14.0), 8.0, light)
	draw_circle(Vector2(12.0, -14.0), 7.0, light)


## A weathered boulder with a lit top face.
func _draw_rock() -> void:
	_draw_shadow(34.0, 0.20)
	var body := Color("9a9a92")
	var light := Color("b6b6ac")
	var dark := Color("7c7c74")
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-16.0, 0.0),
				Vector2(-13.0, -13.0),
				Vector2(-3.0, -20.0),
				Vector2(10.0, -17.0),
				Vector2(16.0, -6.0),
				Vector2(14.0, 0.0),
			]
		),
		body
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-11.0, -13.0),
				Vector2(-3.0, -19.0),
				Vector2(7.0, -16.0),
				Vector2(-1.0, -10.0),
			]
		),
		light
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(14.0, -6.0),
				Vector2(16.0, -6.0),
				Vector2(14.0, 0.0),
				Vector2(7.0, 0.0),
			]
		),
		dark
	)
