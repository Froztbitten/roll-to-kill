extends VBoxContainer

signal die_clicked(die_display)

# --- IMPORTANT ---
# You must replace these placeholder paths with the actual paths to your dice face images.
# The paths have been corrected to match your project structure.
const FACES = [
	preload("res://assets/d6.svg"),
	preload("res://assets/d8.svg"),
	preload("res://assets/d10.svg")
]

# When the 'die' variable is set from dice_ui.gd, the 'set_die' function will be called.
var die: Dictionary:
	set = set_die

@onready var icon: TextureRect = $Icon
@onready var roll_label: Label = $Icon/RollLabel

func _ready():
	print("DieDisplay _ready: die = " + str(die))
	# Temporary debug text to see if it gets overwritten
	roll_label.text = "DEBUG_DEFAULT" 
	if die:
		update_display()
	
	# Make sure the control can receive mouse input
	mouse_filter = MOUSE_FILTER_PASS


func set_die(value: Dictionary):
	die = value
	print("DieDisplay set_die: die = " + str(die))
	# Wait until the node is ready before trying to update its children.
	if is_node_ready():
		update_display()


func update_display():
	print("DieDisplay update_display called. Current die: " + str(die))
	if die and die.has("value"):
		var die_value = die["value"]
		var die_sides = die["sides"]
		print("DieDisplay: Displaying Roll: " + str(die_value) + ", Sides: " + str(die_sides))
		roll_label.text = str(die_value)
		var icon_index = -1
		match die_sides:
			6:
				icon_index = 0
			8:
				icon_index = 1
			10:
				icon_index = 2
		
		if icon_index != -1 and not FACES.is_empty():
			icon.texture = FACES[icon_index]


func select():
	# Visually indicate that the die is selected (e.g., make it brighter)
	modulate = Color(1.5, 1.5, 1.5)


func deselect():
	# Return to normal appearance
	modulate = Color(1, 1, 1)


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			# When clicked, emit a signal with a reference to itself
			emit_signal("die_clicked", self)
			get_viewport().set_input_as_handled()
