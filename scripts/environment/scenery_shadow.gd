class_name SceneryShadow
extends Node2D
## Soft contact shadow under a piece of scenery, so houses, farms, trees and
## windmills sit on the grass instead of floating above it.

@export var shadow_size: Vector2 = Vector2(64.0, 16.0)
@export var shadow_color: Color = Color(0.09, 0.18, 0.10, 0.26)


func _draw() -> void:
	var squash := shadow_size.x / maxf(shadow_size.y, 1.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(squash, 1.0))
	for i in 3:
		var t := float(i) / 2.0
		draw_circle(
			Vector2.ZERO,
			shadow_size.y * lerpf(1.0, 0.5, t),
			Color(shadow_color, shadow_color.a * 0.55)
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
