extends HBoxContainer
class_name DiceUI

signal die_clicked(die_display)

# You must replace this placeholder path with the actual path to your DieDisplay scene.
const DIE_DISPLAY_SCENE = preload("res://scenes/die_display.tscn")

var die_displays = []

func set_hand(rolled_dice: Array):
	# First, clear out the old dice from the previous turn.
	clear_displays()
	
	# Now, create and display the new hand.
	for die_data in rolled_dice:
		var die_display = DIE_DISPLAY_SCENE.instantiate()
		add_child(die_display)
		die_display.set_die(die_data)
		die_display.die_clicked.connect(func(display): emit_signal("die_clicked", display))
		die_displays.append(die_display)


func clear_displays():
	"""
	Removes all die display nodes that are children of this container.
	"""
	for display in get_children():
		display.queue_free()
	die_displays.clear()
