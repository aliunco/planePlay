extends CanvasLayer
## Distant cloud layer painted in screen space. Because it never scrolls with the
## camera it reads as "far away", which is what gives the world-space clouds
## their parallax depth. It animates on the same cloud sheet, at its own pace.

const CLOUD_SHEET: Texture2D = preload("res://assets/environment/cloud_sheet.svg")
const CLOUD_FRAMES: Array[int] = [0, 1, 2, 3, 4, 5]

@export var cloud_count: int = 7

var _clouds: Array[AnimatedSprite2D] = []
var _speeds: Array[float] = []
var _view_size := Vector2(1280.0, 720.0)


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_on_viewport_resized)


func _build() -> void:
	for cloud in _clouds:
		cloud.queue_free()
	_clouds.clear()
	_speeds.clear()

	var frames := SheetFrames.build(
		CLOUD_SHEET,
		CloudSprite.FRAME_SIZE,
		[{"name": &"drift", "frames": CLOUD_FRAMES, "fps": 5.0, "loop": true}]
	)

	_view_size = get_viewport().get_visible_rect().size
	for i in cloud_count:
		var cloud := AnimatedSprite2D.new()
		cloud.sprite_frames = frames
		cloud.scale = Vector2.ONE * randf_range(0.4, 0.8)
		cloud.modulate = Color(1.0, 1.0, 1.0, randf_range(0.45, 0.72))
		cloud.position = Vector2(
			randf_range(-200.0, _view_size.x + 200.0),
			randf_range(_view_size.y * 0.24, _view_size.y * 0.62)
		)
		cloud.speed_scale = randf_range(0.15, 0.35)
		cloud.frame = randi() % CLOUD_FRAMES.size()
		cloud.play(&"drift")
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(randf_range(-9.0, 9.0))


func _on_viewport_resized() -> void:
	_build()


func _process(delta: float) -> void:
	var width := get_viewport().get_visible_rect().size.x
	for i in _clouds.size():
		var cloud := _clouds[i]
		cloud.position.x += _speeds[i] * delta
		if cloud.position.x > width + 260.0:
			cloud.position.x = -260.0
		elif cloud.position.x < -260.0:
			cloud.position.x = width + 260.0
