class_name GroundDepth
extends Node2D
## The near ground: bands of real countryside drawn in front of the painted
## landscape, each sliding at its own rate as the camera travels. That difference
## in rate is the whole trick — distinct objects (bales, rocks, bushes, fence
## posts, big fern fans) whip past the camera at different speeds, so the flat
## strip at the bottom of the frame stops reading as a stripe and starts reading
## as ground the camera is flying over, while everything the game touches (the
## ground line, the runway, the soldiers, the plane shadows) stays exactly where
## it was.
##
## Both bands are tied to the world, not the screen: they are drawn in world space
## so the day/night tint and the camera zoom apply to them like everything else.
## Their content is generated per tile from the tile index, so the strip never
## visibly repeats and never pops as it slides.

## Width of one tile of detail. Tiles are generated from their index, so no two
## are alike.
const VERGE_TILE: float = 300.0
const FOREGROUND_TILE: float = 420.0
## Where each band starts below the ground line.
const VERGE_TOP: float = 142.0
const FOREGROUND_TOP: float = 196.0
## How much faster than the world each band travels. The jump from 1.38 to 2.15
## is what sells the depth: the near silhouette overtakes the verge, which in
## turn overtakes the fields behind both.
const VERGE_PARALLAX: float = 1.38
const FOREGROUND_PARALLAX: float = 2.15

const VERGE_DIRT := Color("8a7c52")
const VERGE_GRASS := Color("4f7c39")
const VERGE_GRASS_DARK := Color("3d6630")
const VERGE_LIGHT := Color("6fa04b")
const FLOWER: Array[Color] = [Color("f2e071"), Color("f0f0e6"), Color("e8879b")]
const STONE := Color("8b8a7d")
const BUSH_DARK := Color("33562a")
const BUSH_LIGHT := Color("4b753a")
const BALE := Color("c8a95e")
const BALE_DARK := Color("a98a44")
const BARK := Color("6b5334")
const FOREGROUND_BLADE := Color(0.11, 0.20, 0.11, 0.95)
const FOREGROUND_BLADE_LIGHT := Color(0.16, 0.27, 0.14, 0.92)
const FOREGROUND_ROCK := Color(0.10, 0.16, 0.11, 0.96)
const FOREGROUND_ROCK_LIGHT := Color(0.17, 0.24, 0.16, 0.95)
const FENCE_POST := Color("a98d63")

@export var ground_y: float = 0.0
@export var world_width: float = 3200.0


func configure(ground_line: float, width: float) -> void:
	ground_y = ground_line
	world_width = width
	queue_redraw()


func _ready() -> void:
	# In front of the planes and the effects, behind the interface.
	z_index = 5


## How far a band slides at a given camera position. The band's content is drawn
## at world x plus this shift, so a band that travels at `parallax` times the
## world's rate ends up ahead of it by the difference. Exposed so the parallax
## itself can be checked without reading pixels.
static func slide_offset(camera_x: float, parallax: float, tile: float) -> float:
	return -fposmod((parallax - 1.0) * camera_x, tile)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		return
	var centre := camera.get_screen_center_position()
	var zoom := maxf(0.01, camera.zoom.y)
	var half := get_viewport_rect().size * 0.5 / zoom
	var view_left := centre.x - half.x
	var view_right := centre.x + half.x
	var visible_bottom := centre.y + half.y
	var world_bottom := ground_y + 288.0
	var bottom := minf(visible_bottom, world_bottom)
	if bottom <= ground_y + VERGE_TOP + 2.0:
		return

	_draw_verge(centre.x, view_left, view_right, bottom)
	if bottom > ground_y + FOREGROUND_TOP + 2.0:
		_draw_foreground(centre.x, view_left, view_right, bottom)


## The near verge: the strip of rougher grass just past the road, carrying the
## things you would find there — bales left in the field, boulders, bushes,
## saplings, a fence line and a worn track. It overtakes the fields behind it.
func _draw_verge(camera_x: float, view_left: float, view_right: float, bottom: float) -> void:
	var top := ground_y + VERGE_TOP
	var offset := slide_offset(camera_x, VERGE_PARALLAX, VERGE_TILE)
	var width := view_right - view_left + 80.0
	var left := view_left - 40.0

	# The band itself, with a soft lip so the transition from the fields reads as
	# a change of ground rather than a stripe.
	draw_rect(Rect2(left, top, width, bottom - top), VERGE_GRASS)
	draw_rect(Rect2(left, top, width, 4.0), Color(VERGE_GRASS_DARK, 0.85))
	draw_rect(Rect2(left, top + 4.0, width, 3.0), Color(VERGE_LIGHT, 0.35))
	for i in 3:
		var t := float(i) / 2.0
		draw_rect(
			Rect2(left, top + 8.0 + t * 12.0, width, 6.0), Color(VERGE_GRASS_DARK, 0.10)
		)

	# A worn farm track running through the band, kept soft so it is a track in the
	# grass rather than a stripe across the screen.
	var track_y := top + 44.0
	if track_y + 18.0 < bottom:
		draw_rect(Rect2(left, track_y, width, 11.0), Color(VERGE_DIRT, 0.42))
		draw_rect(Rect2(left, track_y, width, 2.0), Color(1.0, 1.0, 1.0, 0.10))
		draw_rect(Rect2(left, track_y + 9.0, width, 3.0), Color(VERGE_GRASS_DARK, 0.25))

	var first := floori((view_left - VERGE_TILE - offset) / VERGE_TILE)
	var last := ceili((view_right + VERGE_TILE - offset) / VERGE_TILE)
	for index in range(first, last + 1):
		_draw_verge_tile(float(index) * VERGE_TILE + offset, index, top, bottom, track_y)


