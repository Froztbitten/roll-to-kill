extends Resource
class_name EnemyData

@export var enemy_name: String = "Enemy"
@export var sprite_texture: Texture2D
@export var minimum_hp: int = 1
@export var hp_dice: Array[Dice]
@export var action_pool: Array[EnemyAction]
