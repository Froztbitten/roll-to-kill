extends Node2D

var end_turn_button: Button
@onready var dice_ui: DiceUI = $"UI/DiceUI"
@onready var dice_bag_ui: Control = $"UI/DiceBagUI"

var intents: Dictionary = {}
var selected_die_display = null

func _ready():
	end_turn_button = $"UI/EndTurnButton"
	GameManager.player = $Player
	GameManager.enemy = $Enemies.get_child(0)

	# Connect signals
	dice_ui.die_clicked.connect(_on_die_clicked)

	player_turn()

func player_turn():
	dice_ui.clear_displays()
	# Reset block at the start of the turn
	GameManager.player.block = 0
	intents = {}
	_clear_selection()
	
	var rolled_dice = []
	var hand = GameManager.player.draw_hand()
	for die in hand:
		var roll = die.roll()
		rolled_dice.append({"object": die, "value": roll, "sides": die.sides})
	
	dice_ui.set_hand(rolled_dice)
	dice_bag_ui.update_label(GameManager.player.dice.size())
	end_turn_button.disabled = false

func _on_end_turn_button_pressed():
	if GameManager.current_turn == GameManager.Turn.PLAYER:
		resolve_dice_intents()
		GameManager.next_turn()
		enemy_turn()

func resolve_dice_intents():
	for intent in intents.values():
		if intent.target is Player:
			GameManager.player.block += intent.roll
		else:
			Utils.take_turn(GameManager.player, intent.target)
		
	print("Player block: " + str(GameManager.player.block))

func enemy_turn():
	end_turn_button.disabled = true
	await get_tree().create_timer(1.0).timeout
	if GameManager.current_turn == GameManager.Turn.ENEMY:
		Utils.take_turn(GameManager.enemy, GameManager.player)
		GameManager.next_turn()
		player_turn()

func _on_die_clicked(die_display):
	if selected_die_display == die_display:
		# If the same die is clicked again, deselect it
		_clear_selection()
	else:
		# Deselect the old one (if any)
		if selected_die_display:
			selected_die_display.deselect()
		
		# Select the new one
		selected_die_display = die_display
		selected_die_display.select()
		print("Intent action started. Select a target for die with value: " + str(selected_die_display.die.value))

func _unhandled_input(event: InputEvent):
	# This function catches input that was not handled by the UI.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		# Perform a physics query at the click position.
		# Use get_global_mouse_position() for coordinates in the global 2D world space.
		var mouse_pos = get_global_mouse_position()
		var space_state = get_world_2d().direct_space_state
		# Create a point query parameter object, not a ray query.
		var query = PhysicsPointQueryParameters2D.new()
		query.position = mouse_pos
		query.collide_with_bodies = true # Ensure we check for characters
		query.collision_mask = 1 # Check physics layer 1
		var result = space_state.intersect_point(query)

		for r in result:
			if r.collider is Character:
				# We clicked a character, so call the handler function manually.
				_on_character_clicked(r.collider)
				# Mark the event as handled so it doesn't trigger other things.
				get_viewport().set_input_as_handled()
				return


func _on_character_clicked(character):
	print("Character clicked: " + str(character))
	# If no die is selected, do nothing
	if not selected_die_display:
		return

	var die_value = selected_die_display.die.value
	print("Intent action: Use die with value %d on %s." % [die_value, character.name])

	# Create an intent using the selected die's data
	# Use the die_display object as the key, since it's a unique reference.
	# A dictionary (die_data) cannot be used as a key.
	var die_object = selected_die_display.die.object
	var die_roll_value = selected_die_display.die.value
	intents[selected_die_display] = {"die": die_object, "roll": die_roll_value, "target": character}
	print("Intents: " + str(intents))

	# Visually "consume" the die by making it inactive.
	# This prevents using the same die for multiple intents.
	selected_die_display.set_process_input(false)
	selected_die_display.modulate = Color(0.5, 0.5, 0.5)
	# Deselect the die after using it
	_clear_selection()

func _clear_selection():
	if selected_die_display:
		selected_die_display.deselect()
	selected_die_display = null
