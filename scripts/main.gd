extends Node2D

@export var player: Player
@onready var enemy_container = $EnemySpawner/Enemies
@onready var enemy_spawner = $EnemySpawner
@onready var dice_pool_ui: DicePool = $UI/DicePool
@onready var abilities_ui: VBoxContainer = $UI/Abilities
@onready var total_dice_value_label: Label = $UI/TotalDiceValueLabel
@onready var total_incoming_damage_label: Label = $UI/TotalIncomingDamageLabel
@onready var gold_label: Label = $UI/GameInfo/GoldContainer/GoldLabel

@onready var dice_bag_icon: TextureRect = $UI/RoundInfo/DiceBag/DiceBagIcon
@onready var dice_bag_label: Label = $UI/RoundInfo/DiceBag/DiceBagLabel
@onready var dice_discard_label: Label = $UI/RoundInfo/DiceDiscard/DiceDiscardLabel

@onready var victory_screen = $UI/VictoryScreen
@onready var defeat_screen = $UI/DefeatScreen
@onready var reward_screen = $UI/RewardScreen
@onready var end_turn_button = $UI/EndTurnButton

enum Turn {PLAYER, ENEMY}

const ABILITY_UI_SCENE = preload("res://scenes/ui/ability.tscn")
const DIE_DISPLAY_SCENE = preload("res://scenes/dice/die_display.tscn")
var selected_dice_display: Array[DieDisplay] = []
var current_incoming_damage: int = 0
var is_resolving_action := false

var current_turn = Turn.PLAYER
var round_number := 1
const BOSS_ROUND = 10
@export var start_with_boss_fight := false

# Testing values
var starting_abilities: Array[AbilityData] = [load("res://resources/abilities/heal.tres"), 
	load("res://resources/abilities/sweep.tres"), load("res://resources/abilities/hold.tres")]

func _ready() -> void:
	# Connect signals
	player.died.connect(_on_player_died)
	player.gold_changed.connect(_update_gold)
	player.dice_bag_changed.connect(_update_dice_bag)
	player.dice_discard_changed.connect(_update_dice_discard)
	player.abilities_changed.connect(_add_player_ability)
	player.dice_drawn.connect(_on_player_dice_drawn)
	player.statuses_changed.connect(_on_player_statuses_changed)

	dice_pool_ui.die_clicked.connect(_on_die_clicked)
	dice_pool_ui.die_drag_started.connect(_on_die_drag_started)
	dice_pool_ui.die_value_changed.connect(_update_total_dice_value)
	reward_screen.reward_chosen.connect(_on_reward_chosen)

	# Initialize player's starting abilities
	for child: Node in abilities_ui.get_children():
		child.queue_free()
	for ability in starting_abilities:
		player.add_ability(ability)

	# Wait for one frame to ensure all newly created nodes (like abilities) are fully ready.
	await get_tree().process_frame

	await start_new_round()

func _add_player_ability(new_ability: AbilityData):
	# Instantiate and display a UI element for each ability the player has
	var ability_ui_instance: AbilityUI = ABILITY_UI_SCENE.instantiate() as AbilityUI
	abilities_ui.add_child(ability_ui_instance)
	ability_ui_instance.die_returned_from_slot.connect(_on_die_returned_to_pool)
	ability_ui_instance.ability_activated.connect(_on_ability_activated)
	ability_ui_instance.initialize(new_ability)

