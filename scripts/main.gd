extends Node2D
class_name MainGame

static var debug_mode: bool = false

@export var player: Player
@onready var enemy_container = $EnemySpawner/Enemies
@onready var enemy_spawner = $EnemySpawner
@onready var dice_pool_ui: DicePool = $UI/DicePool
@onready var abilities_ui: VBoxContainer = $UI/Abilities
@onready var selected_value_label: Label = $UI/SelectedValueLabel
@onready var gold_label: Label = $UI/GameInfo/TopBar/GoldContainer/GoldLabel

@onready var dice_bag_icon: TextureRect = $UI/RoundInfo/DiceBag/DiceBagIcon
@onready var dice_bag_label: Label = $UI/RoundInfo/DiceBag/DiceBagLabel
@onready var dice_discard_label: Label = $UI/RoundInfo/DiceDiscard/DiceDiscardLabel

@onready var victory_screen = $UI/VictoryScreen
@onready var defeat_screen = $UI/DefeatScreen
@onready var reward_screen = $UI/RewardScreen
@onready var map_screen = $UI/MapScreen
@onready var shop_screen = $UI/ShopScreen
@onready var campfire_screen = $UI/CampfireScreen
@onready var end_turn_button = $UI/EndTurnButton
@onready var debug_menu = $UI/DebugMenu

@onready var dice_bag_button = $UI/GameInfo/TopBar/DiceBagButton
@onready var dice_bag_screen = $UI/DiceBagScreen
@onready var dice_bag_grid = $UI/DiceBagScreen/Panel/VBoxContainer/ScrollContainer/GridContainer
@onready var dice_bag_close_button = $UI/DiceBagScreen/Panel/VBoxContainer/CloseButton

enum Turn {PLAYER, ENEMY}

const ABILITY_UI_SCENE = preload("res://scenes/ui/ability.tscn")
const DIE_DISPLAY_SCENE = preload("res://scenes/dice/die_display.tscn")
const ARROW_SCENE = preload("res://scenes/ui/arrow.tscn")
var selected_dice_display: Array[DieDisplay] = []
var current_incoming_damage: int = 0
var is_resolving_action := false

var current_turn = Turn.PLAYER
var round_number := 1
const BOSS_ROUND = 10
@export var start_with_boss_fight := false

# Testing values
var starting_abilities: Array[AbilityData] = [load("res://resources/abilities/heal.tres"), 
	load("res://resources/abilities/sweep.tres"), load("res://resources/abilities/hold.tres"),
	load("res://resources/abilities/roulette.tres"), load("res://resources/abilities/explosive_shot.tres")]

var pause_menu_ui: Control
var debug_ability_ui: Control

var active_targeting_ability: AbilityUI = null
var targeting_arrow: Line2D = null

func _ready() -> void:
	# Set process modes to allow the MainGame script to handle input while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	dice_pool_ui.process_mode = Node.PROCESS_MODE_PAUSABLE
	abilities_ui.process_mode = Node.PROCESS_MODE_PAUSABLE

	if debug_mode:
		print("--- DEBUG / GODMODE ACTIVE ---")
		player.max_hp = 999
		player.hp = 999
		player.add_gold(1000)
		player.update_health_display()

	# Connect signals
	player.died.connect(_on_player_died)
	player.gold_changed.connect(_update_gold)
	player.dice_bag_changed.connect(_update_dice_bag)
	player.dice_discard_changed.connect(_update_dice_discard)
	player.abilities_changed.connect(_add_player_ability)
	player.total_dice_count_changed.connect(_update_total_dice_count)
	player.statuses_changed.connect(_on_player_statuses_changed)

	map_screen.node_selected.connect(_on_map_node_selected)
	dice_pool_ui.player = player
	dice_pool_ui.die_clicked.connect(_on_die_clicked)
	dice_pool_ui.drag_started.connect(_on_die_drag_started)
	dice_pool_ui.die_value_changed.connect(_on_die_value_changed)
	reward_screen.reward_chosen.connect(_on_reward_chosen)
	
	debug_menu.encounter_selected.connect(_on_debug_menu_encounter_selected)
	debug_menu.close_requested.connect(func(): debug_menu.visible = false)
	campfire_screen.leave_campfire.connect(func(): map_screen.visible = true)
	
	dice_bag_button.pressed.connect(_on_dice_bag_button_pressed)
	dice_bag_close_button.pressed.connect(func(): dice_bag_screen.visible = false)

	# Initialize player's starting abilities
	for child: Node in abilities_ui.get_children():
		child.queue_free()
	if debug_mode:
		for ability in starting_abilities:
			player.add_ability(ability)

	# Wait for one frame to ensure all newly created nodes (like abilities) are fully ready.
	await get_tree().process_frame

	_update_total_dice_count(player._game_dice_bag.size())
	_update_selected_value_label()

	if debug_mode:
		await start_new_round()
	else:
		map_screen.generate_new_map()
		map_screen.visible = true

