extends Node

var main_game
var overlay: TutorialOverlay
var player_highlight: Control
var combined_highlight: Control
var highlight_targets: Array[Control] = []

func _ready():
	# Wait for MainGame to be ready
	await get_tree().process_frame
	main_game = get_parent()
	
	overlay = preload("res://scenes/ui/tutorial_overlay.tscn").instantiate() as TutorialOverlay
	if not overlay:
		push_error("TutorialOverlay failed to instantiate. Check if the script path in the tscn matches the file location.")
		return
	main_game.get_node("UI").add_child(overlay)
	
	start_tutorial()

func _process(_delta):
	# Keep the player highlight synced with the player's position and scale
	if is_instance_valid(player_highlight) and player_highlight.is_inside_tree() and \
			is_instance_valid(main_game) and is_instance_valid(main_game.player) and main_game.player.is_inside_tree():
		var p = main_game.player
		var p_size = Vector2(128, 128) * p.current_scale_factor
		player_highlight.size = p_size
		var p_screen_pos = p.get_global_transform_with_canvas().origin
		player_highlight.position = p_screen_pos + (Vector2(0, -20) * p.current_scale_factor) - (p_size / 2)
		
	# Update combined highlight for multiple targets (e.g. drag and drop steps)
	if is_instance_valid(combined_highlight) and not highlight_targets.is_empty():
		var union_rect: Rect2
		var first = true
		for target in highlight_targets:
			if is_instance_valid(target) and target.is_visible_in_tree():
				var rect = target.get_global_rect()
				if first:
					union_rect = rect
					first = false
				else:
					union_rect = union_rect.merge(rect)
		
		if not first:
			combined_highlight.size = union_rect.size
			combined_highlight.global_position = union_rect.position