func player_turn() -> void:
	# Failsafe: Reset the action lock at the start of the player's turn.
	# This prevents the player from being locked out if the flag gets stuck
	# during a previous action, especially when transitioning between rounds.
	is_resolving_action = false

	# Reset abilities and player block from the previous turn.
	_tick_ability_cooldowns()
	player.block = 0
	for die_display in selected_dice_display:
		die_display.deselect()
	selected_dice_display.clear()
	
	dice_pool_ui.clear_pool()
	var total_dice_value = 0
	
	# Add any dice held from the previous turn to the hand first.
	var held_dice = player.get_and_clear_held_dice()
	dice_pool_ui.add_dice_instantly(held_dice)
	for die in held_dice:
		total_dice_value += die.result_value
	
	# Draw and roll new dice
	var new_dice: Array[Die] = player.draw_hand()
	for die: Die in new_dice:
		total_dice_value += die.roll()
	
	# Animate the new dice into the pool
	await dice_pool_ui.animate_add_dice(new_dice, dice_bag_icon.get_global_rect().get_center())

	total_dice_value_label.text = "Total: " + str(total_dice_value)
	current_incoming_damage = 0
	var active_enemies = get_active_enemies()
	# Have all living enemies declare their intents for the turn
	for enemy: Enemy in active_enemies:
		# Reset enemy block at the start of the player's turn
		enemy.block = 0
		# Immediately update the health bar to show the shield has been removed.
		enemy.update_health_display()

		enemy.declare_intent(active_enemies)
		if enemy.next_action and enemy.next_action.action_type == EnemyAction.ActionType.ATTACK:
			current_incoming_damage += enemy.next_action_value
	
	# Proactively apply shields that are meant to be active for the player's turn
	for enemy: Enemy in active_enemies:
		if enemy.next_action:
			if enemy.next_action.action_type == EnemyAction.ActionType.SHIELD:
				enemy.add_block(enemy.next_action_value)
			elif enemy.next_action.action_type == EnemyAction.ActionType.SUPPORT_SHIELD:
				if enemy.enemy_data.enemy_name == "Shield Generator":
					# Special case: Shield Generator shields all tinkerers.
					var shield_amount = enemy.next_action_value
					var tinkerers = active_enemies.filter(func(e): return e.enemy_data.enemy_name == "Gnomish Tinkerer")
					for tinkerer in tinkerers:
						tinkerer.add_block(shield_amount)
						print("%s shields %s for %d" % [enemy.name, tinkerer.name, shield_amount])
				else:
					# Default behavior: Shield self and one random ally.
					enemy.add_block(enemy.next_action_value)
					var other_enemies = active_enemies.filter(func(e): return e != enemy)
					if not other_enemies.is_empty():
						var random_ally = other_enemies.pick_random()
						random_ally.add_block(enemy.next_action_value)
						print("%s shields self and %s for %d" % [enemy.name, random_ally.name, enemy.next_action_value])

	total_incoming_damage_label.text = str(current_incoming_damage)
	player.update_health_display(current_incoming_damage)

	end_turn_button.disabled = false

func _on_end_turn_button_pressed():
	if current_turn == Turn.PLAYER:
		# Discard all dice that are left in the hand this turn.
		player.discard(dice_pool_ui.get_current_dice())
		print("Player block: " + str(player.block))
		await player.tick_down_statuses()
		next_turn()
		await enemy_turn()

func _tick_ability_cooldowns():
	for ability_ui: AbilityUI in abilities_ui.get_children():
		# This function now handles cooldowns for all abilities, not just used ones.
		var dice_to_discard = ability_ui.reset_for_new_turn()
		if not dice_to_discard.is_empty():
			player.discard(dice_to_discard)

func _on_ability_activated(ability_ui: AbilityUI):
	var ability_data: AbilityData = ability_ui.ability_data
	var slotted_dice_displays: Array[DieDisplay] = ability_ui.get_slotted_dice_displays()

	# --- ABILITY LOGIC ---
	# This is where you'll implement the effects for different abilities.
	if ability_data.title == "Heal":
		var total_heal = 0
		for die_display in slotted_dice_displays:
			total_heal += die_display.die.result_value
		
		player.heal(total_heal)
		print("Resolved 'Heal' ability for %d health." % total_heal)
	elif ability_data.title == "Sweep":
		if slotted_dice_displays.is_empty(): return
		
		var die_value = slotted_dice_displays[0].die.result_value
		var damage = ceili(die_value / 2.0)
		
		for enemy in get_active_enemies():
			enemy.take_damage(damage, true, player, true)
		print("Resolved 'Sweep' ability for %d damage to all enemies." % damage)
	elif ability_data.title == "Hold":
		if slotted_dice_displays.is_empty(): return
		
		var die_to_hold = slotted_dice_displays[0].die
		player.hold_die(die_to_hold)
		print("Resolved 'Hold' ability. Die with value %d will be kept." % die_to_hold.result_value)
	
	# After an ability resolves, refresh the player's health bar preview.
	var net_damage = max(0, current_incoming_damage - player.block)
	player.update_health_display(net_damage)