func _add_player_ability(new_ability: AbilityData):
	# Instantiate and display a UI element for each ability the player has
	var ability_ui_instance: AbilityUI = ABILITY_UI_SCENE.instantiate() as AbilityUI
	abilities_ui.add_child(ability_ui_instance)
	ability_ui_instance.die_returned_from_slot.connect(_on_die_returned_to_pool)
	ability_ui_instance.ability_activated.connect(_on_ability_activated)
	ability_ui_instance.initialize(new_ability, player)

func player_turn() -> void:
	# Failsafe: Reset the action lock at the start of the player's turn.
	# This prevents the player from being locked out if the flag gets stuck
	# during a previous action, especially when transitioning between rounds.
	is_resolving_action = false

	await player.trigger_start_of_turn_statuses()
	# Decrement duration of statuses at the start of the turn.
	await player.tick_down_statuses()

	# Reset abilities and player block from the previous turn.
	_tick_ability_cooldowns()
	player.block = 0
	for die_display in selected_dice_display:
		die_display.deselect()
	selected_dice_display.clear()
	
	dice_pool_ui.clear_pool()
	
	# Add any dice held from the previous turn to the hand first.
	var held_dice = player.get_and_clear_held_dice()
	dice_pool_ui.add_dice_instantly(held_dice)
	
	# Draw and roll new dice
	var new_dice: Array[Die] = player.draw_hand()
	for die: Die in new_dice:
		die.roll()
	
	# Animate the new dice into the pool
	await dice_pool_ui.animate_add_dice(new_dice, dice_bag_icon.get_global_rect().get_center())
	current_incoming_damage = 0
	var active_enemies = get_active_enemies()
	# Have all living enemies declare their intents for the turn
	for enemy: Enemy in active_enemies:
		# Reset enemy block at the start of the player's turn
		enemy.block = 0
		# Immediately update the health bar to show the shield has been removed.
		enemy.update_health_display()

		enemy.declare_intent(active_enemies)
		if enemy.next_action and (enemy.next_action.action_type == EnemyAction.ActionType.ATTACK or \
			enemy.next_action.action_type == EnemyAction.ActionType.PIERCING_ATTACK or \
			(enemy.next_action.action_type == EnemyAction.ActionType.DEBUFF and enemy.next_action_value > 0)):
			current_incoming_damage += enemy.next_action_value
	
	# Proactively apply shields that are meant to be active for the player's turn
	for enemy: Enemy in active_enemies:
		enemy.clear_provided_shields()
		if enemy.next_action:
			if enemy.next_action.action_name == "Wing Buffet":
				enemy.apply_duration_status("glance_blows", 1)
				# Ensure it expires at the end of the round (enemy turn) by removing it from the "new" list
				var gb_status = StatusLibrary.get_status("glance_blows")
				if enemy._new_statuses_this_turn.has(gb_status):
					enemy._new_statuses_this_turn.erase(gb_status)
				print("%s gains Glance Blows!" % enemy.name)

			if enemy.next_action.action_type == EnemyAction.ActionType.SHIELD:
				enemy.add_block(enemy.next_action_value)
			elif enemy.next_action.action_type == EnemyAction.ActionType.SUPPORT_SHIELD:
				if enemy.enemy_data.enemy_name == "Shield Generator":
					# Special case: Shield Generator shields all tinkerers.
					var shield_amount = enemy.next_action_value
					var tinkerers = active_enemies.filter(func(e): return e.enemy_data.enemy_name == "Gnomish Tinkerer")
					for tinkerer in tinkerers:
						tinkerer.add_block(shield_amount)
						enemy.register_provided_shield(tinkerer, shield_amount)
						print("%s shields %s for %d" % [enemy.name, tinkerer.name, shield_amount])
				elif enemy.enemy_data.enemy_name == "White Knight":
					var femme_fatales = active_enemies.filter(func(e): return e.enemy_data.enemy_name == "Femme Fatale")
					if not femme_fatales.is_empty():
						var target = femme_fatales[0]
						target.add_block(enemy.next_action_value)
						enemy.register_provided_shield(target, enemy.next_action_value)
						print("%s shields %s for %d" % [enemy.name, target.name, enemy.next_action_value])
				else:
					# Default behavior: Shield self and one random ally.
					enemy.add_block(enemy.next_action_value)
					var other_enemies = active_enemies.filter(func(e): return e != enemy)
					if not other_enemies.is_empty():
						var random_ally = other_enemies.pick_random()
						random_ally.add_block(enemy.next_action_value)
						enemy.register_provided_shield(random_ally, enemy.next_action_value)
						print("%s shields self and %s for %d" % [enemy.name, random_ally.name, enemy.next_action_value])

	player.update_health_display(current_incoming_damage)

	end_turn_button.disabled = false

