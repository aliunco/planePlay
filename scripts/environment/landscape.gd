class_name Landscape
extends Node2D
## Painted ground for the world. Nothing here moves by hand: the camera scrolls
## over static world coordinates, and the airplane flies above the flat surface.
##
## Draw order (all in world space):
##   ParallaxLayer / Hills   distant silhouettes (behind)
##   Landscape._draw()       the flat surface the planes take off from (front)
##   Scenery children        farms, houses, trees, props -> behind the surface,
##                           so only their silhouettes show above the horizon
##
## The surface is painted the way a diorama is staged: sunlit grass at the
## horizon, patchwork fields with furrows and hedges behind them, a road with
## guard posts, water with highlights, and a power line with sagging wires.

const HOUSE_SCENE: PackedScene = preload("res://scenes/environment/house.tscn")
const FARM_SCENE: PackedScene = preload("res://scenes/environment/farm.tscn")
const TREE_SCENE: PackedScene = preload("res://scenes/environment/tree.tscn")

const HOUSE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/environment/house_small.svg"),
	preload("res://assets/environment/house_farm.svg"),
]
const TREE_TEXTURES: Array[Texture2D] = [
	preload("res://assets/environment/tree_round.svg"),
	preload("res://assets/environment/tree_pine.svg"),
]
const WINDMILL_TEXTURE: Texture2D = preload("res://assets/environment/windmill.svg")

# Sunlit countryside palette: values stay close together so the ground reads as
# one soft surface instead of a set of bright blocks.
const GRASS := Color("8ec267")
const GRASS_TOP := Color("a4d478")
const GRASS_DEEP := Color("5f9a44")
const PASTURE := Color("a6cb7d")
const WHEAT := Color("d8c78d")
const GREEN_FIELD := Color("93bf6a")
const STUBBLE := Color("c9bd8b")
const HEDGE_DARK := Color("4c7c3d")
const HEDGE_LIGHT := Color("6d9f52")
const ROAD := Color("a9a79e")
const ROAD_SHOULDER := Color("c6c3b6")
const ROAD_EDGE := Color("c2c0b5")
const ROAD_DARK := Color("86857c")
const ROAD_DASH := Color("f6f4e8")
const WATER := Color("57a1d6")
const WATER_LIGHT := Color("8ccaf0")
const WATER_DEEP := Color("3f80b5")
const SHORE := Color("d9d3a8")
const FENCE_POST := Color("b59b73")
const FENCE_RAIL := Color("cbb68f")
const POLE := Color("8a7154")
const WIRE := Color("4b4a45")
const STRIP := Color("76a34f")
const STRIP_MARK := Color("f1f1e4")

@export var world_width: float = 3200.0
@export var ground_y: float = 0.0
@export var ground_depth: float = 240.0
@export var clear_zone_centers: Array[float] = [560.0, 2640.0]
@export var clear_zone_radius: float = 240.0
@export var generation_seed: int = 20261107

var _scenery: Node2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = generation_seed
	_scenery = $Scenery
	_generate_scenery()
	queue_redraw()


func configure(width: float, ground_line: float, depth: float, clears: Array[float]) -> void:
	world_width = width
	ground_y = ground_line
	ground_depth = depth
	clear_zone_centers = clears
	if _scenery != null:
		_generate_scenery()
	queue_redraw()


