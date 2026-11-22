class_name GameOverScreen
extends Control
## Result overlay shown when a match ends. The dim screen fades in first, then
## the panel pops into place so the result lands with a bit of weight.

signal rematch_pressed
signal menu_pressed

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel
@onready var box: VBoxContainer = $Panel/Box
@onready var title_label: Label = $Panel/Box/Title
@onready var subtitle_label: Label = $Panel/Box/Subtitle
@onready var rematch_button: Button = $Panel/Box/Buttons/RematchButton
@onready var menu_button: Button = $Panel/Box/Buttons/MenuButton

var _shown_once: bool = false


func _ready() -> void:
	UIStyle.style_label(title_label, 46, UIStyle.ACCENT)
	UIStyle.style_label(subtitle_label, 21, UIStyle.TEXT_PRIMARY)
	UIStyle.style_button(rematch_button, UIStyle.ACCENT, 23)
	UIStyle.style_primary_button(rematch_button, UIStyle.ACCENT, 23)
	UIStyle.style_button(menu_button, UIStyle.ACCENT, 23)

	var style := UIStyle.panel_style(Color(0.05, 0.11, 0.17, 0.96), 24, UIStyle.ACCENT)
	style.content_margin_left = 40.0
	style.content_margin_right = 40.0
	style.content_margin_top = 30.0
	style.content_margin_bottom = 30.0
	style.shadow_size = 30
	style.shadow_offset = Vector2(0.0, 14.0)
	panel.add_theme_stylebox_override("panel", style)

	# A gold rule under the headline, matching the title screen.
	var rule := UIStyle.make_rule(UIStyle.ACCENT, 3.0, 110.0)
	box.add_child(rule)
	box.move_child(rule, title_label.get_index() + 1)

	rematch_button.pressed.connect(func() -> void: rematch_pressed.emit())
	menu_button.pressed.connect(func() -> void: menu_pressed.emit())


func show_result(title: String, subtitle: String) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	rematch_button.disabled = false
	visible = true
	modulate.a = 0.0
	dim.modulate.a = 0.0

	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.93, 0.93)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "modulate:a", 1.0, 0.22)
	tween.tween_property(dim, "modulate:a", 1.0, 0.3)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(
		Tween.EASE_OUT
	)
	_shown_once = true


func hide_result() -> void:
	visible = false


## Replaces the subtitle, e.g. while waiting for the other pilot's rematch.
func set_status(text: String) -> void:
	subtitle_label.text = text


func set_rematch_enabled(enabled: bool) -> void:
	rematch_button.disabled = not enabled