func _on_end_turn_button_pressed():
	if current_turn == Turn.PLAYER:
		# Discard all dice that are left in the hand this turn.
		player.discard(dice_pool_ui.get_current_dice())
		print("Player block: " + str(player.block))
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
			await enemy.take_damage(damage, true, player, true)
			await _apply_all_die_effects(slotted_dice_displays[0].die, enemy, damage)
		print("Resolved 'Sweep' ability for %d damage to all enemies." % damage)
	elif ability_data.title == "Hold":
		if slotted_dice_displays.is_empty(): return
		
		var die_to_hold = slotted_dice_displays[0].die
		player.hold_die(die_to_hold)
		print("Resolved 'Hold' ability. Die with value %d will be kept." % die_to_hold.result_value)
	elif ability_data.title == "Roulette":
		if slotted_dice_displays.is_empty(): return
		
		var die_display = slotted_dice_displays[0]
		var die_value = die_display.die.result_value
		var damage = die_value * 2
		
		var enemies = get_active_enemies()
		if not enemies.is_empty():
			var target = enemies.pick_random()
			
			# Create a visual copy for the animation so the original stays in the slot
			var temp_display = DIE_DISPLAY_SCENE.instantiate()
			$UI.add_child(temp_display)
			temp_display.set_die(die_display.die)
			var rect = die_display.get_global_rect()
			temp_display.global_position = rect.position
			temp_display.size = rect.size
			
			# Animate the temp die flying to the random target
			await _animate_dice_to_target([temp_display], target)
			
			await target.take_damage(damage, true, player, true)
			print("Resolved 'Roulette' ability for %d damage to %s." % [damage, target.name])

			# Apply die face effects to the target
			await _apply_all_die_effects(die_display.die, target, damage)
	elif ability_data.title == "Explosive Shot":
		if slotted_dice_displays.is_empty(): return
		
		# Enter targeting mode
		active_targeting_ability = ability_ui
		targeting_arrow = ARROW_SCENE.instantiate()
		$UI.add_child(targeting_arrow)
		targeting_arrow.set_source(ability_ui.dice_slots_container.get_child(0))
	
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
			if enemy.hp > 0:
				await enemy.trigger_start_of_turn_statuses()
			
			if enemy.hp > 0 and enemy.next_action:
				match enemy.next_action.action_type:
					EnemyAction.ActionType.ATTACK:
						await player.take_damage(enemy.next_action_value, true, enemy, true)
						if enemy.next_action.action_name == "Shrink Ray":
							player.apply_duration_status("shrunk", 1)
							print("Player has been shrunk!")
						
						if enemy.has_status("Raging"):
							var recoil = ceili(enemy.next_action_value / 2.0)
							await enemy.take_damage(recoil, true, enemy, false)

					EnemyAction.ActionType.PIERCING_ATTACK:
						await player.take_piercing_damage(enemy.next_action_value, true, enemy, true)

					EnemyAction.ActionType.SHIELD:
						pass # Proactive shield.
					EnemyAction.ActionType.SUPPORT_SHIELD:
						pass # Proactive shield.
					EnemyAction.ActionType.HEAL_ALLY:
						if enemy.enemy_data.enemy_name == "White Knight" and enemy.next_action.action_name == "M'lady":
							var femme_fatales = active_enemies.filter(func(e): return e.enemy_data.enemy_name == "Femme Fatale")
							if not femme_fatales.is_empty():
								femme_fatales[0].heal(enemy.next_action_value)
								print("%s heals %s for %d" % [enemy.name, femme_fatales[0].name, enemy.next_action_value])
						else:
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
							e.apply_duration_status("advantageous", 2)

					EnemyAction.ActionType.DO_NOTHING:
						pass # Do nothing, as intended.

					EnemyAction.ActionType.DEBUFF:
						# If the debuff action has damage associated with it (e.g. Shrink Ray), deal it.
						var damage_dealt = false
						if enemy.next_action_value > 0:
							var hp_before = player.hp
							await player.take_damage(enemy.next_action_value, true, enemy, true)
							if player.hp < hp_before:
								damage_dealt = true
						
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
								
								# Special logic for Charm and Ragebait: only apply if damage was dealt
								if (enemy.next_action.action_name == "Charm" or enemy.next_action.action_name == "Ragebait") and not damage_dealt:
									print("%s failed: Player took no damage." % enemy.next_action.action_name)
								else:
									# Charm and Ragebait now apply buffs to the caster (enemy), not debuffs to the player.
									if enemy.next_action.action_name == "Charm" or enemy.next_action.action_name == "Ragebait":
										enemy.apply_effect(effect, value, enemy)
									else:
										player.apply_effect(effect, value, enemy)

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
		new_enemy.died.connect(_on_enemy_died)
		new_enemy.exploded.connect(_on_enemy_exploded)
		new_enemy.gold_dropped.connect(_on_enemy_gold_dropped.bind(new_enemy))
	
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
	new_enemy.died.connect(_on_enemy_died)
	new_enemy.exploded.connect(_on_enemy_exploded)
	new_enemy.gold_dropped.connect(_on_enemy_gold_dropped.bind(new_enemy))
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
	_update_selected_value_label()

