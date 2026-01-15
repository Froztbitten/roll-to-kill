extends Node2D
class_name MainGame

static var debug_mode: bool = false

signal player_performed_action(action_type, target)

@export var player: Player
@onready var enemy_container = $EnemySpawner/Enemies
@onready var enemy_spawner = $EnemySpawner
@onready var dice_pool_ui: DicePool = $UI/DicePool
@onready var abilities_ui: VBoxContainer = $UI/Abilities
@onready var selected_value_label: Label = $UI/SelectedValueLabel
@onready var gold_label: Label = $UI/GameInfo/TopBar/GoldContainer/GoldLabel

@onready var dice_bag_icon: TextureRect = $UI/RoundInfo/DiceBag/Content/DiceBagIcon
@onready var dice_bag_label: Label = $UI/RoundInfo/DiceBag/Content/DiceBagLabel
@onready var dice_discard_label: Label = $UI/RoundInfo/DiceDiscard/Content/DiceDiscardLabel
@onready var dice_discard_icon: TextureRect = $UI/RoundInfo/DiceDiscard/Content/DiceDiscardIcon

@onready var victory_screen = $UI/VictoryScreen
@onready var defeat_screen = $UI/DefeatScreen
@onready var reward_screen = $UI/RewardScreen
@onready var map_screen = $UI/MapScreen
@onready var shop_screen = $UI/ShopScreen
@onready var campfire_screen = $UI/CampfireScreen
@onready var town_screen = $UI/TownScreen
@onready var quest_board_screen = $UI/QuestBoardScreen
@onready var end_turn_button = $UI/EndTurnButton
@onready var debug_menu = $UI/DebugMenu

@onready var dice_bag_button = $UI/GameInfo/TopBar/DiceBagButton
@onready var dice_bag_screen = $UI/DiceBagScreen
@onready var dice_bag_grid = $UI/DiceBagScreen/Panel/VBoxContainer/ScrollContainer/GridContainer
@onready var dice_bag_count_label: Label = $UI/GameInfo/TopBar/DiceBagButton/DiceCountLabel
@onready var map_button: Button = $UI/GameInfo/TopBar/MapButton
@onready var dice_bag_screen_title: Label = $UI/DiceBagScreen/Panel/VBoxContainer/Label
@onready var dice_bag_close_button = $UI/DiceBagScreen/Panel/VBoxContainer/CloseButton
var steam_manager

enum Turn {PLAYER, ENEMY}

const ABILITY_UI_SCENE = preload("res://scenes/ui/ability.tscn")
const DIE_DISPLAY_SCENE = preload("res://scenes/dice/die_display.tscn")
const DIE_GRID_CELL_SCENE = preload("res://scenes/dice/die_grid_cell.tscn")
const ARROW_SCENE = preload("res://scenes/ui/arrow.tscn")
const DIE_3D_RENDERER_SCENE = preload("res://scenes/ui/die_3d_renderer.tscn")
const RHYTHM_GAME_UI_SCENE = preload("res://scenes/ui/rhythm_game_ui.tscn")
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
	load("res://resources/abilities/roulette.tres"), load("res://resources/abilities/explosive_shot.tres"),
	load("res://resources/abilities/higher_lower.tres"), load("res://resources/abilities/even_odd.tres"),
	load("res://resources/abilities/rhythm_game.tres")]

var pause_menu_ui: Control
var debug_ability_ui: Control

var active_targeting_ability: AbilityUI = null
var targeting_arrow: Line2D = null

# Higher Lower Ability Variables
var higher_lower_ui: Control
var higher_lower_target: Character
var higher_lower_die: Die
var higher_lower_die_display_node: DieDisplay
var higher_lower_message_label: Label
var higher_lower_buttons_container: HBoxContainer
var higher_lower_accumulated_results: Array = []
var higher_lower_grid: GridContainer
var higher_lower_used_faces: Array = []

# Even Odd Ability Variables
var even_odd_ui: Control
var even_odd_target: Character
var even_odd_die: Die
var even_odd_die_display_node: DieDisplay
var even_odd_message_label: Label
var even_odd_buttons_container: HBoxContainer
var even_odd_accumulated_results: Array = []
var even_odd_grid: GridContainer
var even_odd_used_faces: Array = []

# --- Rhythm Game Ability Variables ---
var rhythm_game_ui: Control
var rhythm_game_target: Character
var rhythm_game_die: Die

# --- Crypt Variables ---
var is_in_crypt: bool = false
var current_crypt_stage: int = 0

# --- Multiplayer Variables ---
var game_state
var remote_players: Dictionary = {} # steam_id: Player node
var remote_dice_pools: Dictionary = {} # steam_id: DicePool node
var player_turn_ended_status: Dictionary = {} # steam_id: bool

# --- Custom Tooltip Variables ---
var _tooltip_panel: PanelContainer
var _tooltip_label: Label
var _tooltip_timer: Timer
var _tooltip_tween: Tween
var _hovered_control: Control

var active_quests = {}

func _ready() -> void:
	# Set process modes to allow the MainGame script to handle input while the game is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Ensure GameInfo (TopBar) is always on top of other screens (Map, Shop, etc.)
	$UI/GameInfo.z_index = 400
	$UI.move_child($UI/GameInfo, -1)
	
	# --- Analytics Debug Check ---
	if has_node("/root/GameAnalyticsManager"):
		print("MainGame: GameAnalyticsManager is loaded.")
	else:
		push_error("MainGame: GameAnalyticsManager NOT found. Please add it to Project Settings > Globals.")

	if has_node("/root/GoogleAnalytics"):
		print("MainGame: GoogleAnalytics plugin is loaded.")
	else:
		push_warning("MainGame: GoogleAnalytics plugin NOT found. Check if it is enabled or named differently (e.g. 'GA4').")
	# -----------------------------

	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	enemy_container.process_mode = Node.PROCESS_MODE_PAUSABLE
	dice_pool_ui.process_mode = Node.PROCESS_MODE_PAUSABLE
	abilities_ui.process_mode = Node.PROCESS_MODE_PAUSABLE

	if get_tree().root.has_node("SteamManager"):
		steam_manager = get_tree().root.get_node("SteamManager")

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
	player.dice_drawn.connect(_on_player_dice_drawn)

	map_screen.node_selected.connect(_on_map_node_selected)
	dice_pool_ui.player = player
	dice_pool_ui.die_clicked.connect(_on_die_clicked)
	dice_pool_ui.drag_started.connect(_on_die_drag_started)
	dice_pool_ui.die_value_changed.connect(_on_die_value_changed)
	reward_screen.reward_chosen.connect(_on_reward_chosen)

	# Multiplayer Setup
	if get_tree().root.has_node("GameState"):
		game_state = get_tree().root.get_node("GameState")
		_setup_multiplayer_game()
	
	debug_menu.encounter_selected.connect(_on_debug_menu_encounter_selected)
	debug_menu.close_requested.connect(func(): debug_menu.visible = false)
	campfire_screen.leave_campfire.connect(_on_leave_campfire)
	
	if not town_screen and has_node("UI/TownScreen"): town_screen = $UI/TownScreen
	if not quest_board_screen and has_node("UI/QuestBoardScreen"): quest_board_screen = $UI/QuestBoardScreen
	
	if town_screen:
		town_screen.z_index = 200
		town_screen.open_quest_board.connect(func(): 
			var directions = {}
			if map_screen and map_screen.has_method("get_quest_directions"):
				directions = map_screen.get_quest_directions()
			
			quest_board_screen.open(player, directions)
		)
		town_screen.open_shop.connect(func(): shop_screen.open())
		town_screen.open_map.connect(_on_town_open_map)
	
	if quest_board_screen:
		quest_board_screen.z_index = 210
		quest_board_screen.close_requested.connect(func(): 
			quest_board_screen.visible = false
			if town_screen and not (map_screen and map_screen.visible):
				town_screen.visible = true
			if map_screen and map_screen.has_method("open_town_menu") and map_screen.visible:
				map_screen.open_town_menu()
		)
		quest_board_screen.quests_confirmed.connect(_on_quests_confirmed)
	
	dice_bag_button.pressed.connect(_on_dice_bag_button_pressed)
	dice_bag_close_button.pressed.connect(func(): dice_bag_screen.visible = false)

	# Connect hover signals for round info icons
	$UI/RoundInfo/DiceBag/Button.mouse_entered.connect(_on_dice_bag_hover_entered)
	$UI/RoundInfo/DiceBag/Button.mouse_exited.connect(_on_dice_bag_hover_exited)
	$UI/RoundInfo/DiceDiscard/Button.mouse_entered.connect(_on_dice_discard_hover_entered)
	$UI/RoundInfo/DiceDiscard/Button.mouse_exited.connect(_on_dice_discard_hover_exited)
	$UI/RoundInfo/DiceBag/Button.mouse_entered.connect(_on_control_hover_entered.bind($UI/RoundInfo/DiceBag/Button, "Draw Pile"))
	$UI/RoundInfo/DiceDiscard/Button.mouse_entered.connect(_on_control_hover_entered.bind($UI/RoundInfo/DiceDiscard/Button, "Discard Pile"))
	dice_bag_button.mouse_entered.connect(_on_control_hover_entered.bind(dice_bag_button, "Dice Bag"))
	dice_bag_button.mouse_entered.connect(_on_dice_bag_button_hover_entered)
	dice_bag_button.mouse_exited.connect(_on_dice_bag_button_hover_exited)
	map_button.pressed.connect(_on_map_button_pressed)
	map_button.mouse_entered.connect(_on_control_hover_entered.bind(map_button, "Map"))
	map_button.mouse_entered.connect(_on_map_button_hover_entered)
	map_button.mouse_exited.connect(_on_map_button_hover_exited)
	map_button.icon = load("res://assets/ai/ui/map.png")

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_on_viewport_size_changed")

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

	if get_tree().root.has_meta("experimental_mode") and get_tree().root.get_meta("experimental_mode"):
		map_screen.queue_free()
		var triangle_map = load("res://scenes/screens/triangle_map_screen.tscn").instantiate()
		$UI.add_child(triangle_map)
		# Move it to where MapScreen was in the tree order if needed, or just ensure it's below other UI
		$UI.move_child(triangle_map, $UI/MapScreen.get_index() if has_node("UI/MapScreen") else 0)
		map_screen = triangle_map
		map_screen.player = player
		map_screen.node_selected.connect(_on_map_node_selected)
		
		# Connect Triangle Map town signals
		map_screen.open_quest_board.connect(func(): 
			quest_board_screen.open(player)
			map_screen.close_town_menu()
		)
		map_screen.open_shop.connect(func(): 
			shop_screen.open()
			map_screen.close_town_menu()
		)
		# map_screen.open_forge.connect(...) 
		# map_screen.open_dice_shop.connect(...)
		# map_screen.open_inn.connect(...)
		
		map_screen.visibility_changed.connect(func():
			var show_combat_ui = !map_screen.visible
			var round_info = $UI/RoundInfo
			if round_info:
				round_info.visible = show_combat_ui
			if end_turn_button:
				end_turn_button.visible = show_combat_ui
			if dice_pool_ui:
				dice_pool_ui.visible = show_combat_ui
			if abilities_ui:
				abilities_ui.visible = show_combat_ui
		)

	if get_tree().root.has_meta("tutorial_mode") and get_tree().root.get_meta("tutorial_mode"):
		var tutorial_script = load("res://scripts/tutorial_manager.gd")
		if tutorial_script:
			var tutorial_manager = tutorial_script.new()
			add_child(tutorial_manager)
			var tutorial_encounter = load("res://resources/encounters/tutorial.tres")
			if tutorial_encounter:
				var spawned_enemies = enemy_spawner.spawn_specific_encounter(tutorial_encounter)
				await _setup_round(spawned_enemies)
			else:
				push_error("Failed to load tutorial encounter.")
				map_screen.visible = true
			return

	if debug_mode:
		await start_new_round()
	else:
		# In multiplayer, map generation is deferred until the seed is synced.
		if not (game_state and game_state.is_multiplayer):
			map_screen.generate_new_map()
			map_screen.visible = true

	# --- Custom Tooltip Setup ---
	_tooltip_panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	style.content_margin_left = 8
	style.content_margin_top = 4
	style.content_margin_right = 8
	style.content_margin_bottom = 4
	_tooltip_panel.add_theme_stylebox_override("panel", style)
	_tooltip_label = Label.new()
	_tooltip_panel.add_child(_tooltip_label)
	_tooltip_panel.visible = false
	_tooltip_panel.set_as_top_level(true)
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$UI.add_child(_tooltip_panel)

	_tooltip_timer = Timer.new()
	_tooltip_timer.wait_time = 0.1
	_tooltip_timer.one_shot = true
	_tooltip_timer.timeout.connect(_show_tooltip)
	add_child(_tooltip_timer)

