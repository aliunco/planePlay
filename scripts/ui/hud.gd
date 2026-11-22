class_name GameHUD
extends CanvasLayer
## In-game HUD: both pilot cards, mode text, take-off prompt, pause overlay.
## The two cards are the focus: glass panels with a badge, an accent rail that
## turns red when that plane is nearly done, a readable health number, and a
## hand-drawn capsule bar under it. The whole layer fades in with a match so the
## game has a moment to settle.

signal pause_pressed
signal resume_pressed
signal restart_pressed
signal menu_pressed

@onready var root: Control = $Root
@onready var player_name_label: Label = $Root/PlayerPanel/PlayerName
@onready var player_bar: HealthBar = $Root/PlayerPanel/PlayerBar
@onready var opponent_name_label: Label = $Root/OpponentPanel/OpponentName
@onready var opponent_bar: HealthBar = $Root/OpponentPanel/OpponentBar
@onready var mode_label: Label = $Root/ModeLabel
@onready var prompt_label: Label = $Root/PromptLabel
@onready var pause_button: Button = $Root/PauseButton
@onready var pause_overlay: Control = $Root/PauseOverlay
@onready var pause_title: Label = $Root/PauseOverlay/Panel/Box/PauseTitle

var _player_base_name: String = "Player 1"
var _opponent_base_name: String = "Player 2"
var _cards: Dictionary = {}
var _value_labels: Dictionary = {}
var _boost_gauges: Dictionary = {}
var _bomb_labels: Dictionary = {}
var _flare_labels: Dictionary = {}
var _shield_labels: Dictionary = {}
var _bomb_counts: Dictionary = {}
var _bomb_reloads: Dictionary = {}
var _gear_labels: Dictionary = {}
var _special_labels: Dictionary = {}
var _radar: RadarDial
var _prompt_pill: Panel
var _score_label: Label
var _score_value: int = -1


func _ready() -> void:
	_apply_style()
	pause_overlay.visible = false
	pause_button.pressed.connect(func() -> void: pause_pressed.emit())
	($Root/PauseOverlay/Panel/Box/ResumeButton as Button).pressed.connect(
		func() -> void: resume_pressed.emit()
	)
	($Root/PauseOverlay/Panel/Box/RestartButton as Button).pressed.connect(
		func() -> void: restart_pressed.emit()
	)
	($Root/PauseOverlay/Panel/Box/MenuButton as Button).pressed.connect(
		func() -> void: menu_pressed.emit()
	)
	set_prompt("")
	_fade_in()


func _fade_in() -> void:
	root.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(root, "modulate:a", 1.0, 0.35)


func _apply_style() -> void:
	_build_cards()
	_add_label_backdrop(mode_label)
	player_bar.segments = PlaneConfig.HITS_TO_KILL
	opponent_bar.segments = PlaneConfig.HITS_TO_KILL
	UIStyle.style_label(player_name_label, 19)
	UIStyle.style_label(opponent_name_label, 19, Color("ffd9cf"))
	UIStyle.style_label(mode_label, 19, UIStyle.TEXT_MUTED)
	UIStyle.style_label(prompt_label, 27, UIStyle.ACCENT)
	prompt_label.add_theme_color_override("font_outline_color", Color(0.04, 0.09, 0.14, 0.85))
	prompt_label.add_theme_constant_override("outline_size", 6)

	# The prompt sits over the road and fields, so it carries its own pill instead
	# of relying on the sky behind it for contrast.
	_prompt_pill = Panel.new()
	_prompt_pill.add_theme_stylebox_override(
		"panel", UIStyle.panel_style(Color(0.04, 0.09, 0.14, 0.70), 13, Color(1, 1, 1, 0.09), false)
	)
	_prompt_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt_pill.visible = false
	root.add_child(_prompt_pill)
	root.move_child(_prompt_pill, prompt_label.get_index())

	UIStyle.style_circle_button(pause_button, UIStyle.ACCENT, 20)
	pause_button.text = "II"
	_add_gear_labels()
	_build_score_label()
	_build_radar()

	UIStyle.style_label(pause_title, 34, UIStyle.ACCENT)
	for button: Button in [
		$Root/PauseOverlay/Panel/Box/ResumeButton,
		$Root/PauseOverlay/Panel/Box/RestartButton,
		$Root/PauseOverlay/Panel/Box/MenuButton,
	]:
		UIStyle.style_button(button)
	var panel := $Root/PauseOverlay/Panel as PanelContainer
	var style := UIStyle.panel_style(Color(0.05, 0.11, 0.17, 0.96), 22, UIStyle.ACCENT)
	style.content_margin_left = 30.0
	style.content_margin_right = 30.0
	style.content_margin_top = 26.0
	style.content_margin_bottom = 26.0
	style.shadow_size = 28
	style.shadow_offset = Vector2(0.0, 12.0)
	panel.add_theme_stylebox_override("panel", style)