func _on_die_drag_started(die_display: DieDisplay):
	# If the die being dragged is in the selection, remove it.
	if selected_dice_display.has(die_display):
		selected_dice_display.erase(die_display)
		die_display.deselect()
	_update_selected_value_label()

func _unhandled_input(event: InputEvent):
	# This function catches input that was not handled by the UI.
	if event.is_action_pressed("ui_cancel"):
		if active_targeting_ability:
			_cancel_targeting()
			get_viewport().set_input_as_handled()
			return

		_toggle_pause_menu()
		get_viewport().set_input_as_handled()
		return

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
	
	# Right click to cancel targeting
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.is_pressed():
		if active_targeting_ability:
			_cancel_targeting()
			get_viewport().set_input_as_handled()
			return


func _on_character_clicked(character: Character) -> void:
	if active_targeting_ability:
		_resolve_targeted_ability(character)
		return

	# print("Character clicked: " + character.name)
	print(is_resolving_action)
	if selected_dice_display.is_empty() or is_resolving_action:
		return
	
	is_resolving_action = true

	var is_targeting_player = character is Player

	# Check for Taunt restriction
	if not is_targeting_player:
		var taunting_enemies = get_active_enemies().filter(func(e): return e.has_status("Taunting"))
		if not taunting_enemies.is_empty():
			if not character.has_status("Taunting"):
				print("Must attack a taunting enemy!")
				is_resolving_action = false
				return

	var total_roll = 0
	var dice_to_discard: Array[Die] = []
	
	# Make a copy because we will be modifying the dice pool
	var used_dice_displays = selected_dice_display.duplicate()
	selected_dice_display.clear()
	_update_selected_value_label()
	
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

