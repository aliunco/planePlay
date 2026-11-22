class_name SoldierModel3D
extends SubViewport
## A low-poly infantryman, rendered into a side-view texture exactly the way the
## airplanes are: a real 3D figure behind an orthographic camera that looks at his
## right side, so the world stays flat 2D but the soldier has volume.
##
## The model is built at "art scale" (1 unit = 1 pixel), standing on FEET_Y with
## his rifle rigged on a pivot at the shoulder: aiming means rotating that pivot,
## which the 2D Soldier does every frame as it follows a plane.
##
## Life comes from three things: a slow breathing sway, an idle stance per soldier
## (torso lean and head tilt), and the kick of a shot - the rifle jumps back and
## up, the torso rocks with it and the whole thing settles in a damped wobble.
##
## Unlike the airplanes, a squad of these is cheap: each viewport renders only
## when the pose changes (UPDATE_ONCE + request_render()).

## Wide enough to hold the heavy gun at full elevation: the frame is centred on
## the figure, so widening it never moves him.
const ART_WIDTH: float = 60.0
const ART_HEIGHT: float = 44.0
## Texture pixels per art unit; the sprite showing this texture scales back down.
const RENDER_SCALE: int = 2
const CAMERA_DISTANCE: float = 180.0
const CAMERA_ORTHO_SIZE: float = 44.0
## A few degrees of elevation: enough to show the helmet and shoulders in the
## round, not enough to stop reading as a side profile.
const CAMERA_PITCH_DEGREES: float = 7.0
## The frame is centred on 0, so the boots stand just inside its bottom edge.
const FEET_Y: float = -21.0
## Shoulder pivot in model units (y up), and the distance from it to the muzzle.
const SHOULDER := Vector2(1.5, -3.0)
## Far enough out to clear the heavier gun: the 2D soldier spawns its shells from
## this same distance, so the tracer leaves the muzzle instead of the stock.
const RIFLE_REACH: float = 18.0
const AIM_MIN: float = -0.25
const AIM_MAX: float = 1.45
## How long the shot's kick takes to die away, in seconds.
const KICK_TIME: float = 0.5
## Torso lean and head tilt for each idle stance: alert, relaxed, shouldered.
const STANCE_LEAN: Array[float] = [-0.02, 0.1, -0.12]
const STANCE_HEAD: Array[float] = [0.0, -0.12, 0.1]

var _upper: Node3D
var _head: Node3D
var _rifle: Node3D
var _flash: MeshInstance3D
var _aim: float = AIM_MIN
var _lean: float = 0.0
var _head_tilt: float = 0.0
var _breath_phase: float = 0.0
var _time: float = 0.0
var _kick_time: float = -1.0
var _flash_time: float = 0.0
var _idle_tick: float = 0.0


## Builds the figure, the camera and the lights. The uniform colour is the only
## thing that varies between soldiers.
func build(uniform: Color) -> void:
	size = Vector2i(int(ART_WIDTH * RENDER_SCALE), int(ART_HEIGHT * RENDER_SCALE))
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	# Renders only when asked to; see request_render().
	render_target_update_mode = SubViewport.UPDATE_ONCE

	_build_camera()
	_build_lighting()
	_build_figure(uniform)
	_apply_pose(0.0)


## Renders one more frame. Called whenever the pose changes, so a squad of idle
## soldiers costs a handful of tiny renders a second instead of one per frame.
func request_render() -> void:
	render_target_update_mode = SubViewport.UPDATE_ONCE


## Scale a Sprite2D showing this viewport must use so one model unit is one pixel.
func sprite_scale() -> float:
	return CAMERA_ORTHO_SIZE / (ART_HEIGHT * float(RENDER_SCALE))


## Swings the rifle to an angle in radians: 0 is level, positive points up.
func set_aim(angle: float) -> void:
	var clamped := clampf(angle, AIM_MIN, AIM_MAX)
	if absf(clamped - _aim) < 0.012:
		return
	_aim = clamped
	_apply_pose(_current_kick())


## Picks the stance this soldier stands in when nothing is overhead, so a squad
## is made of people rather than copies.
func set_stance(stance: int) -> void:
	var index := clampi(stance, 0, STANCE_LEAN.size() - 1)
	_lean = STANCE_LEAN[index]
	_head_tilt = STANCE_HEAD[index]
	_apply_pose(_current_kick())


