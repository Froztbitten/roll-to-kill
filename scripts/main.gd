extends Node2D

var end_turn_button: Button
@onready var dice_ui: DiceUI = $"UI/DiceUI"
@onready var dice_bag_ui: Control = $"UI/DiceBagUI"
@onready var intent_lines: Node2D = $IntentLines
@onready var discard_pile_ui = $"UI/DiscardPileUI"
@onready var total_dice_value_label: Label = $"UI/TotalDiceValueLabel"
@onready var total_incoming_damage_label: Label = $"UI/TotalIncomingDamageLabel"
@onready var victory_screen = $"UI/VictoryScreen"
@onready var defeat_screen = $"UI/DefeatScreen"

var intents: Dictionary = {}
var selected_die_display = null
var current_hand_dice: Array[Dice] = []
var current_incoming_damage: int = 0


func _ready():
	end_turn_button = $"UI/EndTurnButton"
	GameManager.player = $Player
	GameManager.enemy = $Enemies.get_child(0)

	# Connect signals
	dice_ui.die_clicked.connect(_on_die_clicked)
	GameManager.player.died.connect(_on_player_died)
	
	# Connect the died signal for each enemy
	for enemy in $Enemies.get_children():
		enemy.died.connect(_on_enemy_died)

	player_turn()

func player_turn():
	dice_ui.clear_displays()
	# Reset block at the start of the turn
	GameManager.player.block = 0
	_clear_intents()
	_clear_selection()

	# Discard the dice from the previous hand
	if not current_hand_dice.is_empty():
		GameManager.player.discard_pile.append_array(current_hand_dice)
		current_hand_dice.clear()
	
	var rolled_dice = []
	var total_dice_value = 0
	var hand = GameManager.player.draw_hand()
	for die in hand:
		var roll = die.roll()
		current_hand_dice.append(die) # Keep track of the dice in the current hand
		total_dice_value += roll
		rolled_dice.append({"object": die, "value": roll, "sides": die.sides})
	
	total_dice_value_label.text = "Total: " + str(total_dice_value)
	current_incoming_damage = 0
	# Have all living enemies declare their intents for the turn
	for enemy in $Enemies.get_children():
		if enemy.hp > 0:
			# Reset enemy block at the start of the player's turn
			enemy.block = 0
			enemy.update_health_display()

			enemy.declare_intent()
			current_incoming_damage += enemy.next_action_value
	
	total_incoming_damage_label.text = str(current_incoming_damage)
	_update_intended_block_display()
	_update_all_intended_damage_displays()

	dice_ui.set_hand(rolled_dice)
	dice_bag_ui.update_label(GameManager.player.dice.size())
	discard_pile_ui.update_label(GameManager.player.discard_pile.size())
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
			var enemy_target = intent.target
			# Check if the enemy has a shield intent and apply it before damage.
			if enemy_target.next_action and enemy_target.next_action.action_type == EnemyAction.ActionType.SHIELD:
				enemy_target.block += enemy_target.next_action_value
				# We can clear the intent here since it's now "used"
				enemy_target.clear_intent()

			enemy_target.take_damage(intent.roll)
		
	print("Player block: " + str(GameManager.player.block))

func enemy_turn():
	end_turn_button.disabled = true
	await get_tree().create_timer(1.0).timeout
	if GameManager.current_turn == GameManager.Turn.ENEMY:
		# Each living enemy attacks with its declared damage
		for enemy in $Enemies.get_children():
			if enemy.hp > 0:
				if enemy.next_action.action_type == EnemyAction.ActionType.ATTACK:
					GameManager.player.take_damage(enemy.next_action_value)
				elif enemy.next_action.action_type == EnemyAction.ActionType.SHIELD: # Shield was already applied
					enemy.update_health_display()
				enemy.clear_intent()
		GameManager.next_turn()
		player_turn()