func _process(delta):
	# The new steam manager uses signals, so we connect to it in _setup_multiplayer_game
	pass

func _add_player_ability(new_ability: AbilityData):
	# Instantiate and display a UI element for each ability the player has
	var ability_ui_instance: AbilityUI = ABILITY_UI_SCENE.instantiate() as AbilityUI
	abilities_ui.add_child(ability_ui_instance)
	ability_ui_instance.die_returned_from_slot.connect(_on_die_returned_to_pool)
	ability_ui_instance.ability_activated.connect(_on_ability_activated)
	ability_ui_instance.initialize(new_ability, player)
	
	# Apply current scale to the new ability UI
	var viewport_size = get_viewport().get_visible_rect().size
	var scale_factor = viewport_size.y / 648.0
	if ability_ui_instance.has_method("update_scale"):
		ability_ui_instance.update_scale(scale_factor)

func player_turn() -> void:
	# Reset turn flags
	player_turn_ended_status.clear()
	
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
	# Diverge RNG for player rolls so they are unique per player
	if game_state and game_state.is_multiplayer:
		seed(Time.get_ticks_usec() + steam_manager.get_my_id())

	var new_dice: Array[Die] = player.draw_hand()
	
	# Roll dice using 3D renderer
	var roll_result = await _roll_dice_3d(new_dice)
	var start_positions = roll_result.positions
	var overlay = roll_result.overlay
	
	if start_positions.is_empty():
		start_positions = dice_bag_icon.get_global_rect().get_center()
		if overlay: overlay.queue_free()
	
	# Animate the new dice into the pool
	await dice_pool_ui.animate_add_dice(new_dice, start_positions, overlay)
	
	if game_state and game_state.is_multiplayer:
		_send_dice_to_all_remotes(new_dice)
	
	current_incoming_damage = 0
	var active_enemies = get_active_enemies()
	
	# Reset enemy block at the start of the player's turn for everyone
	for enemy in active_enemies:
		enemy.block = 0
		enemy.update_health_display()

	if game_state and game_state.is_multiplayer:
		if steam_manager.is_host:
			var intents_data = []
			for i in range(active_enemies.size()):
				var enemy = active_enemies[i]
				enemy.declare_intent(active_enemies)
				
				if enemy.next_action:
					intents_data.append({
						"index": i,
						"action_name": enemy.next_action.action_name,
						"value": enemy.next_action_value
					})
			
			steam_manager.send_p2p_packet_to_all({"type": "sync_enemy_intents", "intents": intents_data})
			_process_enemy_intents(active_enemies)
		else:
			# Client waits for packet to process intents
			pass
	else:
		# Single player
		for enemy in active_enemies:
			enemy.declare_intent(active_enemies)
		_process_enemy_intents(active_enemies)

	player.update_health_display(current_incoming_damage)

	end_turn_button.disabled = false

func _on_end_turn_button_pressed():
	if current_turn == Turn.PLAYER:
		# Discard all dice that are left in the hand this turn.
		player.discard(dice_pool_ui.get_current_dice())
		print("Player block: " + str(player.block))
		
		if game_state and game_state.is_multiplayer:
			var my_id = steam_manager.get_my_id()
			player_turn_ended_status[my_id] = true
			end_turn_button.disabled = true
			end_turn_button.text = "Waiting..."
			steam_manager.send_p2p_packet_to_all({"type": "end_turn", "from_id": my_id})
			_check_all_turns_ended()
		else:
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
		emit_signal("player_performed_action", "ability", player)
		for die_display in slotted_dice_displays:
			total_heal += die_display.die.result_value
		
		player.heal(total_heal)
		print("Resolved 'Heal' ability for %d health." % total_heal)
	elif ability_data.title == "Sweep":
		if slotted_dice_displays.is_empty(): return
		
		var die_value = slotted_dice_displays[0].die.result_value
		var damage = ceili(die_value / 2.0)
		
		emit_signal("player_performed_action", "ability", get_active_enemies())
		for enemy in get_active_enemies():
			await enemy.take_damage(damage, true, player, true)
			await _apply_all_die_effects(slotted_dice_displays[0].die, enemy, damage)
		print("Resolved 'Sweep' ability for %d damage to all enemies." % damage)
	elif ability_data.title == "Hold":
		if slotted_dice_displays.is_empty(): return
		
		var die_to_hold = slotted_dice_displays[0].die
		emit_signal("player_performed_action", "ability", player)
		player.hold_die(die_to_hold)
		print("Resolved 'Hold' ability. Die with value %d will be kept." % die_to_hold.result_value)
	elif ability_data.title == "Roulette":
		if slotted_dice_displays.is_empty(): return
		
		var die_display = slotted_dice_displays[0]
		var die_value = die_display.die.result_value
		var die_list_for_packet: Array[Die] = [die_display.die] # Store for packet before animation
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
			
			emit_signal("player_performed_action", "ability", target)
			await target.take_damage(damage, true, player, true)
			print("Resolved 'Roulette' ability for %d damage to %s." % [damage, target.name])

			# Apply die face effects to the target
			await _apply_all_die_effects(die_display.die, target, damage)
			
			_broadcast_player_action(die_list_for_packet, target, damage, 0, "Roulette")
	elif ability_data.title == "Explosive Shot":
		if slotted_dice_displays.is_empty(): return
		
		# Enter targeting mode
		active_targeting_ability = ability_ui
		targeting_arrow = ARROW_SCENE.instantiate()
		$UI.add_child(targeting_arrow)
		targeting_arrow.set_source(ability_ui.dice_slots_container.get_child(0))
	elif ability_data.title == "Higher Lower":
		if slotted_dice_displays.is_empty(): return
		active_targeting_ability = ability_ui
		targeting_arrow = ARROW_SCENE.instantiate()
		$UI.add_child(targeting_arrow)
		targeting_arrow.set_source(ability_ui.dice_slots_container.get_child(0))
	elif ability_data.title == "Even Odd":
		if slotted_dice_displays.is_empty(): return
		active_targeting_ability = ability_ui
		targeting_arrow = ARROW_SCENE.instantiate()
		$UI.add_child(targeting_arrow)
		targeting_arrow.set_source(ability_ui.dice_slots_container.get_child(0))
	elif ability_data.title == "Rhythm Game":
		if slotted_dice_displays.is_empty(): return
		active_targeting_ability = ability_ui
		targeting_arrow = ARROW_SCENE.instantiate()
		$UI.add_child(targeting_arrow)
		targeting_arrow.set_source(ability_ui.dice_slots_container.get_child(0))
	
	# After an ability resolves, refresh the player's health bar preview.
	var net_damage = max(0, current_incoming_damage - player.block)
	player.update_health_display(net_damage)

func enemy_turn() -> void:
	end_turn_button.disabled = true
	# Only the host processes the enemy turn
	if game_state and game_state.is_multiplayer and not steam_manager.is_host:
		return # Client waits for host to sync enemy actions

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
						var spawned_nodes: Array[Enemy] = []
						if enemy.enemy_data.enemy_name == "Evil Dice Tower":
							spawned_nodes = _spawn_boss_minions(3)
						elif enemy.enemy_data.enemy_name == "Gnomish Tinkerer":
							spawned_nodes = _spawn_gnomish_invention()
						
						if game_state and game_state.is_multiplayer and steam_manager.is_host and not spawned_nodes.is_empty():
							var paths = []
							for node in spawned_nodes:
								paths.append(node.enemy_data.resource_path)
							steam_manager.send_p2p_packet_to_all({"type": "spawn_minions", "paths": paths})

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
						if game_state and game_state.is_multiplayer and steam_manager.is_host:
							var enemy_idx = active_enemies.find(enemy)
							if enemy_idx != -1:
								steam_manager.send_p2p_packet_to_all({"type": "enemy_fled", "index": enemy_idx})
						enemy.die()

				if enemy.next_action.self_destructs:
					enemy.die()

				enemy.clear_intent()
			
			# Tick down statuses at the end of this enemy's turn
			if not enemy._is_dead:
				await enemy.tick_down_statuses()
		
		if game_state and game_state.is_multiplayer:
			if steam_manager.is_host:
				_broadcast_enemy_turn_results()
			next_turn()
			await player_turn()
		else:
			next_turn()
			await player_turn()