func _resolve_targeted_ability(target: Character):
	if not target is Enemy:
		return # Only target enemies for now

	var ability_data = active_targeting_ability.ability_data
	var slotted_dice = active_targeting_ability.get_slotted_dice_displays()
	var die_display = slotted_dice[0]
	var damage = die_display.die.result_value
	
	if ability_data.title == "Explosive Shot":
		var enemies = get_active_enemies()
		var target_index = enemies.find(target)
		
		# Create a visual copy for the animation so the original stays in the slot
		var temp_display = DIE_DISPLAY_SCENE.instantiate()
		$UI.add_child(temp_display)
		temp_display.set_die(die_display.die)
		var rect = die_display.get_global_rect()
		temp_display.global_position = rect.position
		temp_display.size = rect.size
		
		await _animate_dice_to_target([temp_display], target)
		
		# Main damage
		await target.take_damage(damage, true, player, true)
		
		# Splash damage
		var splash_damage = ceili(damage / 2.0)
		if target_index > 0:
			var left_enemy = enemies[target_index - 1]
			if not left_enemy._is_dead:
				await left_enemy.take_damage(splash_damage, true, player, true)
				await _apply_all_die_effects(die_display.die, left_enemy, splash_damage)
		
		if target_index < enemies.size() - 1:
			var right_enemy = enemies[target_index + 1]
			if not right_enemy._is_dead:
				await right_enemy.take_damage(splash_damage, true, player, true)
				await _apply_all_die_effects(die_display.die, right_enemy, splash_damage)
				
		print("Resolved 'Explosive Shot' on %s" % target.name)

		# Apply die face effects to the main target
		await _apply_all_die_effects(die_display.die, target, damage)

	# Cleanup
	if targeting_arrow:
		targeting_arrow.queue_free()
		targeting_arrow = null
	active_targeting_ability = null
	
	# Refresh health preview
	var net_damage = max(0, current_incoming_damage - player.block)
	player.update_health_display(net_damage)

func _cancel_targeting():
	if targeting_arrow:
		targeting_arrow.queue_free()
		targeting_arrow = null
	
	if active_targeting_ability:
		# Revert ability UI state since we are cancelling the activation
		active_targeting_ability.is_consumed_this_turn = false
		active_targeting_ability.modulate = Color.WHITE
		active_targeting_ability.cooldown_label.visible = false
		active_targeting_ability.add_theme_stylebox_override("panel", active_targeting_ability.original_stylebox)
		for slot in active_targeting_ability.dice_slots_container.get_children():
			if slot is DieSlotUI:
				slot.mouse_filter = Control.MOUSE_FILTER_STOP
		
		active_targeting_ability = null

func _apply_all_die_effects(die: Die, target: Character, value: int):
	if die.result_face and not die.result_face.effects.is_empty():
		for effect in die.result_face.effects:
			# Spikes is a self-buff, it should not be applied to enemies.
			if effect.name == "Spikes":
				continue
			await _process_die_face_effect(effect, value, target, die)

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

func _on_map_node_selected(node_data):
	map_screen.visible = false
	
	player.reset_for_new_round()
	enemy_container.clear_everything()
	
	if node_data.type == "combat":
		var spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.NORMAL)
		await _setup_round(spawned_enemies)
	elif node_data.type == "rare_combat":
		var spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.RARE)
		await _setup_round(spawned_enemies)
	elif node_data.type == "boss":
		var spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.BOSS)
		await _setup_round(spawned_enemies)
	elif node_data.type == "campfire":
		campfire_screen.open()
	else:
		print("Unknown node type selected: ", node_data.type)

func _on_enemy_died(dead_enemy: Character):
	# Check if a Femme Fatale died, and if so, enrage any White Knights
	if dead_enemy is Enemy and dead_enemy.enemy_data and dead_enemy.enemy_data.enemy_name == "Femme Fatale":
		var active_enemies = get_active_enemies()
		for enemy in active_enemies:
			if enemy.enemy_data.enemy_name == "White Knight" and enemy.has_status("Crash Out"):
				print("White Knight becomes enraged!")
				enemy.remove_status("crash_out")
				enemy.apply_duration_status("raging", 99)

	if get_active_enemies().is_empty():
		# All enemies for the round are defeated
		if map_screen.current_node and map_screen.current_node.type == "boss":
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
	
	if MainGame.debug_mode:
		_show_debug_encounter_selection()
		return
	
	var spawned_enemies: Array
	if start_with_boss_fight or round_number == BOSS_ROUND:
		spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.BOSS)
	else:
		spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.NORMAL)
	
	await _setup_round(spawned_enemies)