## The glass card behind each pilot, plus the health readout on the far side of
## the header from the name.
func _build_cards() -> void:
	for slot: int in [1, 2]:
		var panel := get_node("Root/PlayerPanel" if slot == 1 else "Root/OpponentPanel") as Control
		var card := PilotCard.new()
		card.mirrored = slot != 1
		card.accent = UIStyle.ACCENT if slot == 1 else UIStyle.ACCENT_WARM
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.add_child(card)
		panel.move_child(card, 0)
		_cards[slot] = card

		# The jet-boost tank: a slim strip in the gap under the health bar.
		var gauge := BoostGauge.new()
		gauge.mirrored = slot != 1
		gauge.position = Vector2(14.0, 73.0)
		gauge.size = Vector2(312.0, 7.0)
		panel.add_child(gauge)
		_boost_gauges[slot] = gauge

		var value := Label.new()
		value.text = ""
		value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		value.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT if slot == 1 else HORIZONTAL_ALIGNMENT_LEFT
		)
		value.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if slot == 1:
			value.position = Vector2(244.0, 8.0)
		else:
			value.position = Vector2(16.0, 8.0)
		value.size = Vector2(78.0, 32.0)
		panel.add_child(value)
		UIStyle.style_label(value, 17, UIStyle.ACCENT if slot == 1 else Color("ffd9cf"))
		value.horizontal_alignment = (
			HORIZONTAL_ALIGNMENT_RIGHT if slot == 1 else HORIZONTAL_ALIGNMENT_LEFT
		)
		_value_labels[slot] = value


## Two lines under each pilot card: the throttle gear and the bomb rack on the
## first, then the flare dispenser opposite the crate round the guns are holding
## (empty until one is picked up).
func _add_gear_labels() -> void:
	for slot: int in [1, 2]:
		var gear := _make_card_label(slot, 108.0, 130.0)
		gear.text = "GEAR %d / %d" % [PlaneConfig.DEFAULT_GEAR, PlaneConfig.GEAR_FACTORS.size()]
		_gear_labels[slot] = gear

		# Bombs share the gear's line, reading in from the other end of the card.
		var bombs := _make_card_label(slot, 108.0, 130.0)
		if slot == 1:
			bombs.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			bombs.offset_left = 196.0
		else:
			bombs.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			bombs.offset_right = -196.0
		bombs.text = "BOMBS 0"
		_bomb_labels[slot] = bombs

		var special := _make_card_label(slot, 130.0, 152.0)
		special.text = ""
		_special_labels[slot] = special

		# Flares share the crate-round line, reading in from the other end.
		var flares := _make_card_label(slot, 130.0, 152.0)
		if slot == 1:
			flares.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			flares.offset_left = 210.0
		else:
			flares.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			flares.offset_right = -210.0
		flares.text = "FLARES 0"
		_flare_labels[slot] = flares

		# The shield reads on its own line, so a live countdown is never squeezed
		# in beside the flare count.
		var shield := _make_card_label(slot, 152.0, 174.0)
		if slot == 1:
			shield.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			shield.offset_left = 190.0
		else:
			shield.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			shield.offset_right = -190.0
		shield.text = ""
		_shield_labels[slot] = shield


## The survival tally, just under the mode line: how many fighters this run has
## shot down, and the best run on this device.
func _build_score_label() -> void:
	_score_label = Label.new()
	root.add_child(_score_label)
	_score_label.anchor_left = 0.5
	_score_label.anchor_right = 0.5
	_score_label.offset_left = -240.0
	_score_label.offset_right = 240.0
	_score_label.offset_top = 54.0
	_score_label.offset_bottom = 82.0
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(_score_label, 21, UIStyle.ACCENT)
	_score_label.add_theme_constant_override("outline_size", 5)
	_score_label.add_theme_color_override("font_outline_color", Color(0.04, 0.09, 0.14, 0.85))
	_score_label.visible = false


func set_score_visible(shown: bool) -> void:
	if _score_label != null:
		_score_label.visible = shown