func _spawn_boss_minions(count: int) -> Array[Enemy]:
	var current_enemy_count = get_active_enemies().size()
	var max_to_spawn = 6 - current_enemy_count
	if max_to_spawn <= 0:
		print("Cannot spawn more minions, enemy limit of 6 reached.")
		return []

	if enemy_spawner.minion_pool.is_empty():
		push_warning("Minion pool is empty!")
		return []

	var available_minions = enemy_spawner.minion_pool.duplicate()
	available_minions.shuffle()

	var minions_to_spawn = []
	var spawned_enemies: Array[Enemy] = []
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
		spawned_enemies.append(new_enemy)
	
	enemy_container.call_deferred("arrange_enemies")
	return spawned_enemies

func _spawn_gnomish_invention() -> Array[Enemy]:
	if get_active_enemies().size() >= 6:
		print("Cannot spawn invention, enemy limit of 6 reached.")
		return []

	if enemy_spawner.invention_pool.is_empty():
		push_warning("Gnomish invention pool is empty! Cannot spawn.")
		return []

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
	return [new_enemy]

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
			if die_display.die.effect:
				if die_display.die.effect.process_effect == EffectLogic.pierce:
					is_piercing = true
		
		if not is_piercing:
			total_roll += die_display.die.result_value
		dice_to_discard.append(die_display.die)

	# Animate the dice, which will also remove them from the hand UI.
	await _animate_dice_to_target(used_dice_displays, character)

	if is_targeting_player:
		emit_signal("player_performed_action", "block", player)
		player.add_block(total_roll)
		print("Player blocked for %d. Total block: %d" % [total_roll, player.block])
		# Update player health preview immediately
		var net_damage = max(0, current_incoming_damage - player.block)
		player.update_health_display(net_damage)

		for die in dice_to_discard:
			if die.effect:
				var effect = die.effect
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
		emit_signal("player_performed_action", "attack", enemy_target)
		await enemy_target.take_damage(total_roll, false, player, true)
		print("Dealt %d damage to %s" % [total_roll, enemy_target.name])

		# After the main action, process any effects from the dice faces
		# We iterate over `dice_to_discard` which contains the actual Die objects,
		# because `used_dice_displays` contains references to nodes that were freed
		# inside `_animate_dice_to_target`.
		for die in dice_to_discard:
			if die.effect:
				var effect = die.effect
				# Spikes is a self-buff, it should not be applied to enemies.
				if effect.name == "Spikes":
					continue
				_process_die_face_effect(effect, die.result_value, enemy_target, die)

	# Broadcast action to multiplayer peers
	_broadcast_player_action(dice_to_discard, character, total_roll if not is_targeting_player else 0, total_roll if is_targeting_player else 0)

	player.discard(dice_to_discard)
	is_resolving_action = false

func _resolve_targeted_ability(target: Character):
	if not target is Enemy:
		return # Only target enemies for now

	var ability_data = active_targeting_ability.ability_data
	var slotted_dice = active_targeting_ability.get_slotted_dice_displays()
	var die_display = slotted_dice[0]
	var damage = die_display.die.result_value
	var dice_list_for_packet: Array[Die] = [die_display.die]
	
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
		emit_signal("player_performed_action", "ability", target)
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
		
		_broadcast_player_action(dice_list_for_packet, target, damage, 0, "Explosive Shot")
		
	elif ability_data.title == "Higher Lower":
		emit_signal("player_performed_action", "ability", target)
		_start_higher_lower(target, die_display)
		# Clean up targeting arrow immediately, but keep active_targeting_ability set until game ends
		if targeting_arrow:
			targeting_arrow.queue_free()
			targeting_arrow = null
		return
	elif ability_data.title == "Even Odd":
		emit_signal("player_performed_action", "ability", target)
		_start_even_odd(target, die_display)
		if targeting_arrow:
			targeting_arrow.queue_free()
			targeting_arrow = null
		return
	elif ability_data.title == "Rhythm Game":
		emit_signal("player_performed_action", "ability", target)
		_start_rhythm_game(target, die_display)
		if targeting_arrow:
			targeting_arrow.queue_free()
			targeting_arrow = null
		return


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
	
	if rhythm_game_ui and is_instance_valid(rhythm_game_ui):
		rhythm_game_ui.cancel_game()

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

func _start_higher_lower(target: Character, source_display: DieDisplay):
	higher_lower_target = target
	higher_lower_die = source_display.die
	higher_lower_accumulated_results.clear()
	higher_lower_used_faces.clear()
	# Add the initial die result to the accumulated results
	higher_lower_accumulated_results.append({"face": higher_lower_die.result_face, "multiplier": 1})
	higher_lower_used_faces.append(higher_lower_die.result_face)
	
	_create_higher_lower_ui()
	
	# Update UI with current die state
	higher_lower_die_display_node.set_die(higher_lower_die)
	higher_lower_message_label.text = "Current Roll: %d\nGuess Higher or Lower!" % higher_lower_die.result_value
	
	_update_higher_lower_grid()
	
	# Enable buttons
	for btn in higher_lower_buttons_container.get_children():
		if btn is Button: btn.disabled = false
	
	higher_lower_ui.visible = true

func _create_higher_lower_ui():
	if higher_lower_ui: return
	
	var canvas = get_node("UI")
	var panel = Panel.new()
	panel.name = "HigherLowerUI"
	panel.custom_minimum_size = Vector2(500, 500)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -250
	panel.offset_top = -250
	panel.offset_right = 250
	panel.offset_bottom = 250
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.6, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	panel.add_theme_stylebox_override("panel", style)
	
	canvas.add_child(panel)
	higher_lower_ui = panel
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Higher or Lower?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# Container for the die display
	var die_container = CenterContainer.new()
	vbox.add_child(die_container)
	
	higher_lower_die_display_node = DIE_DISPLAY_SCENE.instantiate()
	die_container.add_child(higher_lower_die_display_node)
	# We don't want interactions with this display
	higher_lower_die_display_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	higher_lower_grid = GridContainer.new()
	higher_lower_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	higher_lower_grid.add_theme_constant_override("h_separation", 2)
	higher_lower_grid.add_theme_constant_override("v_separation", 2)
	vbox.add_child(higher_lower_grid)
	
	higher_lower_message_label = Label.new()
	higher_lower_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	higher_lower_message_label.text = "Current Roll: ?"
	vbox.add_child(higher_lower_message_label)
	
	higher_lower_buttons_container = HBoxContainer.new()
	higher_lower_buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	higher_lower_buttons_container.add_theme_constant_override("separation", 20)
	vbox.add_child(higher_lower_buttons_container)
	
	var btn_higher = Button.new()
	btn_higher.text = "Higher"
	btn_higher.custom_minimum_size = Vector2(100, 50)
	btn_higher.pressed.connect(_on_higher_lower_guess.bind("higher"))
	higher_lower_buttons_container.add_child(btn_higher)
	
	var btn_lower = Button.new()
	btn_lower.text = "Lower"
	btn_lower.custom_minimum_size = Vector2(100, 50)
	btn_lower.pressed.connect(_on_higher_lower_guess.bind("lower"))
	higher_lower_buttons_container.add_child(btn_lower)
	
	var btn_equal = Button.new()
	btn_equal.text = "Equal"
	btn_equal.custom_minimum_size = Vector2(100, 50)
	btn_equal.pressed.connect(_on_higher_lower_guess.bind("equal"))
	higher_lower_buttons_container.add_child(btn_equal)

func _update_higher_lower_grid():
	if not higher_lower_grid: return
	for child in higher_lower_grid.get_children():
		child.queue_free()
	
	var die = higher_lower_die
	match die.sides:
		4, 6: higher_lower_grid.columns = die.sides
		8: higher_lower_grid.columns = 4
		10: higher_lower_grid.columns = 5
		12: higher_lower_grid.columns = 6
		20: higher_lower_grid.columns = 5
		_: higher_lower_grid.columns = 4
		
	for face in die.faces:
		var cell = DIE_GRID_CELL_SCENE.instantiate()
		cell.custom_minimum_size = Vector2(30, 30)
		var label = cell.get_node("Label")
		label.text = str(face.value)
		
		var style = StyleBoxFlat.new()
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color.BLACK
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_right = 2
		style.corner_radius_bottom_left = 2
		
		if higher_lower_used_faces.has(face):
			style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
			label.modulate = Color(0.5, 0.5, 0.5)
		else:
			style.bg_color = Color(0.2, 0.6, 0.8, 0.8)
			if die.effect:
				style.bg_color = die.effect.highlight_color
			
			if face == die.result_face:
				style.border_color = Color.GOLD
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
		
		cell.add_theme_stylebox_override("panel", style)
		higher_lower_grid.add_child(cell)

func _on_higher_lower_guess(guess_type: String):
	# Disable buttons during animation/processing
	for btn in higher_lower_buttons_container.get_children():
		if btn is Button: btn.disabled = true
	
	var old_val = higher_lower_die.result_value
	
	# Custom roll logic: pick from unused faces
	var available_faces = []
	for face in higher_lower_die.faces:
		if not higher_lower_used_faces.has(face):
			available_faces.append(face)
	
	if available_faces.is_empty():
		# Should not happen if logic is correct, but handle gracefully
		_end_higher_lower()
		return
		
	var new_face = available_faces.pick_random()
	higher_lower_die.result_face = new_face
	higher_lower_die.result_value = new_face.value
	higher_lower_used_faces.append(new_face)
	
	_update_higher_lower_grid()
	
	var new_val = higher_lower_die.result_value
	
	higher_lower_die_display_node.set_die(higher_lower_die)
	
	var success = false
	var multiplier = 1
	
	if guess_type == "higher" and new_val > old_val: success = true
	elif guess_type == "lower" and new_val < old_val: success = true
	elif guess_type == "equal" and new_val == old_val:
		success = true
		multiplier = 2
	
	if success:
		higher_lower_accumulated_results.append({"face": higher_lower_die.result_face, "multiplier": multiplier})
		if multiplier > 1:
			higher_lower_message_label.text = "Correct! Equal! (x2) Rolled %d. Guess again?" % new_val
		else:
			higher_lower_message_label.text = "Correct! Rolled %d. Guess again?" % new_val
			
		# Check if any faces left
		if higher_lower_used_faces.size() >= higher_lower_die.faces.size():
			higher_lower_message_label.text += "\n(All faces used!)"
			await get_tree().create_timer(1.5).timeout
			_end_higher_lower()
		else:
			# Re-enable buttons
			for btn in higher_lower_buttons_container.get_children():
				if btn is Button: btn.disabled = false
	else:
		if new_val == old_val:
			higher_lower_message_label.text = "Equal! (%d) It's a loss." % new_val
		else:
			higher_lower_message_label.text = "Wrong! Rolled %d." % new_val
		
		await get_tree().create_timer(1.5).timeout
		_end_higher_lower()

