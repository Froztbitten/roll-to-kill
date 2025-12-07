extends Node2D

@export var player: Player
@onready var enemy_container = $EnemySpawner/Enemies
@onready var enemy_spawner = $EnemySpawner
@onready var intent_lines: Node2D = $IntentLines
@onready var dice_pool_ui: DicePool = $UI/DicePool
@onready var abilities_ui: VBoxContainer = $UI/Abilities
@onready var total_dice_value_label: Label = $UI/TotalDiceValueLabel
@onready var total_incoming_damage_label: Label = $UI/TotalIncomingDamageLabel
@onready var gold_label: Label = $UI/GameInfo/GoldContainer/GoldLabel

@onready var dice_bag_label: Label = $UI/RoundInfo/DiceBag/DiceBagLabel
@onready var dice_discard_label: Label = $UI/RoundInfo/DiceDiscard/DiceDiscardLabel

@onready var victory_screen = $UI/VictoryScreen
@onready var defeat_screen = $UI/DefeatScreen
@onready var reward_screen = $UI/RewardScreen
@onready var end_turn_button = $UI/EndTurnButton

enum Turn {PLAYER, ENEMY}

const ABILITY_UI_SCENE = preload("res://scenes/ui/ability.tscn")
var intents: Dictionary = {}
var selected_dice_display: Array[DieDisplay] = []
var current_incoming_damage: int = 0

var current_turn = Turn.PLAYER
var round_number := 1
const BOSS_ROUND = 10

# Testing values
var starting_abilities: Array[AbilityData] = [load("res://resources/abilities/heal.tres")]

func _ready():
	# Connect signals
	player.died.connect(_on_player_died)
	player.gold_changed.connect(_update_gold)
	player.dice_bag_changed.connect(_update_dice_bag)
	player.dice_discard_changed.connect(_update_dice_discard)
	player.abilities_changed.connect(_add_player_ability)

	dice_pool_ui.die_clicked.connect(_on_die_clicked)
	dice_pool_ui.die_drag_started.connect(_on_die_drag_started)
	reward_screen.reward_chosen.connect(_on_reward_chosen)

	# Initialize player's starting abilities
	for child: Node in abilities_ui.get_children():
		child.queue_free()
	for ability in starting_abilities:
		player.add_ability(ability)

	start_new_round()

func _add_player_ability(new_ability: AbilityData):
	# Instantiate and display a UI element for each ability the player has
	var ability_ui_instance: AbilityUI = ABILITY_UI_SCENE.instantiate() as AbilityUI
	abilities_ui.add_child(ability_ui_instance)
	ability_ui_instance.die_returned_from_slot.connect(_on_die_returned_to_pool)
	ability_ui_instance.initialize(new_ability)

func player_turn():
	enemy_container.arrange_enemies()
	# Reset block at the start of the turn
	player.block = 0
	_clear_intents()
	selected_dice_display = []
	
	var rolled_dice: Array[Die] = []
	var total_dice_value = 0
	var hand: Array[Die] = player.draw_hand()
	for die: Die in hand:
		var roll = die.roll()
		total_dice_value += roll
		rolled_dice.append(die)
	
	total_dice_value_label.text = "Total: " + str(total_dice_value)
	current_incoming_damage = 0
	# Have all living enemies declare their intents for the turn
	for enemy: Enemy in get_active_enemies():
		if enemy.hp > 0:
			# Reset enemy block at the start of the player's turn
			enemy.block = 0
			enemy.update_health_display()

			enemy.declare_intent()
			if (enemy.next_action.action_type == EnemyAction.ActionType.ATTACK):
				current_incoming_damage += enemy.next_action_value
	
	total_incoming_damage_label.text = str(current_incoming_damage)
	_update_intended_block_display()
	_update_all_intended_damage_displays()

	dice_pool_ui.set_hand(rolled_dice)
	end_turn_button.disabled = false

func _on_end_turn_button_pressed():
	if current_turn == Turn.PLAYER:
		resolve_dice_intents()
		resolve_active_abilities()
		next_turn()
		enemy_turn()