## Offsets the breathing cycle, so no two soldiers breathe in time.
func set_breath_phase(phase: float) -> void:
	_breath_phase = phase


## One muzzle flash, then the shot's kick: the rifle jumps back and up and rocks
## itself still again.
func flash_muzzle() -> void:
	_flash_time = 0.09
	_kick_time = 0.0


func _process(delta: float) -> void:
	_time += delta

	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		if _flash != null:
			_flash.visible = _flash_time > 0.0
		request_render()

	if _kick_time >= 0.0:
		_kick_time += delta
		_apply_pose(_current_kick())
		if _kick_time > KICK_TIME:
			_kick_time = -1.0
			_apply_pose(0.0)

	# Breathing and the idle sway, at a fraction of the frame rate: plenty for a
	# figure that is thirty pixels tall.
	_idle_tick += delta
	if _idle_tick >= 0.1:
		_idle_tick = 0.0
		_apply_pose(_current_kick())


## The shot's wobble: a decaying oscillation, so the rifle rocks rather than
## snapping straight back.
func _current_kick() -> float:
	if _kick_time < 0.0:
		return 0.0
	return exp(-_kick_time * 9.0) * cos(_kick_time * 26.0)


func _apply_pose(kick: float) -> void:
	var breath := sin(_time * 1.6 + _breath_phase)

	if _upper != null:
		_upper.rotation.z = _lean + breath * 0.012 + kick * 0.05
	if _head != null:
		_head.rotation.z = _head_tilt + breath * 0.02 - kick * 0.04
	if _rifle != null:
		_rifle.rotation.z = _aim + kick * 0.26
		_rifle.position = Vector3(SHOULDER.x - absf(kick) * 2.2, SHOULDER.y, 0.0)
	request_render()


# --- Scene setup -------------------------------------------------------------

func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = CAMERA_ORTHO_SIZE
	camera.near = 1.0
	camera.far = CAMERA_DISTANCE * 2.0
	camera.current = true
	add_child(camera)
	camera.position = Vector3(
		0.0,
		sin(deg_to_rad(CAMERA_PITCH_DEGREES)) * CAMERA_DISTANCE,
		cos(deg_to_rad(CAMERA_PITCH_DEGREES)) * CAMERA_DISTANCE
	)
	camera.look_at(Vector3(0.0, -6.0, 0.0), Vector3.UP)


func _build_lighting() -> void:
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 1.3
	key.rotation_degrees = Vector3(-30.0, 28.0, 0.0)
	key.shadow_enabled = false
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.76, 1.0)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(22.0, -40.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

	var front := DirectionalLight3D.new()
	front.light_color = Color(0.95, 0.97, 1.0)
	front.light_energy = 0.25
	front.shadow_enabled = false
	add_child(front)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.66, 0.76, 0.9)
	environment.ambient_light_energy = 0.55
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


# --- Figure ------------------------------------------------------------------