func _end_higher_lower():
	higher_lower_ui.visible = false
	
	if not higher_lower_accumulated_results.is_empty() and is_instance_valid(higher_lower_target) and not higher_lower_target._is_dead:
		await _animate_higher_lower_damage_sequence()
	
	active_targeting_ability = null
	
	# Refresh health preview
	var net_damage = max(0, current_incoming_damage - player.block)
	player.update_health_display(net_damage)

func _animate_higher_lower_damage_sequence():
	# Get scale factor for UI scaling
	var scale_factor = 1.0
	if is_instance_valid(player):
		scale_factor = player.current_scale_factor

	# Create a visual die for animation
	var anim_die = DIE_DISPLAY_SCENE.instantiate()
	$UI.add_child(anim_die)
	# Set initial state
	anim_die.set_die(higher_lower_die)
	anim_die.pivot_offset = anim_die.size / 2.0
	anim_die.scale = Vector2(0.6, 0.6) * scale_factor
	
	# Start position: Center of screen (where UI was)
	var start_pos = get_viewport_rect().size / 2
	anim_die.global_position = start_pos - (anim_die.size * anim_die.scale / 2.0)
	
	# Adjust for center of target
	var target_pos = higher_lower_target.global_position # Fallback
	var sprite = higher_lower_target.get_node_or_null("Visuals/Sprite2D")
	if sprite and sprite is Control:
		target_pos = sprite.get_global_rect().get_center()
	
	for i in range(higher_lower_accumulated_results.size()):
		if not is_instance_valid(higher_lower_target) or higher_lower_target._is_dead:
			break
			
		var result_entry = higher_lower_accumulated_results[i]
		var face = result_entry["face"]
		var multiplier = result_entry["multiplier"]
		# Update die data to match this specific result
		higher_lower_die.result_face = face
		higher_lower_die.result_value = face.value
		anim_die.set_die(higher_lower_die)
		
		var tween = create_tween()
		var end_pos = target_pos - (anim_die.size * anim_die.scale / 2.0)
		
		if i == 0:
			# First hit: Fly from center to target
			tween.tween_property(anim_die, "global_position", end_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		else:
			# Subsequent hits: Bounce up and down
			var bounce_height = 100.0 * scale_factor
			var up_pos = target_pos - Vector2(0, bounce_height) - (anim_die.size * anim_die.scale / 2.0)
			var down_pos = end_pos
			
			tween.tween_property(anim_die, "global_position", up_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(anim_die, "global_position", down_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			
		await tween.finished
		
		# Deal damage
		var damage = face.value * multiplier
		await higher_lower_target.take_damage(damage, true, player, true)
		await _apply_all_die_effects(higher_lower_die, higher_lower_target, face.value, face)
		
	anim_die.queue_free()

func _start_even_odd(target: Character, source_display: DieDisplay):
	# This function is very similar to _start_higher_lower.
	# In a future refactor, these could be combined into a single "minigame" system.
	# For now, we keep them separate for clarity.
	if even_odd_ui and even_odd_ui.visible:
		# Prevent starting a new game while one is in progress
		return

	even_odd_target = target
	even_odd_die = source_display.die
	even_odd_accumulated_results.clear()
	even_odd_used_faces.clear()
	# Add the initial die result to the accumulated results
	even_odd_accumulated_results.append({"face": even_odd_die.result_face, "multiplier": 1})
	even_odd_used_faces.append(even_odd_die.result_face)
	
	_create_even_odd_ui()
	
	# Update UI with current die state
	even_odd_die_display_node.set_die(even_odd_die)
	even_odd_message_label.text = "Current Roll: %d\nGuess Even or Odd!" % even_odd_die.result_value
	
	_update_even_odd_grid()
	
	# Enable buttons
	for btn in even_odd_buttons_container.get_children():
		if btn is Button: btn.disabled = false
	
	even_odd_ui.visible = true

func _create_even_odd_ui():
	if even_odd_ui: return
	
	var canvas = get_node("UI")
	var panel = Panel.new()
	panel.name = "EvenOddUI"
	panel.custom_minimum_size = Vector2(500, 500)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -250
	panel.offset_top = -250
	panel.offset_right = 250
	panel.offset_bottom = 250
	
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.1, 0.15, 0.95)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.7, 0.3, 0.8)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	panel.add_theme_stylebox_override("panel", style)
	
	canvas.add_child(panel)
	even_odd_ui = panel
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 20
	vbox.offset_top = 20
	vbox.offset_right = -20
	vbox.offset_bottom = -20
	vbox.add_theme_constant_override("separation", 20)
	panel.add_child(vbox)
	
	var title = Label.new()
	title.text = "Even or Odd?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(title)
	
	# Container for the die display
	var die_container = CenterContainer.new()
	vbox.add_child(die_container)
	
	even_odd_die_display_node = DIE_DISPLAY_SCENE.instantiate()
	die_container.add_child(even_odd_die_display_node)
	# We don't want interactions with this display
	even_odd_die_display_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	even_odd_grid = GridContainer.new()
	even_odd_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	even_odd_grid.add_theme_constant_override("h_separation", 2)
	even_odd_grid.add_theme_constant_override("v_separation", 2)
	vbox.add_child(even_odd_grid)
	
	even_odd_message_label = Label.new()
	even_odd_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	even_odd_message_label.text = "Current Roll: ?"
	vbox.add_child(even_odd_message_label)
	
	even_odd_buttons_container = HBoxContainer.new()
	even_odd_buttons_container.alignment = BoxContainer.ALIGNMENT_CENTER
	even_odd_buttons_container.add_theme_constant_override("separation", 20)
	vbox.add_child(even_odd_buttons_container)
	
	var btn_even = Button.new()
	btn_even.text = "Even"
	btn_even.custom_minimum_size = Vector2(100, 50)
	btn_even.pressed.connect(_on_even_odd_guess.bind("even"))
	even_odd_buttons_container.add_child(btn_even)
	
	var btn_odd = Button.new()
	btn_odd.text = "Odd"
	btn_odd.custom_minimum_size = Vector2(100, 50)
	btn_odd.pressed.connect(_on_even_odd_guess.bind("odd"))
	even_odd_buttons_container.add_child(btn_odd)

func _update_even_odd_grid():
	if not even_odd_grid: return
	for child in even_odd_grid.get_children():
		child.queue_free()
	
	var die = even_odd_die
	match die.sides:
		4, 6: even_odd_grid.columns = die.sides
		8: even_odd_grid.columns = 4
		10: even_odd_grid.columns = 5
		12: even_odd_grid.columns = 6
		20: even_odd_grid.columns = 5
		_: even_odd_grid.columns = 4
		
	for face in die.faces:
		var cell = DIE_GRID_CELL_SCENE.instantiate()
		cell.custom_minimum_size = Vector2(30, 30)
		var label = cell.get_node("Label")
		label.text = str(face.value)
		
		var style = StyleBoxFlat.new()
		style.border_width_left = 1
		style.border_width_top = 1
		style.border_width_right = 1
		style.border_width_bottom = 1
		style.border_color = Color.BLACK
		style.corner_radius_top_left = 2
		style.corner_radius_top_right = 2
		style.corner_radius_bottom_right = 2
		style.corner_radius_bottom_left = 2
		
		if even_odd_used_faces.has(face):
			style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
			label.modulate = Color(0.5, 0.5, 0.5)
		else:
			style.bg_color = Color(0.7, 0.3, 0.8, 0.8) # Purple-ish
			if die.effect:
				style.bg_color = die.effect.highlight_color
			
			if face == die.result_face:
				style.border_color = Color.GOLD
				style.border_width_left = 2
				style.border_width_top = 2
				style.border_width_right = 2
				style.border_width_bottom = 2
		
		cell.add_theme_stylebox_override("panel", style)
		even_odd_grid.add_child(cell)

func _on_even_odd_guess(guess_type: String):
	# Disable buttons during animation/processing
	for btn in even_odd_buttons_container.get_children():
		if btn is Button: btn.disabled = true
	
	# Custom roll logic
	var available_faces = []
	for face in even_odd_die.faces:
		if not even_odd_used_faces.has(face):
			available_faces.append(face)
	
	if available_faces.is_empty():
		_end_even_odd()
		return
		
	var new_face = available_faces.pick_random()
	even_odd_die.result_face = new_face
	even_odd_die.result_value = new_face.value
	even_odd_used_faces.append(new_face)
	
	_update_even_odd_grid()
	
	var new_val = even_odd_die.result_value
	
	even_odd_die_display_node.set_die(even_odd_die)
	
	var success = false
	var multiplier = 1
	
	if guess_type == "even" and new_val % 2 == 0: success = true
	elif guess_type == "odd" and new_val % 2 != 0: success = true
	
	if success:
		even_odd_accumulated_results.append({"face": even_odd_die.result_face, "multiplier": multiplier})
		even_odd_message_label.text = "Correct! Rolled %d. Guess again?" % new_val
		
		if even_odd_used_faces.size() >= even_odd_die.faces.size():
			even_odd_message_label.text += "\n(All faces used!)"
			await get_tree().create_timer(1.5).timeout
			_end_even_odd()
		else:
			# Re-enable buttons
			for btn in even_odd_buttons_container.get_children():
				if btn is Button: btn.disabled = false
	else:
		even_odd_message_label.text = "Wrong! Rolled %d." % new_val
		
		await get_tree().create_timer(1.5).timeout
		_end_even_odd()

func _end_even_odd():
	even_odd_ui.visible = false
	
	if not even_odd_accumulated_results.is_empty() and is_instance_valid(even_odd_target) and not even_odd_target._is_dead:
		await _animate_even_odd_damage_sequence()
	
	active_targeting_ability = null
	
	# Refresh health preview
	var net_damage = max(0, current_incoming_damage - player.block)
	player.update_health_display(net_damage)

func _animate_even_odd_damage_sequence():
	# Get scale factor for UI scaling
	var scale_factor = 1.0
	if is_instance_valid(player):
		scale_factor = player.current_scale_factor

	# Create a visual die for animation
	var anim_die = DIE_DISPLAY_SCENE.instantiate()
	$UI.add_child(anim_die)
	# Set initial state
	anim_die.set_die(even_odd_die)
	anim_die.pivot_offset = anim_die.size / 2.0
	anim_die.scale = Vector2(0.6, 0.6) * scale_factor
	
	# Start position: Center of screen (where UI was)
	var start_pos = get_viewport_rect().size / 2
	anim_die.global_position = start_pos - (anim_die.size * anim_die.scale / 2.0)
	
	# Adjust for center of target
	var target_pos = even_odd_target.global_position # Fallback
	var sprite = even_odd_target.get_node_or_null("Visuals/Sprite2D")
	if sprite and sprite is Control:
		target_pos = sprite.get_global_rect().get_center()
	
	for i in range(even_odd_accumulated_results.size()):
		if not is_instance_valid(even_odd_target) or even_odd_target._is_dead:
			break
			
		var result_entry = even_odd_accumulated_results[i]
		var face = result_entry["face"]
		var multiplier = result_entry["multiplier"]
		# Update die data to match this specific result
		even_odd_die.result_face = face
		even_odd_die.result_value = face.value
		anim_die.set_die(even_odd_die)
		
		var tween = create_tween()
		var end_pos = target_pos - (anim_die.size * anim_die.scale / 2.0)
		
		if i == 0:
			# First hit: Fly from center to target
			tween.tween_property(anim_die, "global_position", end_pos, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		else:
			# Subsequent hits: Bounce up and down
			var bounce_height = 100.0 * scale_factor
			var up_pos = target_pos - Vector2(0, bounce_height) - (anim_die.size * anim_die.scale / 2.0)
			var down_pos = end_pos
			
			tween.tween_property(anim_die, "global_position", up_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tween.tween_property(anim_die, "global_position", down_pos, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			
		await tween.finished
		
		# Deal damage
		var damage = face.value * multiplier
		await even_odd_target.take_damage(damage, true, player, true)
		await _apply_all_die_effects(even_odd_die, even_odd_target, face.value, face)
		
	anim_die.queue_free()

func _start_rhythm_game(target: Character, source_display: DieDisplay):
	if rhythm_game_ui and is_instance_valid(rhythm_game_ui):
		rhythm_game_ui.cancel_game()

	rhythm_game_target = target
	rhythm_game_die = source_display.die
	
	rhythm_game_ui = RHYTHM_GAME_UI_SCENE.instantiate()
	$UI.add_child(rhythm_game_ui)
	rhythm_game_ui.game_finished.connect(_on_rhythm_game_finished)
	rhythm_game_ui.start_game()

func _on_rhythm_game_finished(successful_hits: int):
	if not rhythm_game_target or rhythm_game_target._is_dead:
		active_targeting_ability = null
		return

	var base_damage = rhythm_game_die.result_value
	# Each hit is worth 1/3 of the die's value. 6 hits = 200% damage.
	var total_damage = base_damage * (float(successful_hits) / 3.0)
	
	if total_damage > 0:
		await rhythm_game_target.take_damage(total_damage, true, player, true)
	
	# Effects are applied based on the die's original value, regardless of rhythm game performance.
	await _apply_all_die_effects(rhythm_game_die, rhythm_game_target, base_damage)
	
	active_targeting_ability = null

func _roll_dice_3d(dice: Array[Die]) -> Dictionary:
	if dice.is_empty(): return {"positions": [], "overlay": null}

	var roll_overlay = Control.new()
	roll_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.z_index = 300
	$UI.add_child(roll_overlay)
	
	var dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.5)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	roll_overlay.add_child(dimmer)
	
	var results_map = {}
	
	var viewport_size = get_viewport_rect().size
	
	var r = DIE_3D_RENDERER_SCENE.instantiate()
	roll_overlay.add_child(r)
	r.custom_minimum_size = viewport_size
	r.size = viewport_size
	
	r.roll_finished.connect(func(die, val):
		results_map[die] = val
	)

	for i in range(dice.size()):
		var die = dice[i]
		r.add_die(die, die.sides, 0, die.effect.highlight_color if die.effect else Color.WHITE)
	
	r.roll_all()

	# Wait for finish signal or timeout
	# The timer calls skip_animation, which forces the signal to emit, breaking the await.
	var safety_timer = get_tree().create_timer(10.0)
	safety_timer.timeout.connect(func(): if is_instance_valid(r): r.skip_animation())
	
	await r.all_dice_settled
		
	# Process results
	for die in dice:
		if results_map.has(die):
			var face_val = results_map[die]
			if face_val > 0 and face_val <= die.faces.size():
				die.result_face = die.faces[face_val - 1]
			else:
				die.result_face = die.faces.pick_random()
			
			var bonus = die.get_meta("upgrade_count", 0)
			die.result_value = die.result_face.value + bonus
		else:
			die.roll() # Fallback
			
	var positions = []
	for die in dice:
		positions.append(r.get_die_screen_position(die))
		
	return {"positions": positions, "overlay": roll_overlay}

func _apply_all_die_effects(die: Die, target: Character, value: int, _force_face: Resource = null):
	if die.effect:
		var effect = die.effect
		# Spikes is a self-buff, it should not be applied to enemies.
		if effect.name == "Spikes":
			return
		print("Applying effect '%s' (Value: %d) to %s" % [effect.name, value, target.name])
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
	# modifying the scene tree.
	for die_display in dice_displays:
		var main_display = die_display.get_node("MainDisplay")
		
		# We duplicate individual components to break them free from the PanelContainer's layout,
		# allowing us to animate their scale independently.
		animation_data.append({
			"start_center": main_display.get_global_rect().get_center(),
			"start_scale": main_display.scale,
			"start_size": main_display.size,
			"die_data": die_display.die,
			# Duplicate the visual elements we want to animate
			"icon_dup": main_display.get_node("Icon").duplicate(),
			"label_dup": main_display.get_node("LabelContainer").duplicate()
		})

	# Step 2: Clear the original dice from the hand/pool.
	for die_display in dice_displays:
		if die_display.dice_pool:
			die_display.dice_pool.remove_die(die_display)
			die_display.queue_free()
		else:
			# Fallback if not attached to a pool
			die_display.queue_free()

	# Step 3: Create animation nodes and tweens.
	for i in range(animation_data.size()):
		var data = animation_data[i]
		var start_scale: Vector2 = data.start_scale
		var start_size: Vector2 = data.start_size
		var icon: Control = data.icon_dup
		var label: Control = data.label_dup

		# Create an anchor to handle position
		var anchor = Node2D.new()
		get_tree().get_root().add_child(anchor)
		var anchor_start_pos: Vector2 = data.start_center
		anchor.global_position = anchor_start_pos
		
		# Setup Visuals on Anchor
		anchor.add_child(icon)
		icon.size = start_size
		icon.position = -start_size / 2.0
		icon.scale = start_scale
		icon.pivot_offset = start_size / 2.0
		
		anchor.add_child(label)
		label.size = start_size
		label.position = -start_size / 2.0
		label.scale = start_scale
		label.pivot_offset = start_size / 2.0
		# Ensure label container centers its children
		if label is BoxContainer:
			label.alignment = BoxContainer.ALIGNMENT_CENTER

		var tween = create_tween()
		if tween:
			tweens.append(tween)
		
		# Targeting Logic
		var sprite_node: Node = target.get_node("Visuals/Sprite2D")
		var end_pos: Vector2
		if sprite_node is Control:
			end_pos = (sprite_node as Control).get_global_rect().get_center()
		elif sprite_node is Node2D:
			end_pos = (sprite_node as Node2D).global_position
		else:
			end_pos = target.global_position
			
		var control_pos_x = lerp(anchor_start_pos.x, end_pos.x, 0.2)
		var control_pos_y = min(anchor_start_pos.y, end_pos.y) - 150
		var control_pos = Vector2(control_pos_x, control_pos_y)

		var reveal_time = 0.2
		var move_duration = 0.4
		var delay = i * 0.1

		# 1. Reveal Phase: Pop Die (Icon + Number)
		tween.tween_property(icon, "scale", start_scale * 1.2, reveal_time).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(label, "scale", start_scale * 1.2, reveal_time).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		# 2. Movement Phase: Move Anchor
		tween.parallel().tween_method(
			func(t: float): anchor.global_position = anchor_start_pos.lerp(control_pos, t).lerp(control_pos.lerp(end_pos, t), t),
			0.0, 1.0, move_duration
		).set_delay(delay + reveal_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)

		# 3. Impact Phase: Shrink Anchor
		tween.parallel().tween_property(anchor, "scale", Vector2(0.5, 0.5), move_duration / 2.0).set_delay(delay + reveal_time + move_duration / 2.0)

		# Callbacks
		tween.parallel().tween_callback(target._recoil.bind(data.die_data.result_value)).set_delay(delay + reveal_time + move_duration)
		tween.parallel().tween_callback(anchor.queue_free).set_delay(delay + reveal_time + move_duration)

	if not tweens.is_empty():
		await tweens.back().finished

func _on_map_node_selected(node_data):
	# Multiplayer Sync Logic
	if game_state and game_state.is_multiplayer:
		if steam_manager.is_host:
			# Host generates a seed for the encounter to ensure enemies match on both sides
			var encounter_seed = randi()
			seed(encounter_seed)
			steam_manager.send_p2p_packet_to_all({"type": "enter_encounter", "layer": node_data.layer, "index": node_data.index, "seed": encounter_seed})
		else:
			# Client should not trigger this via UI (input disabled), but if called via code, proceed.
			pass

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
	elif node_data.type == "goblin_camp":
		var encounter = load("res://resources/encounters/pack_o_goblins.tres")
		var spawned_enemies = enemy_spawner.spawn_specific_encounter(encounter)
		_apply_quest_modifiers(spawned_enemies, "goblin_camp")
		await _setup_round(spawned_enemies)
	elif node_data.type == "dragon_roost":
		var encounter = load("res://resources/encounters/white_eyes_blue_dragon.tres")
		var spawned_enemies = enemy_spawner.spawn_specific_encounter(encounter)
		_apply_quest_modifiers(spawned_enemies, "dragons_roost")
		await _setup_round(spawned_enemies)
	elif node_data.type == "dwarven_forge":
		var encounter = load("res://resources/encounters/gnomish_tinkerers.tres")
		var spawned_enemies = enemy_spawner.spawn_specific_encounter(encounter)
		_apply_quest_modifiers(spawned_enemies, "dwarven_forge")
		await _setup_round(spawned_enemies)
	elif node_data.type == "campfire":
		campfire_screen.open()
	elif node_data.type == "crypt":
		is_in_crypt = true
		current_crypt_stage = 0
		_advance_crypt_stage()
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
				enemy.apply_duration_status("raging", -1)

	if get_active_enemies().is_empty():
		if get_tree().root.has_meta("tutorial_mode") and get_tree().root.get_meta("tutorial_mode"):
			return

		# All enemies for the round are defeated
		if map_screen.current_node and map_screen.current_node.type == "boss":
			victory_screen.visible = true
		else:
			_show_reward_screen()
	else:
		# Defer arrangement to prevent physics race conditions where the collision
		# shape position doesn't update in the same frame as the visual position.
		enemy_container.call_deferred("arrange_enemies")

func _advance_crypt_stage():
	# Stages: 0, 1, 2 = Normal. 3 = Campfire. 4 = Mini-boss (Rare).
	if current_crypt_stage < 3:
		print("Crypt Stage %d: Normal Encounter" % current_crypt_stage)
		if current_crypt_stage > 0:
			player.reset_for_new_round()
			enemy_container.clear_everything()
		var spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.NORMAL)
		_apply_quest_modifiers(spawned_enemies, "crypt")
		await _setup_round(spawned_enemies)
	elif current_crypt_stage == 3:
		print("Crypt Stage %d: Rest Area" % current_crypt_stage)
		campfire_screen.open()
	elif current_crypt_stage == 4:
		print("Crypt Stage %d: Mini-Boss" % current_crypt_stage)
		player.reset_for_new_round()
		enemy_container.clear_everything()
		var spawned_enemies = enemy_spawner.spawn_random_encounter(EncounterData.EncounterType.RARE)
		_apply_quest_modifiers(spawned_enemies, "crypt")
		await _setup_round(spawned_enemies)
	else:
		print("Crypt Completed")
		is_in_crypt = false
		map_screen.visible = true

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

	if has_node("/root/GameAnalyticsManager"):
		get_node("/root/GameAnalyticsManager").start_round(round_number)

func _setup_round(spawned_enemies: Array) -> void:
	if spawned_enemies.is_empty():
		push_error("No enemies spawned, cannot start round.")
		return

	for enemy in spawned_enemies:
		# Connect to each new enemy's death signal
		enemy.died.connect(_on_enemy_died)
		enemy.exploded.connect(_on_enemy_exploded)
		enemy.gold_dropped.connect(_on_enemy_gold_dropped.bind(enemy))
	
	# Defer positioning and scaling to ensure physics bodies are ready.
	call_deferred("_on_viewport_size_changed")
	
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
	if source_enemy.has_meta("quest_die_value"):
		var die_val = source_enemy.get_meta("quest_die_value")
		if die_val >= 5:
			amount = ceili(amount * 1.5)
		elif die_val <= 2:
			amount = ceili(amount * 0.7)

	_show_gold_popup(amount, source_enemy.global_position)
	_animate_gold_collection(amount, source_enemy)
	
	# Delay adding gold until the animation (approx) finishes so the counter updates when gold arrives
	get_tree().create_timer(0.8).timeout.connect(func(): 
		player.add_gold(amount)
		if has_node("/root/GameAnalyticsManager"):
			get_node("/root/GameAnalyticsManager").track_gold_source(amount, "loot", source_enemy.enemy_data.enemy_name if source_enemy.enemy_data else "enemy")
	)

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
		
		# Add an effect
		var effect = EffectLibrary.get_random_effect_for_die(sides, tier_limit)
		if effect:
			new_die.effect = effect
					
		dice_options.append(new_die)

	# --- Option 3: Upgrade Existing Die ---
	if not player._game_dice_bag.is_empty():
		var original_die = player._game_dice_bag.pick_random()
		
		# Create a copy for the offer
		var upgrade_offer = Die.new(original_die.sides)
		for j in range(original_die.faces.size()):
			upgrade_offer.faces[j].value = original_die.faces[j].value
		upgrade_offer.effect = original_die.effect
			
		# If no effect, add one. If effect exists, maybe replace? 
		# For now, let's say upgrade adds an effect if missing.
		if not upgrade_offer.effect:
			var effect = EffectLibrary.get_random_effect_for_die(upgrade_offer.sides, tier_limit)
			if effect:
				upgrade_offer.effect = effect
		
		upgrade_offer.set_meta("is_upgrade_reward", true)
		upgrade_offer.set_meta("upgrade_target", original_die)
		
		dice_options.append(upgrade_offer)
	else:
		# Fallback if bag is empty
		var sides = available_sizes.pick_random()
		var new_die = Die.new(sides)
		var effect = EffectLibrary.get_random_effect_for_die(sides, tier_limit)
		if effect:
			new_die.effect = effect
		dice_options.append(new_die)

	return dice_options

func _on_reward_chosen(chosen_die: Die) -> void:
	if (chosen_die == null):
		player.add_gold(10)
		if has_node("/root/GameAnalyticsManager"):
			get_node("/root/GameAnalyticsManager").track_gold_source(10, "reward", "skip_reward")
	else:
		if chosen_die.has_meta("is_upgrade_reward"):
			var target_die = chosen_die.get_meta("upgrade_target")
			# Apply the upgrade: Replace faces of target with chosen
			target_die.faces = chosen_die.faces
			target_die.effect = chosen_die.effect
			print("Upgraded existing die via reward.")
		else:
			# Add the chosen die to the player's deck
			player.add_to_game_bag([chosen_die])
	
	if has_node("/root/GameAnalyticsManager"):
		get_node("/root/GameAnalyticsManager").complete_round(round_number)

	round_number += 1
	reward_screen.visible = false
	
	if is_in_crypt:
		current_crypt_stage += 1
		_advance_crypt_stage()
	elif debug_mode:
		await start_new_round()
	else:
		# Return to map
		if map_screen.has_method("set_view_only"):
			map_screen.set_view_only(false)
		map_screen.visible = true

func _on_play_again_button_pressed():
	# Reload the entire main scene to restart the game.
	get_tree().reload_current_scene()

func _on_leave_campfire():
	if is_in_crypt:
		current_crypt_stage += 1
		_advance_crypt_stage()
	else:
		if map_screen.has_method("set_view_only"):
			map_screen.set_view_only(false)
		map_screen.visible = true

func _on_player_died():
	if has_node("/root/GameAnalyticsManager"):
		get_node("/root/GameAnalyticsManager").fail_round(round_number)
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
	if is_instance_valid(dice_bag_count_label):
		dice_bag_count_label.text = str(count)

func _update_dice_discard(count: int):
	dice_discard_label.text = str(count)

func _on_die_returned_to_pool(die_display: DieDisplay):
	# This is called when a die is removed from an ability slot via right-click.
	dice_pool_ui.add_die_display(die_display)

func _on_player_dice_drawn(new_dice: Array[Die]):
	for die in new_dice:
		die.roll()
	dice_pool_ui.animate_add_dice(new_dice, dice_bag_icon.get_global_rect().get_center())

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
		selected_value_label.text = str(current_selection_total)
		
		var scale_factor = 1.0
		if is_instance_valid(player):
			scale_factor = player.current_scale_factor
			
		var t = inverse_lerp(1.0, 30.0, float(current_selection_total))
		t = clamp(t, 0.0, 1.0)
		
		selected_value_label.add_theme_font_size_override("font_size", int(lerp(48.0, 96.0, t) * scale_factor))
		selected_value_label.add_theme_color_override("font_color", Color.WHITE.lerp(Color.RED, t))
		selected_value_label.add_theme_color_override("font_outline_color", Color.BLACK)
		selected_value_label.add_theme_constant_override("outline_size", int(4 * scale_factor))
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
	panel.z_index = 1000
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.8)
	panel.add_theme_stylebox_override("panel", style)
	canvas.add_child(panel)
	pause_menu_ui = panel

	var center_container = CenterContainer.new()
	center_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center_container)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	center_container.add_child(vbox)

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

func _on_viewport_size_changed():
	# Define a base resolution to calculate the scale factor.
	# 648 seems to be the original design height.
	var base_height = 648.0
	var viewport_size = get_viewport().get_visible_rect().size
	var scale_factor = viewport_size.y / base_height

	# Scale Top Bar elements
	var gold_icon = $UI/GameInfo/TopBar/GoldContainer/GoldIcon
	if gold_icon:
		gold_icon.custom_minimum_size = Vector2(50, 50) * scale_factor

	if dice_bag_button:
		var base_button_size = 50.0
		dice_bag_button.custom_minimum_size = Vector2(base_button_size, base_button_size) * scale_factor
		dice_bag_button.pivot_offset = dice_bag_button.custom_minimum_size / 2.0

	if map_button:
		var base_button_size = 60.0
		map_button.custom_minimum_size = Vector2(base_button_size, base_button_size) * scale_factor
		map_button.pivot_offset = map_button.custom_minimum_size / 2.0

	# Scale Round Info (Dice Bag and Discard Pile)
	if dice_bag_icon:
		dice_bag_icon.custom_minimum_size = Vector2(50, 50) * scale_factor
		dice_bag_icon.pivot_offset = dice_bag_icon.custom_minimum_size / 2.0
	if dice_bag_label:
		dice_bag_label.add_theme_font_size_override("font_size", int(16 * scale_factor))
	
	if dice_discard_icon:
		dice_discard_icon.custom_minimum_size = Vector2(50, 50) * scale_factor
		dice_discard_icon.pivot_offset = dice_discard_icon.custom_minimum_size / 2.0
	if dice_discard_label:
		dice_discard_label.add_theme_font_size_override("font_size", int(16 * scale_factor))

	# Scale Dice Bag Screen
	if dice_bag_screen:
		var panel = dice_bag_screen.get_node_or_null("Panel")
		if panel:
			panel.custom_minimum_size = Vector2(800, 500) * scale_factor
			
			var label = panel.get_node_or_null("VBoxContainer/Label")
			if label:
				label.add_theme_font_size_override("font_size", int(32 * scale_factor))
				
			var close_btn = panel.get_node_or_null("VBoxContainer/CloseButton")
			if close_btn:
				close_btn.custom_minimum_size = Vector2(200, 50) * scale_factor

	if dice_bag_grid:
		dice_bag_grid.add_theme_constant_override("h_separation", int(20 * scale_factor))
		dice_bag_grid.add_theme_constant_override("v_separation", int(20 * scale_factor))
		for child in dice_bag_grid.get_children():
			if child.has_method("update_scale"):
				child.update_scale(scale_factor)
		
		if dice_bag_screen.visible:
			call_deferred("_recalculate_dice_bag_columns")

	player.update_scale(scale_factor)
	if game_state and game_state.is_multiplayer:
		for p in remote_players.values():
			p.update_scale(scale_factor)
		_reposition_players()
	elif is_instance_valid(player):
		player.position.x = viewport_size.x * 0.25
		player.position.y = viewport_size.y * 0.5
		player.update_resting_state()

	if is_instance_valid(enemy_container):
		var top_bar_height = 55.0 * scale_factor
		var available_height = viewport_size.y - top_bar_height
		var available_width = viewport_size.x * 0.5 # Use half the screen width for enemies
		
		enemy_container.position.x = viewport_size.x * 0.75
		enemy_container.position.y = top_bar_height + (available_height / 2.0)
		enemy_container.spawn_area_width = available_width
		
		for enemy in enemy_container.get_children():
			if enemy is Enemy:
				enemy.update_scale(scale_factor)
		# Re-arrange enemies to update their resting positions relative to the new container position.
		enemy_container.arrange_enemies()

	if is_instance_valid(dice_pool_ui):
		dice_pool_ui.update_scale(scale_factor)
		
		# Scale position to avoid overlap with End Turn button
		var pool_base_bottom = -60.0
		var pool_base_height = 100.0
		dice_pool_ui.offset_bottom = pool_base_bottom * scale_factor
		dice_pool_ui.offset_top = (pool_base_bottom - pool_base_height) * scale_factor

	if is_instance_valid(abilities_ui):
		# Adjust offsets to prevent overlap with the scaled top bar and bottom dice pool
		var base_width = 250.0
		var base_left_margin = 20.0
		abilities_ui.offset_left = base_left_margin
		abilities_ui.offset_right = base_left_margin + (base_width * scale_factor)

		var top_bar_height = 70.0 * scale_factor
		abilities_ui.offset_top = top_bar_height
		abilities_ui.offset_bottom = -150.0 * scale_factor
		for ability in abilities_ui.get_children():
			if ability.has_method("update_scale"):
				ability.update_scale(scale_factor)

	if is_instance_valid(end_turn_button):
		var base_width = 100.0
		var button_base_height = 30.0
		var base_bottom_margin = 20.0
		
		var scaled_width = base_width * scale_factor
		var scaled_height = button_base_height * scale_factor
		var scaled_bottom_margin = base_bottom_margin * scale_factor
		
		end_turn_button.offset_left = -scaled_width / 2.0
		end_turn_button.offset_right = scaled_width / 2.0
		end_turn_button.offset_bottom = -scaled_bottom_margin
		end_turn_button.offset_top = -scaled_bottom_margin - scaled_height
		
		end_turn_button.add_theme_font_size_override("font_size", int(16 * scale_factor))

	if is_instance_valid(selected_value_label):
		var label_base_bottom = -200.0
		var label_base_height = 50.0
		selected_value_label.offset_bottom = label_base_bottom * scale_factor
		selected_value_label.offset_top = (label_base_bottom - label_base_height) * scale_factor

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
	_show_dice_list_screen(player._game_dice_bag, "Your Dice Bag")