func start_tutorial():
	# Step 1: Welcome
	overlay.show_message("Welcome to Roll to Kill!\n\nIn this game, you use dice to battle enemies. Let's go over the basics.")
	await overlay.next_step
	
	# Step 2: Player Info
	var player_info = main_game.get_node("UI/GameInfo/TopBar")
	overlay.show_message("This is your status bar.\n\nHere you can see your Gold, Map, and Dice Bag.", player_info)
	await overlay.next_step
	
	# Step 3: Health
	var player_health = main_game.player.get_node("Visuals/InfoContainer/HealthBar")
	overlay.show_message("This is your Health.\n\nIf it reaches 0, you lose. Keep an eye on it!", player_health)
	await overlay.next_step
	
	# Step 4: Enemy
	var enemies = main_game.get_active_enemies()
	if enemies.is_empty():
		await get_tree().create_timer(0.5).timeout
		enemies = main_game.get_active_enemies()
	
	var enemy = enemies[0]
	# Use Sprite2D (TextureRect) for highlighting as Visuals is Node2D and cannot be highlighted by the overlay
	var enemy_visuals = enemy.get_node("Visuals/Sprite2D")
	overlay.show_message("This is your enemy.\n\nAbove their head, you can see their INTENT. This tells you what they will do next turn.", enemy_visuals)
	await overlay.next_step
	
	# Step 5: Dice Pool
	var dice_pool = main_game.dice_pool_ui
	
	# Spawn specific dice for the tutorial so the player has something to use
	dice_pool.clear_pool()
	var die1 = Die.new(6)
	die1.result_value = 3
	die1.result_face = die1.faces[2]
	
	var die2 = Die.new(6)
	die2.result_value = 3
	die2.result_face = die2.faces[2]
	
	var tutorial_dice: Array[Die] = [die1, die2]
	dice_pool.add_dice_instantly(tutorial_dice)
	
	# Disable dice interaction during explanation
	for d in dice_pool.dice_pool_display:
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	overlay.show_message("These are your dice.\n\nAt the start of your turn, you draw dice from your bag and roll them.", dice_pool)
	await overlay.next_step
	
	# Step 6: Attack (Select)
	var die_3_display = null
	for d in dice_pool.dice_pool_display:
		if d.die.result_value == 3:
			die_3_display = d
			break
	
	if die_3_display:
		die_3_display.mouse_filter = Control.MOUSE_FILTER_STOP
	
	overlay.show_message("To ATTACK, first click the die with value 3.", die_3_display, false)
	
	# Wait for selection
	while true:
		await get_tree().process_frame
		if not main_game.selected_dice_display.is_empty():
			if main_game.selected_dice_display[0].die.result_value == 3:
				break
	
	# Step 6b: Attack (Target)
	overlay.show_message("Now click the enemy to deal 3 damage.", enemy_visuals, false)
	
	# Wait for attack
	var action_data = await main_game.player_performed_action
	while not action_data[1] is Enemy: # Wait until target is enemy
		action_data = await main_game.player_performed_action
	
	# Step 7: Block (Select)
	var die_block_display = null
	for d in dice_pool.dice_pool_display:
		if d.die.result_value == 3:
			die_block_display = d
			break
			
	if die_block_display:
		die_block_display.mouse_filter = Control.MOUSE_FILTER_STOP
			
	overlay.show_message("Great!\n\nTo BLOCK, click the remaining die (value 3).", die_block_display, false)
	
	# Wait for selection
	while true:
		await get_tree().process_frame
		if not main_game.selected_dice_display.is_empty():
			if main_game.selected_dice_display[0].die.result_value == 3:
				break
		
	# Step 7b: Block (Target)
	# Create a dummy control to highlight the player body since Sprite2D is not a Control
	player_highlight = Control.new()
	# Position is now handled in _process
	player_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_game.get_node("UI").add_child(player_highlight)
	
	overlay.show_message("Now click YOURSELF to gain Block equal to the die's value.\n\nBlock reduces incoming damage.", player_highlight, false)
	
	# Wait for block
	action_data = await main_game.player_performed_action
	while not action_data[1] is Player: # Wait until target is player
		action_data = await main_game.player_performed_action
		
	player_highlight.queue_free()
	player_highlight = null
		
	# Step 8: End Turn
	var end_turn = main_game.end_turn_button
	overlay.show_message("You are out of dice. Press END TURN to let the enemy act.", end_turn, false)
	
	await end_turn.pressed
	
	# Wait for enemy turn to finish and player turn to start
	while main_game.current_turn == 0: # 0 is PLAYER
		await get_tree().process_frame
	while main_game.current_turn != 0: # Wait for it to be PLAYER again
		await get_tree().process_frame
		
	# Step 9: Abilities
	var heal_ability = load("res://resources/abilities/heal.tres")
	main_game.player.add_ability(heal_ability)
	
	# Force spawn a 3 for the tutorial
	dice_pool.clear_pool()
	var die_heal = Die.new(6)
	die_heal.result_value = 3
	die_heal.result_face = die_heal.faces[2]
	var tutorial_dice_heal: Array[Die] = [die_heal]
	dice_pool.add_dice_instantly(tutorial_dice_heal)
	
	await get_tree().process_frame
	var ability_ui = main_game.abilities_ui.get_child(0)
	
	# Find the die display
	var die_heal_display = null
	for d in dice_pool.dice_pool_display:
		if d.die == die_heal:
			die_heal_display = d
			break
			
	# Create combined highlight covering both the die and the ability slot
	combined_highlight = Control.new()
	combined_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_game.get_node("UI").add_child(combined_highlight)
	highlight_targets = [ability_ui, die_heal_display]
	
	# Disable normal die clicking (selection for attack/block) to force drag-and-drop
	if main_game.dice_pool_ui.die_clicked.is_connected(main_game._on_die_clicked):
		main_game.dice_pool_ui.die_clicked.disconnect(main_game._on_die_clicked)
	
	overlay.show_message("It's your turn again!\n\nYou have received the HEAL ability.\nDrag the die into the ability slot to heal yourself.", combined_highlight, false)
	
	# Wait for ability usage
	action_data = await main_game.player_performed_action
	while action_data[0] != "ability":
		action_data = await main_game.player_performed_action
		
	# Re-enable die clicking
	if not main_game.dice_pool_ui.die_clicked.is_connected(main_game._on_die_clicked):
		main_game.dice_pool_ui.die_clicked.connect(main_game._on_die_clicked)
		
	combined_highlight.queue_free()
	combined_highlight = null
	highlight_targets.clear()

	# Step 10: Die Face Effects
	dice_pool.clear_pool()
	var die_bleed = Die.new(8)
	die_bleed.result_value = 3
	die_bleed.result_face = die_bleed.faces[2]
	
	# Add Bleed effect
	var bleed_template = EffectLibrary.get_effect_by_name("Bleed")
	var bleed_effect
	if bleed_template:
		bleed_effect = DieFaceEffect.new(
			bleed_template.name,
			bleed_template.description,
			bleed_template.tier,
			bleed_template.highlight_color
		)
		bleed_effect.process_effect = bleed_template.process_effect
	else:
		bleed_effect = DieFaceEffect.new("Bleed", "If used to attack, apply [color=yellow]{value}[/color] [b]Bleed[/b].", 1, Color("#a12020"))
		bleed_effect.process_effect = EffectLogic.bleed
		
	die_bleed.effect = bleed_effect
	
	var tutorial_dice_bleed: Array[Die] = [die_bleed]
	dice_pool.add_dice_instantly(tutorial_dice_bleed)
	
	var die_bleed_display = dice_pool.dice_pool_display[0]
	
	overlay.show_message("Some dice have special effects on their faces.\n\nThis die has a [color=#a12020]Bleed[/color] effect. Hover over it to see details.", die_bleed_display, false)
	
	# Wait for selection
	while true:
		await get_tree().process_frame
		if not main_game.selected_dice_display.is_empty():
			if main_game.selected_dice_display[0].die == die_bleed:
				break
	
	overlay.show_message("Attack the enemy with this die to apply the effect.", enemy_visuals, false)
	
	# Wait for attack
	action_data = await main_game.player_performed_action
	while not action_data[1] is Enemy:
		action_data = await main_game.player_performed_action
		
	# Wait for the effect to be applied (signal is emitted before effects in main.gd)
	while is_instance_valid(enemy) and not enemy.has_status("Bleeding"):
		await get_tree().process_frame

	# Explain Debuff
	var enemy_status_display = enemy.get_node("Visuals/InfoContainer/StatusEffectDisplay")
	overlay.show_message("The enemy is now [color=#a12020]Bleeding[/color]!\n\nStatus effects appear here. Hover over them to see what they do.", enemy_status_display)
	await overlay.next_step

	# Finish
	overlay.show_message("Excellent!\n\nAbilities are powerful tools. Use them wisely.\n\nDefeat the dummy to finish the tutorial.")
	await overlay.next_step
	
	# Give the player a fresh hand of dice to finish the fight
	dice_pool.clear_pool()
	main_game.player.reset_for_new_round()
	var new_dice = main_game.player.draw_hand()
	for d in new_dice:
		d.roll()
	dice_pool.animate_add_dice(new_dice, main_game.dice_bag_icon.get_global_rect().get_center())
	
	overlay.visible = false
	
	var active_enemies = main_game.get_active_enemies()
	if not active_enemies.is_empty():
		var dummy = active_enemies[0]
		if is_instance_valid(dummy) and not dummy._is_dead:
			await dummy.died
			
	overlay.show_message("Tutorial Complete!\n\nYou are now ready to face the dungeon.")
	await overlay.next_step
	
	get_tree().root.set_meta("tutorial_mode", false)
	get_tree().change_scene_to_file("res://scenes/screens/main_menu.tscn")
