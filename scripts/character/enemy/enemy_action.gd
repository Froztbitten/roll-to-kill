extends Resource
class_name EnemyAction

enum ActionType { ATTACK, SHIELD, SUPPORT_SHIELD, HEAL_ALLY, PIERCING_ATTACK, SPAWN_MINIONS, BUFF_ADVANTAGE, DO_NOTHING }

@export var action_name: String = "Action"
@export var action_type: ActionType = ActionType.ATTACK

@export var base_value: int = 0
@export var dice_to_roll: Array[Die]
@export var self_destructs: bool = false
@export var ignore_dice_roll: bool = false