func _on_round_dice_bag_pressed():
	_show_dice_list_screen(player._round_dice_bag, "Draw Pile")

func _on_dice_discard_pressed():
	_show_dice_list_screen(player._dice_discard, "Discard Pile")

func _show_dice_list_screen(dice_list: Array[Die], title: String):
	for child in dice_bag_grid.get_children():
		child.queue_free()
		
	for die in dice_list:
		var display = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		dice_bag_grid.add_child(display)
		display.set_die(die, true)
		
	dice_bag_screen_title.text = title
	dice_bag_screen.visible = true
	_on_viewport_size_changed()
	
	# Defer column calculation to ensure container sizes are correct.
	call_deferred("_recalculate_dice_bag_columns")

func _on_dice_bag_hover_entered():
	_animate_icon_scale(dice_bag_icon, 1.2)

func _on_dice_bag_hover_exited():
	_animate_icon_scale(dice_bag_icon, 1.0)

func _on_dice_discard_hover_entered():
	_animate_icon_scale(dice_discard_icon, 1.2)

func _on_dice_discard_hover_exited():
	_animate_icon_scale(dice_discard_icon, 1.0)

func _animate_icon_scale(icon: Control, target_scale: float):
	var tween = create_tween()
	tween.tween_property(icon, "scale", Vector2.ONE * target_scale, 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _on_dice_bag_button_hover_entered():
	_animate_icon_scale(dice_bag_button, 1.2)

func _on_dice_bag_button_hover_exited():
	_animate_icon_scale(dice_bag_button, 1.0)

func _on_map_button_pressed():
	if map_screen.has_method("set_view_only"):
		map_screen.set_view_only(true)
	map_screen.visible = true
	if map_screen.has_node("CloseButton"):
		map_screen.get_node("CloseButton").visible = true

func _on_map_button_hover_entered():
	_animate_icon_scale(map_button, 1.2)

func _on_map_button_hover_exited():
	_animate_icon_scale(map_button, 1.0)

func _recalculate_dice_bag_columns():
	if not is_instance_valid(dice_bag_grid) or not dice_bag_grid is GridContainer:
		return

	var scroll_container = dice_bag_grid.get_parent() as ScrollContainer
	if not is_instance_valid(scroll_container):
		return

	var available_width = scroll_container.size.x
	if available_width == 0:
		return

	var scale_factor = get_viewport().get_visible_rect().size.y / 648.0
	var item_base_width = 100.0 # from rewards_die_display.gd
	var h_sep = dice_bag_grid.get_theme_constant("h_separation")
	var item_width = (item_base_width * scale_factor) + h_sep
	
	if item_width > 0:
		var new_columns = floor(available_width / item_width)
		dice_bag_grid.columns = max(1, new_columns)

# --- Custom Tooltip Handlers ---

func _on_control_hover_entered(control: Control, text: String):
	# This generic handler can be connected to any control's mouse_entered signal.
	# Use .bind(control, "Tooltip text") when connecting.
	_tooltip_timer.stop() # Stop any pending hide
	_hide_tooltip(false) # Instantly hide previous tooltip
	_hovered_control = control
	_tooltip_label.text = text
	_tooltip_timer.start()
	# Also connect the exited signal dynamically
	if not control.is_connected("mouse_exited", _on_control_hover_exited):
		control.mouse_exited.connect(_on_control_hover_exited)

func _on_control_hover_exited():
	_tooltip_timer.stop()
	_hovered_control = null
	_hide_tooltip()

func _show_tooltip():
	if not is_instance_valid(_hovered_control): return
	
	if _tooltip_tween and _tooltip_tween.is_running(): _tooltip_tween.kill()
	_tooltip_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	
	var viewport_rect = get_viewport().get_visible_rect()
	var tooltip_size = _tooltip_panel.get_minimum_size()
	var mouse_pos = get_global_mouse_position()
	
	var tooltip_pos = mouse_pos + Vector2(15, 15)
	
	if tooltip_pos.x + tooltip_size.x > viewport_rect.end.x:
		tooltip_pos.x = mouse_pos.x - tooltip_size.x - 15
	if tooltip_pos.y + tooltip_size.y > viewport_rect.end.y:
		tooltip_pos.y = mouse_pos.y - tooltip_size.y - 15
		
	_tooltip_panel.global_position = tooltip_pos
	_tooltip_panel.modulate.a = 0.0
	_tooltip_panel.visible = true
	_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 1.0, 0.2)

