class_name MainMenu
extends Control
## Title screen: pick a mode, pick the AI difficulty, launch the match.
## Also the LAN lobby: host a match or join one by address.
##
## The backdrop is the game's own art: the golden-hour sky, three hazy hill
## ridges, drifting clouds and the real field, with one of the fighters cruising
## past behind a frosted card. Nothing here is a separate illustration, so the
## menu and the match always look like the same world.

signal play_requested(mode: int, difficulty: int)
signal lan_host_requested
signal lan_join_requested(address: String)

const CLOUD_COUNT: int = 7
const BACKDROP_WIDTH: float = 3200.0
const HERO_SPEED: float = 26.0
## Shown while the menu broadcasts for a host on the local network.
const LAN_SEARCH_NOTICE: String = "Looking for a LAN host on your network..."
const LAN_SEARCH_NOTICE_MS: int = 7000

@onready var card: PanelContainer = $Center/Content/Card
@onready var title_label: Label = $Center/Content/Card/Column/Title
@onready var rule: ColorRect = $Center/Content/Card/Column/Rule
@onready var subtitle_label: Label = $Center/Content/Card/Column/Subtitle
@onready var plane_label: Label = $Center/Content/Card/Column/PlaneLabel
@onready var prev_plane_button: Button = $Center/Content/Card/Column/PlaneRow/PrevButton
@onready var next_plane_button: Button = $Center/Content/Card/Column/PlaneRow/NextButton
@onready var plane_preview: TextureRect = $Center/Content/Card/Column/PlaneRow/PlaneCard/PlaneBox/PlanePreview
@onready var plane_name_label: Label = $Center/Content/Card/Column/PlaneRow/PlaneCard/PlaneBox/PlaneInfo/PlaneName
@onready var plane_stats: PlaneStatBars = $Center/Content/Card/Column/PlaneRow/PlaneCard/PlaneBox/PlaneInfo/PlaneStats
@onready var difficulty_label: Label = $Center/Content/Card/Column/DifficultyLabel
@onready var play_button: Button = $Center/Content/Card/Column/PlayRow/PlayButton
@onready var survival_button: Button = $Center/Content/Card/Column/PlayRow/SurvivalButton
@onready var local_button: Button = $Center/Content/Card/Column/LocalButton
@onready var host_button: Button = $Center/Content/Card/Column/LanRow/HostButton
@onready var address_field: LineEdit = $Center/Content/Card/Column/LanRow/AddressField
@onready var join_button: Button = $Center/Content/Card/Column/LanRow/JoinButton
@onready var easy_button: Button = $Center/Content/Card/Column/DifficultyRow/EasyButton
@onready var normal_button: Button = $Center/Content/Card/Column/DifficultyRow/NormalButton
@onready var hard_button: Button = $Center/Content/Card/Column/DifficultyRow/HardButton
@onready var weather_label: Label = $Center/Content/Card/Column/WeatherLabel
@onready var auto_button: Button = $Center/Content/Card/Column/WeatherRow/AutoButton
@onready var clear_button: Button = $Center/Content/Card/Column/WeatherRow/ClearButton
@onready var cloudy_button: Button = $Center/Content/Card/Column/WeatherRow/CloudyButton
@onready var rain_button: Button = $Center/Content/Card/Column/WeatherRow/RainButton
@onready var snow_button: Button = $Center/Content/Card/Column/WeatherRow/SnowButton
@onready var hint_label: Label = $Center/Content/Card/Column/Hint
@onready var status_label: Label = $Center/Content/Card/Column/Status
@onready var hills: HillSilhouettes = $Backdrop/Hills
@onready var landscape: Landscape = $Backdrop/Landscape
@onready var hero_plane: Node2D = $Backdrop/HeroPlane
@onready var hero_body: Sprite2D = $Backdrop/HeroPlane/Body
@onready var cloud_layer: Node2D = $Backdrop/Clouds

var _difficulty: int = AIConfig.Difficulty.NORMAL
## The fighter the next match launches with: an index into PlaneRoster.
var selected_plane: int = 0
## Renderer behind the picker's preview strip, rebuilt when the choice changes.
var _preview_model: PlaneModel3D
## Weather picked for the next match. -1 is AUTO: the match rolls its own opening
## sky from the session key, so no two sessions start the same. Survival changes
## it on its own as the run goes on; every other mode keeps this choice.
var selected_weather: int = -1
var _hero_x: float = 0.0
var _hero_started: bool = false
var _hero_bob: float = 0.0
var _hero_model: PlaneModel3D
var _clouds: Array[AnimatedSprite2D] = []
var _cloud_speeds: Array[float] = []
var _cloud_frames: SpriteFrames
## Address this menu filled in itself, so it never overwrites a typed one.
var _auto_address: String = ""
var _search_notice_until: int = 0


