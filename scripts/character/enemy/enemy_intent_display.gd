extends Control

var FACES = {}
var ACTION_ICONS = {}

@onready var icon: TextureRect = $Icon
@onready var roll_label: Label = $RollLabel
@onready var action_type_icon: TextureRect = $ActionTypeIcon
@onready var action_name_label: Label = $ActionNameLabel

func _ready():
	# Use load() at runtime instead of preload() at parse time to avoid importer issues.
	FACES = {
		2: load("res://assets/ai/dice/d2.svg"),
		4: load("res://assets/ai/dice/d4.svg"),
		6: load("res://assets/ai/dice/d6.svg"),
		8: load("res://assets/ai/dice/d8.svg"),
		10: load("res://assets/ai/dice/d10.svg"),
		12: load("res://assets/ai/dice/d12.svg"),
		20: load("res://assets/ai/dice/d20.svg")
	}
	ACTION_ICONS = {
		"attack": load("res://assets/ai/ui/sword.svg"),
		"shield": load("res://assets/ai/ui/shield.svg"),
		"charge": load("res://assets/ai/ui/reload.svg")
	}

func update_display(action_name: String, value: int, sides: int, action_type: String):
	action_name_label.text = action_name

	if action_type == "charge":
		# For charging actions, hide the value and die icon, and show the reload icon.
		roll_label.visible = false
		icon.visible = false
		action_type_icon.texture = ACTION_ICONS["charge"]
		action_type_icon.visible = true
		icon.modulate = Color.WHITE # Reset color just in case
	else:
		# For standard attack/shield actions, show all info.
		roll_label.visible = true
		icon.visible = true
		roll_label.text = str(value)
		
		if FACES.has(sides):
			icon.texture = FACES[sides]
		else:
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
