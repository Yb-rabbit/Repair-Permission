extends PanelContainer
## Hint popup: draggable title bar, close with the × in the top right, confirm with the button below.
## Built entirely in code and attached under a CanvasLayer:
##     var p := preload("res://popup.gd").new()
##     layer.add_child(p)
##     p.open("Title", "[color=#8fe3ff]BBCode[/color] body")

signal confirmed
signal closed

const WIDTH := 380.0
const EDGE := 8.0
const UI_FONT := preload("res://ui_font.tres")

var _title_label: Label
var _body: RichTextLabel
var _ok_button: Button
var _built := false
var _dragging := false
var _drag_offset := Vector2.ZERO


func _ready() -> void:
	add_to_group("hint_popup")
	if not _built:
		_build()


func _build() -> void:
	_built = true
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	var th := Theme.new()
	th.default_font = UI_FONT
	th.default_font_size = 16
	theme = th

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.043, 0.078, 0.102, 0.97)
	sb.border_color = Color(0.271, 0.663, 0.784, 1)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(3)
	sb.set_content_margin_all(10)
	add_theme_stylebox_override("panel", sb)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# Title bar: the whole strip is draggable
	var head := HBoxContainer.new()
	head.custom_minimum_size = Vector2(0, 22)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_MOVE
	head.gui_input.connect(_on_head_input)
	root.add_child(head)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(0.768, 0.957, 1, 1))
	_title_label.add_theme_font_size_override("font_size", 15)
	head.add_child(_title_label)

	var x_button := Button.new()
	x_button.text = "×"
	x_button.flat = true
	x_button.focus_mode = Control.FOCUS_NONE
	x_button.tooltip_text = "Close"
	x_button.add_theme_color_override("font_color", Color(0.55, 0.68, 0.74, 1))
	x_button.pressed.connect(close)
	head.add_child(x_button)

	root.add_child(HSeparator.new())

	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - 24, 0)
	_body.add_theme_color_override("default_color", Color(0.804, 0.878, 0.902, 1))
	_body.add_theme_font_size_override("normal_font_size", 16)
	root.add_child(_body)

	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(foot)

	_ok_button = Button.new()
	_ok_button.text = "Got it"
	_ok_button.focus_mode = Control.FOCUS_NONE
	_ok_button.custom_minimum_size = Vector2(88, 28)
	_ok_button.pressed.connect(_on_confirm)
	foot.add_child(_ok_button)


func open(title: String, body: String, ok_text := "Got it") -> void:
	if not _built:
		_build()
	_title_label.text = title
	_body.text = body
	_ok_button.text = ok_text

	reset_size()
	var vp := get_viewport_rect().size
	var slot := get_tree().get_nodes_in_group("hint_popup").size() - 1
	position = Vector2(vp.x - size.x - 32.0, 104.0 + maxf(0.0, float(slot)) * 26.0)
	_clamp_into_view()

	modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 0.16)


func title_text() -> String:
	return _title_label.text if _built else ""


func close() -> void:
	if not _built:
		queue_free()
		return
	closed.emit()
	hide()
	queue_free()


func _on_confirm() -> void:
	confirmed.emit()
	close()


func _on_head_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(event.global_position)
		else:
			_end_drag()
	elif event is InputEventMouseMotion and _dragging:
		_drag_to(event.global_position)


func _begin_drag(mouse_global: Vector2) -> void:
	_dragging = true
	_drag_offset = mouse_global - global_position
	move_to_front()


func _drag_to(mouse_global: Vector2) -> void:
	position = mouse_global - _drag_offset
	_clamp_into_view()


func _end_drag() -> void:
	_dragging = false


func _clamp_into_view() -> void:
	var vp := get_viewport_rect().size
	position.x = clampf(position.x, EDGE, maxf(EDGE, vp.x - size.x - EDGE))
	position.y = clampf(position.y, EDGE, maxf(EDGE, vp.y - size.y - EDGE))


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
