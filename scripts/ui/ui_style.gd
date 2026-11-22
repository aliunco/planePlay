class_name UIStyle
extends RefCounted
## Shared look for HUD and menus. Styles are built in code so scenes stay small
## and every panel/button picks up the same colours, radii, shadows and font
## sizes. The look is a warm aviation poster: deep navy panels, a gold accent and
## soft shadows that lift the interface off the sky.

const INK := Color("0a1723")
const PANEL_BG := Color(0.05, 0.11, 0.17, 0.80)
const PANEL_BORDER := Color(1.0, 1.0, 1.0, 0.14)
const ACCENT := Color("ffcb5c")
const ACCENT_WARM := Color("ff9a52")
const TEXT_PRIMARY := Color("f6faff")
const TEXT_MUTED := Color(0.78, 0.86, 0.94, 0.82)


static func panel_style(
	bg: Color = PANEL_BG,
	radius: int = 16,
	border: Color = PANEL_BORDER,
	shadow: bool = true
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border
	style.set_border_width_all(2)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 10.0
	style.content_margin_bottom = 10.0
	if shadow:
		style.shadow_color = Color(0.02, 0.05, 0.09, 0.35)
		style.shadow_size = 14
		style.shadow_offset = Vector2(0.0, 7.0)
	style.anti_aliasing = true
	return style


## The fill colour for a health ratio: green, then amber, then a hot red.
static func health_color(ratio: float) -> Color:
	if ratio > 0.55:
		return Color("6fd68f")
	if ratio > 0.25:
		return Color("f7c95c")
	return Color("f0705c")


static func style_button(button: Button, accent: Color = ACCENT, font_size: int = 24) -> void:
	var normal := panel_style(Color(0.07, 0.15, 0.22, 0.90), 14, Color(1, 1, 1, 0.10), false)
	var hover := panel_style(Color(0.12, 0.23, 0.32, 0.96), 14, accent, true)
	var pressed := panel_style(Color(0.05, 0.12, 0.18, 0.98), 14, accent, false)
	var disabled := panel_style(Color(0.07, 0.11, 0.15, 0.55), 14, Color(1, 1, 1, 0.07), false)

	# A gold edge on the left of every button ties the interface together.
	normal.border_width_left = 3
	normal.border_color = Color(1, 1, 1, 0.10)
	hover.border_width_left = 5

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", TEXT_PRIMARY)
	button.add_theme_color_override("font_hover_color", accent)
	button.add_theme_color_override("font_pressed_color", accent)
	button.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.3))
	button.focus_mode = Control.FOCUS_NONE


## The one button that should be hit first: filled with the accent, dark text.
static func style_primary_button(button: Button, accent: Color = ACCENT, font_size: int = 26) -> void:
	var normal := panel_style(accent, 16, accent.lightened(0.25), true)
	var hover := panel_style(accent.lightened(0.12), 16, Color.WHITE, true)
	var pressed := panel_style(accent.darkened(0.10), 16, accent, false)
	normal.content_margin_top = 12.0
	normal.content_margin_bottom = 12.0
	hover.content_margin_top = 12.0
	hover.content_margin_bottom = 12.0

	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("disabled", panel_style(Color(0.35, 0.33, 0.28, 0.7), 16, Color(1, 1, 1, 0.1), false))
	button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_theme_font_size_override("font_size", font_size)
	button.add_theme_color_override("font_color", INK)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", Color(0.9, 0.9, 0.9, 0.5))
	button.focus_mode = Control.FOCUS_NONE


static func style_toggle(button: Button, accent: Color = ACCENT, font_size: int = 20) -> void:
	style_button(button, accent, font_size)
	var on_style := panel_style(accent, 12, accent.lightened(0.3), false)
	on_style.border_width_left = 3
	button.add_theme_stylebox_override("pressed", on_style)
	button.add_theme_stylebox_override("hover_pressed", on_style)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_hover_pressed_color", INK)


static func style_circle_button(button: Button, accent: Color = ACCENT, font_size: int = 20) -> void:
	style_button(button, accent, font_size)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button.get_theme_stylebox(state) as StyleBoxFlat
		if style == null:
			continue
		var radius := 28
		style.corner_radius_top_left = radius
		style.corner_radius_top_right = radius
		style.corner_radius_bottom_left = radius
		style.corner_radius_bottom_right = radius
		style.content_margin_left = 0.0
		style.content_margin_right = 0.0
		style.content_margin_top = 0.0
		style.content_margin_bottom = 0.0


static func style_line_edit(field: LineEdit, font_size: int = 22) -> void:
	var normal := panel_style(Color(0.06, 0.13, 0.20, 0.9), 14, Color(1, 1, 1, 0.10), false)
	var focus := panel_style(Color(0.10, 0.20, 0.29, 0.95), 14, ACCENT, false)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_font_size_override("font_size", font_size)
	field.add_theme_color_override("font_color", TEXT_PRIMARY)
	field.add_theme_color_override("font_placeholder_color", Color(1, 1, 1, 0.35))
	field.add_theme_color_override("caret_color", ACCENT)
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER


static func style_label(label: Label, font_size: int, color: Color = TEXT_PRIMARY) -> void:
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 2)


## Small caps label used above groups ("AI DIFFICULTY").
static func style_caption(label: Label, color: Color = Color(0.88, 0.93, 0.98, 0.92)) -> void:
	style_label(label, 15, color)
	label.add_theme_constant_override("outline_size", 0)


## Gold rule under a title, drawn as a plain control so it scales with the layout.
static func make_rule(color: Color = ACCENT, height: float = 3.0, width: float = 120.0) -> ColorRect:
	var rule := ColorRect.new()
	rule.color = color
	rule.custom_minimum_size = Vector2(width, height)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule
