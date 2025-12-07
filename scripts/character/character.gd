extends CharacterBody2D
class_name Character

signal died
signal statuses_changed(statuses)

@export var hp: int = 100
@export var max_hp: int = 100
@export var block: int = 0
var statuses: Dictionary = {} # {StatusEffect: duration}
var _is_dead := false

@onready var health_bar = $HealthBar
@onready var name_label: Label = $NameLabel

func _ready():
	update_health_display()

func take_damage(damage: int):
	var damage_to_take = damage
	if block > 0:
		var blocked_damage = min(damage_to_take, block)
		damage_to_take -= blocked_damage
		block -= blocked_damage
		print("%s blocked %d damage." % [name, blocked_damage])
	
	_apply_damage(damage_to_take, "damage")

func take_piercing_damage(damage: int):
	# This damage type ignores block.
	_apply_damage(damage, "piercing damage")

func _apply_damage(amount: int, type: String):
	hp -= amount
	if hp < 0:
		hp = 0

	if hp <= 0:
		die()

	update_health_display()
	print("%s took %d %s, has %d HP left." % [name, amount, type, hp])

func heal(amount: int):
	hp = min(hp + amount, max_hp)
	update_health_display()
	print("%s healed for %d, has %d HP left." % [name, amount, hp])

func apply_status(status_effect, duration: int):
	statuses[status_effect] = duration
	print("%s gained status '%s' for %d rounds." % [name, status_effect.status_name, duration])
	statuses_changed.emit(statuses)

func has_status(status_name: String) -> bool:
	# Check if any of the active status effects match the given name.
	for effect in statuses:
		if effect.status_name == status_name:
			return true
	return false

func tick_down_statuses():
	if statuses.is_empty():
		return
	
	var keys_to_remove = []
	for status in statuses:
		statuses[status] -= 1
		if statuses[status] <= 0:
			keys_to_remove.append(status)
			print("%s lost status '%s'." % [name, status.status_name])
	for key in keys_to_remove:
		statuses.erase(key)
	if not keys_to_remove.is_empty():
		statuses_changed.emit(statuses)

func die():
	if _is_dead: return
	_is_dead = true
	
	hp = 0
	emit_signal("died")
	hide()  # Hide the character visually.
	get_node("CollisionShape2D").set_deferred("disabled", true)  # Disable collision.

func update_health_display(intended_damage: int = 0, intended_block: int = 0):
	if health_bar:
		health_bar.update_display(hp, max_hp, block + intended_block, intended_damage)