func enemy_turn() -> void:
	end_turn_button.disabled = true

	var active_enemies = get_active_enemies()

	await get_tree().create_timer(1.0).timeout
	if current_turn == Turn.ENEMY:
		# Each living enemy attacks with its declared damage
		for enemy in active_enemies:
			if enemy.hp > 0 and enemy.next_action:
				match enemy.next_action.action_type:
					EnemyAction.ActionType.ATTACK:
						await player.take_damage(enemy.next_action_value, true, enemy, true)
						if enemy.next_action.action_name == "Shrink Ray":
							player.apply_duration_status("shrunk", 1)
							print("Player has been shrunk!")

					EnemyAction.ActionType.PIERCING_ATTACK:
						await player.take_piercing_damage(enemy.next_action_value, true, enemy, true)

					EnemyAction.ActionType.SHIELD:
						pass # Proactive shield.
					EnemyAction.ActionType.SUPPORT_SHIELD:
						pass # Proactive shield.
					EnemyAction.ActionType.HEAL_ALLY:
						# Prioritize healing injured allies
						var injured_allies = active_enemies.filter(func(e): return e != enemy and e.hp < e.max_hp)
						if not injured_allies.is_empty():
							var ally_to_heal = injured_allies.pick_random()
							ally_to_heal.heal(enemy.next_action_value)
							print("%s is healing %s for %d" % [enemy.name, ally_to_heal.name, enemy.next_action_value])
						enemy.update_health_display()

					EnemyAction.ActionType.SPAWN_MINIONS:
						if enemy.enemy_data.enemy_name == "Evil Dice Tower":
							_spawn_boss_minions(3)
						elif enemy.enemy_data.enemy_name == "Gnomish Tinkerer":
							_spawn_gnomish_invention()

					EnemyAction.ActionType.BUFF:
						# Apply advantage to all allies (including self) for 2 rounds.
						# A duration of 2 means it lasts this enemy turn and the next.
						for e in active_enemies:
							e.apply_status("advantage", 2)

					EnemyAction.ActionType.DO_NOTHING:
						pass # Do nothing, as intended.

					EnemyAction.ActionType.DEBUFF:
						if enemy.next_action.status_id != "":
							var effect = StatusLibrary.get_status(enemy.next_action.status_id)
							if effect:
								var value = 1
								if effect.charges != -1:
									if enemy.next_action.charges > -1:
										value = enemy.next_action.charges
								else:
									if enemy.next_action.duration > -1:
										value = enemy.next_action.duration
								
								player.apply_effect(effect, value)

					EnemyAction.ActionType.FLEE:
						enemy.die()

				if enemy.next_action.self_destructs:
					enemy.die()

				enemy.clear_intent()
			
			# Tick down statuses at the end of this enemy's turn
			if not enemy._is_dead:
				await enemy.tick_down_statuses()
		next_turn()
		await player_turn()

func _spawn_boss_minions(count: int):
	var current_enemy_count = get_active_enemies().size()
	var max_to_spawn = 6 - current_enemy_count
	if max_to_spawn <= 0:
		print("Cannot spawn more minions, enemy limit of 6 reached.")
		return

	if enemy_spawner.minion_pool.is_empty():
		push_warning("Minion pool is empty!")
		return

	var available_minions = enemy_spawner.minion_pool.duplicate()
	available_minions.shuffle()

	var minions_to_spawn = []
	var num_to_spawn = min(count, max_to_spawn)
	for i in range(min(num_to_spawn, available_minions.size())):
		minions_to_spawn.append(available_minions[i])

	for minion_data in minions_to_spawn:
		var new_enemy: Enemy = enemy_spawner.ENEMY_UI.instantiate()
		new_enemy.enemy_data = minion_data
		enemy_container.add_child(new_enemy)
		new_enemy.died.connect(_on_enemy_died.bind())
		new_enemy.exploded.connect(_on_enemy_exploded)
	
	enemy_container.call_deferred("arrange_enemies")

