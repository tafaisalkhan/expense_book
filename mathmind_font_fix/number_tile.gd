class_name NumberTile
extends Control

signal bank_tile_selected(tile: NumberTile)
signal touch_drop_requested(tile: NumberTile, viewport_position: Vector2)

@export var value: String = "0"
var is_selected: bool = false
var is_used: bool = false
var touch_drag_started: bool = false
var active_touch_index: int = -1
var mouse_pressed: bool = false
var touch_preview: Control = null

@onready var panel: Panel = $Panel
@onready var label: Label = $Label
@onready var button: Button = $Button

func setup(val: String) -> void:
	value = val
	is_selected = false
	is_used = false

func _ready() -> void:
	# Visual children must not intercept pointer events intended for this tile.
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	update_visuals()

func set_mobile_size(tile_size: float) -> void:
	custom_minimum_size = Vector2(tile_size, tile_size)
	label.add_theme_font_size_override("font_size", clampi(roundi(tile_size * 0.55), 26, 36))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and not is_used:
			mouse_pressed = true
			touch_drag_started = false
			bank_tile_selected.emit(self)
	elif event is InputEventScreenTouch:
		if event.pressed and not is_used:
			active_touch_index = event.index
			touch_drag_started = false
			bank_tile_selected.emit(self)

func _input(event: InputEvent) -> void:
	if is_used:
		return

	if event is InputEventMouseMotion and mouse_pressed:
		if not touch_drag_started:
			_start_pointer_preview()
		_update_pointer_preview(event.position)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if mouse_pressed and not event.pressed:
			if touch_drag_started:
				touch_drop_requested.emit(self, event.position)
			_end_touch_drag()

	elif event is InputEventScreenDrag and event.index == active_touch_index:
		if not touch_drag_started:
			_start_pointer_preview()
		_update_pointer_preview(event.position)

	elif event is InputEventScreenTouch and event.index == active_touch_index and not event.pressed:
		if touch_drag_started:
			touch_drop_requested.emit(self, event.position)
		_end_touch_drag()

func _end_touch_drag() -> void:
	active_touch_index = -1
	mouse_pressed = false
	touch_drag_started = false
	if is_instance_valid(touch_preview):
		touch_preview.queue_free()
	touch_preview = null
	# A rejected drop returns the original tile to the bank. A successful drop
	# keeps it hidden because set_used(true) has already changed its state.
	update_visuals()

func _start_pointer_preview() -> void:
	touch_drag_started = true
	touch_preview = _make_drag_preview()
	touch_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	touch_preview.z_index = 100
	get_tree().root.add_child(touch_preview)
	# The preview is the tile while dragging; do not leave a duplicate behind
	# in the number bank.
	visible = false

func _update_pointer_preview(viewport_position: Vector2) -> void:
	if is_instance_valid(touch_preview):
		touch_preview.position = viewport_position - touch_preview.size * 0.5

func _make_drag_preview() -> Control:
	var preview := PanelContainer.new()
	preview.custom_minimum_size = Vector2(84, 84)
	preview.size = Vector2(84, 84)
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var preview_style := StyleBoxFlat.new()
	preview_style.bg_color = Color("#cefacf")
	preview_style.border_color = Color("#49a451")
	preview_style.border_width_left = 2
	preview_style.border_width_top = 2
	preview_style.border_width_right = 3
	preview_style.border_width_bottom = 3
	preview_style.set_corner_radius_all(12)
	preview.add_theme_stylebox_override("panel", preview_style)

	var preview_label := Label.new()
	preview_label.text = value
	preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_label.add_theme_font_size_override("font_size", 36)
	preview_label.add_theme_color_override("font_color", Color("#1b6e22"))
	preview.add_child(preview_label)
	return preview

func make_visual_copy() -> Control:
	return _make_drag_preview()

func set_selected(selected: bool) -> void:
	is_selected = selected
	update_visuals()

func set_used(used: bool) -> void:
	is_used = used
	if used:
		_end_touch_drag()
	update_visuals()

func update_visuals() -> void:
	if not is_inside_tree():
		return
		
	label.text = value
	
	if is_used:
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	else:
		visible = true
		mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 3
	style.border_width_bottom = 3
	
	if is_selected:
		# Highlighted state (active selection)
		style.bg_color = Color("#b5ecc1") # Brighter green
		style.border_color = Color("#228b2e") # Dark green border
		label.add_theme_color_override("font_color", Color("#0e5217"))
	else:
		# Standard screenshot green tile style
		style.bg_color = Color("#cefacf") # Soft light green
		style.border_color = Color("#7fcd83") # Green border
		label.add_theme_color_override("font_color", Color("#1b6e22"))
		
	panel.add_theme_stylebox_override("panel", style)