func _ready() -> void:
	_apply_style()
	_layout_backdrop()
	resized.connect(_layout_backdrop)
	_build_clouds()
	_build_hero_plane()
	prev_plane_button.pressed.connect(func() -> void: _set_plane(selected_plane - 1))
	next_plane_button.pressed.connect(func() -> void: _set_plane(selected_plane + 1))

	play_button.pressed.connect(func() -> void: _start(GameManager.Mode.SINGLE_PLAYER))
	survival_button.pressed.connect(func() -> void: _start(GameManager.Mode.SURVIVAL))
	local_button.pressed.connect(func() -> void: _start(GameManager.Mode.LOCAL_VERSUS))
	refresh_record()
	host_button.pressed.connect(func() -> void: lan_host_requested.emit())
	join_button.pressed.connect(func() -> void: lan_join_requested.emit(address_field.text))
	address_field.text_submitted.connect(
		func(_text: String) -> void: lan_join_requested.emit(address_field.text)
	)
	easy_button.pressed.connect(func() -> void: _set_difficulty(AIConfig.Difficulty.EASY))
	normal_button.pressed.connect(func() -> void: _set_difficulty(AIConfig.Difficulty.NORMAL))
	hard_button.pressed.connect(func() -> void: _set_difficulty(AIConfig.Difficulty.HARD))
	auto_button.pressed.connect(func() -> void: _set_weather(-1))
	clear_button.pressed.connect(func() -> void: _set_weather(Weather.Kind.CLEAR))
	cloudy_button.pressed.connect(func() -> void: _set_weather(Weather.Kind.CLOUDY))
	rain_button.pressed.connect(func() -> void: _set_weather(Weather.Kind.RAIN))
	snow_button.pressed.connect(func() -> void: _set_weather(Weather.Kind.SNOW))
	_set_difficulty(AIConfig.Difficulty.NORMAL)
	_set_plane(0)
	_set_weather(-1)
	Lan.host_found.connect(_on_lan_host_found)
	visibility_changed.connect(_update_model_rendering)
	set_status("")
	search_for_host()
	_intro_animation()


## Puts this device's best survival run on the button, so the record is visible
## before the run rather than only after it.
func refresh_record() -> void:
	if survival_button == null:
		return
	var best := SurvivalRecord.load_best()
	survival_button.text = "Survival" if best <= 0 else "Survival  ·  Best %d" % best


## Broadcasts for a host on the local network and fills the join field when one
## answers, so joining a second phone needs no typed address. Safe to call every
## time the menu is shown: an existing search is replaced.
func search_for_host() -> void:
	Lan.stop_host_search()
	_search_notice_until = Time.get_ticks_msec() + LAN_SEARCH_NOTICE_MS
	set_status(LAN_SEARCH_NOTICE)
	Lan.search_for_host(6.0)


func _on_lan_host_found(address: String) -> void:
	if not visible:
		return
	var current := address_field.text.strip_edges()
	# Never overwrite an address the pilot typed in themselves.
	if not current.is_empty() and current != _auto_address:
		return
	_auto_address = address
	address_field.text = address
	_search_notice_until = 0
	set_status("Found a host at %s - press Join" % address)


func _apply_style() -> void:
	UIStyle.style_label(title_label, 44, UIStyle.ACCENT)
	title_label.add_theme_color_override("font_shadow_color", Color(0.05, 0.10, 0.16, 0.55))
	title_label.add_theme_constant_override("shadow_offset_y", 6)
	UIStyle.style_label(subtitle_label, 21, UIStyle.TEXT_PRIMARY)
	UIStyle.style_label(hint_label, 15, UIStyle.TEXT_MUTED)
	UIStyle.style_caption(difficulty_label)
	UIStyle.style_caption(plane_label)
	UIStyle.style_label(plane_name_label, 18, UIStyle.TEXT_PRIMARY)
	UIStyle.style_label(status_label, 19, UIStyle.ACCENT)
	for button: Button in [prev_plane_button, next_plane_button]:
		UIStyle.style_button(button, UIStyle.ACCENT, 22)

	for button: Button in [play_button, survival_button, local_button, host_button, join_button]:
		UIStyle.style_button(button, UIStyle.ACCENT, 23)
	UIStyle.style_primary_button(play_button, UIStyle.ACCENT, 25)
	for button: Button in [easy_button, normal_button, hard_button]:
		UIStyle.style_toggle(button, UIStyle.ACCENT, 19)
		button.toggle_mode = true
	UIStyle.style_caption(weather_label)
	for button: Button in [auto_button, clear_button, cloudy_button, rain_button, snow_button]:
		UIStyle.style_toggle(button, UIStyle.ACCENT, 17)
		button.toggle_mode = true
	if address_field != null:
		UIStyle.style_line_edit(address_field)

	var panel_style := UIStyle.panel_style(Color(0.04, 0.09, 0.14, 0.82), 26, Color(1, 1, 1, 0.10))
	panel_style.content_margin_left = 42.0
	panel_style.content_margin_right = 42.0
	panel_style.content_margin_top = 14.0
	panel_style.content_margin_bottom = 14.0
	panel_style.shadow_size = 26
	panel_style.shadow_offset = Vector2(0.0, 14.0)
	card.add_theme_stylebox_override("panel", panel_style)
	rule.color = UIStyle.ACCENT

	# The preview strip sits in its own recessed well, so the fighter reads as a
	# picture of the aircraft rather than another button label.
	var preview_style := UIStyle.panel_style(
		Color(0.02, 0.05, 0.08, 0.62), 12, Color(1, 1, 1, 0.09)
	)
	preview_style.content_margin_left = 12.0
	preview_style.content_margin_right = 12.0
	preview_style.content_margin_top = 5.0
	preview_style.content_margin_bottom = 3.0
	(plane_preview.get_parent().get_parent() as PanelContainer).add_theme_stylebox_override(
		"panel", preview_style
	)


