extends Node2D
## One-shot explosion: an animated fireball from the fireball sheet, an expanding
## shockwave ring, sparks and debris. Frees itself when the animation has run out.

const FIREBALL_SHEET: Texture2D = preload("res://assets/effects/fireball_sheet.svg")
const FRAME_SIZE := Vector2i(200, 200)
const FIREBALL_FRAMES: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

@export var flash_scale: float = 1.1
@export var duration: float = 0.9

@onready var fireball: AnimatedSprite2D = $Fireball
@onready var sparks: CPUParticles2D = $Sparks
@onready var shockwave: Line2D = $Shockwave


func _ready() -> void:
	fireball.sprite_frames = SheetFrames.build(
		FIREBALL_SHEET,
		FRAME_SIZE,
		[{"name": &"boom", "frames": FIREBALL_FRAMES, "fps": 14.0, "loop": false}]
	)
	fireball.scale = Vector2.ONE * flash_scale * 0.8
	fireball.modulate.a = 1.0
	fireball.play(&"boom")
	sparks.emitting = true

	# Keep growing while it burns, so the ball swells out of the wreckage.
	var tween := create_tween()
	tween.tween_property(fireball, "scale", Vector2.ONE * flash_scale * 1.25, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

	_play_shockwave()

	await get_tree().create_timer(duration).timeout
	queue_free()


## A thin ring that races outward and fades: what sells the bang as an impact.
func _play_shockwave() -> void:
	var points := PackedVector2Array()
	var steps := 40
	for i in steps + 1:
		var angle := TAU * float(i) / float(steps)
		points.append(Vector2(cos(angle), sin(angle)) * 30.0)
	shockwave.points = points
	shockwave.scale = Vector2.ONE * 0.5
	shockwave.modulate.a = 0.85

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(shockwave, "scale", Vector2.ONE * 3.4, 0.5).set_trans(
		Tween.TRANS_QUAD
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(shockwave, "modulate:a", 0.0, 0.5)