func _spawn_gnomish_invention():
	if get_active_enemies().size() >= 6:
		print("Cannot spawn invention, enemy limit of 6 reached.")
		return

	if enemy_spawner.invention_pool.is_empty():
		push_warning("Gnomish invention pool is empty! Cannot spawn.")
		return

	var invention_data: EnemyData = enemy_spawner.invention_pool.pick_random()
	var new_enemy: Enemy = enemy_spawner.ENEMY_UI.instantiate()
	new_enemy.enemy_data = invention_data
	enemy_container.add_child(new_enemy)
	# Connect the death signal so the game knows when it's defeated.
	new_enemy.died.connect(_on_enemy_died.bind())
	new_enemy.exploded.connect(_on_enemy_exploded)
	# Defer arrangement to prevent physics race conditions.
	enemy_container.call_deferred("arrange_enemies")
	print("Eureka! A %s has been summoned!" % invention_data.enemy_name)

func _on_die_clicked(die_display):
	# If the clicked die is already selected, deselect it. Otherwise, select it.
	if selected_dice_display.has(die_display):
		selected_dice_display.erase(die_display)
		die_display.deselect()
	else:
		selected_dice_display.append(die_display)
		die_display.select()

func _on_die_drag_started(die_display: DieDisplay):
	# If the die being dragged is in the selection, remove it.
	if selected_dice_display.has(die_display):
		selected_dice_display.erase(die_display)
		die_display.deselect()

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


func _on_character_clicked(character: Character) -> void:
	print("Character clicked: " + character.name)
	print(is_resolving_action)
	if selected_dice_display.is_empty() or is_resolving_action:
		return
	
	is_resolving_action = true

	var is_targeting_player = character is Player
	var total_roll = 0
	var dice_to_discard: Array[Die] = []
	
	# Make a copy because we will be modifying the dice pool
	var used_dice_displays = selected_dice_display.duplicate()
	selected_dice_display.clear()
	
	for die_display in used_dice_displays:
		var is_piercing = false
		# Pierce effect should only be excluded from the main damage roll if targeting an enemy.
		if not is_targeting_player:
			if die_display.die.result_face:
				for effect in die_display.die.result_face.effects:
					if effect.process_effect == EffectLogic.pierce:
						is_piercing = true
						break
		
		if not is_piercing:
			total_roll += die_display.die.result_value
		dice_to_discard.append(die_display.die)

	# Animate the dice, which will also remove them from the hand UI.
	await _animate_dice_to_target(used_dice_displays, character)

	if is_targeting_player:
		player.add_block(total_roll)
		print("Player blocked for %d. Total block: %d" % [total_roll, player.block])
		# Update player health preview immediately
		var net_damage = max(0, current_incoming_damage - player.block)
		player.update_health_display(net_damage)

		for die in dice_to_discard:
			if die.result_face and not die.result_face.effects.is_empty():
				for effect in die.result_face.effects:
					# Check the status library to see if this effect is a debuff
					var status_id = effect.name.to_lower()
					var status_effect = StatusLibrary.get_status(status_id)
					if status_effect and status_effect.is_debuff:
						continue
					# Pierce effect should not damage the player, it just acts as a normal block die.
					# The value was already added to total_roll, so we just skip the effect processing.
					if effect.process_effect == EffectLogic.pierce:
						continue
					# For self-targeted block+damage effects, the block value is already in total_roll.
					# We must skip the effect to prevent adding block twice and taking damage,
					# but manually trigger any other parts of the effect, like healing.
					if effect.process_effect == EffectLogic.ss:
						# Sword+Shield: Block is handled, no other effect to apply.
						continue
					if effect.process_effect == EffectLogic.ssh:
						# Sword+Shield+Heal: Block is handled, just apply heal.
						player.heal(die.result_value)
						continue
					_process_die_face_effect(effect, die.result_value, player, die)
	else: # It's an enemy
		var enemy_target: Enemy = character
		await enemy_target.take_damage(total_roll, false, player, true)
		print("Dealt %d damage to %s" % [total_roll, enemy_target.name])

		# After the main action, process any effects from the dice faces
		# We iterate over `dice_to_discard` which contains the actual Die objects,
		# because `used_dice_displays` contains references to nodes that were freed
		# inside `_animate_dice_to_target`.
		for die in dice_to_discard:
			if die.result_face and not die.result_face.effects.is_empty():
				for effect in die.result_face.effects:
					# Spikes is a self-buff, it should not be applied to enemies.
					if effect.name == "Spikes":
						continue
					_process_die_face_effect(effect, die.result_value, enemy_target, die)

	player.discard(dice_to_discard)
	is_resolving_action = false

