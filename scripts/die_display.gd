extends Control
class_name DieDisplay

signal die_clicked(die_display)

const DieGridCell = preload("res://scenes/dice/die_grid_cell.tscn")

var die: Die:
	set = set_die

@onready var main_display: PanelContainer = $MainDisplay
@onready var icon_texture: TextureRect = $MainDisplay/Icon
@onready var roll_label: Label = $MainDisplay/RollLabel
@onready var face_grid: PanelContainer = $FaceGrid
@onready var grid_container: GridContainer = $FaceGrid/Grid

func set_die(value: Die):
	die = value
	if is_node_ready():
		update_display()

func update_display():
	if not die:
		return

	# --- 1. Update the default display (Icon and RollLabel) ---
	roll_label.text = str(die.result_value)
	icon_texture.texture = load(die.icon_path)

	# --- 2. Populate the hidden hover grid ---
	# Clear previous grid contents
	for child in grid_container.get_children():
		child.queue_free()
	
	# Set separation to -1 so that 1px borders on adjacent cells overlap perfectly
	# This creates a "shared border" look for the grid.
	grid_container.add_theme_constant_override("h_separation", -1)
	grid_container.add_theme_constant_override("v_separation", -1)

	# Set grid columns for a nice layout, similar to the reward screen
	match die.sides:
		4: grid_container.columns = 2
		6: grid_container.columns = 3
		8: grid_container.columns = 4
		10: grid_container.columns = 5
		12: grid_container.columns = 4
		20: grid_container.columns = 5
		_: grid_container.columns = 4

	for i in range(die.face_values.size()):
		var face_value = die.face_values[i]
		var cell = DieGridCell.instantiate()
		var label = cell.get_node("Label")
		label.text = str(face_value)
		
		# Add a black outline to the grid cell labels for readability
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		
		# Default style for non-highlighted cells
		var default_style = StyleBoxFlat.new()
		default_style.bg_color = Color(0.2, 0.2, 0.2, 0.8) # Dark, slightly transparent
		default_style.border_width_left = 1
		default_style.border_width_top = 1
		default_style.border_width_right = 1
		default_style.border_width_bottom = 1
		default_style.border_color = Color.BLACK
		cell.add_theme_stylebox_override("panel", default_style)
		
		# Highlight the rolled face
		if i == die.result_face:
			# Create a unique stylebox to highlight the rolled face
			var style = StyleBoxFlat.new()
			style.bg_color = Color(0.9, 0.7, 0.2, 0.5) # Translucent gold
			style.border_width_left = 1
			style.border_width_top = 1 
			style.border_width_right = 1
			style.border_width_bottom = 1
			style.border_color = Color.BLACK
			cell.add_theme_stylebox_override("panel", style) # Overwrite the default style

		grid_container.add_child(cell)

func select():
	# Visually indicate that the die is selected (e.g., make it brighter)
	main_display.modulate = Color(1.8, 1.8, 1.8)
	var tween = create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(main_display, "scale", Vector2(1.15, 1.15), 0.1)

func deselect():
	# Return to normal appearance
	main_display.modulate = Color(1, 1, 1)
	var tween = create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(main_display, "scale", Vector2(1.0, 1.0), 0.1)

func _on_mouse_entered():
	face_grid.visible = true

func _on_mouse_exited():
	face_grid.visible = false

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			# When clicked, emit a signal with a reference to itself
			emit_signal("die_clicked", self)
			get_viewport().set_input_as_handled()

func _notification(what):
	if what == NOTIFICATION_MOUSE_ENTER:
		face_grid.visible = true
	elif what == NOTIFICATION_MOUSE_EXIT:
		face_grid.visible = false
