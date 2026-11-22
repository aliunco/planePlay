class_name PlaneGroundShadow
extends Node2D
## Soft shadow the airplane casts on the field. It stays on the ground while the
## plane climbs, spreading and fading with altitude, which is what makes height
## readable in a flat side view.

@export var radius: float = 52.0


func set_shape(new_radius: float) -> void:
	radius = new_radius
	queue_redraw()


func _draw() -> void:
	# Squashed circles stack into a soft ellipse: no texture, no shader.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.24))
	for i in 6:
		var t := float(i) / 5.0
		draw_circle(
			Vector2.ZERO,
			radius * lerpf(1.0, 0.45, t),
			Color(0.06, 0.13, 0.09, 0.10)
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
