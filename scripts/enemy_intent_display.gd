extends Control

@onready var roll_label: Label = $Icon/RollLabel

func update_display(value: int):
	roll_label.text = str(value)