func _draw_verge_tile(base_x: float, index: int, top: float, bottom: float, track_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("verge") + index * 7919
	var span := maxf(26.0, bottom - top - 8.0)

	# Low bushes: the most legible thing in the band, so the verge visibly slides.
	for i in rng.randi_range(1, 2):
		var bush_x := base_x + rng.randf_range(20.0, VERGE_TILE - 20.0)
		var bush_y := top + rng.randf_range(14.0, minf(46.0, span))
		var bush_r := rng.randf_range(9.0, 17.0)
		draw_circle(Vector2(bush_x, bush_y), bush_r, BUSH_DARK)
		for lobe in 3:
			var lobe_x := bush_x + float(lobe - 1) * bush_r * 0.55
			draw_circle(
				Vector2(lobe_x, bush_y - bush_r * 0.38), bush_r * 0.62, BUSH_LIGHT
			)
		draw_circle(
			Vector2(bush_x, bush_y - bush_r * 0.55), bush_r * 0.34, Color(VERGE_LIGHT, 0.55)
		)

	# Tall grass clumps along the band.
	for i in 7:
		var x := base_x + rng.randf() * VERGE_TILE
		var height := rng.randf_range(10.0, 26.0)
		var lean := rng.randf_range(-7.0, 7.0)
		var foot := top + rng.randf_range(12.0, span)
		var shade := VERGE_LIGHT if i % 3 == 0 else VERGE_GRASS_DARK
		for blade in 3:
			var spread := float(blade - 1) * 5.0
			draw_line(
				Vector2(x + spread, foot),
				Vector2(x + spread + lean, foot - height * (0.7 + 0.3 * float(blade % 2))),
				shade,
				2.2,
				true
			)

	# Stones and flowers, so it is a place rather than a texture.
	for i in 3:
		var x := base_x + rng.randf() * VERGE_TILE
		var y := top + rng.randf_range(16.0, minf(70.0, span))
		var w := rng.randf_range(3.5, 8.0)
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(x - w, y),
					Vector2(x - w * 0.4, y - w * 0.85),
					Vector2(x + w * 0.5, y - w * 0.7),
					Vector2(x + w, y),
				]
			),
			Color(STONE, 0.9)
		)
		draw_line(Vector2(x - w, y), Vector2(x + w, y), Color(0.25, 0.28, 0.24, 0.5), 1.0)
		draw_line(Vector2(x, y), Vector2(x - w * 0.2, y - w * 0.7), Color(1, 1, 1, 0.25), 1.0)
	for i in 4:
		var x := base_x + rng.randf() * VERGE_TILE
		var y := top + rng.randf_range(10.0, minf(44.0, span))
		var petal: Color = FLOWER[rng.randi() % FLOWER.size()]
		draw_circle(Vector2(x, y), 2.2, petal)
		draw_circle(Vector2(x, y), 1.0, Color(0.98, 0.85, 0.4, 0.95))

	# A straw bale left in the grass, on every third tile.
	if index % 3 == 1:
		var x := base_x + rng.randf_range(30.0, VERGE_TILE - 60.0)
		var y := top + rng.randf_range(24.0, minf(52.0, span))
		draw_rect(Rect2(x, y - 15.0, 42.0, 17.0), BALE)
		draw_rect(Rect2(x, y - 15.0, 42.0, 5.0), BALE_DARK)
		draw_rect(Rect2(x, y - 2.0, 42.0, 4.0), Color(0.15, 0.20, 0.10, 0.25))
		for strand in 5:
			draw_line(
				Vector2(x + 5.0 + float(strand) * 8.0, y - 14.0),
				Vector2(x + 3.0 + float(strand) * 8.0, y),
				Color(0.42, 0.34, 0.16, 0.5),
				1.2
			)

	# A sapling standing in the verge, on every fifth tile.
	if index % 5 == 2:
		var x := base_x + rng.randf_range(50.0, VERGE_TILE - 50.0)
		var y := top + rng.randf_range(20.0, minf(50.0, span))
		var trunk := rng.randf_range(16.0, 24.0)
		draw_line(Vector2(x, y), Vector2(x + 3.0, y - trunk), BARK, 3.0, true)
		for lobe in 3:
			draw_circle(
				Vector2(x + 3.0 + float(lobe - 1) * 7.0, y - trunk - 5.0 + float(lobe) * 2.0),
				rng.randf_range(8.0, 11.0),
				BUSH_DARK
			)

	# Every other tile carries a fence post, with the wire sagging between them.
	if index % 2 == 0:
		var x := base_x + VERGE_TILE * 0.35
		var post_top := top + 2.0
		var post_bottom := track_y + 6.0
		draw_rect(Rect2(x - 2.5, post_top, 5.0, post_bottom - post_top), FENCE_POST)
		draw_rect(Rect2(x - 2.5, post_top, 5.0, 3.0), Color(1.0, 1.0, 1.0, 0.35))
		draw_line(
			Vector2(x + 2.5, post_top + 12.0),
			Vector2(x + VERGE_TILE * 0.5, post_top + 17.0),
			Color(0.32, 0.30, 0.26, 0.65),
			1.2
		)


