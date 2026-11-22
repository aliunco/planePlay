class_name PlaneModel3D
extends SubViewport
## A low-poly 3D fighter, rendered into a side-view texture. This is the "2.5D"
## part of the game: physics, hitboxes, projectiles and the world stay flat 2D,
## but the airplane itself is a real 3D model behind an orthographic camera that
## never moves off the plane's side - so the aircraft is always shown in profile,
## whatever the 2D node does with its rotation or mirroring.
##
## The model is built from primitives at "art scale": 1 unit = 1 pixel of the
## final 190 px airplane, nose toward +X, wings along Z, up is +Y. Rendering at
## 2x and showing the texture scaled down keeps it crisp on high-density screens.
##
## Every airplane owns one of these, so the local and remote aircraft (or the
## menu's cruising hero plane) each get their own livery.

const ART_WIDTH: float = 190.0
const ART_HEIGHT: float = 53.0
## Texture pixels per model unit. The sprite that shows this texture is scaled by
## the matching factor, so one model unit is one world pixel whatever the frame
## around the aircraft costs.
const RENDER_SCALE: int = 2
## Camera distance: far enough that the whole airframe is between near and far.
const CAMERA_DISTANCE: float = 260.0
## What the camera frames, in model units. Wider and taller than the 190 x 53
## airframe on purpose: seen from a little above, the wings reach up and down the
## frame, and when the plane rolls about its own axis a wingtip sweeps a full
## span up out of the profile. The frame has to be big enough that a wing is never
## cut off at the edge of the texture mid-roll.
const VIEW_WIDTH: float = 200.0
const VIEW_HEIGHT: float = 148.0
const CAMERA_ORTHO_SIZE: float = VIEW_HEIGHT
## How far above the aircraft the camera sits, in degrees. A dead-flat side view
## hides the wings completely, so the camera looks down a touch: still a side
## profile, but one that reads as a three-dimensional aircraft.
const CAMERA_PITCH_DEGREES: float = 13.0
## Radius of the main wheels in model units. The airplane divides its ground
## speed by this to spin them, so they roll at the right rate.
const WHEEL_RADIUS: float = 6.0
## How long the gear takes to fold away and to come back down. Real airliners wind
## their gear up over several seconds; at this scale a deliberate swing reads as
## the same thing without stalling the take-off.
const GEAR_RETRACT_SECONDS: float = 0.8
const GEAR_EXTEND_SECONDS: float = 0.7
## How far each leg swings up into its bay, in degrees about the view axis. The
## mains fold forward into the wing root, the tail wheel folds back under the tail.
const GEAR_MAIN_FOLD_DEGREES: float = 82.0
const GEAR_TAIL_FOLD_DEGREES: float = 64.0
## The folded assembly shrinks and rises slightly as it sinks into the airframe,
## which is what makes it disappear rather than hang in mid air.
const GEAR_FOLD_SCALE: float = 0.55
const GEAR_FOLD_LIFT: float = 2.5

## The airframes PlaneRoster can put a pilot in: five piston fighters, four jets,
## and one that has never flown. The order is the order of the roster, oldest
## first.
enum Silhouette { PROP, GULL, ELLIPSE, LONGNOSE, TWIN_BOOM, EARLY_JET, DELTA, TWIN_TAIL, STEALTH, SCIFI }

## How many rain beads sit on the airframe at once. Small enough to be a handful
## of tiny meshes, enough that the aircraft looks properly soaked.
const DROPLET_COUNT: int = 13
## Beads slide this far back along the airframe before another lands at the front.
const DROPLET_TRAVEL: float = 34.0

## Everything that makes up the aircraft, so it can roll about its fuselage axis
## with the camera and lights left where they are.
var _airframe: Node3D
## Rain beads riding the airframe, and where each one starts and how fast it
## slides: (start x, surface y, surface z, speed).
var _droplets: Array[MeshInstance3D] = []
var _droplet_specs: Array[Vector4] = []
var _droplet_material: StandardMaterial3D
## 0 dry, 1 soaked. Drives the beads and the wet sheen on the paint.
var _wet: float = 0.0
var _drop_time: float = 0.0
## Every painted material, with its dry roughness, so rain can gloss the airframe
## without losing the dry look afterwards.
var _paint: Array[StandardMaterial3D] = []
var _paint_roughness: Array[float] = []
var _roll: float = 0.0
## Every spinning propeller (or energy intake) on the airframe: a twin-boom
## fighter has two, everything else one.
var _propeller_hubs: Array[Node3D] = []
var _propeller_speed: float = 20.0
var _wheels: Array[MeshInstance3D] = []
var _wheel_speed: float = 0.0
var _gear_root: Node3D
var _gear_hinges: Array[Node3D] = []
var _gear_fold_angles: Array[float] = []
var _gear_down: bool = true
var _gear_tween: Tween


## Builds the whole scene inside the viewport: aircraft, side camera, lights and
## a transparent environment.
func build(
	body_color: Color,
	accent_color: Color,
	belly_color: Color,
	silhouette: int = Silhouette.PROP
) -> void:
	size = Vector2i(int(VIEW_WIDTH * RENDER_SCALE), int(VIEW_HEIGHT * RENDER_SCALE))
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS

	_build_camera()
	_build_lighting()
	_airframe = Node3D.new()
	add_child(_airframe)
	_build_aircraft(
		_material(body_color, 0.62, 0.05),
		_material(accent_color, 0.45, 0.15),
		_material(belly_color, 0.7, 0.0),
		silhouette
	)
	_build_droplets()


## Radians per second the propeller spins at. Driven by the airplane so the prop
## settles with the engine instead of running at a fixed speed.
func set_propeller_speed(radians_per_second: float) -> void:
	_propeller_speed = radians_per_second


## Radians per second the landing-gear wheels turn at. The airplane drives this
## from its ground speed while it rolls along the strip.
func set_wheel_speed(radians_per_second: float) -> void:
	_wheel_speed = radians_per_second


