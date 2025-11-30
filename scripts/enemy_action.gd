extends Resource
class_name EnemyAction

enum ActionType { ATTACK, SHIELD }

@export var action_name: String = "Action"
@export var action_type: ActionType = ActionType.ATTACK

@export var dice_to_roll: Array[Dice]
