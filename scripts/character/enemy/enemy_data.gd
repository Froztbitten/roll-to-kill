extends Resource
class_name EnemyData

@export var enemy_name: String = "Enemy"
@export var sprite_texture: Texture2D
@export var minimum_hp: int = 1
@export var gold_minimum: int = 0
@export var gold_dice: int = 0
@export var gold_dice_sides: int = 6
@export var hp_dice_count: int = 1
@export var hp_dice_sides: int = 6
@export var action_pool: Array[EnemyAction]
@export var passives: Array[EnemyAction]
