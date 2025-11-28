extends ProgressBar

@onready var label: Label = $Label
@onready var damage_preview_bar: ProgressBar = $DamagePreviewBar

func update_display(current_value: int, new_max_value: int, intended_damage: int = 0):
	# Set the max value for both bars
	self.max_value = new_max_value
	damage_preview_bar.max_value = new_max_value
	
	# The red bar shows the current health.
	damage_preview_bar.value = current_value
	
	# The green bar underneath shows what the health will be after damage.
	value = current_value - intended_damage
	
	# Update the text label
	label.text = "%d / %d" % [current_value, new_max_value]