func _setup_round(spawned_enemies: Array) -> void:
	if spawned_enemies.is_empty():
		push_error("No enemies spawned, cannot start round.")
		return

	for enemy in spawned_enemies:
		# Connect to each new enemy's death signal
		enemy.died.connect(_on_enemy_died)
		enemy.exploded.connect(_on_enemy_exploded)
		enemy.gold_dropped.connect(_on_enemy_gold_dropped.bind(enemy))
	
	# Wait for one frame. This is CRITICAL. It allows the engine to:
	# 1. Process the `queue_free` from `clear_everything()`.
	# 2. Process the `call_deferred` for `arrange_enemies()`.
	# 3. Update the physics server with the new positions of the collision shapes.
	# Without this, the collision shapes might still be at origin (0,0) when the player's turn starts.
	await get_tree().process_frame

	# Start the player's turn for the new round
	await player_turn()

func _show_debug_encounter_selection():
	debug_menu.setup_encounters(enemy_spawner.encounter_pool)
	debug_menu.visible = true

func _on_debug_menu_encounter_selected(type, data):
	debug_menu.visible = false
	if type == "shop":
		shop_screen.open()
	elif type == "combat":
		var spawned_enemies = enemy_spawner.spawn_specific_encounter(data)
		await _setup_round(spawned_enemies)

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

func _on_enemy_gold_dropped(amount: int, source_enemy: Node2D):
	_show_gold_popup(amount, source_enemy.global_position)
	_animate_gold_collection(amount, source_enemy)
	
	# Delay adding gold until the animation (approx) finishes so the counter updates when gold arrives
	get_tree().create_timer(0.8).timeout.connect(func(): player.add_gold(amount))

func _show_gold_popup(amount: int, pos: Vector2):
	var label = Label.new()
	label.text = "+%d" % amount
	label.add_theme_color_override("font_color", Color.GOLD)
	label.add_theme_font_size_override("font_size", 32)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	label.z_index = 100
	add_child(label)
	label.global_position = pos + Vector2(-20, -60)
	
	var tween = create_tween()
	tween.tween_property(label, "global_position", label.global_position + Vector2(0, -50), 1.0)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 1.0)
	tween.tween_callback(label.queue_free)

