extends HBoxContainer
class_name DiceUI

signal intent_created(die, roll, target)

var die_display_scene = preload("res://scenes/die_display.tscn")

func clear_arrows():
	get_tree().call_group("arrows", "queue_free")

func _on_intent_created(die, roll, target):
	emit_signal("intent_created", die, roll, target)

func set_hand(dice_hand):
	# Clear existing dice displays
	for child in get_children():
		child.queue_free()

	for die_data in dice_hand:
		var die_display = die_display_scene.instantiate()
		die_display.die = die_data
		die_display.intent_created.connect(_on_intent_created)
		add_child(die_display)