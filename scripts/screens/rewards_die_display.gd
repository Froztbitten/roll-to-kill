extends Button
class_name RewardsDieDisplay

signal die_hovered(die_display)

@onready var die_label: Label = $DieLabel
@onready var die_icon: TextureRect = $DieLabel/DieIcon
@onready var face_grid: GridContainer = $FaceGrid
@onready var average_label: Label = $AverageLabel
const DieGridCell = preload("res://scenes/dice/die_grid_cell.tscn")

var die: Die
var original_grid_text: String # Used for the Alt-hover average display
var is_selected = false
var average_roll = 0
var upgrades_list: VBoxContainer

func _ready():
	# 1. Create a new stylebox
	var new_style = StyleBoxFlat.new()
	new_style.bg_color = Color(0.9, 0.7, 0.2)
		
	# Optional: Apply it to hover/pressed so it doesn't flicker gray
	add_theme_stylebox_override("hover", new_style)
	add_theme_stylebox_override("pressed", new_style)

	# Create a container to display the list of upgrades on the die.
	upgrades_list = VBoxContainer.new()
	upgrades_list.name = "UpgradesList"
	upgrades_list.mouse_filter = MOUSE_FILTER_IGNORE # Let clicks pass through to the button.
	upgrades_list.set_anchors_preset(Control.PRESET_TOP_WIDE)
	upgrades_list.position.y = 45 # Position it below the face grid.
	add_child(upgrades_list)

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


func set_die(die_data: Die):
	deselect()
	
	self.die = die_data
	var die_object: Die = die_data

	# Clear previous contents of the grid
	for child in face_grid.get_children():
		child.queue_free()

	if die.result_value > 0:
		# Standard display for rolled dice in hand
		scale = Vector2(1, 1) # Reset scale for hand display
		face_grid.columns = 1
		
		var cell = DieGridCell.instantiate()
		var label = cell.get_node("Label")
		label.text = str(die.result_value)
		label.set("theme_override_font_sizes/font_size", 48) # Make the single number large
		cell.add_theme_stylebox_override("panel", StyleBoxEmpty.new()) # Remove panel style for single value
		face_grid.add_child(cell)
		original_grid_text = str(die.result_value)
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
		
		# The die resource now has an array of DieFace objects
		for face_data in die_object.faces:
			var cell = DieGridCell.instantiate()
			cell.get_node("Label").text = str(face_data.value)
			face_grid.add_child(cell)
			
			# If the face has an effect, highlight it
			if not face_data.effects.is_empty():
				var effect: DieFaceEffect = face_data.effects[0]
				var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
				style.bg_color = effect.highlight_color
				cell.add_theme_stylebox_override("panel", style)
		
		# Clear previous list
		for child in upgrades_list.get_children():
			child.queue_free()
			
		var unique_effects = []
		for face_data in die_object.faces:
			if not face_data.effects.is_empty():
				for effect in face_data.effects:
					if not unique_effects.has(effect.name):
						unique_effects.append(effect.name)
						
						var label = RichTextLabel.new()
						label.bbcode_enabled = true
						label.text = "[center][color=#%s]%s[/color][/center]" % [effect.highlight_color.to_html(), effect.name]
						label.fit_content = true
						label.autowrap_mode = TextServer.AUTOWRAP_OFF
						label.mouse_filter = MOUSE_FILTER_PASS
						label.scroll_active = false
						label.add_theme_font_size_override("normal_font_size", 14)
						
						label.tooltip_text = _clean_bbcode(effect.description.replace("{value}", "Face Value").replace("{value / 2}", "Face Value / 2"))
						upgrades_list.add_child(label)
		
		upgrades_list.visible = not unique_effects.is_empty()

		original_grid_text = "" # Not needed for multi-cell grid
		
	die_label.text = "d" + str(die.sides)
	
	# Set the icon behind the side label
	if die_icon:
		if die_object:
			var icon_path = die_object.icon_path
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
	#self.color = Color(0.9, 0.7, 0.2) # Gold color for selection
	
func deselect():
	is_selected = false
	#self.colo color = Color(0.2, 0.2, 0.2) # Default dark gray

func _on_mouse_entered():
	emit_signal("die_hovered", self)

func _on_mouse_exited():
	# Revert text when mouse exits, in case Alt was held.
	if face_grid.get_child_count() > 0 and original_grid_text != "":
		var first_cell_label = face_grid.get_child(0).get_node("Label") as Label
		first_cell_label.text = original_grid_text

func _clean_bbcode(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(text, "", true)
