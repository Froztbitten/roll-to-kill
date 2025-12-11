extends HBoxContainer
class_name DicePool

signal die_clicked(die_display)
signal die_drag_started(die_display)
signal layout_changed

const DIE_DISPLAY_SCENE = preload("res://scenes/dice/die_display.tscn")

var dice_pool_display: Array[DieDisplay] = []

func clear_pool():
	for child in get_children():
		child.queue_free()
	dice_pool_display.clear()

func add_dice_instantly(dice_array: Array[Die]):
	for die_data in dice_array:
		_add_die_to_pool(die_data, false)

func _add_die_to_pool(die_data: Die, invisible: bool) -> DieDisplay:
	var die_display: DieDisplay = DIE_DISPLAY_SCENE.instantiate()
	add_child(die_display)
	die_display.dice_pool = self
	die_display.die_clicked.connect(func(display): emit_signal("die_clicked", display))
	die_display.drag_started.connect(func(display): emit_signal("die_drag_started", display))
	die_display.set_die(die_data)
	if invisible:
		die_display.modulate.a = 0.0
	dice_pool_display.append(die_display)
	return die_display

func animate_add_dice(dice_to_draw: Array[Die], start_pos: Vector2):
	if dice_to_draw.is_empty():
		return

	# 1. Add the dice to the pool invisibly to let the container arrange them.
	var displays_to_animate: Array[DieDisplay] = []
	for die_data in dice_to_draw:
		var die_display = _add_die_to_pool(die_data, true) # 'true' means invisible
		displays_to_animate.append(die_display)

	# 2. Wait for two frames to ensure the HBoxContainer has sorted and positioned the new dice.
	await get_tree().process_frame
	await get_tree().process_frame

	# 3. Animate the actual DieDisplay nodes from the bag to their now-known final positions.
	var tweens: Array[Tween] = []
	for i in range(displays_to_animate.size()):
		var display: DieDisplay = displays_to_animate[i]
		
		# Store the final destination, which is now correct.
		var final_pos = display.global_position
		var final_scale = display.scale
		var final_rotation = display.rotation
		
		# Instantly move the die to the start position and shrink it.
		# This happens between frames, so it won't be visible to the player.
		display.global_position = start_pos - (display.size / 2.0)
		display.pivot_offset = display.size / 2.0 # Set pivot for scaling from the center
		var rotation_amount = randf_range(PI * 2, PI * 4) * ([1, -1].pick_random())
		display.rotation = rotation_amount
		display.scale = Vector2.ZERO
		display.modulate.a = 1.0 # Make it visible just before the animation starts
		
		# Animate it back to its final position and scale.
		var tween = create_tween().set_parallel()
		tweens.append(tween)
		
		var duration = 0.4
		var delay = i * 0.07
		tween.tween_property(display, "global_position", final_pos, duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(display, "scale", final_scale, duration * 0.75).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(display, "rotation", final_rotation, duration).set_delay(delay).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	if not tweens.is_empty():
		await tweens.back().finished

func get_current_dice() -> Array[Die]:
	"""Returns the array of Die objects currently being displayed."""
	var current_dice: Array[Die] = []
	for display in dice_pool_display:
		# A die is "current" if it's a valid node and fully visible (not animating in).
		if is_instance_valid(display) and display.modulate.a == 1.0 and display.die:
			current_dice.append(display.die)
	return current_dice

func remove_die(die_to_remove: DieDisplay):
	if is_instance_valid(die_to_remove) and die_to_remove.get_parent() == self:
		remove_child(die_to_remove)
		if dice_pool_display.has(die_to_remove):
			dice_pool_display.erase(die_to_remove)
		layout_changed.emit()

func add_die_display(die_display: DieDisplay):
	"""Adds a die display back to the pool, e.g., when removed from a slot."""
	add_child(die_display)
	if not dice_pool_display.has(die_display):
		dice_pool_display.append(die_display)
	layout_changed.emit()
