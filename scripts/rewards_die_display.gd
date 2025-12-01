extends Button

signal die_hovered(die_display)

@onready var background: ColorRect = $Background
@onready var die_label: Label = $DieLabel
@onready var die_icon: TextureRect = $DieLabel/DieIcon
@onready var face_grid: GridContainer = $FaceGrid
@onready var average_label: Label = $AverageLabel
const DiceGridCell = preload("res://scenes/dice_grid_cell.tscn")

var die: Dictionary # {"object": Dice, "value": int, "sides": int}
var original_grid_text: String # Used for the Alt-hover average display
var is_selected = false # Renamed from 'selected' for clarity
var average_roll = 0

func _ready():
	# Hide by default until set_die is called.
	# This is useful for the reward screen where displays are pre-placed.
	visible = false

func _process(_delta):
	# On every frame, check if the mouse is over this control and if ALT is pressed.
	# This provides immediate feedback to the user.
	if get_global_rect().has_point(get_global_mouse_position()):
		if Input.is_key_pressed(KEY_ALT) and average_roll > 0:
			average_label.text = "Avg:\n%.1f" % average_roll
			average_label.visible = true
		else:
			average_label.visible = false
	else:
		# Ensure the label is hidden if the mouse is not hovering.
		average_label.visible = false


func set_die(die_data: Dictionary):
	deselect()
	
	self.die = die_data
	var die_object: Dice = die_data.object

	# Clear previous contents of the grid
	for child in face_grid.get_children():
		child.queue_free()

	if die.value > 0:
		# Standard display for rolled dice in hand
		scale = Vector2(1, 1) # Reset scale for hand display
		face_grid.columns = 1
		
		var cell = DiceGridCell.instantiate()
		var label = cell.get_node("Label")
		label.text = str(die.value)
		label.set("theme_override_font_sizes/font_size", 48) # Make the single number large
		cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new()) # Remove panel style for single value
		face_grid.add_child(cell)
		original_grid_text = str(die.value)
	else:
		# Larger display for unrolled dice on the reward screen
		scale = Vector2(1.5, 1.5) # Scale up the entire control
		
		# Set columns to achieve the desired number of rows
		match die.sides:
			4, 6:
				face_grid.columns = die.sides
			8:
				face_grid.columns = 4 # 2 rows
			10:
				face_grid.columns = 5 # 2 rows
			12:
				face_grid.columns = 6 # 2 rows
			20:
				face_grid.columns = 5 # 4 rows
			_:
				face_grid.columns = 4 # Default fallback
		face_grid.add_theme_constant_override("h_separation", -1)
		face_grid.add_theme_constant_override("v_separation", -1)
		
		var faces: Array
		if die_object and not die_object.face_values.is_empty():
			faces = die_object.face_values.duplicate() # Duplicate to avoid modifying the resource
			faces.sort()
		else:
			faces = range(1, die.sides + 1)
		
		for face in faces:
			var cell = DiceGridCell.instantiate()
			cell.get_node("Label").text = str(face)
			face_grid.add_child(cell)
		original_grid_text = "" # Not needed for multi-cell grid
		
	die_label.text = "d" + str(die.sides)
	
	# Set the icon behind the side label
	if die_icon:
		if die_object:
			var icon_path = die_object.get_icon_path()
			if not icon_path.is_empty():
				die_icon.texture = load(icon_path)
			else:
				die_icon.texture = null # Clear texture if no icon is found
		else:
			die_icon.texture = null
	
	average_roll = (float(die.sides) + 1.0) / 2.0

	visible = true

func select():
	is_selected = true
	background.color = Color(0.9, 0.7, 0.2) # Gold color for selection
	
func deselect():
	is_selected = false
	background.color = Color(0.2, 0.2, 0.2) # Default dark gray

func _on_mouse_entered():
	emit_signal("die_hovered", self)

func _on_mouse_exited():
	# Revert text when mouse exits, in case Alt was held.
	if face_grid.get_child_count() > 0 and original_grid_text != "":
		var first_cell_label = face_grid.get_child(0).get_node("Label") as Label
		first_cell_label.text = original_grid_text
