extends HBoxContainer
class_name DicePool

signal die_clicked(die_display)

const DIE_DISPLAY_SCENE = preload("res://scenes/dice/die_display.tscn")

var dice_pool_display: Array[DieDisplay] = []

func set_hand(rolled_dice: Array[Die]):
	var num_new_dice = rolled_dice.size()

	# Ensure we have enough display nodes, creating more if necessary.
	while dice_pool_display.size() < num_new_dice:
		var die_display = DIE_DISPLAY_SCENE.instantiate()
		add_child(die_display)
		die_display.die_clicked.connect(func(display): emit_signal("die_clicked", display))
		dice_pool_display.append(die_display)
		# Start new dice as hidden so they can be animated in.
		#die_display.hide()

	# Update displays, animating dice that are entering or leaving the hand.
	for i in range(dice_pool_display.size()):
		var display = dice_pool_display[i]
		if i < num_new_dice:
			# This display is needed. Update its data.
			display.set_die(rolled_dice[i])
			# If it was hidden (either new or from a smaller previous hand), animate it in.
			#if not display.visible:
				#display.animate_in()
		#else:
			# This display is not needed. If it's currently visible, animate it out.
			#if display.visible:
				#display.animate_out()

func get_current_dice() -> Array[Die]:
	"""Returns the array of Die objects currently being displayed."""
	var current_dice: Array[Die] = []
	for display in dice_pool_display:
		if display.visible and display.die:
			current_dice.append(display.die)
	return current_dice