## The closest band: near-black silhouettes that frame the bottom of the shot.
## Oversized fern fans, boulders and grass, travelling more than twice as fast as
## the world, so the nearest things on screen sweep past while the landscape
## barely creeps.
func _draw_foreground(camera_x: float, view_left: float, view_right: float, bottom: float) -> void:
	var top := ground_y + FOREGROUND_TOP
	var offset := slide_offset(camera_x, FOREGROUND_PARALLAX, FOREGROUND_TILE)

	# The band's top edge undulates, so it reads as the heaped lip of a bank rather
	# than a stripe drawn across the screen. The wave rides the tile offset, so it
	# travels with the band like the rest of its detail.
	var fringe := Color(0.10, 0.18, 0.10, 0.68)
	var wave := PackedVector2Array()
	var wave_x := view_left - 60.0
	while wave_x <= view_right + 60.0:
		var phase := (wave_x - offset) * 0.045
		var lift := sin(phase) * 9.0 + sin(phase * 0.37 + 1.2) * 6.0
		wave.append(Vector2(wave_x, top + lift))
		wave_x += 16.0
	wave.append(Vector2(view_right + 60.0, bottom + 30.0))
	wave.append(Vector2(view_left - 60.0, bottom + 30.0))
	draw_colored_polygon(wave, fringe)

	var first := floori((view_left - FOREGROUND_TILE - offset) / FOREGROUND_TILE)
	var last := ceili((view_right + FOREGROUND_TILE - offset) / FOREGROUND_TILE)
	for index in range(first, last + 1):
		var base_x := float(index) * FOREGROUND_TILE + offset
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("foreground") + index * 6151

		# Big blades, drawn from the bottom of the band upward.
		for i in 12:
			var x := base_x + rng.randf() * FOREGROUND_TILE
			var height := rng.randf_range(38.0, 92.0)
			var width := rng.randf_range(4.0, 9.0)
			var lean := rng.randf_range(-30.0, 30.0)
			var color := FOREGROUND_BLADE if i % 3 != 0 else FOREGROUND_BLADE_LIGHT
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(x - width * 0.5, bottom + 6.0),
						Vector2(x + width * 0.5, bottom + 6.0),
						Vector2(x + lean, bottom - height),
					]
				),
				color
			)

		# A fern fan: the reading "close plant" that makes the sweep obvious.
		if index % 2 == 0:
			var fan_x := base_x + rng.randf_range(40.0, FOREGROUND_TILE - 40.0)
			var fan_y := bottom + 4.0
			for leaf in 6:
				var angle := -PI * 0.5 + (float(leaf) - 2.5) * 0.34
				var reach := rng.randf_range(34.0, 66.0)
				var tip := Vector2(fan_x + cos(angle) * reach, fan_y + sin(angle) * reach)
				draw_line(Vector2(fan_x, fan_y), tip, FOREGROUND_BLADE, 4.0, true)
				for pinna in 3:
					var along := 0.55 + float(pinna) * 0.16
					var point := Vector2(fan_x, fan_y).lerp(tip, along)
					draw_circle(point, 3.0 - float(pinna) * 0.5, FOREGROUND_BLADE_LIGHT)

		# A boulder every third tile, so there is something with a solid silhouette.
		if index % 3 == 1:
			var rock_x := base_x + rng.randf_range(60.0, FOREGROUND_TILE - 60.0)
			var rock_r := rng.randf_range(16.0, 30.0)
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(rock_x - rock_r, bottom + 6.0),
						Vector2(rock_x - rock_r * 0.75, bottom - rock_r * 0.9),
						Vector2(rock_x - rock_r * 0.1, bottom - rock_r * 1.25),
						Vector2(rock_x + rock_r * 0.6, bottom - rock_r * 1.0),
						Vector2(rock_x + rock_r, bottom + 6.0),
					]
				),
				FOREGROUND_ROCK
			)
			draw_colored_polygon(
				PackedVector2Array(
					[
						Vector2(rock_x - rock_r * 0.1, bottom - rock_r * 1.25),
						Vector2(rock_x + rock_r * 0.6, bottom - rock_r * 1.0),
						Vector2(rock_x + rock_r * 0.2, bottom - rock_r * 0.55),
					]
				),
				FOREGROUND_ROCK_LIGHT
			)