func _hide_tooltip(animated: bool = true):
	if _tooltip_tween and _tooltip_tween.is_running(): _tooltip_tween.kill()
	if animated and _tooltip_panel.visible:
		_tooltip_tween = create_tween().set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		_tooltip_tween.tween_property(_tooltip_panel, "modulate:a", 0.0, 0.1)
		_tooltip_tween.tween_callback(func(): if is_instance_valid(_tooltip_panel): _tooltip_panel.visible = false)
	else:
		_tooltip_panel.visible = false

# --- Multiplayer Logic ---

func _setup_multiplayer_game():
	if not game_state or not game_state.is_multiplayer:
		return

	steam_manager.p2p_packet_received.connect(_handle_p2p_packet)

	var my_id = steam_manager.get_my_id()
	player.name_label.text = steam_manager.get_friend_name(my_id)
	var remote_ids = game_state.player_steam_ids.filter(func(id): return id != my_id)

	# Create remote player nodes and UI
	for i in range(remote_ids.size()):
		var remote_id = remote_ids[i]
		
		# Create player node
		var remote_p_node = preload("res://scenes/characters/player.tscn").instantiate()
		remote_p_node.name = "RemotePlayer_%d" % remote_id
		add_child(remote_p_node)
		remote_players[remote_id] = remote_p_node
		remote_p_node.name_label.text = steam_manager.get_friend_name(remote_id)
		
		# Create dice pool UI
		var remote_dp_ui = preload("res://scenes/ui/dice_pool.tscn").instantiate()
		remote_dp_ui.is_read_only = true
		remote_dp_ui.name = "RemoteDicePool_%d" % remote_id
		$UI.add_child(remote_dp_ui)
		remote_dice_pools[remote_id] = remote_dp_ui
		
		# Position the remote dice pool
		var pool_width = 400
		var pool_height = 80
		remote_dp_ui.set_anchors_preset(Control.PRESET_CENTER_TOP)
		remote_dp_ui.offset_top = 60 + (i * (pool_height + 10))
		remote_dp_ui.offset_left = -pool_width / 2
		remote_dp_ui.offset_right = pool_width / 2
		remote_dp_ui.offset_bottom = remote_dp_ui.offset_top + pool_height
		remote_dp_ui.scale = Vector2(0.7, 0.7)

	# Host initializes the game map
	if steam_manager.is_host:
		var game_seed = randi()
		seed(game_seed)
		steam_manager.send_p2p_packet_to_all({"type": "game_start_sync", "seed": game_seed})
		map_screen.generate_new_map()
		if map_screen.has_method("set_view_only"):
			map_screen.set_view_only(false)
		map_screen.visible = true
	else:
		map_screen.set_input_enabled(false) # Client cannot pick nodes

	# Reposition players
	_reposition_players()

