extends Character
class_name Enemy

@export var enemy_data: EnemyData

var next_action: EnemyAction
var next_action_value: int = 0
var _is_charging := false

@onready var intent_display: Control = $EnemyIntentDisplay
@onready var sprite: TextureRect = $Sprite2D

func _ready():
	super._ready()
	if not enemy_data:
		# Disable the enemy if it has no data, to prevent crashes.
		# This can be useful for debugging in the editor.
		print_debug("Enemy has no EnemyData assigned. Disabling.")
		set_process(false)
		return

	setup()

func setup():
	"""Initializes the enemy's stats and appearance from its EnemyData resource."""
	name_label.text = enemy_data.enemy_name
	sprite.texture = enemy_data.sprite_texture
	
	var rolled_hp = 0
	for hp_die in enemy_data.hp_dice:
		rolled_hp += hp_die.roll()
	
	# Set the health properties inherited from the Character class
	# Ensure the starting HP is not below the defined minimum.
	var starting_hp = rolled_hp + enemy_data.minimum_hp
	max_hp = starting_hp
	hp = starting_hp
	_is_charging = false

func declare_intent():
	# Guard against calling this on an enemy that has no data assigned.
	if not enemy_data or enemy_data.action_pool.is_empty():
		return

	# --- Sequential Action Logic ---
	# Check if the enemy has a "charge" and "fire" type action, indicating a sequence.
	var charge_action: EnemyAction = null
	var fire_action: EnemyAction = null
	for action in enemy_data.action_pool:
		if action.action_name == "Draw Arrow":
			charge_action = action
		elif action.action_name == "Fire Arrow":
			fire_action = action

	if charge_action and fire_action:
		# This enemy uses a charge/fire sequence.
		if _is_charging:
			next_action = fire_action
			_is_charging = false
		else:
			next_action = charge_action
			_is_charging = true
	else:
		# Default behavior: pick a random action from the pool.
		next_action = enemy_data.action_pool.pick_random()

	print("Next action: ", next_action.action_name)
	# Roll the dice for that action and sum the result
	next_action_value = 0
	for action_die: Die in next_action.dice_to_roll:
		next_action_value += action_die.roll()
	
	# Safely get the icon for the intent display.
	# This prevents a crash if an action has no dice.
	var die_sides_for_icon = 8 # Default to d8 icon
	if not next_action.dice_to_roll.is_empty():
		die_sides_for_icon = next_action.dice_to_roll[0].sides

	var intent_icon_type = "attack"
	if next_action.dice_to_roll.is_empty():
		# Any action with no dice is considered a "charge" or "setup" move.
		intent_icon_type = "charge"
	elif next_action.action_type == EnemyAction.ActionType.SHIELD:
		intent_icon_type = "shield"

	# Update the UI to show the intent
	intent_display.update_display(next_action.action_name, next_action_value, die_sides_for_icon, intent_icon_type)
	intent_display.visible = true


func clear_intent():
	next_action_value = 0
	intent_display.visible = false
