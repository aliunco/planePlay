class_name CloudField
extends Node2D
## World-space clouds above the landscape. A fixed pool follows the camera: when
## a cloud drops below the view it is recycled to the top, so the sky is always
## populated without ever spawning or freeing nodes during play.
##
## Every cloud animates through the cloud sheet and wanders on its own, so no two
## clouds move in lockstep.

const CLOUD_SCENE: PackedScene = preload("res://scenes/environment/cloud.tscn")
const CLOUD_SHEET: Texture2D = preload("res://assets/environment/cloud_sheet.svg")
const CLOUD_FRAMES: Array[int] = [0, 1, 2, 3, 4, 5]

@export var cloud_count: int = 16
@export var world_width: float = 3200.0
@export var spawn_top: float = -2400.0
@export var spawn_bottom: float = 0.0

var camera: Camera2D
var _clouds: Array[CloudSprite] = []
var _frames: SpriteFrames


static func build_frames() -> SpriteFrames:
	return SheetFrames.build(
		CLOUD_SHEET,
		CloudSprite.FRAME_SIZE,
		[{"name": &"drift", "frames": CLOUD_FRAMES, "fps": 6.0, "loop": true}]
	)


func _ready() -> void:
	_frames = build_frames()
	for i in cloud_count:
		var cloud: CloudSprite = CLOUD_SCENE.instantiate()
		add_child(cloud)
		cloud.position = Vector2(
			randf_range(-200.0, world_width + 200.0),
			randf_range(spawn_top, spawn_bottom)
		)
		cloud.setup(
			_frames,
			randf_range(0.45, 0.95),
			randf_range(0.72, 0.98),
			-260.0,
			world_width + 260.0,
			randi()
		)
		_clouds.append(cloud)


## Weather recolours the whole deck at once: greyed out under cloud, darker and
## heavier in rain, still bright in snow.
func set_weather(kind: int, strength: float) -> void:
	var tint := Color.WHITE.lerp(Weather.cloud_tint(kind), strength)
	var alpha_scale := lerpf(1.0, Weather.cloud_alpha_scale(kind), strength)
	for cloud in _clouds:
		cloud.set_weather(tint, alpha_scale)


func _process(_delta: float) -> void:
	if camera == null:
		return
	var cam_center := camera.get_screen_center_position()
	var half_height := get_viewport_rect().size.y * 0.5 / camera.zoom.y
	var below_limit := cam_center.y + half_height + 320.0
	var above_limit := cam_center.y - half_height - 320.0

	for cloud in _clouds:
		if cloud.position.y > below_limit:
			cloud.position.y = above_limit - randf_range(0.0, 900.0)
			cloud.position.x = randf_range(-200.0, world_width + 200.0)
			cloud.reset_wander()
