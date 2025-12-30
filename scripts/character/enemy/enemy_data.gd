extends Resource
class_name EnemyData

@export var enemy_name: String = "Enemy"
@export var sprite_texture: Texture2D
@export var minimum_hp: int = 1
@export var gold_minimum: int = 0
@export var gold_amount: Array[Die] = []
@export var hp_dice: Array[Die]
@export var action_pool: Array[EnemyAction]
