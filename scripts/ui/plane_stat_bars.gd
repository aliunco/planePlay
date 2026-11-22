class_name PlaneStatBars
extends Control
## The fighter picker's readout: one labelled bar per property, with the number
## itself on the right, so two aircraft can be compared before the match instead
## of in the middle of one.
##
## Drawn rather than built from nodes: four rows of a track, a fill and two lines
## of text is less code as a paint routine, and it scales with the card.

## Height of one row, and what the control asks for when it has four of them.
const ROW_HEIGHT: float = 12.0
const LABEL_WIDTH: float = 46.0
const VALUE_WIDTH: float = 30.0
const BAR_GAP: float = 8.0
const BAR_HEIGHT: float = 5.0
const FONT_SIZE: int = 10

const TRACK_COLOR := Color(0.35, 0.45, 0.55, 0.30)
const FILL_COLOR := Color("ffcb5c")
const LABEL_COLOR := Color(0.78, 0.86, 0.94, 0.82)
const VALUE_COLOR := Color(0.94, 0.97, 1.0, 0.95)

var _rows: Array[Dictionary] = []
var _style := StyleBoxFlat.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style.anti_aliasing = true
	_style.corner_detail = 6
	resized.connect(queue_redraw)


func set_stats(rows: Array[Dictionary]) -> void:
	_rows = rows
	custom_minimum_size = Vector2(0.0, ROW_HEIGHT * float(maxi(1, rows.size())))
	queue_redraw()


func row_count() -> int:
	return _rows.size()


func _draw() -> void:
	if _rows.is_empty() or size.x < LABEL_WIDTH + VALUE_WIDTH + 40.0:
		return
	var font := ThemeDB.fallback_font
	for i in _rows.size():
		var row := _rows[i]
		var top := float(i) * ROW_HEIGHT
		var baseline := top + ROW_HEIGHT - 3.0
		draw_string(
			font,
			Vector2(0.0, baseline),
			str(row.get("label", "")),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			FONT_SIZE,
			LABEL_COLOR
		)

		var bar_width := size.x - LABEL_WIDTH - VALUE_WIDTH - BAR_GAP
		var bar := Rect2(
			LABEL_WIDTH, top + (ROW_HEIGHT - BAR_HEIGHT) * 0.5, bar_width, BAR_HEIGHT
		)
		_box(bar, 3, TRACK_COLOR)

		var ratio := clampf(float(row.get("ratio", 0.0)), 0.0, 1.0)
		if ratio > 0.01:
			_box(Rect2(bar.position, Vector2(bar_width * ratio, BAR_HEIGHT)), 3, FILL_COLOR)
			# A bright cap on the leading edge, so a short bar still reads as filled.
			if bar_width * ratio > 4.0:
				_box(
					Rect2(bar.position + Vector2(bar_width * ratio - 2.0, 0.0), Vector2(2.0, BAR_HEIGHT)),
					1,
					Color(1.0, 1.0, 1.0, 0.65)
				)

		draw_string(
			font,
			Vector2(size.x - VALUE_WIDTH, baseline),
			str(row.get("value", "")),
			HORIZONTAL_ALIGNMENT_RIGHT,
			VALUE_WIDTH,
			FONT_SIZE,
			VALUE_COLOR
		)


func _box(rect: Rect2, radius: int, color: Color) -> void:
	_style.bg_color = color
	_style.border_color = Color(0, 0, 0, 0)
	_style.set_border_width_all(0)
	_style.set_corner_radius_all(maxi(0, radius))
	draw_style_box(_style, rect)
