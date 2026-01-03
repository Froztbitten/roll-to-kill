extends Panel
class_name DieSlotUI

signal die_placed(die_display, die_data)
signal die_removed(die_display)

var player: Player = null
var current_die_display: Control = null
var current_scale_factor: float = 1.0

func _ready():
	resized.connect(_on_resized)

func _on_resized():
	if current_die_display:
		# Ensure the die display is centered
		current_die_display.size = current_die_display.custom_minimum_size
		current_die_display.position = (size - current_die_display.size) / 2.0

# Checks if the dragged data can be dropped here.
func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if player and player.has_status("Silence"):
		print("Player is Silenced and cannot use abilities!")
		return false

	# We only accept drops if the slot is empty and the data is from a DieDisplay.
	if current_die_display == null and data is Dictionary and data.has("die_data"):
		return true
			
	return false

# Handles the actual drop.
func _drop_data(_at_position: Vector2, data: Variant):
	var die_display_node: DieDisplay = data.source_display

	# Tell the source pool to remove the die. This handles scene tree removal and signals.
	if die_display_node.dice_pool:
		die_display_node.dice_pool.remove_die(die_display_node)

	# Now, reparent the die to this slot.
	add_child(die_display_node)
	die_display_node.set_anchors_preset(Control.PRESET_TOP_LEFT)
	die_display_node.scale = Vector2.ONE
	die_display_node.main_display.visible = true # Ensure it's visible
	if die_display_node.has_method("update_scale"):
		die_display_node.update_scale(current_scale_factor * 0.8)
	
	# Center it after scaling
	die_display_node.size = die_display_node.custom_minimum_size
	die_display_node.position = (size - die_display_node.size) / 2.0
	
	current_die_display = die_display_node
	current_die_display.set_mouse_filter(MOUSE_FILTER_IGNORE) # Prevent dragging from the slot
	
	emit_signal("die_placed", current_die_display, data.die_data)

func _gui_input(event: InputEvent):
	# Handle right-clicking on the slot to return the die.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		if current_die_display:
			var die_to_return = current_die_display
			current_die_display = null
			
			# The die display is a child of the slot, so we remove it.
			remove_child(die_to_return)
			# Allow the die to be dragged and clicked again by restoring its default mouse filter.
			die_to_return.set_mouse_filter(Control.MOUSE_FILTER_STOP)
			emit_signal("die_removed", die_to_return)
			get_viewport().set_input_as_handled()

func update_scale(factor: float):
	current_scale_factor = factor
	var base_size = 40.0
	custom_minimum_size = Vector2(base_size, base_size) * factor
	
	if current_die_display and current_die_display.has_method("update_scale"):
		current_die_display.update_scale(factor * 0.8)
		current_die_display.size = current_die_display.custom_minimum_size
		current_die_display.position = (size - current_die_display.size) / 2.0