## Keeps the painted world anchored to the bottom of the window whatever the
## aspect ratio, and parks the cruising fighter in the open sky.
func _layout_backdrop() -> void:
	var view := _view_size()
	var ground_line := view.y * 0.74
	var no_clears: Array[float] = []
	hills.configure(BACKDROP_WIDTH, ground_line)
	landscape.configure(BACKDROP_WIDTH, ground_line, view.y - ground_line + 80.0, no_clears)
	hero_plane.position.y = view.y * 0.10
	if _hero_started == false:
		_hero_started = true
		_hero_x = (view.x + 520.0) * 0.72


func _build_clouds() -> void:
	_cloud_frames = CloudField.build_frames()
	for i in CLOUD_COUNT:
		var cloud := AnimatedSprite2D.new()
		cloud.sprite_frames = _cloud_frames
		cloud.play(&"drift")
		cloud.frame = randi() % 6
		cloud.speed_scale = randf_range(0.2, 0.45)
		var cloud_scale := randf_range(0.55, 1.05)
		cloud.scale = Vector2.ONE * cloud_scale
		cloud.modulate = Color(1.0, 0.99, 0.97, randf_range(0.55, 0.9))
		var view := _view_size()
		cloud.position = Vector2(
			randf_range(-160.0, view.x + 160.0),
			randf_range(view.y * 0.10, view.y * 0.58)
		)
		cloud_layer.add_child(cloud)
		_clouds.append(cloud)
		_cloud_speeds.append(randf_range(-7.0, 7.0))


## The flypast is the same 3D model the match uses and the same fighter the pilot
## picked, so trying planes on the title screen also previews them in the sky.
func _build_hero_plane() -> void:
	_rebuild_hero_model()


func _rebuild_hero_model() -> void:
	if _hero_model != null and is_instance_valid(_hero_model):
		hero_plane.remove_child(_hero_model)
		_hero_model.queue_free()
	_hero_model = PlaneModel3D.new()
	hero_plane.add_child(_hero_model)
	var plane := PlaneRoster.entry(selected_plane)
	_hero_model.build(plane["body"], plane["accent"], plane["belly"], plane["silhouette"])
	_hero_model.set_propeller_speed(34.0)
	_hero_model.set_wheel_speed(0.0)
	hero_body.texture = _hero_model.get_texture()
	hero_body.scale = Vector2.ONE * _hero_model.sprite_scale()
	_update_model_rendering()


## Picks the fighter the next match launches with. The preview strip and the
## cruising hero plane both follow the choice, so the title screen always shows
## the aircraft that is about to go up.
func _set_plane(index: int) -> void:
	selected_plane = posmod(index, PlaneRoster.count())
	var plane := PlaneRoster.entry(selected_plane)
	plane_name_label.text = str(plane["name"])
	plane_label.text = "FIGHTER %d/%d   ·   %s" % [
		selected_plane + 1, PlaneRoster.count(), str(plane["role"]).to_upper()
	]
	# The bars carry the real numbers: speed, turn rate, rounds per second and
	# armour, each against the whole roster's spread.
	plane_stats.set_stats(PlaneRoster.stat_rows(selected_plane))
	_rebuild_preview_model()
	_rebuild_hero_model()
	# A quick lift on the name, so a click reads as the list moving.
	plane_name_label.modulate.a = 0.35
	var tween := create_tween()
	tween.tween_property(plane_name_label, "modulate:a", 1.0, 0.18)


