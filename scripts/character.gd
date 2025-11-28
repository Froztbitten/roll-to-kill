extends CharacterBody2D
class_name Character

signal died

@export var hp: int = 100
@export var max_hp: int = 100
@export var block: int = 0

@onready var health_bar = $HealthBar

func _ready():
	update_health_display()

func take_damage(damage: int):
	var damage_to_take = damage
	if block > 0:
		var blocked_damage = min(damage_to_take, block)
		damage_to_take -= blocked_damage
		block -= blocked_damage
		print("%s blocked %d damage." % [name, blocked_damage])

	hp -= damage_to_take
	if hp < 0:
		hp = 0

	if hp <= 0:
		# Emit the signal before hiding so other nodes can react.
		emit_signal("died")
		# Call the die function to handle visual removal.
		die()

	update_health_display()
	print("%s took %d damage, has %d HP left." % [name, damage_to_take, hp])

func die():
	hide() # Hide the character visually.
	get_node("CollisionShape2D").set_deferred("disabled", true) # Disable collision.

func update_health_display(intended_damage: int = 0):
	if health_bar:
		health_bar.update_display(hp, max_hp, intended_damage)