func _on_die_clicked(die_display):
	var just_cleared_intent = false
	# If the clicked die already has an intent, clear that intent first.
	if intents.has(die_display):
		var intent_data = intents[die_display]
		if intent_data.has("line"):
			intent_data.line.queue_free()
		intents.erase(die_display)
		print("Cleared existing intent for die with value: " + str(die_display.die.value))
		_update_all_intended_damage_displays()
		_update_intended_block_display()
		just_cleared_intent = true

	# If we clicked the currently selected die (and didn't just clear its intent), deselect it.
	if selected_die_display == die_display and not just_cleared_intent:
		_clear_selection()
	else:
		# A new die was clicked, or an old intent was just cleared.
		# Deselect any other die that might be selected.
		if selected_die_display:
			selected_die_display.deselect()
		
		# Select the clicked die and start the intent action.
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

	# --- Create the full arrow with outline and arrowhead ---
	var arrow_container = Node2D.new()

	# 1. Create the black outline line (drawn first)
	var line_outline = Line2D.new()
	line_outline.width = 7.0 # Thicker for the outline effect
	line_outline.default_color = Color.BLACK
	arrow_container.add_child(line_outline)

	# 2. Create the main colored line
	var line_main = Line2D.new()
	line_main.width = 3.0
	if character is Player:
		line_main.default_color = Color(0.6, 0.7, 1, 1)
	else:
		line_main.default_color = Color.CRIMSON
	arrow_container.add_child(line_main)

	var start_pos = selected_die_display.get_global_transform_with_canvas().get_origin() + selected_die_display.size / 2
	var end_pos = character.global_position
	var control_pos = (start_pos + end_pos) / 2 - Vector2(0, 200)
	
	# Generate points for the curve and add them to both lines
	var point_count = 20
	for i in range(point_count + 1):
		var t = float(i) / point_count
		var point = start_pos.lerp(control_pos, t).lerp(control_pos.lerp(end_pos, t), t)
		line_main.add_point(point)
		line_outline.add_point(point)

	# 3. Create the arrowhead
	var arrowhead = Polygon2D.new()
	arrowhead.color = line_main.default_color
	var arrowhead_outline = Polygon2D.new() # For the black outline
	arrowhead_outline.color = Color.BLACK
	
	var last_point = line_main.points[-1]
	var second_last_point = line_main.points[-2]
	var direction = (last_point - second_last_point).normalized()
	
	# Define arrowhead shape and outline
	arrowhead.polygon = [last_point, last_point - direction * 15 + direction.orthogonal() * 8, last_point - direction * 15 - direction.orthogonal() * 8]
	arrowhead_outline.polygon = [last_point + direction * 3, last_point - direction * 19 + direction.orthogonal() * 11, last_point - direction * 19 - direction.orthogonal() * 11]
	
	arrow_container.add_child(arrowhead_outline)
	arrow_container.add_child(arrowhead)

	intent_lines.add_child(arrow_container)

	intents[selected_die_display] = {"die": die_object, "roll": die_roll_value, "target": character, "line": arrow_container}
	print("Intents: " + str(intents))

	# Visually "consume" the die by making it inactive.
	# This prevents using the same die for multiple intents.
	# Deselect the die after using it
	_clear_selection()
	_update_intended_block_display()
	_update_all_intended_damage_displays()

func _clear_selection():
	if selected_die_display:
		selected_die_display.deselect()
	selected_die_display = null

func _clear_intents():
	# Free the line nodes before clearing the dictionary
	for intent_data in intents.values():
		if intent_data.has("line"):
			intent_data.line.queue_free()
	intents.clear()

func _update_intended_block_display():
	var total_intended_block = 0
	for intent_data in intents.values():
		if intent_data.target is Player:
			total_intended_block += intent_data.roll
	
	var label = GameManager.player.get_node("IntendedBlockLabel")
	if total_intended_block > 0:
		label.text = "+" + str(total_intended_block)
		label.visible = true
	else:
		label.visible = false
	
	# Update the player's health bar to show the damage preview
	var net_damage = max(0, current_incoming_damage - total_intended_block)
	GameManager.player.update_health_display(net_damage)

func _update_all_intended_damage_displays():
	# First, reset the display for all enemies
	for enemy in $Enemies.get_children():
		var label = enemy.get_node("IntendedDamageLabel")
		var skull = enemy.get_node("LethalDamageIndicator")
		enemy.update_health_display() # Reset to show no intended damage
		skull.visible = false
		label.visible = false

	# Then, calculate the total for each enemy based on current intents
	var enemy_damage_map = {}
	for intent_data in intents.values():
		if not intent_data.target is Player:
			if not enemy_damage_map.has(intent_data.target):
				enemy_damage_map[intent_data.target] = 0
			enemy_damage_map[intent_data.target] += intent_data.roll
	
	# Finally, update the labels for enemies with intended damage
	for enemy in enemy_damage_map:
		var label = enemy.get_node("IntendedDamageLabel")
		label.text = "-" + str(enemy_damage_map[enemy])
		label.visible = true

		var player_damage = enemy_damage_map[enemy]
		var enemy_shield = 0
		if enemy.next_action and enemy.next_action.action_type == EnemyAction.ActionType.SHIELD:
			enemy_shield = enemy.next_action_value
		
		var net_damage = max(0, player_damage - enemy_shield)
		
		# Update the health bar preview with the net damage
		enemy.update_health_display(net_damage)
		
		# Check if the intended damage is lethal
		if net_damage >= enemy.hp:
			var skull = enemy.get_node("LethalDamageIndicator")
			skull.visible = true

func _on_enemy_died():
	# Check for victory after a short delay to let other processes finish.
	await get_tree().create_timer(0.1).timeout
	
	var all_enemies_dead = true
	for enemy in $Enemies.get_children():
		if enemy.is_visible(): # Check if the enemy is still visible/alive
			all_enemies_dead = false
			break
	
	if all_enemies_dead:
		victory_screen.visible = true

func _on_play_again_button_pressed():
	# Reload the entire main scene to restart the game.
	get_tree().reload_current_scene()

func _on_player_died():
	defeat_screen.visible = true
