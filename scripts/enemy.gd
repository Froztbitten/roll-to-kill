extends Character
class_name Enemy

@export var action_pool: Array[EnemyAction]

var next_action: EnemyAction
var next_action_value: int = 0

@onready var intent_display = $EnemyIntentDisplay

func declare_intent():
	if action_pool.is_empty():
		return

	# Pick a random action from the pool
	next_action = action_pool.pick_random()
	
	# Roll the dice for that action and sum the result
	next_action_value = 0
	for die_roll in next_action.dice_to_roll:
		for i in range(die_roll.count):
			next_action_value += randi() % die_roll.sides + 1
	
	# Update the UI to show the intent
	var first_die_sides = next_action.dice_to_roll[0].sides
	intent_display.update_display(next_action_value, first_die_sides, "attack" if next_action.action_type == EnemyAction.ActionType.ATTACK else "shield")
	intent_display.visible = true

func clear_intent():
	next_action_value = 0
	intent_display.visible = false
