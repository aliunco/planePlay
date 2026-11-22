extends TextureRect
## Soft radial vignette laid over the whole screen. It darkens the corners a
## little, which pushes the eye toward the planes in the middle of the frame.

@export var edge_color: Color = Color(0.02, 0.05, 0.10, 0.40)
@export var inner_stop: float = 0.58


func _ready() -> void:
	texture = _build_gradient()
	stretch_mode = TextureRect.STRETCH_SCALE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _build_gradient() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, inner_stop, 1.0])
	gradient.colors = PackedColorArray(
		[Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(edge_color, edge_color.a)]
	)
	var texture_2d := GradientTexture2D.new()
	texture_2d.gradient = gradient
	texture_2d.width = 256
	texture_2d.height = 256
	texture_2d.fill = GradientTexture2D.FILL_RADIAL
	texture_2d.fill_from = Vector2(0.5, 0.5)
	texture_2d.fill_to = Vector2(1.0, 1.0)
	return texture_2d
