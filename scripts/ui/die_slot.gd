extends Panel
class_name DieSlotUI

signal die_placed(die_display, die_data)
signal die_removed(die_display)

var current_die_display: Control = null

# Checks if the dragged data can be dropped here.
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	# We only accept drops if the slot is empty and the data is from a DieDisplay.
	if current_die_display == null and data is Dictionary and data.has("die_data"):
		var die_data: Die = data.die_data
		
		# --- VALIDATION LOGIC ---
		# This is where you can define the rules for this slot based on the
		# ability it belongs to. For now, we accept any die.
		# Example: return die_data.result_value >= 4
		return true
			
	return false

# Handles the actual drop.
func _drop_data(at_position: Vector2, data: Variant):
	var die_display_node: Control = data.source_display
	
	# Notify the die's original pool that it has been successfully moved.
	if die_display_node.has_method("notify_drop_successful"):
		die_display_node.notify_drop_successful()
	
	# Reparent the die from its old container to this slot.
	if die_display_node.get_parent():
		die_display_node.get_parent().remove_child(die_display_node)
	
	add_child(die_display_node)
	die_display_node.position = size / 2 - die_display_node.size / 2 # Center it
	die_display_node.main_display.visible = true # Ensure it's visible
	
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