## Anchors a sprite by its bottom center so scaling keeps it planted on the
## horizon, whatever texture the generator picked.
func _anchor_bottom_center(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	sprite.centered = false
	sprite.offset = Vector2(-texture_size.x * 0.5, -texture_size.y)


## Adds the soft patch of shade that glues a sprite to the grass.
func _add_contact_shadow(sprite: Sprite2D, width_ratio: float = 0.72) -> void:
	if sprite.texture == null:
		return
	var texture_size := sprite.texture.get_size()
	var shadow := SceneryShadow.new()
	shadow.shadow_size = Vector2(texture_size.x * width_ratio, maxf(10.0, texture_size.y * 0.08))
	shadow.position = Vector2(texture_size.x * 0.5, 0.0)
	shadow.z_index = -1
	sprite.add_child(shadow)


# --- Scenery generation ------------------------------------------------------

func _generate_scenery() -> void:
	for child in _scenery.get_children():
		child.queue_free()

	_spawn_windmill(world_width * 0.5 + _rng.randf_range(-320.0, 320.0))

	# Two villages, each a small cluster of houses with trees around them.
	for i in 2:
		var village_x := world_width * (0.22 + 0.42 * float(i)) + _rng.randf_range(-160.0, 160.0)
		_spawn_village(village_x)

	# Farms spread over the rest of the map.
	for i in 4:
		var farm_x := _rng.randf_range(180.0, world_width - 180.0)
		if _is_clear_zone(farm_x):
			continue
		var farm: Sprite2D = FARM_SCENE.instantiate()
		farm.position = Vector2(farm_x, ground_y + _rng.randf_range(8.0, 34.0))
		farm.scale = Vector2.ONE * _rng.randf_range(0.5, 0.72)
		farm.z_index = -1
		_anchor_bottom_center(farm)
		_add_contact_shadow(farm, 0.8)
		_scenery.add_child(farm)

	for i in 38:
		var tree_x := _rng.randf_range(-60.0, world_width + 60.0)
		if _is_clear_zone(tree_x):
			continue
		var tree: Sprite2D = TREE_SCENE.instantiate()
		tree.texture = TREE_TEXTURES[_rng.randi_range(0, TREE_TEXTURES.size() - 1)]
		tree.position = Vector2(tree_x, ground_y + _rng.randf_range(10.0, 60.0))
		tree.scale = Vector2.ONE * _rng.randf_range(0.42, 0.78)
		tree.flip_h = _rng.randf() > 0.5
		tree.z_index = -1
		_anchor_bottom_center(tree)
		_add_contact_shadow(tree, 0.5)
		_scenery.add_child(tree)

	# Countryside clutter: hay bales near the fields, bushes and boulders between.
	for i in 5:
		_spawn_prop(SceneryProp.Kind.HAY, _rng.randf_range(120.0, world_width - 120.0), _rng.randf_range(0.7, 1.0))
	for i in 8:
		_spawn_prop(SceneryProp.Kind.BUSH, _rng.randf_range(80.0, world_width - 80.0), _rng.randf_range(0.7, 1.15))
	for i in 5:
		_spawn_prop(SceneryProp.Kind.ROCK, _rng.randf_range(80.0, world_width - 80.0), _rng.randf_range(0.6, 1.0))


func _spawn_prop(kind: SceneryProp.Kind, x: float, scale_value: float) -> void:
	if _is_clear_zone(x):
		return
	var prop := SceneryProp.new()
	prop.kind = kind
	prop.size_scale = scale_value
	prop.position = Vector2(x, ground_y + _rng.randf_range(12.0, 54.0))
	prop.z_index = -1
	_scenery.add_child(prop)


func _spawn_village(center_x: float) -> void:
	var count := _rng.randi_range(3, 5)
	for i in count:
		var offset_x := (float(i) - float(count - 1) * 0.5) * 92.0 + _rng.randf_range(-22.0, 22.0) + center_x
		if _is_clear_zone(offset_x):
			continue
		var house: Sprite2D = HOUSE_SCENE.instantiate()
		house.texture = HOUSE_TEXTURES[_rng.randi_range(0, HOUSE_TEXTURES.size() - 1)]
		house.position = Vector2(offset_x, ground_y + _rng.randf_range(6.0, 40.0))
		house.scale = Vector2.ONE * _rng.randf_range(0.46, 0.68)
		house.flip_h = _rng.randf() > 0.5
		house.z_index = -1
		_anchor_bottom_center(house)
		_add_contact_shadow(house, 0.78)
		_scenery.add_child(house)


func _spawn_windmill(x: float) -> void:
	if _is_clear_zone(x):
		return
	var windmill := Sprite2D.new()
	windmill.texture = WINDMILL_TEXTURE
	windmill.centered = false
	windmill.offset = Vector2(-42.0, -152.0)
	windmill.position = Vector2(x, ground_y + 18.0)
	windmill.scale = Vector2.ONE * 0.8
	windmill.z_index = -2
	_add_contact_shadow(windmill, 0.45)
	_scenery.add_child(windmill)


func _is_clear_zone(x: float) -> bool:
	for center: float in clear_zone_centers:
		if absf(x - center) < clear_zone_radius:
			return true
	return false


# --- Ground painting ---------------------------------------------------------

func _draw() -> void:
	var left := -220.0
	var width := world_width + 440.0
	var top := ground_y
	var bottom := ground_y + ground_depth

	_draw_grass(left, width, top, bottom)
	_draw_fields(left, width, top, bottom)
	_draw_haze(left, width, top)
	_draw_power_line(left, width, top)
	_draw_road(left, width, top)
	_draw_water(top, bottom)
	_draw_fence(left, width, top)
	_draw_tufts(left, width, top)
	_draw_runways(top)
	_draw_horizon_light(left, width, top)


## Sunlit band at the horizon, cooling into a deeper green further back.
func _draw_grass(left: float, width: float, top: float, bottom: float) -> void:
	draw_rect(Rect2(left, top, width, bottom - top), GRASS)
	draw_rect(Rect2(left, top, width, 15.0), GRASS_TOP)
	for i in 9:
		var t := float(i) / 8.0
		draw_rect(
			Rect2(left, top + 66.0 + t * 96.0, width, 16.0),
			Color(GRASS_DEEP, 0.10)
		)


## Patchwork fields seen across, not from above: every field's furrows converge on
## a vanishing point above the horizon, the rows near the viewer open out, and the
## hedge between two fields throws a shadow across the one beside it. Together
## with the darker bands at the bottom this is what gives the flat surface depth.
func _draw_fields(left: float, width: float, top: float, bottom: float) -> void:
	var field_rng := RandomNumberGenerator.new()
	field_rng.seed = generation_seed + 7
	var palette := [PASTURE, WHEAT, GREEN_FIELD, STUBBLE]
	var depth := bottom - top
	var x := left - 60.0
	while x < left + width:
		var field_width := field_rng.randf_range(200.0, 430.0)
		var color: Color = palette[field_rng.randi_range(0, palette.size() - 1)]
		var field := Rect2(x + 7.0, top, field_width - 14.0, depth)
		draw_rect(field, color)

		# Furrows running away from the viewer: each one fans in toward a point
		# above the field, so the spacing tightens with distance.
		var rows := maxi(4, int(field.size.x / 17.0))
		for row in rows:
			var t := (float(row) + 0.5) / float(rows)
			var foot_x := field.position.x + t * field.size.x
			var head_x := field.get_center().x + (foot_x - field.get_center().x) * 0.58
			var tone := color.darkened(0.06 if row % 2 == 0 else 0.022)
			draw_line(Vector2(head_x, top + 3.0), Vector2(foot_x, bottom), tone, 2.0)

		# Depth shading: the far end of the field hazes out, the near end sits in
		# a little of its own weight.
		for step in 5:
			var shade_y := top + depth * (0.18 + 0.18 * float(step))
			draw_rect(
				Rect2(field.position.x, shade_y, field.size.x, 2.0), Color(0.0, 0.0, 0.0, 0.035)
			)
		# A crest catching the sun along the top edge.
		draw_rect(Rect2(field.position.x, top, field.size.x, 3.0), color.lightened(0.09))
		draw_rect(Rect2(field.position.x, top + 3.0, field.size.x, 2.0), Color(1.0, 1.0, 0.9, 0.05))

		_draw_hedge(x, top, bottom)
		# The hedge's shadow falls into the field on its right.
		for shadow_step in 4:
			draw_rect(
				Rect2(x + 9.0 + float(shadow_step) * 3.0, top, 3.0, depth),
				Color(0.05, 0.12, 0.04, 0.05)
			)
		x += field_width


## Aerial perspective: the far edge of the ground dissolves into the air above it,
## so the fields do not simply stop at a hard line under the hills.
func _draw_haze(left: float, width: float, top: float) -> void:
	for i in 7:
		var t := float(i) / 6.0
		draw_rect(
			Rect2(left, top + t * 24.0, width, 6.0), Color(0.9, 0.95, 1.0, 0.055 * (1.0 - t))
		)


## A clipped hedge between two fields: a dark column with leafy bumps.
func _draw_hedge(x: float, top: float, bottom: float) -> void:
	draw_rect(Rect2(x, top, 9.0, bottom - top), HEDGE_DARK)
	var y := top + 3.0
	var bump := 0
	while y < bottom:
		var radius := 5.5 + 2.2 * sin(float(bump) * 1.9)
		var shade := HEDGE_LIGHT if bump % 2 == 0 else HEDGE_DARK
		draw_circle(Vector2(x + 4.5, y), radius, shade)
		y += 9.0
		bump += 1


## Telegraph poles and their sagging wires, standing just beyond the road.
func _draw_power_line(left: float, width: float, top: float) -> void:
	var spacing := 470.0
	var foot_y := top + 64.0
	var pole_height := 98.0
	var head_y := foot_y - pole_height
	var poles: Array[float] = []
	var x := left + 190.0
	while x < left + width:
		poles.append(x)
		x += spacing

	for px: float in poles:
		draw_rect(Rect2(px - 2.0, head_y, 4.0, pole_height), POLE)
		draw_rect(Rect2(px - 14.0, head_y + 11.0, 28.0, 3.0), POLE)
		draw_circle(Vector2(px - 11.0, head_y + 10.0), 2.4, Color("e8e2d2"))
		draw_circle(Vector2(px + 11.0, head_y + 10.0), 2.4, Color("e8e2d2"))

	for i in poles.size() - 1:
		for offset in [-11.0, 11.0]:
			_wire(
				Vector2(poles[i] + offset, head_y + 10.0),
				Vector2(poles[i + 1] + offset, head_y + 10.0)
			)


func _wire(from: Vector2, to: Vector2) -> void:
	var points := PackedVector2Array()
	var steps := 10
	for i in steps + 1:
		var t := float(i) / float(steps)
		var sag := sin(t * PI) * 7.0
		points.append(Vector2(lerpf(from.x, to.x, t), lerpf(from.y, to.y, t) + sag))
	draw_polyline(points, WIRE, 1.4, true)


func _draw_road(left: float, width: float, top: float) -> void:
	var road_y := top + 96.0
	draw_rect(Rect2(left, road_y - 5.0, width, 54.0), ROAD_SHOULDER)
	draw_rect(Rect2(left, road_y, width, 44.0), ROAD)
	draw_rect(Rect2(left, road_y, width, 3.0), ROAD_EDGE)
	draw_rect(Rect2(left, road_y + 41.0, width, 3.0), ROAD_DARK)

	var dash_x := left
	while dash_x < left + width:
		draw_rect(Rect2(dash_x, road_y + 20.0, 46.0, 5.0), ROAD_DASH)
		dash_x += 94.0

	# Little red-capped guard posts along the verge.
	var post_x := left + 70.0
	while post_x < left + width:
		draw_rect(Rect2(post_x, road_y - 15.0, 4.0, 13.0), Color("efe9d8"))
		draw_rect(Rect2(post_x, road_y - 15.0, 4.0, 4.0), Color("d4553f"))
		post_x += 310.0


func _draw_water(top: float, bottom: float) -> void:
	var water_rng := RandomNumberGenerator.new()
	water_rng.seed = generation_seed + 31

	# A lake, drawn as a wobbly polygon with a sandy shore and two highlights.
	var center := Vector2(world_width * 0.62, top + 44.0)
	var outline := PackedVector2Array()
	var shore_outline := PackedVector2Array()
	var steps := 26
	for i in steps:
		var angle := float(i) / float(steps) * TAU
		var radius := 62.0 + 12.0 * sin(angle * 3.0 + 0.7) + 7.0 * sin(angle * 5.0 + 2.1)
		var point := center + Vector2(cos(angle) * radius * 1.45, sin(angle) * radius * 0.55)
		outline.append(point)
		shore_outline.append(center + (point - center) * 1.08)
	draw_colored_polygon(shore_outline, SHORE)
	draw_colored_polygon(outline, WATER)
	draw_circle(center + Vector2(-24.0, 4.0), 26.0, WATER_LIGHT)
	draw_circle(center + Vector2(30.0, -4.0), 17.0, Color(WATER_LIGHT, 0.7))
	for i in 5:
		var t := float(i) / 4.0
		var line_y := center.y + 10.0 + t * 18.0
		var line_w := 62.0 - t * 30.0
		draw_line(
			Vector2(center.x - line_w * 0.5, line_y),
			Vector2(center.x + line_w * 0.5, line_y),
			Color(1.0, 1.0, 1.0, 0.28),
			2.0
		)

	# A river crossing the ground band, with banks and glinting ripples.
	var river_x := world_width * 0.3
	var river_points := PackedVector2Array()
	for i in 11:
		var t := float(i) / 10.0
		river_points.append(Vector2(river_x + sin(t * 6.0) * 26.0, top - 6.0 + t * (bottom - top + 12.0)))
	draw_polyline(river_points, SHORE, 44.0, true)
	draw_polyline(river_points, WATER, 34.0, true)
	draw_polyline(river_points, WATER_LIGHT, 18.0, true)
	for i in 9:
		var t := float(i) / 9.0
		var index := int(t * float(river_points.size() - 1))
		var point := river_points[index]
		var width := water_rng.randf_range(8.0, 18.0)
		draw_line(
			Vector2(point.x - width * 0.5, point.y + 6.0),
			Vector2(point.x + width * 0.5, point.y + 6.0),
			Color(1.0, 1.0, 1.0, 0.35),
			2.0
		)


func _draw_fence(left: float, width: float, top: float) -> void:
	var fence_x := left
	var index := 0
	while fence_x < left + width:
		var post_height := 25.0 + 2.0 * sin(float(index) * 0.9)
		draw_rect(Rect2(fence_x, top + 44.0, 6.0, post_height), FENCE_POST)
		draw_rect(Rect2(fence_x, top + 44.0, 6.0, 3.0), FENCE_RAIL)
		fence_x += 44.0
		index += 1
	draw_rect(Rect2(left, top + 50.0, width, 4.0), FENCE_RAIL)
	draw_rect(Rect2(left, top + 62.0, width, 3.0), Color(FENCE_RAIL, 0.8))


func _draw_tufts(left: float, width: float, top: float) -> void:
	var tuft_rng := RandomNumberGenerator.new()
	tuft_rng.seed = generation_seed + 13
	for i in 300:
		var tuft_x := left + tuft_rng.randf() * width
		var tuft_height := tuft_rng.randf_range(4.0, 13.0)
		var lean := tuft_rng.randf_range(-3.5, 3.5)
		var color := Color("6ea84a") if i % 3 != 0 else Color("87bd5f")
		draw_line(
			Vector2(tuft_x, top + 3.0),
			Vector2(tuft_x + lean, top - tuft_height),
			color,
			2.0
		)


## Worn take-off strips with threshold bars, a worn centreline and skid marks.
func _draw_runways(top: float) -> void:
	for center: float in clear_zone_centers:
		draw_rect(Rect2(center - 190.0, top, 380.0, 17.0), STRIP)
		draw_rect(Rect2(center - 190.0, top + 15.0, 380.0, 3.0), Color(0.0, 0.0, 0.0, 0.10))
		# Threshold bars marching in from both ends.
		for side: float in [-1.0, 1.0]:
			for i in 4:
				var bar_x: float = center + side * (172.0 - float(i) * 13.0)
				draw_rect(Rect2(bar_x - 4.5, top + 5.0, 9.0, 8.0), STRIP_MARK)
		# Centreline dashes and the twin tyre tracks they wear.
		for i in 6:
			draw_rect(Rect2(center - 120.0 + float(i) * 42.0, top + 10.0, 24.0, 3.0), STRIP_MARK)
		draw_line(Vector2(center - 150.0, top + 8.0), Vector2(center + 150.0, top + 8.0), Color(0.15, 0.2, 0.1, 0.10), 3.0)
		draw_line(Vector2(center - 150.0, top + 13.0), Vector2(center + 150.0, top + 13.0), Color(0.15, 0.2, 0.1, 0.10), 3.0)


## Warm light spilling over the horizon line so the ground meets the hills softly.
func _draw_horizon_light(left: float, width: float, top: float) -> void:
	for i in 6:
		var t := float(i) / 5.0
		draw_rect(
			Rect2(left, top - 22.0 + t * 4.0, width, 7.0),
			Color(1.0, 0.91, 0.76, 0.05 * (1.0 - t))
		)