func _animate_gold_collection(amount: int, source_node: Node2D):
	var particle_count = min(amount, 10)
	if amount > 0 and particle_count < 1: particle_count = 1
	
	var target_node = $UI/GameInfo/TopBar/GoldContainer/GoldIcon
	# Get screen position of the enemy to spawn UI particles correctly
	var start_pos = source_node.get_global_transform_with_canvas().origin
	
	for i in range(particle_count):
		var sprite = TextureRect.new()
		sprite.texture = load("res://assets/ai/ui/gold.svg")
		sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sprite.custom_minimum_size = Vector2(24, 24)
		sprite.size = Vector2(24, 24)
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.pivot_offset = Vector2(12, 12)
		
		$UI.add_child(sprite)
		sprite.global_position = start_pos
		
		var target_pos = target_node.get_global_rect().get_center() - (sprite.size / 2)
		
		# Random scatter
		var scatter_dist = 60.0
		var angle = randf() * TAU
		var dist = randf() * scatter_dist
		var scatter_pos = start_pos + Vector2(cos(angle), sin(angle)) * dist
		
		var tween = create_tween()
		tween.set_parallel(false)
		# Pop out
		tween.tween_property(sprite, "global_position", scatter_pos, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		# Fly to stash
		tween.tween_property(sprite, "global_position", target_pos, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN).set_delay(0.1)
		tween.parallel().tween_property(sprite, "scale", Vector2(0.5, 0.5), 0.6).set_delay(0.1)
		tween.tween_callback(sprite.queue_free)

func _show_reward_screen():
	var reward_dice = _generate_reward_dice()
	reward_screen.display_rewards(reward_dice)
	reward_screen.visible = true

func _generate_reward_dice() -> Array[Die]:
	var dice_options: Array[Die] = []
	
	# Scaling Logic based on round_number
	var available_sizes = [4, 6]
	var max_effects = 1
	var tier_limit = 1
	
	if round_number >= 3:
		available_sizes.append(8)
		max_effects = 2
	if round_number >= 5:
		available_sizes.erase(4)
		tier_limit = 2
	if round_number >= 7:
		available_sizes.append(10)
		max_effects = 3
	if round_number >= 9:
		available_sizes.erase(6)
		available_sizes.append(12)
		tier_limit = 3

	# --- Option 1 & 2: New Dice with potential effects ---
	for i in range(2):
		var sides = available_sizes.pick_random()
		var new_die = Die.new(sides)
		
		# Initialize faces 1..N
		for j in range(sides):
			new_die.faces[j].value = j + 1
		
		# Always add at least one effect
		var num_effects_to_add = randi_range(1, max_effects)
		for k in range(num_effects_to_add):
			var effect = EffectLibrary.get_random_effect_for_die(sides, tier_limit)
			if effect:
				new_die.faces.pick_random().effects.append(effect)
					
		dice_options.append(new_die)

	# --- Option 3: Upgrade Existing Die ---
	if not player._game_dice_bag.is_empty():
		var original_die = player._game_dice_bag.pick_random()
		
		# Create a copy for the offer
		var upgrade_offer = Die.new(original_die.sides)
		for j in range(original_die.faces.size()):
			upgrade_offer.faces[j].value = original_die.faces[j].value
			upgrade_offer.faces[j].effects = original_die.faces[j].effects.duplicate()
			
		# Add new effects (Guaranteed at least 1 for upgrade option)
		var num_upgrade = randi_range(1, max_effects)
		var upgraded_faces_info = []
		for k in range(num_upgrade):
			var effect = EffectLibrary.get_random_effect_for_die(upgrade_offer.sides, tier_limit)
			if effect:
				var target_face = upgrade_offer.faces.pick_random()
				target_face.effects.append(effect)
				upgraded_faces_info.append({"face_value": target_face.value, "effect_name": effect.name, "effect_color": effect.highlight_color.to_html()})
		
		upgrade_offer.set_meta("is_upgrade_reward", true)
		upgrade_offer.set_meta("upgrade_target", original_die)
		upgrade_offer.set_meta("upgraded_faces_info", upgraded_faces_info)
		
		dice_options.append(upgrade_offer)
	else:
		# Fallback if bag is empty
		var sides = available_sizes.pick_random()
		var new_die = Die.new(sides)
		var num_effects_to_add = randi_range(1, max_effects)
		for k in range(num_effects_to_add):
			var effect = EffectLibrary.get_random_effect_for_die(sides, tier_limit)
			if effect:
				new_die.faces.pick_random().effects.append(effect)
		dice_options.append(new_die)

	return dice_options

func _on_reward_chosen(chosen_die: Die) -> void:
	if (chosen_die == null):
		player.add_gold(10)
	else:
		if chosen_die.has_meta("is_upgrade_reward"):
			var target_die = chosen_die.get_meta("upgrade_target")
			# Apply the upgrade: Replace faces of target with chosen
			target_die.faces = chosen_die.faces
			print("Upgraded existing die via reward.")
		else:
			# Add the chosen die to the player's deck
			player.add_to_game_bag([chosen_die])
	
	round_number += 1
	reward_screen.visible = false
	
	if debug_mode:
		await start_new_round()
	else:
		# Return to map
		map_screen.visible = true

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

func _update_total_dice_count(count: int):
	dice_bag_button.text = "Dice Bag: %d" % count

func _update_dice_discard(count: int):
	dice_discard_label.text = str(count)

func _on_die_returned_to_pool(die_display: DieDisplay):
	# This is called when a die is removed from an ability slot via right-click.
	dice_pool_ui.add_die_display(die_display)

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

func _on_die_value_changed(_die_display: DieDisplay):
	_update_selected_value_label()

func _update_selected_value_label():
	var current_selection_total = 0
	for die_display in selected_dice_display:
		if is_instance_valid(die_display) and die_display.die:
			current_selection_total += die_display.die.result_value
	
	if current_selection_total > 0:
		selected_value_label.text = "Selected: " + str(current_selection_total)
	else:
		selected_value_label.text = ""

func _toggle_pause_menu():
	if not pause_menu_ui:
		_create_pause_menu()
	
	pause_menu_ui.visible = not pause_menu_ui.visible
	get_tree().paused = pause_menu_ui.visible

func _create_pause_menu():
	var canvas = get_node("UI")
	var panel = Panel.new()
	panel.name = "PauseMenu"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	pause_menu_ui = panel
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var label = Label.new()
	label.text = "Paused"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 32)
	vbox.add_child(label)
	
	var resume_btn = Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(200, 50)
	resume_btn.pressed.connect(_toggle_pause_menu)
	vbox.add_child(resume_btn)
	
	if MainGame.debug_mode:
		var debug_btn = Button.new()
		debug_btn.text = "Debug: Change Encounter"
		debug_btn.custom_minimum_size = Vector2(200, 50)
		debug_btn.pressed.connect(_on_debug_change_encounter_pressed)
		vbox.add_child(debug_btn)
	
		var debug_abilities_btn = Button.new()
		debug_abilities_btn.text = "Debug: Manage Abilities"
		debug_abilities_btn.custom_minimum_size = Vector2(200, 50)
		debug_abilities_btn.pressed.connect(_show_debug_ability_selection)
		vbox.add_child(debug_abilities_btn)
	
	var menu_btn = Button.new()
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(200, 50)
	menu_btn.pressed.connect(_on_main_menu_pressed)
	vbox.add_child(menu_btn)
	
	var quit_btn = Button.new()
	quit_btn.text = "Quit Game"
	quit_btn.custom_minimum_size = Vector2(200, 50)
	quit_btn.pressed.connect(func(): get_tree().quit())
	vbox.add_child(quit_btn)

