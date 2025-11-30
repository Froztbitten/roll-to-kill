extends Control

signal die_selected(display)
signal reward_chosen(die: Dice)

@onready var dice_choices_container = $VBoxContainer/DiceChoices

func _ready():
	visible = false
	# This node and its children should continue processing when the game is paused.
	# This is crucial for the UI to remain interactive.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED

	# This ensures that when the reward screen is visible, it blocks mouse
	# events from passing through to the game world behind it.
	mouse_filter = MOUSE_FILTER_STOP

	# When the screen is hidden, we allow input to pass through again.
	visibility_changed.connect(func(): 
		get_tree().paused = visible
	)
	# Connect the signal that tells us when a child node is ready.
	dice_choices_container.child_entered_tree.connect(_on_dice_display_ready)

func _on_dice_display_ready(display_node):
	# Now that the child is ready, we can safely connect its signals.
	# A Button's "pressed" signal is the most reliable way to handle clicks.
	if display_node is Button:
		display_node.pressed.connect(_on_die_display_clicked.bind(display_node))

func display_rewards(dice_options: Array[Dice]):
	visible = true
	var dice_displays = dice_choices_container.get_children()
	for i in range(dice_options.size()):
		var die = dice_options[i]
		if i < dice_displays.size():
			# Cast the node to its actual script type to access custom functions.
			var display = dice_displays[i]
			if display.has_method("set_die"):
				# The display expects a dictionary, so we create one.
				# The "value" isn't used here, but the structure is required.
				display.set_die({"object": die, "value": 0, "sides": die.sides})

func _on_die_display_clicked(display):
	# Deselect all other dice first
	for other_display in dice_choices_container.get_children():
		if other_display != display and other_display.has_method("deselect"):
			other_display.deselect()
	
	# Select the clicked die to give visual feedback
	if display.has_method("select"):
		display.select()
	
	# After a short delay to show the selection, confirm the choice.
	await get_tree().create_timer(0.3).timeout
	emit_signal("reward_chosen", display.die.object)

func _gui_input(event: InputEvent):
	# This logic shows the average value of a die when the user holds ALT.
	if event is InputEventMouseMotion:
		for display in dice_choices_container.get_children():
			if not display.visible or not display.has_method("set_die") or not display.die:
				continue
				
			var is_hovering = display.get_global_rect().has_point(event.position)
			
			if is_hovering and Input.is_key_pressed(KEY_ALT):
				var die: Dice = display.die.object
				if die and die.face_values.size() > 0:
					var average = die.face_values.reduce(func(sum, val): return sum + val, 0) / float(die.face_values.size())
					display.roll_label.text = "Avg:\n%.1f" % average
			elif display.roll_label.text.begins_with("Avg"):
				# If not hovering with ALT, clear the average text.
				display.roll_label.text = ""
