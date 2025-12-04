extends Control

var FACES = {}
var ACTION_ICONS = {}

@onready var icon: TextureRect = $Icon
@onready var roll_label: Label = $Icon/RollLabel
@onready var action_type_icon: TextureRect = $ActionTypeIcon

func _ready():
	# Use load() at runtime instead of preload() at parse time to avoid importer issues.
	FACES = {
		2: load("res://assets/ai/dice/coin.svg"),
		4: load("res://assets/ai/dice/d4.svg"),
		6: load("res://assets/ai/dice/d6.svg"),
		8: load("res://assets/ai/dice/d8.svg"),
		10: load("res://assets/ai/dice/d10.svg"),
		12: load("res://assets/ai/dice/d12.svg"),
		20: load("res://assets/ai/dice/d20.svg")
	}
	ACTION_ICONS = {
		"attack": load("res://assets/ai/ui/sword.svg"),
		"shield": load("res://assets/ai/ui/shield.svg")
	}

func update_display(value: int, sides: int, action_type: String):
	roll_label.text = str(value)
	
	if FACES.has(sides):
		icon.texture = FACES[sides]
	else:
		# Fallback to d8 if an unknown die type is used
		icon.texture = FACES[8]
	
	if ACTION_ICONS.has(action_type):
		action_type_icon.texture = ACTION_ICONS[action_type]
		action_type_icon.visible = true
	else:
		action_type_icon.visible = false

	if action_type == "attack":
		icon.modulate = Color.CRIMSON
	elif action_type == "shield":
		icon.modulate = Color(0.6, 0.7, 1, 1) # Same blue as player's shield
	else:
		icon.modulate = Color.WHITE # Default color