## A soldier in profile, facing +X: boots, legs, tunic with a belt and pack, head
## under a helmet, and a rifle held across the chest on a pivot. Everything above
## the hips hangs off one node so the torso can lean and rock.
func _build_figure(uniform: Color) -> void:
	var cloth := _material(uniform, 0.85, 0.0)
	var cloth_dark := _material(uniform.darkened(0.3), 0.85, 0.0)
	var skin := _material(Color(0.72, 0.55, 0.42), 0.8, 0.0)
	var metal := _material(Color(0.16, 0.16, 0.17), 0.45, 0.55)
	var wood := _material(Color(0.35, 0.24, 0.15), 0.75, 0.0)

	# Boots and legs stay planted; the hips are the pivot for everything above.
	_add_box(Vector3(5.4, 3.0, 5.4), Vector3(1.6, FEET_Y + 1.5, 0.0), cloth_dark)
	_add_box(Vector3(5.2, 3.0, 5.2), Vector3(-2.0, FEET_Y + 1.5, 0.0), cloth_dark)
	_add_box(Vector3(4.0, 11.0, 4.4), Vector3(1.2, FEET_Y + 8.5, 0.0), cloth)
	_add_box(Vector3(4.0, 11.0, 4.4), Vector3(-2.2, FEET_Y + 8.5, 0.0), cloth)

	_upper = Node3D.new()
	_upper.position = Vector3(0.0, FEET_Y + 11.0, 0.0)
	add_child(_upper)

	# Tunic, belt and pack, measured from the hips.
	_add_box(Vector3(9.0, 13.0, 5.6), Vector3(0.0, 8.5, 0.0), cloth, _upper)
	_add_box(Vector3(9.4, 1.4, 6.0), Vector3(0.0, 2.0, 0.0), cloth_dark, _upper)
	_add_box(Vector3(4.4, 8.0, 5.0), Vector3(-4.6, 9.0, 0.0), cloth_dark, _upper)

	# Head and helmet on their own node, so he can look around.
	_head = Node3D.new()
	_head.position = Vector3(0.6, 16.5, 0.0)
	_upper.add_child(_head)

	var head := SphereMesh.new()
	head.radius = 3.0
	head.height = 6.0
	head.radial_segments = 10
	head.rings = 5
	_add_mesh(head, skin, Vector3.ZERO, _head)

	var helmet := SphereMesh.new()
	helmet.radius = 3.5
	helmet.height = 4.6
	helmet.radial_segments = 10
	helmet.rings = 4
	_add_mesh(helmet, cloth_dark, Vector3(0.0, 2.0, 0.0), _head)

	# The gun: a pintle-mounted heavy cannon built to hurt aeroplanes, not a rifle.
	# Everything turns on the same shoulder pivot, so aiming still works; it is
	# simply a lot more hardware than the soldier could once carry.
	_rifle = Node3D.new()
	_rifle.position = Vector3(SHOULDER.x, SHOULDER.y, 0.0)
	_rifle.rotation.z = _aim
	add_child(_rifle)

	# Pintle and cradle: the yoke the gun swings in.
	_add_box(Vector3(4.6, 4.4, 4.6), Vector3(0.4, -1.2, 0.0), metal, _rifle)
	_add_box(Vector3(3.2, 2.0, 3.4), Vector3(0.6, 1.2, 0.0), cloth_dark, _rifle)
	# Receiver and the shoulder rest behind it.
	_add_box(Vector3(11.0, 4.6, 4.2), Vector3(5.6, 0.4, 0.0), metal, _rifle)
	_add_box(Vector3(2.6, 3.0, 3.2), Vector3(-1.4, 0.2, 0.0), wood, _rifle)
	# Ammunition drum on the near side, and the feed chute climbing into the
	# receiver: the giveaway that this fires something serious.
	var drum := CylinderMesh.new()
	drum.top_radius = 3.4
	drum.bottom_radius = 3.4
	drum.height = 3.2
	drum.radial_segments = 12
	drum.rings = 1
	var drum_instance := _add_mesh(drum, metal, Vector3(3.4, -2.0, 2.8), _rifle)
	drum_instance.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_add_box(Vector3(2.4, 3.4, 2.2), Vector3(5.2, -2.4, 1.6), cloth_dark, _rifle)
	# Barrel jacket, the barrel itself and a fat muzzle brake.
	_add_box(Vector3(8.0, 3.0, 2.9), Vector3(13.6, 0.9, 0.0), metal, _rifle)
	_add_box(Vector3(6.0, 2.0, 2.0), Vector3(16.4, 1.1, 0.0), metal, _rifle)
	_add_box(Vector3(2.8, 3.2, 2.8), Vector3(17.8, 1.1, 0.0), cloth_dark, _rifle)
	# Recoil spring under the barrel, and the grips.
	_add_box(Vector3(7.0, 1.2, 1.2), Vector3(14.4, -1.1, 0.0), metal, _rifle)
	_add_box(Vector3(3.0, 3.6, 2.0), Vector3(1.8, -2.2, 0.0), wood, _rifle)

	# Muzzle flash, hidden until the rifle fires.
	var flash_material := StandardMaterial3D.new()
	flash_material.albedo_color = Color(1.0, 0.78, 0.35)
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 3.6
	flash_mesh.height = 7.2
	flash_mesh.radial_segments = 8
	flash_mesh.rings = 4
	_flash = _add_mesh(flash_mesh, flash_material, Vector3(RIFLE_REACH + 0.6, 1.1, 0.0), _rifle)
	_flash.visible = false


# --- Mesh helpers ------------------------------------------------------------

func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _add_box(
	size: Vector3,
	position: Vector3,
	material: Material,
	parent: Node3D = null
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(mesh, material, position, parent)


func _add_mesh(
	mesh: Mesh,
	material: Material,
	position: Vector3,
	parent: Node3D = null
) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	if parent != null:
		parent.add_child(instance)
	else:
		add_child(instance)
	return instance