func _on_main_menu_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")

func _on_debug_change_encounter_pressed():
	_toggle_pause_menu()
	start_new_round()

func _show_debug_ability_selection():
	_toggle_pause_menu() # Hide pause menu
	
	if not debug_ability_ui:
		_create_debug_ability_ui()
	
	var container = debug_ability_ui.get_node("ScrollContainer/VBoxContainer")
	for child in container.get_children():
		child.queue_free()
		
	var label = Label.new()
	label.text = "DEBUG: Manage Abilities"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)
	
	var all_abilities = Utils.load_all_resources("res://resources/abilities")
	
	for res in all_abilities:
		if res is AbilityData:
			var ability: AbilityData = res
			var btn = CheckBox.new()
			btn.text = ability.title
			btn.button_pressed = player.abilities.has(ability)
			btn.toggled.connect(_on_debug_ability_toggled.bind(ability))
			container.add_child(btn)
			
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): 
		debug_ability_ui.visible = false
		_toggle_pause_menu() # Re-open pause menu
	)
	container.add_child(close_btn)
	
	debug_ability_ui.visible = true

func _create_debug_ability_ui():
	var canvas = get_node("UI")
	var panel = Panel.new()
	panel.name = "DebugAbilitySelector"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.9)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	debug_ability_ui = panel
	
	var scroll = ScrollContainer.new()
	scroll.name = "ScrollContainer"
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 50
	scroll.offset_top = 50
	scroll.offset_right = -50
	scroll.offset_bottom = -50
	panel.add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

func _on_debug_ability_toggled(toggled_on: bool, ability: AbilityData):
	if toggled_on:
		if not player.abilities.has(ability):
			player.add_ability(ability)
	else:
		if player.abilities.has(ability):
			player.remove_ability(ability)
			_refresh_player_abilities_ui()

func _refresh_player_abilities_ui():
	for child in abilities_ui.get_children():
		abilities_ui.remove_child(child)
		child.queue_free()
	for ability in player.abilities:
		_add_player_ability(ability)

func _on_dice_bag_button_pressed():
	for child in dice_bag_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		var display = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		dice_bag_grid.add_child(display)
		display.set_die(die, true)
		display.scale = Vector2.ONE
		
	dice_bag_screen.visible = true