func _rebuild_preview_model() -> void:
	if _preview_model != null and is_instance_valid(_preview_model):
		remove_child(_preview_model)
		_preview_model.queue_free()
	_preview_model = PlaneModel3D.new()
	add_child(_preview_model)
	var plane := PlaneRoster.entry(selected_plane)
	_preview_model.build(plane["body"], plane["accent"], plane["belly"], plane["silhouette"])
	# The render covers the whole sky around the aircraft, so the picker shows a
	# band around the fuselage instead: the full airframe, not a slice of it.
	var atlas := AtlasTexture.new()
	atlas.atlas = _preview_model.get_texture()
	atlas.region = Rect2(
		0.0,
		PlaneModel3D.VIEW_HEIGHT * PlaneModel3D.RENDER_SCALE * 0.25,
		PlaneModel3D.VIEW_WIDTH * PlaneModel3D.RENDER_SCALE,
		PlaneModel3D.VIEW_HEIGHT * PlaneModel3D.RENDER_SCALE * 0.5
	)
	plane_preview.texture = atlas
	_update_model_rendering()


## The menu keeps its two renderers alive behind a match, and a SubViewport set to
## UPDATE_ALWAYS renders every frame whether or not anyone can see it. Stopping
## them while the menu is hidden keeps that cost out of the match.
func _update_model_rendering() -> void:
	var mode := (
		SubViewport.UPDATE_ALWAYS if visible else SubViewport.UPDATE_DISABLED
	)
	for model: PlaneModel3D in [_hero_model, _preview_model]:
		if model != null and is_instance_valid(model):
			model.render_target_update_mode = mode


func _process(delta: float) -> void:
	_animate_clouds(delta)
	_animate_hero_plane(delta)
	_expire_search_notice()


## Takes the "looking for a host" line away again once the search window is over.
func _expire_search_notice() -> void:
	if _search_notice_until == 0 or Time.get_ticks_msec() < _search_notice_until:
		return
	_search_notice_until = 0
	if status_label.text == LAN_SEARCH_NOTICE:
		set_status("")


## The hero fighter cruises right, bobbing gently, then comes back around.
func _animate_hero_plane(delta: float) -> void:
	var view := _view_size()
	var span := view.x + 520.0
	_hero_x = fposmod(_hero_x + HERO_SPEED * delta, span)
	_hero_bob += delta
	hero_plane.position.x = -260.0 + _hero_x
	hero_plane.position.y = view.y * 0.10 + sin(_hero_bob * 0.9) * 9.0
	hero_plane.rotation = -0.05 + sin(_hero_bob * 0.7) * 0.03


func _animate_clouds(delta: float) -> void:
	var view := _view_size()
	for i in _clouds.size():
		var cloud := _clouds[i]
		cloud.position.x += _cloud_speeds[i] * delta
		if cloud.position.x > view.x + 200.0:
			cloud.position.x = -200.0
		elif cloud.position.x < -200.0:
			cloud.position.x = view.x + 200.0


## Fades the card in with a short rise so the title screen has a beat of motion.
func _intro_animation() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	card.pivot_offset = card.size * 0.5
	card.modulate.a = 0.0
	card.scale = Vector2(0.97, 0.97)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, 0.35)
	tween.tween_property(card, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _view_size() -> Vector2:
	var view := get_viewport_rect().size
	return view if view.x > 0.0 else Vector2(1280.0, 720.0)


func _set_weather(kind: int) -> void:
	selected_weather = kind
	auto_button.button_pressed = kind < 0
	clear_button.button_pressed = kind == Weather.Kind.CLEAR
	cloudy_button.button_pressed = kind == Weather.Kind.CLOUDY
	rain_button.button_pressed = kind == Weather.Kind.RAIN
	snow_button.button_pressed = kind == Weather.Kind.SNOW


func _set_difficulty(difficulty: int) -> void:
	_difficulty = difficulty
	easy_button.button_pressed = difficulty == AIConfig.Difficulty.EASY
	normal_button.button_pressed = difficulty == AIConfig.Difficulty.NORMAL
	hard_button.button_pressed = difficulty == AIConfig.Difficulty.HARD


## Shows a status line under the buttons (LAN lobby state, errors, notices).
func set_status(text: String) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()


## Disables the mode buttons while a LAN connection is being set up.
func set_lan_waiting(waiting: bool) -> void:
	if waiting:
		Lan.stop_host_search()
		_search_notice_until = 0
	play_button.disabled = waiting
	survival_button.disabled = waiting
	local_button.disabled = waiting
	for button: Button in [auto_button, clear_button, cloudy_button, rain_button, snow_button]:
		button.disabled = waiting
	prev_plane_button.disabled = waiting
	next_plane_button.disabled = waiting
	host_button.disabled = waiting
	join_button.disabled = waiting
	address_field.editable = not waiting


func _start(mode: int) -> void:
	InputManager.clear_virtual_actions()
	play_requested.emit(mode, _difficulty)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_accept"):
		_start(GameManager.Mode.SINGLE_PLAYER)
