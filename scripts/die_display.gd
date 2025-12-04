extends Control

signal die_clicked(die_display)

const DieGridCell = preload("res://scenes/dice/die_grid_cell.tscn")

# --- IMPORTANT ---
# You must replace these placeholder paths with the actual paths to your dice face images.
var FACES = {}

var die: Dictionary:
	set = set_die

@onready var main_display: PanelContainer = $MainDisplay
@onready var icon_texture: TextureRect = $MainDisplay/Icon
@onready var roll_label: Label = $MainDisplay/RollLabel
@onready var face_grid: PanelContainer = $FaceGrid
@onready var grid_container: GridContainer = $FaceGrid/Grid

func _ready():
	FACES = {
		4: load("res://assets/d4.svg"),
		6: load("res://assets/d6.svg"),
		8: load("res://assets/d8.svg"),
		10: load("res://assets/d10.svg"),
		12: load("res://assets/d12.svg"),
		20: load("res://assets/d20.svg")
	}
	
	# Add a black outline to the main roll label for better readability
	roll_label.add_theme_color_override("font_outline_color", Color.BLACK)
	roll_label.add_theme_constant_override("outline_size", 8)
	
	# Remove the default panel background from the main display area
	main_display.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


func set_die(value: Dictionary):
	die = value
	if is_node_ready():
		update_display()

func update_display():
	if not die or not die.has("object"):
		return

	# --- 1. Update the default display (Icon and RollLabel) ---
	var rolled_value = die.value
	var die_sides = die.sides
	roll_label.text = str(rolled_value)
	if FACES.has(die_sides):
		icon_texture.texture = FACES[die_sides]

	# --- 2. Populate the hidden hover grid ---
	# Clear previous grid contents
	for child in grid_container.get_children():
		child.queue_free()

	var die_object: Dice = die.object
	
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

	var faces = die_object.face_values
	if faces.is_empty():
		# Fallback if face_values isn't set on the Dice resource
		faces = range(1, die.sides + 1)

	for i in range(faces.size()):
		var face_value = faces[i]
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
		if i == die_object.result_face:
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
