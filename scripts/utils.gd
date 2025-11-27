extends Node

func take_turn(attacker, defender):
	var damage = randi_range(5, 15)
	defender.take_damage(damage)
	print(attacker.name + " attacks " + defender.name + " for " + str(damage) + " damage.")