## Puts the wheels down on the strip, or winds them up into their bays. The
## airplane calls this as the gear leaves the ground and when it parks again.
##
## Retraction is a swing, not a slide: each leg rotates about its hinge into the
## airframe while the whole assembly shrinks and lifts into the wheel bay, and the
## gear is only hidden once it is inside. Coming back down plays the same motion
## in reverse.
func set_gear_down(down: bool) -> void:
	if _gear_root == null or down == _gear_down:
		return
	_gear_down = down
	if _gear_tween != null and _gear_tween.is_valid():
		_gear_tween.kill()

	var duration := GEAR_EXTEND_SECONDS if down else GEAR_RETRACT_SECONDS
	var curve_ease := Tween.EASE_IN_OUT
	_gear_tween = create_tween()
	_gear_tween.set_parallel(true)
	for i in _gear_hinges.size():
		var target := 0.0 if down else _gear_fold_angles[i]
		_gear_tween.tween_property(_gear_hinges[i], "rotation:z", target, duration).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(curve_ease)
	_gear_tween.tween_property(
		_gear_root, "position:y", 0.0 if down else GEAR_FOLD_LIFT, duration
	).set_trans(Tween.TRANS_CUBIC).set_ease(curve_ease)
	_gear_tween.tween_property(
		_gear_root, "scale", Vector3.ONE * (1.0 if down else GEAR_FOLD_SCALE), duration * 0.9
	).set_trans(Tween.TRANS_CUBIC).set_ease(curve_ease)

	if down:
		_gear_root.visible = true
		return
	# Only once the legs are inside the airframe does the gear stop drawing.
	_gear_tween.chain().tween_callback(func() -> void: _gear_root.visible = false)


## Scale a Sprite2D showing this viewport must use so that one model unit is
## exactly one pixel in the 2D world (the airframe stays 190 px long).
func sprite_scale() -> float:
	return 1.0 / float(RENDER_SCALE)


## Rolls the whole aircraft about its own fuselage axis, in radians. Seen from the
## side, that swings the wings up out of the profile and turns the airframe over:
## a real barrel roll, not a mirrored picture. The nose never changes direction.
func set_roll(radians: float) -> void:
	_roll = radians
	if _airframe != null:
		_airframe.rotation.x = radians


func roll() -> float:
	return _roll


## 0 dry, 1 flying through a downpour. Beads on the airframe fade in, the paint
## picks up a wet sheen, and each bead slides back along the fuselage in the
## airstream as though the drops are being hammered onto the plane.
func set_wetness(amount: float) -> void:
	var next := clampf(amount, 0.0, 1.0)
	if is_equal_approx(next, _wet):
		return
	_wet = next
	for i in _paint.size():
		# Water fills the micro-texture of the paint, so it reflects far more.
		_paint[i].roughness = lerpf(_paint_roughness[i], _paint_roughness[i] * 0.34, _wet)
	if _droplet_material != null:
		_droplet_material.albedo_color.a = 0.92 * _wet
	for bead in _droplets:
		bead.visible = _wet > 0.06


func wetness() -> float:
	return _wet


func _process(delta: float) -> void:
	for hub in _propeller_hubs:
		hub.rotation.x -= _propeller_speed * delta
	for wheel in _wheels:
		wheel.rotation.y -= _wheel_speed * delta
	if _wet > 0.06:
		_animate_droplets(delta)


## Beads creep back toward the tail and a fresh one takes their place at the
## leading edge - streaks of water, not a static sheen.
func _animate_droplets(delta: float) -> void:
	_drop_time += delta
	for i in _droplets.size():
		var spec := _droplet_specs[i]
		var t := fposmod(_drop_time * spec.w + float(i) * 0.37, 1.0)
		var bead := _droplets[i]
		bead.position = Vector3(spec.x - DROPLET_TRAVEL * t, spec.y, spec.z)
		# It swells as it lands and thins out as it runs back into the airstream.
		var swell := 0.55 + 0.75 * sin(t * PI)
		bead.scale = Vector3(0.95, 0.6, 1.45) * swell * lerpf(0.5, 1.0, _wet)


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
	camera.look_at(Vector3.ZERO, Vector3.UP)


