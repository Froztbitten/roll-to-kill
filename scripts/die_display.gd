extends VBoxContainer

signal die_clicked(die_display)

# --- IMPORTANT ---
# You must replace these placeholder paths with the actual paths to your dice face images.
var FACES = {}

var die: Dictionary:
	set = set_die

@onready var icon_texture: TextureRect = $Icon
@onready var roll_label: Label = $Icon/RollLabel

func _ready():
	print("DieDisplay _ready: die = " + str(die))
	FACES = {
		2: load("res://assets/coin.svg"),
		4: load("res://assets/d4.svg"),
		6: load("res://assets/d6.svg"),
		8: load("res://assets/d8.svg"),
		10: load("res://assets/d10.svg"),
		12: load("res://assets/d12.svg"),
		20: load("res://assets/d20.svg")
	}
	
	# Set font color to black with a white outline for better readability
	roll_label.add_theme_color_override("font_color", Color.BLACK)
	roll_label.add_theme_color_override("font_outline_color", Color.WHITE)
	roll_label.add_theme_constant_override("outline_size", 4)
	# Temporary debug text to see if it gets overwritten
	roll_label.text = "DEBUG_DEFAULT" 
	if die:
		update_display()
	
	# Make sure the control can receive mouse input.
	mouse_filter = MOUSE_FILTER_STOP


func set_die(value: Dictionary):
	die = value
	print("DieDisplay set_die: die = " + str(die))
	if is_node_ready():
		update_display()


func update_display():
	print("DieDisplay update_display called. Current die: " + str(die))
	if die and die.has("value"):
		var die_value = die["value"]
		var die_sides = die["sides"]
		print("DieDisplay: Displaying Roll: " + str(die_value) + ", Sides: " + str(die_sides))
		roll_label.text = str(die_value)
		
		if FACES.has(die_sides):
			icon_texture.texture = FACES[die_sides]


func select():
	# Visually indicate that the die is selected (e.g., make it brighter)
	modulate = Color(1.8, 1.8, 1.8)
	var tween = create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.1)


func deselect():
	# Return to normal appearance
	modulate = Color(1, 1, 1)
	var tween = create_tween().set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
			print("test2")
			# When clicked, emit a signal with a reference to itself
			emit_signal("die_clicked", self)
			get_viewport().set_input_as_handled()