func _process_die_face_effect(effect: DieFaceEffect, value: int, target: Character = null, die: Die = null):
	var context = {
		"all_enemies": get_active_enemies(),
		"die": die
	}
	if effect.process_effect.is_valid():
		# The logic for the effect is now self-contained within the effect resource,
		# called from here with the necessary context.
		await effect.process_effect.call(value, player, target, context)
	else:
		# Fallback for effects that apply statuses directly by name
		match effect.name:
			"Poison":
				if target: target.apply_duration_status("poison", value)
			"Stun":
				if target: target.apply_duration_status("stun", 1)
			"Regen":
				if target: target.apply_duration_status("regen", value)
			"Vampire":
				# Heal the player for the die value
				player.heal(value)

func _animate_dice_to_target(dice_displays: Array[DieDisplay], target: Character) -> void:
	var tweens: Array[Tween] = []
	var animation_data: Array = []

	# Step 1: Gather all necessary data (start position, node to animate) before
	# modifying the scene tree. This prevents the HBoxContainer from re-sorting
	# and giving us incorrect positions for subsequent dice.
	for die_display in dice_displays:
		animation_data.append({
			"start_center": die_display.get_node("MainDisplay").get_global_rect().get_center(),
			"anim_disp": die_display.get_node("MainDisplay").duplicate(true),
			"start_scale": die_display.get_node("MainDisplay").scale,
			"die_data": die_display.die, # Add the Die object here
			"start_size": die_display.get_node("MainDisplay").size
		})

	# Step 2: Now that we have the data, clear the original dice from the hand.
	for die_display in dice_displays:
		dice_pool_ui.remove_die(die_display)
		die_display.queue_free()

	# Step 3: Add the animation nodes to the scene and start their tweens.
	for i in range(animation_data.size()):
		var data = animation_data[i]
		var anim_disp: PanelContainer = data.anim_disp
		var start_scale: Vector2 = data.start_scale
		var start_size: Vector2 = data.start_size

		# Create an anchor to handle position, so the die can be scaled from its center.
		var anchor = Node2D.new()
		get_tree().get_root().add_child(anchor)
		var anchor_start_pos: Vector2 = data.start_center
		anchor.global_position = anchor_start_pos

		# Add the duplicated display to the anchor and center it.
		# Manually set scale and pivot to ensure it's a perfect match to the original.
		# Reset anchors to prevent the "size is overridden" warning. When a Control node
		# with fill anchors is duplicated, it keeps those properties.
		anim_disp.set_anchors_preset(Control.PRESET_TOP_LEFT)
		anim_disp.size = start_size
		anim_disp.pivot_offset = start_size / 2.0
		anchor.add_child(anim_disp)
		anim_disp.scale = start_scale
		anim_disp.position = -start_size / 2.0
		anim_disp.visible = true

		var tween = create_tween()
		tweens.append(tween)
		
		# Get the visual center of the target character's sprite for a more accurate end position.
		var sprite_node: Node = target.get_node("Sprite2D")
		var end_pos: Vector2
		if sprite_node is Control: # TextureRect is a Control node
			end_pos = (sprite_node as Control).get_global_rect().get_center()
		elif sprite_node is Node2D: # Sprite2D is a Node2D
			end_pos = (sprite_node as Node2D).global_position
		else: # Fallback to the character's origin if the node is something unexpected
			end_pos = target.global_position
		# Define the control point for the quadratic Bezier curve.
		# A lower Y value creates a higher arc.
		var control_pos_x = lerp(anchor_start_pos.x, end_pos.x, 0.2)
		var control_pos_y = min(anchor_start_pos.y, end_pos.y) - 150
		var control_pos = Vector2(control_pos_x, control_pos_y)

		var duration = 0.4
		tween.tween_method(
			func(t: float): anchor.global_position = anchor_start_pos.lerp(control_pos, t).lerp(control_pos.lerp(end_pos, t), t),
			0.0, 1.0, duration
		).set_delay(i * 0.08).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

		tween.parallel().tween_property(anim_disp, "scale", anim_disp.scale * 1.2, duration / 2.0).set_delay(i * 0.08)
		tween.parallel().tween_property(anim_disp, "scale", Vector2(0.5, 0.5), duration / 2.0).set_delay(i * 0.08 + duration / 2.0)

		# When the die "hits" at the end of its animation, trigger the recoil on the target.
		# We don't await this, so multiple recoils can overlap for a cool, rapid-fire effect.
		tween.tween_callback(target._recoil.bind(data.die_data.result_value))
		tween.tween_callback(anchor.queue_free)

	if not tweens.is_empty():
		await tweens.back().finished

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
		# Defer arrangement to prevent physics race conditions where the collision
		# shape position doesn't update in the same frame as the visual position.
		enemy_container.call_deferred("arrange_enemies")

