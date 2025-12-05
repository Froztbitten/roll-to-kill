extends Control

signal reward_chosen(die: Die)

@onready var dice_choices_container = $VBoxContainer/DiceChoices
@onready var skip_reward_button = $Container/SkipRewards

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
	# Connect the "pressed" signal for each die display button that already exists in the scene.
	for display_node: RewardsDieDisplay  in dice_choices_container.get_children():
		if display_node is Button and not display_node.is_connected("pressed", _on_die_display_clicked):
			display_node.pressed.connect(_on_die_display_clicked.bind(display_node))
			
	skip_reward_button.pressed.connect(_on_skip_rewards_clicked.bind(skip_reward_button))

func display_rewards(dice_options: Array[Die]):
	visible = true
	var dice_displays = dice_choices_container.get_children()
	for i in range(dice_options.size()):
		var die = dice_options[i]
		if i < dice_displays.size():
			# Cast the node to its actual script type to access custom functions.
			var display = dice_displays[i]
			display.set_die(die)

func _on_die_display_clicked(display: RewardsDieDisplay):	
	# Select the clicked die to give visual feedback
	if display.has_method("select"):
		display.select()

	# After a short delay to show the selection, confirm the choice.
	await get_tree().create_timer(0.3).timeout
	emit_signal("reward_chosen", display.die)

func _on_skip_rewards_clicked(display):
	print("Skipping reward...")
	# Select the clicked die to give visual feedback
	if display.has_method("select"):
		display.select()

	await get_tree().create_timer(0.3).timeout
	emit_signal("reward_chosen", null)