## The duel scoreboard: how many rounds each pilot has taken, and which round is
## next. A round win flashes the line so the score is noticed without a popup.
func set_tally(text: String, flash: bool = false) -> void:
	if _score_label == null:
		return
	_score_label.text = text
	_score_label.visible = not text.is_empty()
	if flash:
		_score_label.modulate = Color(1.7, 1.55, 1.05, 1.0)
		var tween := create_tween()
		tween.tween_property(_score_label, "modulate", Color.WHITE, 0.5)


## Updates the survival tally; a fresh kill flashes the line so the count is
## noticed without a popup.
func set_score(score: int, best: int) -> void:
	if _score_label == null:
		return
	var previous := _score_value
	_score_value = score
	_score_label.text = "ENEMIES DOWN %d   ·   BEST %d" % [score, best]
	if score > previous:
		_score_label.modulate = Color(1.7, 1.55, 1.05, 1.0)
		var tween := create_tween()
		tween.tween_property(_score_label, "modulate", Color.WHITE, 0.5)


## The scanner on the left, under the pilot card: the first place a pilot looks
## when the enemy is somewhere off screen.
func _build_radar() -> void:
	_radar = RadarDial.new()
	root.add_child(_radar)
	_radar.offset_left = 28.0
	_radar.offset_top = 166.0
	_radar.offset_right = 28.0 + RadarDial.DIAL_SIZE.x
	_radar.offset_bottom = 166.0 + RadarDial.DIAL_SIZE.y
	_radar.visible = false


## Hidden when both airplanes share the screen (local versus), since then there is
## nothing to find.
func set_radar_visible(shown: bool) -> void:
	if _radar != null:
		_radar.visible = shown


func set_radar(offset: Vector2, range_px: float, heading: float, has_enemy: bool) -> void:
	if _radar != null:
		_radar.set_target(offset, range_px, heading, has_enemy)


func set_radar_cargo(
	courier_offset: Vector2,
	has_courier: bool,
	drop_offset: Vector2,
	drop_kind: int,
	has_drop: bool
) -> void:
	if _radar != null:
		_radar.set_cargo(courier_offset, has_courier, drop_offset, drop_kind, has_drop)


## A small muted label pinned under one of the pilot cards.
func _make_card_label(slot: int, top: float, bottom: float) -> Label:
	var label := Label.new()
	label.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if slot == 1 else HORIZONTAL_ALIGNMENT_RIGHT
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UIStyle.style_label(label, 15, UIStyle.TEXT_MUTED)
	root.add_child(label)
	label.offset_top = top
	label.offset_bottom = bottom
	if slot == 1:
		label.offset_left = 38.0
		label.offset_right = 338.0
	else:
		label.anchor_left = 1.0
		label.anchor_right = 1.0
		label.offset_left = -338.0
		label.offset_right = -128.0
	return label


## Shows which crate round is loaded; the next shot spends it, so the line clears
## when it fires.
func set_special(slot: int, round_kind: int) -> void:
	var label: Label = _special_labels.get(slot, null)
	if label == null:
		return
	match round_kind:
		Airplane.SpecialRound.KILLER:
			label.text = "INSTANT ROUND READY"
			label.modulate = Color(1.0, 0.62, 0.52)
		Airplane.SpecialRound.HOMING:
			label.text = "HOMING ROUND READY"
			label.modulate = Color(0.62, 0.86, 1.0)
		_:
			label.text = ""


## Bombs left in the rack. An empty rack dims, so a pilot notices there is
## nothing left to drop before reaching for the button.
func set_bombs(slot: int, count: int) -> void:
	_bomb_counts[slot] = maxi(0, count)
	_render_bombs(slot)


## A reload running on the rack, in seconds. It takes over the bomb line, so the
## wait is part of the readout rather than something to guess at.
func set_bomb_reload(slot: int, seconds_left: float) -> void:
	_bomb_reloads[slot] = maxf(0.0, seconds_left)
	_render_bombs(slot)


func _render_bombs(slot: int) -> void:
	var label: Label = _bomb_labels.get(slot, null)
	if label == null:
		return
	var left: float = _bomb_reloads.get(slot, 0.0)
	if left > 0.0:
		label.text = "RELOAD %ds" % int(ceil(left))
		label.modulate = Color(1.0, 0.84, 0.42)
		return
	var count: int = _bomb_counts.get(slot, 0)
	label.text = "BOMBS %d" % count
	label.modulate = Color.WHITE if count > 0 else Color(1.0, 1.0, 1.0, 0.42)


## Shield charges, or how long the running bubble has left.
func set_shield(slot: int, charges: int, remaining: float) -> void:
	var label: Label = _shield_labels.get(slot, null)
	if label == null:
		return
	if remaining > 0.0:
		label.text = "SHIELD %ds" % int(ceil(remaining))
		label.modulate = Color(0.72, 0.8, 1.0)
	elif charges > 0:
		label.text = "SHIELD %d" % charges
		label.modulate = Color.WHITE
	else:
		label.text = ""