func start_new_round() -> void:
	print("Round start")
	player.reset_for_new_round()
	enemy_container.clear_everything()
	
	var spawned_enemies: Array
	if start_with_boss_fight or round_number == BOSS_ROUND:
		spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.BOSS)
	else:
		spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.NORMAL)
	
	if spawned_enemies.is_empty():
		push_error("No enemies spawned, cannot start round.")
		return

	for enemy in spawned_enemies:
		# Connect to each new enemy's death signal
		enemy.died.connect(_on_enemy_died.bind())
		enemy.exploded.connect(_on_enemy_exploded)
	
	# Wait for one frame. This is CRITICAL. It allows the engine to:
	# 1. Process the `queue_free` from `clear_everything()`.
	# 2. Process the `call_deferred` for `arrange_enemies()`.
	# 3. Update the physics server with the new positions of the collision shapes.
	# Without this, the collision shapes might still be at origin (0,0) when the player's turn starts.
	await get_tree().process_frame

	# Start the player's turn for the new round
	await player_turn()

func get_active_enemies() -> Array[Enemy]:
	# Helper function to get living enemies from the container.
	# We build a new typed array to satisfy the static type checker, which can't
	# infer the type from the result of the filter() method.
	var living_enemies: Array[Enemy]
	for child in enemy_container.get_children():
		if child is Enemy and not child._is_dead:
			living_enemies.append(child)
	return living_enemies