func _reposition_players():
	# This is a simple horizontal layout. Can be improved.
	var all_player_nodes = [player] + remote_players.values()
	var count = all_player_nodes.size()
	var total_width = get_viewport_rect().size.x * 0.4
	var start_x = get_viewport_rect().size.x * 0.05
	var step_x = total_width / (count + 1)
	
	for i in range(count):
		all_player_nodes[i].position.x = start_x + (step_x * (i + 1))
		all_player_nodes[i].position.y = get_viewport_rect().size.y * 0.5
		all_player_nodes[i].update_resting_state()

func _send_dice_to_all_remotes(dice: Array[Die]):
	var dice_values = []
	for d in dice:
		dice_values.append({"sides": d.sides, "value": d.result_value})
	steam_manager.send_p2p_packet_to_all({"type": "sync_dice", "dice": dice_values})

func _handle_p2p_packet(packet: Dictionary, from_id: int):
	match packet.type:
		"game_start_sync":
			seed(packet.seed)
			map_screen.generate_new_map()
			map_screen.visible = true
			map_screen.set_input_enabled(false)
			
		"enter_encounter":
			seed(packet.seed)
			# Find the node the host selected
			var node = map_screen.get_node_by_indices(packet.layer, packet.index)
			if node:
				# Manually trigger selection on client
				_on_map_node_selected(node)
		
		"enemy_turn_sync":
			_handle_enemy_turn_sync(packet)
		
		"spawn_minions":
			_handle_remote_spawn(packet.paths)
			
		"enemy_fled":
			var enemies = get_active_enemies()
			if packet.index >= 0 and packet.index < enemies.size():
				var enemy_to_flee = enemies[packet.index]
				enemy_to_flee.die()
		
		"sync_enemy_intents":
			var active_enemies = get_active_enemies()
			for item in packet.intents:
				if item.index < active_enemies.size():
					var enemy = active_enemies[item.index]
					enemy.set_remote_intent(item.action_name, item.value)
			_process_enemy_intents(active_enemies)
		
		"player_action":
			_handle_remote_player_action(packet)

		"sync_dice":
			if remote_dice_pools.has(from_id):
				var pool = remote_dice_pools[from_id]
				pool.clear_pool()
				var remote_dice: Array[Die] = []
				for d_data in packet.dice:
					var d = Die.new(d_data.sides)
					d.result_value = d_data.value
					if d.faces.size() >= d.result_value:
						d.result_face = d.faces[d.result_value - 1]
					remote_dice.append(d)
				pool.add_dice_instantly(remote_dice)
			
		"end_turn":
			player_turn_ended_status[from_id] = true
			if remote_dice_pools.has(from_id):
				remote_dice_pools[from_id].modulate = Color(0.5, 0.5, 0.5) 
			_check_all_turns_ended()
			
		"enemy_turn_complete":
			pass # Deprecated, handled by enemy_turn_sync

func _check_all_turns_ended():
	if not game_state or not game_state.is_multiplayer: return
	
	for player_id in game_state.player_steam_ids:
		if not player_turn_ended_status.has(player_id) or not player_turn_ended_status[player_id]:
			return # Not everyone has ended their turn
	
	# All players have ended their turn
	print("All players have ended their turn.")
	for pool in remote_dice_pools.values():
		pool.modulate = Color.WHITE
	
	if is_instance_valid(end_turn_button):
		end_turn_button.text = "End Turn"
	
	next_turn()
	await enemy_turn()

func _process_enemy_intents(active_enemies: Array):
	current_incoming_damage = 0
	for enemy in active_enemies:
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

func _handle_remote_spawn(paths: Array):
	if not (game_state and game_state.is_multiplayer and not steam_manager.is_host):
		return # Only clients should process this
	
	for path in paths:
		var enemy_data = load(path)
		if enemy_data:
			var new_enemy: Enemy = enemy_spawner.ENEMY_UI.instantiate()
			new_enemy.enemy_data = enemy_data
			enemy_container.add_child(new_enemy)
			new_enemy.died.connect(_on_enemy_died)
			new_enemy.exploded.connect(_on_enemy_exploded)
			new_enemy.gold_dropped.connect(_on_enemy_gold_dropped.bind(new_enemy))
	
	enemy_container.call_deferred("arrange_enemies")

func _broadcast_enemy_turn_results():
	if not (game_state and game_state.is_multiplayer and steam_manager.is_host):
		return

	var player_states = []
	var all_players = [player] + remote_players.values()
	var all_player_ids = [steam_manager.get_my_id()] + remote_players.keys()

	for i in range(all_players.size()):
		var p = all_players[i]
		var p_id = all_player_ids[i]
		var status_data = {}
		for effect in p.statuses:
			status_data[effect.status_name] = p.statuses[effect]

		player_states.append({ "id": p_id, "hp": p.hp, "block": p.block, "statuses": status_data })

	var enemy_states = []
	var enemies = get_active_enemies()
	for i in range(enemies.size()):
		var e = enemies[i]
		var status_data = {}
		for effect in e.statuses:
			status_data[effect.status_name] = e.statuses[effect]
		
		enemy_states.append({ "index": i, "hp": e.hp, "block": e.block, "statuses": status_data })
	
	var packet = { "type": "enemy_turn_sync", "players": player_states, "enemies": enemy_states }
	steam_manager.send_p2p_packet_to_all(packet)

func _handle_enemy_turn_sync(packet):
	# Apply player states
	for p_state in packet.players:
		var p_id = p_state.id
		var target_player = null
		if p_id == steam_manager.get_my_id():
			target_player = player
		elif remote_players.has(p_id):
			target_player = remote_players[p_id]
		
		if target_player:
			target_player.hp = p_state.hp
			target_player.block = p_state.block
			
			var new_statuses = {}
			for status_name in p_state.statuses:
				var effect = StatusLibrary.get_status(status_name.to_lower())
				if effect: new_statuses[effect] = p_state.statuses[status_name]
			target_player.statuses = new_statuses
			
			target_player.update_health_display()
			target_player.statuses_changed.emit(target_player.statuses)

	# Apply enemy states
	var enemies = get_active_enemies()
	for e_state in packet.enemies:
		var e_idx = e_state.index
		if e_idx >= 0 and e_idx < enemies.size():
			var target_enemy = enemies[e_idx]
			target_enemy.hp = e_state.hp
			target_enemy.block = e_state.block
			
			var new_statuses = {}
			for status_name in e_state.statuses:
				var effect = StatusLibrary.get_status(status_name.to_lower())
				if effect: new_statuses[effect] = e_state.statuses[status_name]
			target_enemy.statuses = new_statuses
			
			target_enemy.update_health_display()
			target_enemy.statuses_changed.emit(target_enemy.statuses)
	
	# Now that state is synced, client can start their turn
	if not steam_manager.is_host:
		next_turn()
		await player_turn()

func _broadcast_player_action(dice_list: Array[Die], target: Character, damage: int, block: int, ability_name: String = ""):
	if not (game_state and game_state.is_multiplayer): return
	
	var dice_data = []
	for d in dice_list:
		dice_data.append({"sides": d.sides, "value": d.result_value})
	
	var target_idx = -1
	var is_enemy = false
	
	if target is Enemy:
		is_enemy = true
		# Find index in container to ensure sync
		var all_children = enemy_container.get_children()
		target_idx = all_children.find(target)
	
	var packet = {
		"type": "player_action",
		"from_id": steam_manager.get_my_id(),
		"dice_data": dice_data,
		"target_index": target_idx,
		"is_enemy": is_enemy,
		"damage": damage,
		"block": block,
		"ability": ability_name
	}
	steam_manager.send_p2p_packet_to_all(packet)

func _handle_remote_player_action(packet):
	var from_id = packet.from_id
	if not remote_players.has(from_id): return
	
	var r_player = remote_players[from_id]
	var r_pool = remote_dice_pools[from_id]
	
	# 1. Identify Target
	var target = null
	if packet.is_enemy:
		var children = enemy_container.get_children()
		if packet.target_index >= 0 and packet.target_index < children.size():
			target = children[packet.target_index]
	else:
		target = r_player # Self target (buff/block)
	
	if not target: return

	# 2. Identify Dice in Remote Pool
	var dice_displays_to_animate: Array[DieDisplay] = []
	
	# We look for dice in the pool that match the sides/value sent.
	var pool_children = r_pool.dice_pool_display.duplicate()
	
	for d_data in packet.dice_data:
		var found_disp = null
		for disp in pool_children:
			if disp.die.sides == d_data.sides and disp.die.result_value == d_data.value:
				found_disp = disp
				break
		
		if found_disp:
			dice_displays_to_animate.append(found_disp)
			pool_children.erase(found_disp)
			# Note: _animate_dice_to_target will handle removal from pool
		else:
			# If not found (e.g. ability slot desync), create a temporary one for visual
			var temp_die = Die.new(d_data.sides)
			temp_die.result_value = d_data.value
			if temp_die.faces.size() >= temp_die.result_value:
				temp_die.result_face = temp_die.faces[temp_die.result_value - 1]
			
			var temp_disp = DIE_DISPLAY_SCENE.instantiate()
			temp_disp.set_die(temp_die)
			temp_disp.global_position = r_pool.global_position + r_pool.size / 2
			$UI.add_child(temp_disp)
			dice_displays_to_animate.append(temp_disp)

	# 3. Animate
	await _animate_dice_to_target(dice_displays_to_animate, target)
	
	# 4. Apply Results
	if packet.damage > 0:
		await target.take_damage(packet.damage, true, r_player, true)
	
	if packet.block > 0 and target == r_player:
		target.add_block(packet.block)

func _on_quests_confirmed(quests_data):
	active_quests.clear()
	for q in quests_data:
		active_quests[q.id] = q
	print("Quests confirmed: ", active_quests)
	
	if map_screen and map_screen.has_method("update_quest_log"):
		map_screen.update_quest_log(quests_data)

func _apply_quest_modifiers(spawned_enemies: Array, quest_id: String):
	if not active_quests.has(quest_id): return
	
	var quest_data = active_quests[quest_id]
	var die_value = quest_data.die_value
	print("Applying quest modifiers for %s with die value %d" % [quest_id, die_value])
	
	var modifier = 1.0
	if die_value <= 2:
		modifier = 0.8
	elif die_value >= 5:
		modifier = 1.2
		
	for enemy in spawned_enemies:
		enemy.max_hp = ceili(enemy.max_hp * modifier)
		enemy.hp = enemy.max_hp
		enemy.update_health_display()
		enemy.set_meta("quest_die_value", die_value)

func _on_town_open_map():
	map_screen.visible = true
	town_screen.visible = false
