extends Button
class_name RewardsDieDisplay

signal die_hovered(die_display)

@onready var die_label: Label = $DieLabel
@onready var die_icon: TextureRect = $DieIcon
@onready var status_label: Label = $StatusLabel
@onready var face_grid: GridContainer = $FaceGrid
@onready var average_label: Label = $AverageLabel
const DieGridCell = preload("res://scenes/dice/die_grid_cell.tscn")

var die: Die
var original_grid_text: String # Used for the Alt-hover average display
var is_selected = false
var average_roll = 0
var upgrades_list: VBoxContainer
var current_scale_factor: float = 1.0
var current_base_size: Vector2 = Vector2(120, 120)

func _ready():
	# 1. Create a new stylebox
	var new_style = StyleBoxFlat.new()
	new_style.bg_color = Color(0.9, 0.7, 0.2)
		
	# Optional: Apply it to hover/pressed so it doesn't flicker gray
	add_theme_stylebox_override("hover", new_style)
	add_theme_stylebox_override("pressed", new_style)

	face_grid.set_anchors_preset(Control.PRESET_TOP_WIDE)

	# Create a container to display the list of upgrades on the die.
	upgrades_list = VBoxContainer.new()
	upgrades_list.name = "UpgradesList"
	upgrades_list.mouse_filter = MOUSE_FILTER_IGNORE # Let clicks pass through to the button.
	upgrades_list.set_anchors_preset(Control.PRESET_TOP_WIDE)
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


func set_die(die_data: Die, force_grid: bool = false, is_upgrade_reward: bool = false, upgraded_faces_info: Array = [], show_status_text: bool = false):
	deselect()
	
	self.die = die_data
	status_label.text = ""
	var die_object: Die = die_data

	# Clear previous contents of the grid
	for child in face_grid.get_children():
		child.queue_free()

	if die.result_value > 0 and not force_grid:
		# Standard display for rolled dice in hand
		current_base_size = Vector2(80, 80)
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
		current_base_size = Vector2(120, 120)
		
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
			
		if is_upgrade_reward:
			die_label.text = "d" + str(die.sides)
			status_label.text = "(Upgrade)" if show_status_text else ""
			for face_info in upgraded_faces_info:
				var face_value = face_info["face_value"]
				var effect_name = face_info["effect_name"]
				var effect_color = face_info["effect_color"]
				
				# Highlight the corresponding cell in the grid
				for cell_idx in range(face_grid.get_child_count()):
					var cell = face_grid.get_child(cell_idx)
					if cell.get_node("Label").text == str(face_value):
						var style = cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
						style.border_color = Color(effect_color)
						style.border_width_left = 3
						style.border_width_top = 3
						style.border_width_right = 3
						style.border_width_bottom = 3
						cell.add_theme_stylebox_override("panel", style)
						break
						
				var panel = PanelContainer.new()
				var style = StyleBoxFlat.new()
				style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
				style.border_width_bottom = 2
				style.border_color = Color(effect_color)
				style.content_margin_left = 6
				style.content_margin_right = 6
				style.content_margin_top = 2
				style.content_margin_bottom = 2
				panel.add_theme_stylebox_override("panel", style)
				
				panel.mouse_filter = MOUSE_FILTER_PASS
				panel.mouse_default_cursor_shape = Control.CURSOR_HELP
				# Need to get the actual effect description from EffectLibrary
				var actual_effect = EffectLibrary.get_effect_by_name(effect_name)
				if actual_effect:
					panel.tooltip_text = _clean_bbcode(actual_effect.description.replace("{value}", str(face_value)).replace("{value / 2}", str(ceili(face_value / 2.0))))
				
				var label = Label.new()
				label.text = "Face %d: %s" % [face_value, effect_name]
				label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				label.add_theme_color_override("font_color", Color(effect_color))
				panel.add_child(label)
				upgrades_list.add_child(panel)
			upgrades_list.visible = not upgraded_faces_info.is_empty()
		else: # New Die
			die_label.text = "d" + str(die.sides)
			status_label.text = "(New)" if show_status_text else ""
			var unique_effects = []
			for face_data in die_object.faces:
				if not face_data.effects.is_empty():
					for effect in face_data.effects:
						if not unique_effects.has(effect.name):
							unique_effects.append(effect.name)
							_add_effect_panel_to_list(upgrades_list, effect, "Face Value") # Re-use existing helper
			upgrades_list.visible = not unique_effects.is_empty()

		original_grid_text = "" # Not needed for multi-cell grid
		
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

	_apply_scale()
	visible = true
	call_deferred("_update_layout")

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

func _add_effect_panel_to_list(parent_container: VBoxContainer, effect: DieFaceEffect, face_value_placeholder: String):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
	style.border_width_bottom = 2
	style.border_color = effect.highlight_color
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	panel.add_theme_stylebox_override("panel", style)
	
	panel.mouse_filter = MOUSE_FILTER_PASS
	panel.mouse_default_cursor_shape = Control.CURSOR_HELP
	
	var tooltip_desc = effect.description
	tooltip_desc = tooltip_desc.replace("{value}", face_value_placeholder)
	tooltip_desc = tooltip_desc.replace("{value / 2}", face_value_placeholder + " / 2")
	panel.tooltip_text = _clean_bbcode(tooltip_desc)
	
	var label = Label.new()
	label.text = effect.name
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", effect.highlight_color)
	panel.add_child(label)
	
	parent_container.add_child(panel)

func _apply_scale():
	custom_minimum_size = current_base_size * current_scale_factor
	
	var cell_base_size = 20.0
	var scaled_cell_size = cell_base_size * current_scale_factor
	
	for cell in face_grid.get_children():
		cell.custom_minimum_size = Vector2(scaled_cell_size, scaled_cell_size)
		var label = cell.get_node("Label")
		if face_grid.columns == 1 and face_grid.get_child_count() == 1:
			label.add_theme_font_size_override("font_size", int(48 * current_scale_factor))
		else:
			label.add_theme_font_size_override("font_size", int(14 * current_scale_factor))
			
	call_deferred("_update_layout")

func _update_layout():
	# Position the grid at the top with a small margin
	face_grid.position.y = 5 * current_scale_factor
	
	# If the upgrades list is visible, position it below the grid
	if upgrades_list.visible:
		upgrades_list.position.y = face_grid.position.y + face_grid.get_minimum_size().y + (5 * current_scale_factor)

func update_scale(factor: float):
	current_scale_factor = factor
	_apply_scale()