func _build_lighting() -> void:
	# Warm key from above and in front of the nose, on the camera's side of the
	# plane so the flanks and the tail fin catch light instead of going black.
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.95, 0.86)
	key.light_energy = 1.35
	key.rotation_degrees = Vector3(-30.0, 32.0, 0.0)
	key.shadow_enabled = false
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.62, 0.76, 1.0)
	fill.light_energy = 0.45
	fill.rotation_degrees = Vector3(24.0, -40.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

	# Camera light: points straight down -Z, so every surface facing the camera
	# stays readable.
	var front := DirectionalLight3D.new()
	front.light_color = Color(0.95, 0.97, 1.0)
	front.light_energy = 0.22
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


func _material(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	# Remembered so rain can gloss it and drying can put it back exactly.
	_paint.append(material)
	_paint_roughness.append(roughness)
	return material


## The rain beads: little translucent drops resting on the spine, the near wing
## and the tailplane, where water would actually pool.
func _build_droplets() -> void:
	_droplet_material = StandardMaterial3D.new()
	_droplet_material.albedo_color = Color(0.82, 0.92, 1.0, 0.0)
	_droplet_material.roughness = 0.08
	_droplet_material.metallic = 0.15
	_droplet_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_droplet_material.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL

	# Positions in model units: nose is +X, up is +Y, the wings run along Z. The
	# camera sits a little above and in front, so the near side of the spine and
	# the near wing are the surfaces it can see.
	var spine: Array[Vector3] = [
		Vector3(-40.0, 7.0, 1.5),
		Vector3(-24.0, 8.2, 1.5),
		Vector3(-8.0, 9.6, 1.5),
		Vector3(10.0, 10.6, 1.5),
		Vector3(28.0, 11.0, 1.5),
		Vector3(46.0, 11.2, 1.5),
		Vector3(62.0, 9.6, 1.5),
	]
	var near_wing: Array[Vector3] = [
		Vector3(-4.0, 0.4, 20.0),
		Vector3(9.0, 0.6, 27.0),
		Vector3(2.0, 0.8, 34.0),
		Vector3(-14.0, 2.6, 30.0),
		Vector3(-72.0, -4.0, 16.0),
		Vector3(-76.0, -4.4, -14.0),
	]

	var bead_mesh := SphereMesh.new()
	bead_mesh.radius = 0.9
	bead_mesh.height = 1.5
	bead_mesh.radial_segments = 8
	bead_mesh.rings = 4

	var index := 0
	for spec: Vector3 in (spine + near_wing):
		if index >= DROPLET_COUNT:
			break
		var bead := MeshInstance3D.new()
		bead.mesh = bead_mesh
		bead.material_override = _droplet_material
		bead.position = spec
		bead.scale = Vector3(0.95, 0.6, 1.45)
		bead.visible = false
		# A little jitter in speed so the beads never move as one sheet.
		var speed := 0.16 + 0.07 * float(index % 3)
		_droplet_specs.append(Vector4(spec.x, spec.y, spec.z, speed))
		_airframe.add_child(bead)
		_droplets.append(bead)
		index += 1


# --- Aircraft ----------------------------------------------------------------

## Builds the airframe the roster asked for. Everything the ten fighters share -
## paint materials, rain beads, gear plumbing - lives outside these builders; what
## differs is the shape of the aircraft and what hangs off it.
func _build_aircraft(
	body: Material, accent: Material, belly: Material, silhouette: int
) -> void:
	var upper := _material(
		(body as StandardMaterial3D).albedo_color.lightened(0.12), 0.6, 0.05
	)
	var glass := _material(Color(0.10, 0.18, 0.22), 0.12, 0.35)
	var metal := _material(Color(0.24, 0.25, 0.26), 0.4, 0.6)
	match silhouette:
		Silhouette.GULL:
			_build_gull_wing(body, upper, accent, belly, glass, metal)
		Silhouette.ELLIPSE:
			_build_elliptical_wing(body, upper, accent, belly, glass, metal)
		Silhouette.LONGNOSE:
			_build_long_nose(body, upper, accent, belly, glass, metal)
		Silhouette.TWIN_BOOM:
			_build_twin_boom(body, upper, accent, belly, glass, metal)
		Silhouette.EARLY_JET:
			_build_sabre(body, upper, accent, belly, glass, metal)
		Silhouette.DELTA:
			_build_delta(body, upper, accent, belly, glass, metal)
		Silhouette.TWIN_TAIL:
			_build_twin_tail(body, upper, accent, belly, glass, metal)
		Silhouette.STEALTH:
			_build_stealth(body, upper, accent, belly, glass, metal)
		Silhouette.SCIFI:
			_build_aurora(body, upper, accent, belly, glass, metal)
		_:
			_build_prop_fighter(body, upper, accent, belly, glass, metal)


## The classic valley fighter, nose to the right: spindle fuselage, bubble canopy,
## big spinner, tapered wing with dihedral, tail fin and the small clutter
## (exhausts, guns, radiator) that makes the profile read as an aircraft.
func _build_prop_fighter(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:

	# Fuselage: four tapering sections so the silhouette curves instead of
	# reading as one tube. Fighter profile: deep cowl, slim tail.
	_tube(-92.0, -46.0, 2.0, 7.5, body)
	_tube(-46.0, 4.0, 7.5, 11.0, body)
	_tube(4.0, 44.0, 11.0, 11.5, body)
	_tube(44.0, 76.0, 11.5, 11.5, body)
	# Spinner, and the dark ring of the engine face behind it.
	_tube(76.0, 94.0, 11.5, 0.0, accent)
	_tube(74.0, 77.0, 12.0, 12.0, metal)
	# Underside panel: the two-tone scheme real fighters carry.
	_add_box(Vector3(74.0, 2.0, 9.0), Vector3(14.0, -8.0, 0.0), belly)

	# Canopy: a stretched bubble sitting proud of the spine.
	_add_sphere(Vector3(1.7, 1.0, 0.85), Vector3(22.0, 10.0, 0.0), glass)
	# Anti-glare panel in front of the windscreen.
	_add_box(Vector3(22.0, 1.2, 11.0), Vector3(47.0, 9.8, 0.0), metal)

	# Tail fin: two stacked slabs, the upper one shorter and set back, which
	# gives the little swept fin every low-poly fighter has.
	_add_box(Vector3(30.0, 15.0, 3.0), Vector3(-76.0, 8.0, 0.0), body)
	_add_box(Vector3(17.0, 14.0, 3.0), Vector3(-71.0, 20.5, 0.0), body)
	# Tailplane: one slab straight through the tail.
	_add_box(Vector3(26.0, 2.6, 62.0), Vector3(-76.0, 1.0, 0.0), body)

	# Wings: an inner and an outer panel per side, the outer one narrower and set
	# back, so the planform reads as a tapered, swept wing. A little dihedral and
	# the camera's slight elevation give the profile its width.
	for side: float in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(2.0, -2.0, 0.0)
		pivot.rotation_degrees = Vector3(-side * 10.0, 0.0, 0.0)
		_airframe.add_child(pivot)
		_add_box(Vector3(46.0, 3.4, 30.0), Vector3(8.0, 0.0, side * 21.0), upper, pivot)
		_add_box(Vector3(36.0, 3.0, 28.0), Vector3(1.0, 0.0, side * 49.0), upper, pivot)
		# Painted wingtip band.
		_add_box(Vector3(26.0, 3.6, 8.0), Vector3(-3.0, 0.0, side * 60.0), accent, pivot)

	# Radiator scoop under the nose.
	_add_box(Vector3(26.0, 9.0, 14.0), Vector3(16.0, -11.0, 0.0), body)
	_add_box(Vector3(4.0, 6.0, 10.0), Vector3(29.0, -11.0, 0.0), metal)

	_build_landing_gear(metal, accent)

	# Exhaust stacks along the cowl, plus the antenna mast.
	for i in 4:
		_add_box(
			Vector3(6.0, 3.0, 3.5),
			Vector3(46.0 + float(i) * 7.0, 7.5, 7.0),
			metal
		)
	_add_box(Vector3(1.5, 9.0, 1.5), Vector3(-42.0, 11.0, 0.0), metal)

	_build_propeller(accent, metal)


# --- The roster's other airframes --------------------------------------------

## Corsair silhouette: the wing drops out of the root and then climbs to the tip,
## wrapped around a fat radial engine, with the tall squared fin the type is known
## for.
func _build_gull_wing(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	_tube(-92.0, -44.0, 2.0, 8.0, body)
	_tube(-44.0, 0.0, 8.0, 11.0, body)
	_tube(0.0, 40.0, 11.0, 12.0, body)
	_tube(40.0, 66.0, 12.0, 13.5, body)
	# Radial cowl: a blunt drum around the engine, with the prop on its face.
	_tube(66.0, 71.0, 14.5, 14.5, metal)
	_tube(71.0, 88.0, 14.5, 11.5, body)
	_add_sphere(Vector3(1.6, 1.05, 0.85), Vector3(2.0, 10.0, 0.0), glass)

	# Tall, squared fin.
	_add_box(Vector3(28.0, 15.0, 3.0), Vector3(-80.0, 8.0, 0.0), body)
	_add_box(Vector3(20.0, 9.0, 3.0), Vector3(-77.0, 18.0, 0.0), body)
	_add_box(Vector3(24.0, 2.6, 52.0), Vector3(-78.0, 1.0, 0.0), body)
	_add_box(Vector3(26.0, 9.0, 15.0), Vector3(16.0, -11.0, 0.0), belly)
	# Chin intake under the cowl: the Corsair's signature jaw.
	_add_box(Vector3(14.0, 10.0, 13.0), Vector3(58.0, -10.0, 0.0), body)

	# Gull wing: droop, then a sharp step up to the tip.
	for side: float in [-1.0, 1.0]:
		var root := Node3D.new()
		root.position = Vector3(4.0, -2.0, 0.0)
		root.rotation_degrees = Vector3(side * 9.0, 0.0, 0.0)
		_airframe.add_child(root)
		_add_box(Vector3(38.0, 3.0, 20.0), Vector3(0.0, 0.0, side * 12.0), upper, root)
		var tip := Node3D.new()
		tip.position = Vector3(-2.0, -3.0, side * 21.0)
		tip.rotation_degrees = Vector3(-side * 26.0, 0.0, 0.0)
		root.add_child(tip)
		_add_box(Vector3(28.0, 2.8, 15.0), Vector3(0.0, 0.0, side * 9.0), upper, tip)
		_add_box(Vector3(18.0, 3.2, 6.0), Vector3(-1.0, 0.0, side * 16.0), accent, tip)

	_build_landing_gear(metal, accent)
	_build_propeller(accent, metal)


## Spitfire silhouette: four wing panels whose chord shrinks along an arc, so the
## planform reads as one continuous curve, with a long spinner and a rounded fin.
func _build_elliptical_wing(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	_tube(-90.0, -42.0, 2.0, 8.0, body)
	_tube(-42.0, 4.0, 8.0, 10.5, body)
	_tube(4.0, 46.0, 10.5, 11.0, body)
	_tube(46.0, 76.0, 11.0, 9.5, body)
	_tube(76.0, 94.0, 9.5, 0.0, accent)
	_tube(74.0, 77.0, 10.0, 10.0, metal)
	_add_sphere(Vector3(1.5, 0.95, 0.8), Vector3(0.0, 9.4, 0.0), glass)

	# Rounded fin: three tapering slabs, which read as a curve at this scale.
	_add_box(Vector3(28.0, 10.0, 2.6), Vector3(-80.0, 5.0, 0.0), body)
	_add_box(Vector3(17.0, 9.0, 2.4), Vector3(-76.0, 12.0, 0.0), body)
	_add_box(Vector3(9.0, 6.0, 2.2), Vector3(-71.0, 18.0, 0.0), body)
	_add_box(Vector3(23.0, 2.5, 54.0), Vector3(-79.0, 1.0, 0.0), body)
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(20.0, 6.0, 10.0), Vector3(6.0, -10.0, side * 8.0), belly)

	for side: float in [-1.0, 1.0]:
		for i in 4:
			var chord := 50.0 - float(i) * 8.0
			var thickness := 3.2 - float(i) * 0.25
			_add_box(
				Vector3(chord, thickness, 15.0),
				Vector3(10.0 - float(i) * 3.0, -2.0 + float(i) * 1.1, side * (12.0 + float(i) * 11.0)),
				upper
			)
		_add_box(Vector3(18.0, 2.8, 5.0), Vector3(0.0, 1.6, side * 50.0), accent)

	_build_landing_gear(metal, accent)
	_build_propeller(accent, metal, 86.0)


## Mustang silhouette: a long, slim nose, a squared-off wing and the big belly
## radiator that gives the type its profile.
func _build_long_nose(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	_tube(-92.0, -44.0, 2.0, 8.0, body)
	_tube(-44.0, 2.0, 8.0, 10.0, body)
	_tube(2.0, 48.0, 10.0, 10.5, body)
	_tube(48.0, 84.0, 10.5, 8.0, body)
	_tube(84.0, 96.0, 8.0, 0.0, accent)
	_tube(82.0, 85.0, 8.6, 8.6, metal)
	_add_sphere(Vector3(1.7, 1.1, 0.9), Vector3(-2.0, 9.2, 0.0), glass)

	# Belly radiator and its intake.
	_add_box(Vector3(34.0, 10.0, 15.0), Vector3(24.0, -11.0, 0.0), belly)
	_add_box(Vector3(5.0, 7.0, 11.0), Vector3(40.0, -11.0, 0.0), metal)
	# Squared fin with a dorsal fillet into the fuselage.
	_add_box(Vector3(30.0, 15.0, 3.0), Vector3(-80.0, 8.0, 0.0), body)
	_add_box(Vector3(14.0, 6.0, 2.8), Vector3(-64.0, 6.0, 0.0), body)
	_add_box(Vector3(26.0, 2.6, 58.0), Vector3(-80.0, 1.0, 0.0), body)

	# Clipped, squared wings.
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(50.0, 3.4, 26.0), Vector3(6.0, -2.0, side * 18.0), upper)
		_add_box(Vector3(28.0, 3.0, 14.0), Vector3(-2.0, -1.0, side * 34.0), upper)
		_add_box(Vector3(18.0, 3.2, 6.0), Vector3(-6.0, -0.6, side * 42.0), accent)

	_build_landing_gear(metal, accent)
	_build_propeller(accent, metal, 88.0)


## Lightning silhouette: a central gondola slung between two engine booms, each
## with its own propeller, joined by one long tailplane.
func _build_twin_boom(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	# Central gondola: guns in the nose, the pilot in the middle.
	_tube(-60.0, -30.0, 3.0, 7.0, body)
	_tube(-30.0, 8.0, 7.0, 8.5, body)
	_tube(8.0, 42.0, 8.5, 7.5, body)
	_tube(42.0, 64.0, 7.5, 4.0, body)
	_tube(64.0, 70.0, 4.0, 3.0, metal)
	_add_sphere(Vector3(1.4, 0.85, 0.8), Vector3(-4.0, 9.4, 0.0), glass)
	_add_box(Vector3(24.0, 9.0, 14.0), Vector3(-20.0, -9.0, 0.0), belly)
	# Four guns and their barrels in the nose.
	for i in 2:
		_add_box(
			Vector3(9.0, 1.6, 1.6),
			Vector3(72.0, -2.0 + float(i) * 4.0, 0.0),
			metal
		)

	# Two booms, each with its own engine and prop, and the twin fins behind.
	for side: float in [-1.0, 1.0]:
		_tube(-92.0, -40.0, 3.0, 5.0, body, side * 28.0)
		_tube(-40.0, 46.0, 5.0, 5.5, body, side * 28.0)
		_tube(46.0, 62.0, 7.0, 7.0, body, side * 28.0)
		_tube(62.0, 76.0, 6.5, 5.5, metal, side * 28.0)
		_add_box(Vector3(22.0, 12.0, 2.4), Vector3(-84.0, 9.0, side * 28.0), body)
		_add_box(Vector3(16.0, 2.4, 16.0), Vector3(-88.0, 2.0, side * 28.0), body)
		_build_propeller(accent, metal, 78.0, side * 28.0)

	# One wing carries both booms; one tailplane joins their tails.
	_add_box(Vector3(34.0, 3.2, 62.0), Vector3(4.0, -1.0, 0.0), upper)
	_add_box(Vector3(26.0, 2.4, 70.0), Vector3(-88.0, 2.0, 0.0), body)

	_build_landing_gear(metal, accent)


## Sabre silhouette: a nose intake, a swept wing and a single swept fin. No
## propeller - the jet nozzle is what the eye finds at the back.
func _build_sabre(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	_tube(-92.0, -46.0, 3.5, 8.0, body)
	_tube(-46.0, 2.0, 8.0, 10.5, body)
	_tube(2.0, 50.0, 10.5, 11.0, body)
	_tube(50.0, 82.0, 11.0, 9.5, body)
	_tube(82.0, 92.0, 9.5, 8.0, metal)
	_add_disc(8.0, 1.0, Color(0.03, 0.035, 0.045), Vector3(89.0, 0.0, 0.0))
	_add_sphere(Vector3(1.75, 1.0, 0.9), Vector3(2.0, 9.6, 0.0), glass)

	# Swept fin, tailplane on the same sweep line.
	var fin := _add_box(Vector3(26.0, 18.0, 3.0), Vector3(-78.0, 9.0, 0.0), body)
	fin.rotation_degrees = Vector3(0.0, 0.0, 8.0)
	_add_box(Vector3(20.0, 10.0, 2.6), Vector3(-72.0, 18.0, 0.0), body)
	_add_box(Vector3(24.0, 2.6, 52.0), Vector3(-80.0, 1.5, 0.0), body)
	# The tailpipe, dark inside its ring.
	_add_disc(6.2, 1.0, Color(0.06, 0.06, 0.07), Vector3(-95.0, 0.0, 0.0))

	# Two swept panels a side, the outer one set back.
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(36.0, 3.0, 22.0), Vector3(4.0, -2.0, side * 14.0), upper)
		_add_box(Vector3(26.0, 2.6, 18.0), Vector3(-10.0, -1.0, side * 30.0), upper)
		_add_box(Vector3(18.0, 2.8, 6.0), Vector3(-16.0, 0.0, side * 38.0), accent)

	_build_jet_nozzle(metal, _glow(Color(1.0, 0.62, 0.3), 1.2), -94.0, 0.0, 6.5)
	_build_tricycle_gear(metal, accent)


## Mirage silhouette: a pure delta. One big triangular wing, small canards forward
## and a single tall fin, with the engine right at the tail.
func _build_delta(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	_tube(-88.0, -44.0, 3.5, 7.5, body)
	_tube(-44.0, 8.0, 7.5, 9.0, body)
	_tube(8.0, 56.0, 9.0, 8.0, body)
	_tube(56.0, 78.0, 8.0, 5.5, body)
	_tube(78.0, 94.0, 5.5, 0.0, accent)
	_add_sphere(Vector3(1.8, 0.95, 0.9), Vector3(14.0, 8.6, 0.0), glass)
	var fin := _add_box(Vector3(24.0, 18.0, 3.0), Vector3(-70.0, 10.0, 0.0), body)
	fin.rotation_degrees = Vector3(0.0, 0.0, 6.0)
	# Long pitot probe on the nose, the delta fighters' calling card.
	_tube(93.0, 100.0, 0.9, 0.5, metal)

	# Delta: three panels a side, each further back, all the way to the tail.
	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(52.0, 3.0, 22.0), Vector3(-8.0, -2.0, side * 13.0), upper)
		_add_box(Vector3(38.0, 2.6, 18.0), Vector3(-26.0, -1.5, side * 27.0), upper)
		_add_box(Vector3(24.0, 2.4, 14.0), Vector3(-42.0, -1.0, side * 38.0), upper)
		_add_box(Vector3(18.0, 2.4, 5.0), Vector3(-46.0, -0.6, side * 44.0), accent)
		_add_box(Vector3(16.0, 2.2, 16.0), Vector3(58.0, 2.0, side * 11.0), upper)

	_build_jet_nozzle(metal, _glow(Color(1.0, 0.62, 0.3), 1.2), -90.0, 0.0, 7.5)
	_build_tricycle_gear(metal, accent)


## Eagle silhouette: a big bubble canopy, strakes along the nose, twin canted
## tails and two engines - the modern heavy fighter.
func _build_twin_tail(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	_tube(-88.0, -44.0, 4.0, 9.0, body)
	_tube(-44.0, 8.0, 9.0, 12.0, body)
	_tube(8.0, 52.0, 12.0, 12.5, body)
	_tube(52.0, 84.0, 12.5, 9.5, body)
	_tube(84.0, 93.0, 9.5, 6.0, metal)
	_add_sphere(Vector3(2.2, 1.15, 0.95), Vector3(6.0, 12.2, 0.0), glass)

	for side: float in [-1.0, 1.0]:
		# LERX strakes running from the wing root along the fuselage.
		_add_box(Vector3(34.0, 1.6, 8.0), Vector3(40.0, 3.0, side * 9.0), body)
		# Canted twin tails.
		var tail := _add_box(Vector3(24.0, 18.0, 2.6), Vector3(-76.0, 14.0, side * 10.0), body)
		tail.rotation_degrees = Vector3(side * 14.0, 0.0, 4.0)
	_add_box(Vector3(26.0, 2.6, 46.0), Vector3(-80.0, 2.0, 0.0), body)

	for side: float in [-1.0, 1.0]:
		_add_box(Vector3(44.0, 3.2, 26.0), Vector3(0.0, -3.0, side * 19.0), upper)
		_add_box(Vector3(28.0, 2.8, 16.0), Vector3(-10.0, -2.0, side * 34.0), upper)
		_add_box(Vector3(18.0, 3.0, 5.0), Vector3(-16.0, -1.0, side * 41.0), accent)
		# Under-wing pylons and their rounds: the loaded heavy fighter.
		_add_box(Vector3(22.0, 1.8, 2.0), Vector3(-2.0, -6.0, side * 22.0), metal)
		_add_box(Vector3(26.0, 3.2, 3.2), Vector3(2.0, -8.0, side * 22.0), body)
		_add_box(Vector3(7.0, 2.4, 2.4), Vector3(18.0, -8.0, side * 22.0), accent)
		_build_jet_nozzle(metal, _glow(Color(1.0, 0.66, 0.34), 1.2), -92.0, side * 8.0, 5.0)

	_build_tricycle_gear(metal, accent)


## Raptor silhouette: faceted, chined, twin tails canted out, everything edges and
## nothing round. The canopy catches the light like a visor.
func _build_stealth(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	var dark := _material(Color(0.12, 0.13, 0.15), 0.55, 0.25)
	# Faceted forward body and a wedge nose.
	var block := _add_box(Vector3(56.0, 13.0, 17.0), Vector3(14.0, 0.0, 0.0), body)
	block.rotation_degrees = Vector3(0.0, 0.0, 1.5)
	_add_box(Vector3(46.0, 10.0, 13.0), Vector3(-34.0, 1.0, 0.0), body)
	var nose := _add_box(Vector3(46.0, 8.0, 9.0), Vector3(62.0, -1.0, 0.0), body)
	nose.rotation_degrees = Vector3(0.0, 0.0, -7.0)
	var canopy := _add_box(Vector3(30.0, 8.0, 8.0), Vector3(30.0, 9.0, 0.0), glass)
	canopy.rotation_degrees = Vector3(0.0, 0.0, 6.0)

	for side: float in [-1.0, 1.0]:
		# Canted twin tails, and the flat thrust-vectoring nozzles under them.
		var tail := _add_box(Vector3(22.0, 17.0, 2.4), Vector3(-70.0, 13.0, side * 11.0), body)
		tail.rotation_degrees = Vector3(side * 24.0, 0.0, 10.0)
		_add_box(Vector3(26.0, 1.8, 20.0), Vector3(-78.0, 1.0, side * 22.0), body)
		_add_box(Vector3(16.0, 7.0, 10.0), Vector3(-88.0, -1.0, side * 7.0), dark)
		_add_box(
			Vector3(2.0, 5.0, 7.0),
			Vector3(-96.0, -1.0, side * 7.0),
			_glow(Color(0.35, 0.85, 1.0), 1.4)
		)

		# Cropped, angular wing with a forward-swept tip.
		var inner := _add_box(Vector3(44.0, 2.8, 28.0), Vector3(0.0, -2.0, side * 18.0), upper)
		inner.rotation_degrees = Vector3(side * -3.0, side * 6.0, 0.0)
		var outer := _add_box(Vector3(28.0, 2.4, 16.0), Vector3(-6.0, -1.0, side * 34.0), upper)
		outer.rotation_degrees = Vector3(0.0, side * -14.0, 0.0)
		_add_box(Vector3(15.0, 2.2, 5.0), Vector3(-2.0, 0.0, side * 42.0), accent)

	_build_tricycle_gear(metal, accent)


## Aurora silhouette: forward-swept wings, a spinning energy intake where a
## propeller would be, glowing strips along the flanks and no horizontal tail at
## all. The last fighter in the list is the one that never had a runway.
func _build_aurora(
	body: Material,
	upper: Material,
	accent: Material,
	belly: Material,
	glass: Material,
	metal: Material
) -> void:
	var glow := _glow(Color(0.42, 1.0, 0.92), 1.8)
	var dark := _material(Color(0.07, 0.06, 0.10), 0.4, 0.5)
	_tube(-86.0, -44.0, 3.0, 7.0, body)
	_tube(-44.0, 4.0, 7.0, 10.0, body)
	_tube(4.0, 46.0, 10.0, 9.0, body)
	_tube(46.0, 78.0, 9.0, 5.5, body)
	_tube(78.0, 92.0, 5.5, 3.0, body)
	_add_sphere(Vector3(1.5, 0.9, 0.8), Vector3(26.0, 8.6, 0.0), glass)

	# Energy intake: a glowing ring with blades that spin on the propeller hub.
	_add_disc(8.4, 0.8, Color(0.35, 1.0, 0.95), Vector3(82.0, 0.0, 0.0))
	_add_disc(6.6, 1.4, Color(0.05, 0.28, 0.30), Vector3(86.0, 0.0, 0.0))
	var intake := Node3D.new()
	intake.position = Vector3(86.0, 0.0, 0.0)
	_airframe.add_child(intake)
	_propeller_hubs.append(intake)
	for i in 3:
		var arm := Node3D.new()
		arm.rotation_degrees = Vector3(120.0 * float(i), 0.0, 0.0)
		intake.add_child(arm)
		_add_box(Vector3(1.0, 9.0, 1.6), Vector3(0.0, 5.0, 0.0), glow, arm)

	for side: float in [-1.0, 1.0]:
		# Forward-swept wing: the tip leads the root.
		var root := Node3D.new()
		root.position = Vector3(-6.0, -2.0, 0.0)
		root.rotation_degrees = Vector3(side * -4.0, side * -18.0, 0.0)
		_airframe.add_child(root)
		_add_box(Vector3(48.0, 3.0, 24.0), Vector3(0.0, 0.0, side * 14.0), upper, root)
		var tip := Node3D.new()
		tip.position = Vector3(5.0, 1.0, side * 24.0)
		tip.rotation_degrees = Vector3(0.0, side * -14.0, 0.0)
		root.add_child(tip)
		_add_box(Vector3(24.0, 2.6, 15.0), Vector3(4.0, 0.0, side * 8.0), upper, tip)
		_add_box(Vector3(11.0, 1.2, 12.0), Vector3(8.0, 1.6, side * 8.0), glow, tip)
		# Canards by the cockpit.
		_add_box(Vector3(18.0, 2.2, 14.0), Vector3(54.0, 2.0, side * 10.0), body)
		# Twin canted fins with a glowing trailing edge.
		var fin := _add_box(Vector3(22.0, 16.0, 2.2), Vector3(-66.0, 12.0, side * 9.0), body)
		fin.rotation_degrees = Vector3(side * 22.0, 0.0, 0.0)
		_add_box(Vector3(3.0, 13.0, 1.4), Vector3(-75.0, 12.0, side * 12.0), glow)

	# Spine strip and the reactor glow behind the cockpit.
	_add_box(Vector3(52.0, 1.4, 5.0), Vector3(12.0, 10.4, 0.0), glow)
	_add_sphere(Vector3(1.6, 0.7, 1.0), Vector3(-24.0, 8.2, 0.0), glow)

	_build_jet_nozzle(dark, glow, -92.0, 0.0, 7.0)
	_build_tricycle_gear(metal, accent)


# --- Shared parts ------------------------------------------------------------

## A thin glowing material: engine flames, running lights, energy strips. Not part
## of the painted set, because a glow does not get wet.
func _glow(color: Color, energy: float = 1.6) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## A disc facing the camera, used for jet intakes.
func _add_disc(
	radius: float, thickness: float, color: Color, position: Vector3
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = thickness
	mesh.radial_segments = 18
	mesh.rings = 1
	var instance := _add_mesh(mesh, _material(color, 0.6, 0.2), position)
	instance.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	return instance


## The back of a jet: a tapered nozzle with a glowing disc inside it.
func _build_jet_nozzle(
	material: Material, glow: Material, x: float, z: float = 0.0, radius: float = 6.0
) -> void:
	var nozzle := CylinderMesh.new()
	nozzle.top_radius = radius
	nozzle.bottom_radius = radius * 1.15
	nozzle.height = 10.0
	nozzle.radial_segments = 14
	var instance := _add_mesh(nozzle, material, Vector3(x, 0.0, z))
	instance.rotation_degrees = Vector3(0.0, 0.0, 90.0)

	var flame := CylinderMesh.new()
	flame.top_radius = radius * 0.72
	flame.bottom_radius = radius * 0.72
	flame.height = 1.0
	flame.radial_segments = 12
	var flame_instance := _add_mesh(flame, glow, Vector3(x - 5.4, 0.0, z))
	flame_instance.rotation_degrees = Vector3(0.0, 0.0, 90.0)


## Tricycle gear for the jets: mains under the wing root and a nose leg whose wheel
## reaches the same strip, so every airframe sits level on the runway.
func _build_tricycle_gear(metal: Material, accent: Material) -> void:
	var rubber := _material(Color(0.12, 0.12, 0.13), 0.9, 0.0)
	_gear_root = Node3D.new()
	_airframe.add_child(_gear_root)

	for side: float in [-1.0, 1.0]:
		var hinge := _add_gear_hinge(
			Vector3(-16.0, -6.0, side * 11.0), GEAR_MAIN_FOLD_DEGREES
		)
		_add_box(Vector3(3.0, 12.0, 3.0), Vector3(0.0, -6.0, 0.0), metal, hinge)
		_add_wheel(Vector3(0.0, -14.0, 0.0), 6.4, 4.4, rubber, accent, hinge)

	var nose_hinge := _add_gear_hinge(Vector3(56.0, -6.0, 0.0), -GEAR_TAIL_FOLD_DEGREES)
	_add_box(Vector3(2.6, 16.0, 2.6), Vector3(0.0, -8.0, 0.0), metal, nose_hinge)
	_add_wheel(Vector3(0.0, -16.0, 0.0), 4.4, 3.4, rubber, accent, nose_hinge)


## Retractable landing gear, sized so the wheels reach exactly the bottom of the
## 53 px art frame: parked, that puts the tyres on the strip instead of the belly.
## Each leg hangs from a hinge at its wheel bay, so it folds up the way real gear
## does instead of sliding out of sight.
func _build_landing_gear(metal: Material, accent: Material) -> void:
	var rubber := _material(Color(0.12, 0.12, 0.13), 0.9, 0.0)
	# Everything the gear is made of hangs off one node, so the whole assembly can
	# sink and shrink into the airframe as it folds.
	_gear_root = Node3D.new()
	_airframe.add_child(_gear_root)

	# Main gear: a pair of legs under the wing root, one each side of the
	# fuselage, so the near wheel covers the far one from the camera. The hinge is
	# at the top of the leg; the wheel sits at the bottom, on the strip.
	for side: float in [-1.0, 1.0]:
		var hinge := _add_gear_hinge(
			Vector3(2.0, -6.0, side * 12.5), GEAR_MAIN_FOLD_DEGREES
		)
		var leg := _add_box(Vector3(3.2, 14.0, 3.0), Vector3(0.0, -7.0, 0.0), metal, hinge)
		leg.rotation_degrees = Vector3(0.0, 0.0, side * 4.0)
		_add_wheel(Vector3(0.0, -14.0, 0.0), 6.4, 4.4, rubber, accent, hinge)

	# Tail wheel on a short strut, its tyre on the same ground line; it folds back
	# under the tail.
	var tail_hinge := _add_gear_hinge(
		Vector3(-70.0, -8.0, 0.0), -GEAR_TAIL_FOLD_DEGREES
	)
	_add_box(Vector3(2.6, 12.0, 2.6), Vector3(0.0, -6.0, 0.0), metal, tail_hinge)
	_add_wheel(Vector3(0.0, -15.0, 0.0), 3.0, 3.4, rubber, accent, tail_hinge)


## A hinge at a wheel bay: rotating this node swings everything under it up into
## the airframe.
func _add_gear_hinge(position: Vector3, fold_degrees: float) -> Node3D:
	var hinge := Node3D.new()
	hinge.position = position
	_gear_root.add_child(hinge)
	_gear_hinges.append(hinge)
	_gear_fold_angles.append(deg_to_rad(fold_degrees))
	return hinge


## One gear wheel: a tyre and a hub, both on a pivot whose local Y becomes the
## axle, so spinning the meshes about their own Y rolls them.
func _add_wheel(
	position: Vector3,
	radius: float,
	width: float,
	rubber: Material,
	hub_material: Material,
	parent: Node3D = null
) -> void:
	var pivot := Node3D.new()
	pivot.position = position
	# CylinderMesh is built along +Y; this turns the axle to +Z, i.e. across the
	# aircraft, where a wheel's axle belongs.
	pivot.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	(parent if parent != null else _gear_root).add_child(pivot)

	var tyre := CylinderMesh.new()
	tyre.top_radius = radius
	tyre.bottom_radius = radius
	tyre.height = width
	tyre.radial_segments = 14
	tyre.rings = 1
	var tyre_instance := _add_mesh(tyre, rubber, Vector3.ZERO, pivot)

	var hub := CylinderMesh.new()
	hub.top_radius = radius * 0.42
	hub.bottom_radius = radius * 0.42
	hub.height = width + 0.6
	hub.radial_segments = 10
	var hub_instance := _add_mesh(hub, hub_material, Vector3.ZERO, pivot)

	_wheels.append(tyre_instance)
	_wheels.append(hub_instance)


func _build_propeller(
	accent: Material, metal: Material, x: float = 80.0, z: float = 0.0
) -> void:
	var hub_root := Node3D.new()
	hub_root.position = Vector3(x, 0.0, z)
	_airframe.add_child(hub_root)
	_propeller_hubs.append(hub_root)

	# Motion-blur disc: a very flat, unlit cylinder.
	var disc_material := StandardMaterial3D.new()
	disc_material.albedo_color = Color(1.0, 1.0, 1.0, 0.16)
	disc_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var disc := CylinderMesh.new()
	disc.top_radius = 22.0
	disc.bottom_radius = 22.0
	disc.height = 0.6
	disc.radial_segments = 24
	disc.rings = 1
	var disc_instance := _add_mesh(disc, disc_material, Vector3.ZERO, hub_root)
	disc_instance.rotation_degrees = Vector3(0.0, 0.0, 90.0)

	# Two blades sweeping in the Y/Z plane: from the side they flash past as an
	# edge, which is exactly how a spinning prop looks.
	for side: float in [-1.0, 1.0]:
		var blade := _add_box(
			Vector3(1.4, 22.0, 6.0),
			Vector3(0.0, side * 11.0, 0.0),
			metal,
			hub_root
		)
		blade.rotation_degrees = Vector3(0.0, 0.0, side * 6.0)

	# A hint of the spinner inside the blur ring.
	var hub := CylinderMesh.new()
	hub.top_radius = 2.5
	hub.bottom_radius = 3.5
	hub.height = 4.0
	hub.radial_segments = 10
	var hub_instance := _add_mesh(hub, accent, Vector3(6.0, 0.0, 0.0), hub_root)
	hub_instance.rotation_degrees = Vector3(0.0, 0.0, 90.0)


# --- Mesh helpers ------------------------------------------------------------

## A cylinder running along the X axis, tapering from radius_at_back to
## radius_at_front.
func _tube(
	from_x: float,
	to_x: float,
	radius_at_back: float,
	radius_at_front: float,
	material: Material,
	z: float = 0.0
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.height = absf(to_x - from_x)
	# CylinderMesh is built along +Y: bottom radius sits at -Y, top at +Y.
	mesh.bottom_radius = radius_at_back
	mesh.top_radius = radius_at_front
	mesh.radial_segments = 12
	mesh.rings = 1
	var instance := _add_mesh(mesh, material, Vector3((from_x + to_x) * 0.5, 0.0, z))
	# +Y -> +X, so the "front" radius ends up toward the nose.
	instance.rotation_degrees = Vector3(0.0, 0.0, -90.0)
	return instance


func _add_box(
	size: Vector3,
	position: Vector3,
	material: Material,
	parent: Node3D = null
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(mesh, material, position, parent)


func _add_sphere(
	scale: Vector3,
	position: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 7.0
	mesh.height = 12.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var instance := _add_mesh(mesh, material, position)
	instance.scale = scale
	return instance


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
		_airframe.add_child(instance)
	return instance