func _on_enemy_exploded(damage: int, source: Enemy):
	# This is a generic handler for any enemy that might explode.
	await player.take_damage(damage, true, source, false)

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
	
	# Create two standard reward dice
	for i in range(2):
		var sides = possible_sides.pop_front()
		var new_die = Die.new(sides)
		
		var total_value = int(round(target_average * sides))
		for face in new_die.faces:
			face.value = 1
		
		var remaining_value = total_value - sides
		
		for _j in range(remaining_value):
			var random_index = randi() % sides
			new_die.faces[random_index].value += 1
		
		new_die.faces.sort_custom(func(a, b): return a.value < b.value)
		dice_options.append(new_die)

	# --- Create the special upgraded die ---
	# Get a list of die sizes that have defined effects in our library
	var upgradable_die_sizes = EffectLibrary.effects_by_die_size.keys()
	if not upgradable_die_sizes.is_empty():
		# Pick a random die size from the ones that have available upgrades
		var random_upgradable_size = upgradable_die_sizes.pick_random()
		var upgraded_die = Die.new(random_upgradable_size)

		# Give it standard 1-to-N faces
		for i in range(random_upgradable_size):
			upgraded_die.faces[i].value = i + 1

		# Pick a random face to upgrade (that isn't 1, to make it more interesting)
		var face_to_upgrade_index = randi_range(1, random_upgradable_size - 1)
		var face_to_upgrade: Die.DieFace = upgraded_die.faces[face_to_upgrade_index]

		# Get a random effect suitable for this die size from the library
		var new_effect = EffectLibrary.get_random_effect_for_die(random_upgradable_size)
		if new_effect:
			face_to_upgrade.effects.append(new_effect)
		
		dice_options.append(upgraded_die)

	dice_options.shuffle()

	return dice_options

func _on_reward_chosen(chosen_die: Die) -> void:
	if (chosen_die == null):
		player.add_gold(10)
	else:
		# Add the chosen die to the player's deck
		player.add_to_game_bag([chosen_die])
	
	round_number += 1
	reward_screen.visible = false
	
	await start_new_round()

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

func _on_player_dice_drawn(new_dice: Array[Die]):
	for die in new_dice:
		die.roll()
	await dice_pool_ui.animate_add_dice(new_dice, dice_bag_icon.get_global_rect().get_center())
	
	_update_total_dice_value()

func _on_player_statuses_changed(statuses: Dictionary):
	# Check if the player is currently shrunk
	var is_shrunk = false
	for effect in statuses:
		if effect.status_name == "Shrunk":
			is_shrunk = true
			break
	
	# If the player is NOT shrunk, revert any shrunken dice currently in the UI.
	if not is_shrunk:
		# 1. Revert dice in the main pool
		for die_display in dice_pool_ui.dice_pool_display:
			if is_instance_valid(die_display) and die_display.die and die_display.die.has_meta("is_shrunken"):
				var original = die_display.die.get_meta("original_die")
				original.roll()
				die_display.die = original # Triggers visual update
				print("Reverted shrunken die in pool.")

		# 2. Revert dice currently slotted in abilities
		for ability_ui in abilities_ui.get_children():
			if ability_ui is AbilityUI:
				for slot in ability_ui.dice_slots_container.get_children():
					if slot is DieSlotUI and slot.current_die_display:
						var die_display = slot.current_die_display
						if is_instance_valid(die_display) and die_display.die and die_display.die.has_meta("is_shrunken"):
							var original = die_display.die.get_meta("original_die")
							original.roll()
							die_display.die = original # Triggers visual update
							print("Reverted shrunken die in ability slot.")
	else:
		# If the player IS shrunk, ensure all active dice are shrunk.
		# 1. Shrink dice in the main pool
		for die_display in dice_pool_ui.dice_pool_display:
			if is_instance_valid(die_display) and die_display.die:
				var old_die = die_display.die
				var new_die = player.shrink_die(old_die)
				if new_die != old_die:
					new_die.roll()
					die_display.die = new_die # Triggers visual update
					print("Shrunk die in pool due to status.")

		# 2. Shrink dice currently slotted in abilities
		for ability_ui in abilities_ui.get_children():
			if ability_ui is AbilityUI:
				for slot in ability_ui.dice_slots_container.get_children():
					if slot is DieSlotUI and slot.current_die_display:
						var die_display = slot.current_die_display
						if is_instance_valid(die_display) and die_display.die:
							var old_die = die_display.die
							var new_die = player.shrink_die(old_die)
							if new_die != old_die:
								new_die.roll()
								die_display.die = new_die # Triggers visual update
								print("Shrunk die in ability slot due to status.")
		
		_update_total_dice_value()

func _update_total_dice_value():
	var current_total = 0
	for die in dice_pool_ui.get_current_dice():
		current_total += die.result_value
	total_dice_value_label.text = "Total: " + str(current_total)
