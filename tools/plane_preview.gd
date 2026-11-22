extends Node
## Debug preview: renders the 3D fighter on its own and saves a big PNG so the
## model can be inspected without playing a match.
##
##   godot --path . res://tools/plane_preview.tscn


func _color(key: String, fallback: String) -> Color:
	var value := fallback
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="):
			value = argument.substr(key.length() + 1)
	return Color(value)


func _ready() -> void:
	var model := PlaneModel3D.new()
	model.size = Vector2i(760, 212)
	add_child(model)
	model.build(_color("--body", "4c5c36"), _color("--accent", "e6b93f"), _color("--belly", "4c5643"))
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	var image := model.get_texture().get_image()
	image.resize(1520, 424, Image.INTERPOLATE_LANCZOS)
	image.save_png("/tmp/plane_preview.png")
	print("saved preview ", image.get_size())
	get_tree().quit()
