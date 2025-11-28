extends Control

var FACES = {}

@onready var icon: TextureRect = $Icon
@onready var roll_label: Label = $Icon/RollLabel

func _ready():
	# Use load() at runtime instead of preload() at parse time to avoid importer issues.
	FACES = {
		2: load("res://assets/coin.svg"),
		4: load("res://assets/d4.svg"),
		8: load("res://assets/d8.svg"),
		12: load("res://assets/d12.svg"),
		20: load("res://assets/d20.svg")
	}

func update_display(value: int, sides: int):
	roll_label.text = str(value)
	
	if FACES.has(sides):
		icon.texture = FACES[sides]
	else:
		# Fallback to d8 if an unknown die type is used
		icon.texture = FACES[8]