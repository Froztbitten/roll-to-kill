extends Node2D
class_name Character

signal no_health

@export var max_health: int = 100
var current_health: int
var block: int = 0

@onready var health_bar = $HealthBar

func _ready():
	current_health = max_health
	health_bar.max_value = max_health
	health_bar.value = current_health

func take_damage(damage_amount):
	var damage_to_take = damage_amount - block
	block = max(0, block - damage_amount)
	
	if damage_to_take > 0:
		current_health -= damage_to_take
		health_bar.value = current_health
		if current_health <= 0:
			emit_signal("no_health")
			die()

func die():
	queue_free()