## Flares left in the dispenser. An empty dispenser dims, so a pilot knows there
## is no countermeasure left before a homing round is already in the air.
func set_flares(slot: int, count: int) -> void:
	var label: Label = _flare_labels.get(slot, null)
	if label == null:
		return
	label.text = "FLARES %d" % maxi(0, count)
	label.modulate = Color.WHITE if count > 0 else Color(1.0, 1.0, 1.0, 0.42)


## How full the jet-boost tank is, 0..1.
func set_boost(slot: int, ratio: float) -> void:
	var gauge: BoostGauge = _boost_gauges.get(slot, null)
	if gauge != null:
		gauge.set_ratio(ratio)


func set_gear(slot: int, gear: int, maximum: int) -> void:
	var label: Label = _gear_labels.get(slot, null)
	if label == null:
		return
	label.text = "GEAR %d / %d" % [gear, maximum]
	label.modulate = Color(1.0, 0.86, 0.55) if gear > 1 else Color.WHITE


## Keeps the mode text readable when a bright cloud drifts behind it.
func _add_label_backdrop(label: Label) -> void:
	var backdrop := Panel.new()
	backdrop.add_theme_stylebox_override(
		"panel", UIStyle.panel_style(Color(0.05, 0.11, 0.17, 0.55), 13, Color(1, 1, 1, 0.07), false)
	)
	backdrop.anchor_left = label.anchor_left
	backdrop.anchor_top = label.anchor_top
	backdrop.anchor_right = label.anchor_right
	backdrop.anchor_bottom = label.anchor_bottom
	backdrop.offset_left = label.offset_left - 16.0
	backdrop.offset_top = label.offset_top - 4.0
	backdrop.offset_right = label.offset_right + 16.0
	backdrop.offset_bottom = label.offset_bottom + 4.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var parent := label.get_parent()
	parent.add_child(backdrop)
	parent.move_child(backdrop, label.get_index())


func setup_names(player_name: String, opponent_name: String, mode_text: String) -> void:
	_player_base_name = player_name
	_opponent_base_name = opponent_name
	player_name_label.text = player_name
	opponent_name_label.text = opponent_name
	mode_label.text = mode_text
	player_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	opponent_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func set_health(slot: int, current: int, maximum: int) -> void:
	maximum = maxi(1, maximum)
	var bar: HealthBar = player_bar if slot == 1 else opponent_bar
	var ratio := float(clampi(current, 0, maximum)) / float(maximum)
	# The bar animates itself: it drains, holds a ghost of the damage just taken
	# and turns its fill from green through amber to red.
	bar.set_health(current, maximum)
	var card: PilotCard = _cards.get(slot, null)
	if card != null:
		card.set_health_ratio(ratio)
	var value: Label = _value_labels.get(slot, null)
	if value != null:
		value.text = "%d/%d" % [current, maximum]
	var name_label := player_name_label if slot == 1 else opponent_name_label
	name_label.text = _player_base_name if slot == 1 else _opponent_base_name


func set_mode_text(text: String) -> void:
	mode_label.text = text


func set_prompt(text: String) -> void:
	prompt_label.text = text
	prompt_label.visible = text != ""
	if _prompt_pill != null:
		_prompt_pill.visible = text != ""
		if text != "":
			_fit_prompt_pill()
	if text != "":
		prompt_label.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(prompt_label, "modulate:a", 1.0, 0.3)


## Sizes the pill to the text, so short prompts do not get a full-width bar.
func _fit_prompt_pill() -> void:
	var font := prompt_label.get_theme_font("font")
	var font_size := prompt_label.get_theme_font_size("font_size")
	var text_width := font.get_string_size(
		prompt_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size
	).x
	_prompt_pill.anchor_left = 0.5
	_prompt_pill.anchor_right = 0.5
	_prompt_pill.anchor_top = 1.0
	_prompt_pill.anchor_bottom = 1.0
	_prompt_pill.offset_left = -text_width * 0.5 - 28.0
	_prompt_pill.offset_right = text_width * 0.5 + 28.0
	_prompt_pill.offset_top = -164.0
	_prompt_pill.offset_bottom = -114.0


func set_paused(paused: bool) -> void:
	pause_overlay.visible = paused
	pause_button.visible = not paused
	if paused:
		pause_overlay.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(pause_overlay, "modulate:a", 1.0, 0.18)