func resolve_dice_intents():
	for intent in intents.values():
		if intent.target is Player:
			player.block += intent.roll
		else:
			var enemy_target = intent.target
			# Check if the enemy has a shield intent and apply it before damage.
			if enemy_target.next_action and enemy_target.next_action.action_type == EnemyAction.ActionType.SHIELD:
				enemy_target.block += enemy_target.next_action_value
				# We can clear the intent here since it's now "used"
				enemy_target.clear_intent()

			enemy_target.take_damage(intent.roll)
		
	# Discard all dice that were in the hand this turn.
	player.discard(dice_pool_ui.get_current_dice())
	print("Player block: " + str(player.block))

func resolve_active_abilities():
	for ability_ui: AbilityUI in abilities_ui.get_children():
		if ability_ui.is_active():
			var ability_data: AbilityData = ability_ui.ability_data
			var slotted_dice_displays: Array[DieDisplay] = ability_ui.get_slotted_dice_displays()
			var dice_to_discard: Array[Die] = []

			# --- ABILITY LOGIC ---
			# This is where you'll implement the effects for different abilities.
			if ability_data.title == "Heal":
				var total_heal = 0
				for die_display in slotted_dice_displays:
					total_heal += die_display.die.result_value
					dice_to_discard.append(die_display.die)
				
				player.heal(total_heal)
				print("Resolved 'Heal' ability for %d health." % total_heal)

			# After resolving the ability, consume it.
			ability_ui.consume_ability()
			
			# Discard the Die resources used in the ability.
			player.discard(dice_to_discard)

func enemy_turn():
	end_turn_button.disabled = true
	await get_tree().create_timer(1.0).timeout
	if current_turn == Turn.ENEMY:
		# Each living enemy attacks with its declared damage
		for enemy in get_active_enemies():
			if enemy.hp > 0:
				if enemy.next_action.action_type == EnemyAction.ActionType.ATTACK:
					player.take_damage(enemy.next_action_value)
				elif enemy.next_action.action_type == EnemyAction.ActionType.SHIELD: # Shield was already applied
					enemy.update_health_display()
				enemy.clear_intent()
		next_turn()
		player_turn()

func _on_die_clicked(die_display):
	var just_cleared_intent = false
	# If the clicked die already has an intent, clear that intent first.
	if intents.has(die_display):
		var intent_data = intents[die_display]
		if intent_data.has("line"):
			intent_data.line.queue_free()
		intents.erase(die_display)
		print("Cleared existing intent for die with value: " + str(die_display.die.result_value))
		_update_all_intended_damage_displays()
		_update_intended_block_display()
		just_cleared_intent = true

	# If we clicked the currently selected die (and didn't just clear its intent), deselect it.
	if selected_dice_display.has(die_display) and not just_cleared_intent:
		selected_dice_display.erase(die_display)
		die_display.deselect()
	else:
		# Select the clicked die and start the intent action.
		selected_dice_display.append(die_display)
		die_display.select()
		print("Intent action started. Select a target for die with value: " + str(die_display.die.result_value))

func _on_die_drag_started(die_display: DieDisplay):
	# If the die being dragged is in the selection, remove it.
	if selected_dice_display.has(die_display):
		selected_dice_display.erase(die_display)
		die_display.deselect()

		# Also clear any intent that was associated with it.
		if intents.has(die_display):
			var intent_data = intents[die_display]
			if intent_data.has("line"):
				intent_data.line.queue_free()
			intents.erase(die_display)
			print("Cleared intent for dragged die.")
			_update_all_intended_damage_displays()
			_update_intended_block_display()

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


