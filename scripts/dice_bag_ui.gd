extends HBoxContainer

@onready var label = $Label

func update_label(count: int):
	label.text = str(count)
