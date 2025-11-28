extends ProgressBar

@onready var label: Label = $Label

func update_display(current_value: int, new_max_value: int):
	# Update the progress bar value
	value = current_value
	self.max_value = new_max_value
	
	# Update the text label
	label.text = "%d / %d" % [current_value, new_max_value]