extends Control

var FACES = {}
var ACTION_ICONS = {}

@onready var icon: TextureRect = $IconContainer/Icon
@onready var action_type_icon: TextureRect = $IconContainer/ActionTypeIcon
@onready var roll_label: Label = $IconContainer/ActionTypeIcon/RollLabel
@onready var action_name_label: Label = $ActionNameLabel
@onready var dice_count_label: Label = $IconContainer/Icon/DiceCountLabel

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
		"charge": load("res://assets/ai/ui/reload.svg"),
		"heal": load("res://assets/ai/ability_icons/heal_ability_icon.jpg")
	}

func update_display(action_name: String, value: int, sides: int, action_type: String, dice_count: int):
	action_name_label.text = action_name

	if action_type == "charge":
		# For charging actions, hide the value and die icon, and show the reload icon.
		roll_label.visible = false
		icon.visible = false
		action_type_icon.texture = ACTION_ICONS["charge"]
		action_type_icon.visible = true
		dice_count_label.visible = false
		icon.modulate = Color.WHITE # Reset color just in case
	else:
		# For standard attack/shield actions, show all info.
		roll_label.visible = true
		icon.visible = true
		
		if dice_count > 1:
			dice_count_label.text = "x%d" % dice_count
			dice_count_label.visible = true
		else:
			dice_count_label.visible = false
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
		elif action_type == "heal":
			icon.modulate = Color.PALE_GREEN
		else:
			icon.modulate = Color.WHITE # Default color
