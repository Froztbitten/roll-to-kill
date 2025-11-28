extends Resource
class_name EnemyAction

enum ActionType { ATTACK, SHIELD }

@export var action_name: String = "Action"
@export var action_type: ActionType = ActionType.ATTACK

# Example: [{"sides": 6, "count": 1}, {"sides": 4, "count": 2}] means 1d6 + 2d4
@export var dice_to_roll: Array[Dictionary]
