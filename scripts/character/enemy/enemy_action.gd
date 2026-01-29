extends Resource
class_name EnemyAction

enum ActionType { ATTACK, SHIELD, SUPPORT_SHIELD, HEAL_ALLY, PIERCING_ATTACK, SPAWN_MINIONS, BUFF, DO_NOTHING, FLEE, DEBUFF }

@export var action_name: String = "Action"
@export var action_type: ActionType = ActionType.ATTACK

@export var base_value: int = 0
@export var dice_count: int = 0
@export var dice_sides: int = 6
@export var status_id: String = ""
@export var duration: int = -1
@export var charges: int = -1
@export var self_destructs: bool = false
@export var ignore_dice_roll: bool = false
@export var self_damage: int = 0
@export var summon_list: Array[String] = []
