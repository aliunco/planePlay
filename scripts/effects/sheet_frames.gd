class_name SheetFrames
extends RefCounted
## Builds `SpriteFrames` from a horizontal-strip sprite sheet.
##
## The game's sheets are single rows of equally sized cells (the soldier sheet
## is two rows, see SoldierField). Every animation is described by the indices
## of the cells it plays, so one sheet can back several animations without any
## per-frame resource files.


## `specs` is an array of dictionaries. Frames are either strip columns or
## explicit (column, row) cells:
##   { "name": StringName, "frames": Array[int], "fps": float, "loop": bool }
##   { "name": StringName, "cells": Array[Vector2i], "fps": float, "loop": bool }
static func build(sheet: Texture2D, cell: Vector2i, specs: Array) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if sheet == null:
		return frames
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")

	for spec in specs:
		var name: StringName = spec.get("name", &"default")
		if not frames.has_animation(name):
			frames.add_animation(name)
		frames.set_animation_speed(name, float(spec.get("fps", 10.0)))
		frames.set_animation_loop(name, bool(spec.get("loop", true)))
		for index in spec.get("frames", []):
			frames.add_frame(name, cell_texture(sheet, cell, int(index)))
		for cell_pos in spec.get("cells", []):
			var at: Vector2i = cell_pos
			frames.add_frame(name, grid_texture(sheet, cell, at.x, at.y))
	return frames


## One cell of a strip sheet, addressed by its column (left to right).
static func cell_texture(sheet: Texture2D, cell: Vector2i, index: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = Rect2(Vector2(index * cell.x, 0.0), Vector2(cell))
	return texture


## One cell of a grid sheet, addressed by row and column.
static func grid_texture(sheet: Texture2D, cell: Vector2i, column: int, row: int) -> AtlasTexture:
	var texture := AtlasTexture.new()
	texture.atlas = sheet
	texture.region = Rect2(Vector2(column * cell.x, row * cell.y), Vector2(cell))
	return texture