func _on_character_clicked(character: Character):
	print("Character clicked: " + str(character.name_label.text))
	# If no die is selected, do nothing
	if selected_dice_display.size() == 0:
		return

	for die_display: DieDisplay in selected_dice_display:
		print("Intent action: Use die with value %d." % die_display.die.result_value)
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

		var start_pos = die_display.get_global_transform_with_canvas().get_origin() + die_display.size / 2
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

		intents[die_display] = {"die": die_display.die, "roll": die_display.die.result_value, "target": character, "line": arrow_container}
		die_display.deselect()

	selected_dice_display = []
	_update_intended_block_display()
	_update_all_intended_damage_displays()

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
	var label = player.get_node("IntendedBlockLabel")
	if total_intended_block > 0:
		label.text = "+" + str(total_intended_block)
		label.visible = true
	else:
		label.visible = false
	
	# Update the player's health bar to show the damage preview
	var net_damage = max(0, current_incoming_damage - total_intended_block)
	player.update_health_display(net_damage)

func _update_all_intended_damage_displays():
	# First, reset the display for all enemies
	for enemy in get_active_enemies():
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
	# A short delay to prevent issues with processing the death mid-turn.
	await get_tree().create_timer(0.1).timeout
	
	if get_active_enemies().is_empty():
		# All enemies for the round are defeated
		if round_number == BOSS_ROUND:
			victory_screen.visible = true
		else:
			_show_reward_screen()
	else:
		enemy_container.arrange_enemies()

func start_new_round():
	print("Round start")
	player.reset_for_new_round()
	enemy_container.clear_everything()
	
	var spawned_enemies: Array
	if round_number == BOSS_ROUND:
		spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.BOSS)
	else:
		spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.NORMAL)
	
	for enemy in spawned_enemies:
		# Connect to each new enemy's death signal
		enemy.died.connect(_on_enemy_died.bind())
	
	# Start the player's turn for the new round
	player_turn()

func get_active_enemies() -> Array[Enemy]:
	# Helper function to get living enemies from the container
	var living_enemies: Array[Enemy] = []
	for enemy: Enemy in $EnemySpawner/Enemies.get_children():
		if enemy.hp > 0:
			living_enemies.append(enemy)
		else:
			enemy.queue_free()
	return living_enemies

func _show_reward_screen():
	var reward_dice = _generate_reward_dice()
	reward_screen.display_rewards(reward_dice)
	reward_screen.visible = true

func _generate_reward_dice() -> Array[Die]:
	var dice_options: Array[Die] = []
	# Define a target average value for the dice. This can be adjusted for balance.
	var target_average = 4.5
	var possible_sides = [4, 6, 8]
	possible_sides.shuffle()

	for i in range(3):
		var new_die = Die.new()
		var sides = possible_sides[i]
		new_die.sides = sides
		
		var total_value = int(round(target_average * sides))
		var faces: Array[int] = []
		
		# Initialize faces with a value of 1
		for _j in range(sides):
			faces.append(1)
		
		var remaining_value = total_value - sides
		
		# Distribute the remaining value randomly among the faces
		for _j in range(remaining_value):
			var random_index = randi() % sides
			faces[random_index] += 1
		
		new_die.face_values = faces
		new_die.face_values.sort()
		dice_options.append(new_die)
		print(new_die.face_values)

	return dice_options

func _on_reward_chosen(chosen_die: Die):
	print("Reward chosen: ", chosen_die.face_values)
	if (chosen_die == null):
		player.add_gold(10)
	else:
		# Add the chosen die to the player's deck
		player.add_to_game_bag([chosen_die])
	
	round_number += 1
	reward_screen.visible = false
	
	start_new_round()

func _on_play_again_button_pressed():
	# Reload the entire main scene to restart the game.
	get_tree().reload_current_scene()

func _on_player_died():
	defeat_screen.visible = true

func next_turn():
	if current_turn == Turn.PLAYER:
		current_turn = Turn.ENEMY
	else:
		current_turn = Turn.PLAYER
	
func _update_gold(gold: int):
	gold_label.text = str(gold)

func _update_dice_bag(count: int):
	dice_bag_label.text = str(count)

func _update_dice_discard(count: int):
	dice_discard_label.text = str(count)

func _on_die_returned_to_pool(die_display: DieDisplay):
	# This is called when a die is removed from an ability slot via right-click.
	dice_pool_ui.add_die_display(die_display)
