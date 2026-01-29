extends Control

signal reward_chosen(result)
signal reroll_requested

@onready var dice_choices_container = $VBoxContainer/DiceChoices
@onready var skip_reward_button = $Container/SkipRewards
@onready var title_label = $VBoxContainer/TitleLabel

var rewardChosen = false
var reroll_button: Button
var player: Player

# Special Reward State
var crypt_choices_remaining = 0
var forge_promotions_remaining = 0
var forge_promoted_dice = []
var crypt_selected_effect_data = null

# Selection Overlay
var selection_overlay: Control
var selection_grid: GridContainer
var selection_title: Label
var selection_cancel_button: Button

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
	
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_on_viewport_size_changed")
	
	if MainGame.debug_mode:
		reroll_button = Button.new()
		reroll_button.text = "Reroll (Debug)"
		reroll_button.custom_minimum_size = Vector2(150, 40)
		reroll_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		reroll_button.pressed.connect(func(): emit_signal("reroll_requested"))
		$VBoxContainer.add_child(reroll_button)
		# Place it below title
		$VBoxContainer.move_child(reroll_button, 1)
		
	_create_selection_overlay()

func display_rewards(dice_options: Array[Die]):
	visible = true
	rewardChosen = false
	title_label.text = "Choose Your Reward"
	skip_reward_button.visible = true
	_update_skip_button_text("Skip Rewards (+10[img=24]res://assets/ai/ui/gold.svg[/img])")
	_clear_choices()
	
	for die in dice_options:
		var display = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		dice_choices_container.add_child(display)
		var is_upgrade = die.has_meta("is_upgrade_reward")
		display.set_die(die, false, is_upgrade, [], true)
		display.pressed.connect(_on_die_display_clicked.bind(display))
		
	_on_viewport_size_changed()

func display_abilities(abilities: Array[AbilityData]):
	visible = true
	rewardChosen = false
	title_label.text = "Choose an Ability"
	skip_reward_button.visible = true
	_update_skip_button_text("Skip Ability")
	_clear_choices()
	
	for ability in abilities:
		var btn = Button.new()
		btn.text = "%s\n%s" % [ability.title, ability.description]
		btn.custom_minimum_size = Vector2(200, 120)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		btn.pressed.connect(_on_ability_selected.bind(ability))
		dice_choices_container.add_child(btn)
	
	_on_viewport_size_changed()

func display_crypt_rewards(effects_data: Array):
	visible = true
	rewardChosen = false
	crypt_choices_remaining = 2
	title_label.text = "Choose up to 2 Inscriptions"
	skip_reward_button.visible = true
	_update_skip_button_text("Done")
	_clear_choices()
	
	for data in effects_data:
		var effect = data.effect
		var sides = data.sides
		var btn = Button.new()
		btn.text = "D%d: %s\n%s" % [sides, effect.name, effect.description]
		btn.custom_minimum_size = Vector2(200, 120)
		btn.size_flags_horizontal = SIZE_EXPAND_FILL
		
		# Style the button with effect color
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.2, 0.2, 0.25)
		style.border_width_bottom = 4
		style.border_color = effect.highlight_color
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		btn.add_theme_stylebox_override("normal", style)
		
		btn.pressed.connect(_on_crypt_effect_clicked.bind(data, btn))
		dice_choices_container.add_child(btn)
	
	_on_viewport_size_changed()

func display_forge_rewards():
	visible = true
	rewardChosen = false
	forge_promotions_remaining = 3
	forge_promoted_dice.clear()
	title_label.text = "Promote 3 Dice (+1 Value)"
	skip_reward_button.visible = true
	_update_skip_button_text("Done")
	_clear_choices()
	
	var btn = Button.new()
	btn.text = "Select Die to Promote (%d left)" % forge_promotions_remaining
	btn.custom_minimum_size = Vector2(300, 100)
	btn.add_theme_font_size_override("font_size", 24)
	btn.pressed.connect(_on_forge_start_clicked.bind(btn))
	dice_choices_container.add_child(btn)
	
	_on_viewport_size_changed()

func _clear_choices():
	for child in dice_choices_container.get_children():
		child.queue_free()

func _update_skip_button_text(text: String):
	var label = skip_reward_button.get_node("RichTextLabel")
	label.text = text

func _on_ability_selected(ability: AbilityData):
	if rewardChosen: return
	rewardChosen = true
	emit_signal("reward_chosen", ability)

func _on_crypt_effect_clicked(data, _btn):
	if crypt_choices_remaining <= 0: return
	crypt_selected_effect_data = data
	_show_dice_selection("Select D%d to Inscribe" % data.sides, data.sides)

func _on_forge_start_clicked(_btn):
	if forge_promotions_remaining <= 0: return
	_show_dice_selection("Select Die to Promote")

func _create_selection_overlay():
	selection_overlay = Control.new()
	selection_overlay.visible = false
	selection_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_overlay.z_index = 100
	add_child(selection_overlay)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.95)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_overlay.add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	selection_overlay.add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	selection_title = Label.new()
	selection_title.text = "Select Die"
	selection_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selection_title.add_theme_font_size_override("font_size", 32)
	vbox.add_child(selection_title)
	
	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 500)
	vbox.add_child(scroll)
	
	selection_grid = GridContainer.new()
	selection_grid.columns = 5
	selection_grid.add_theme_constant_override("h_separation", 20)
	selection_grid.add_theme_constant_override("v_separation", 20)
	selection_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(selection_grid)
	
	selection_cancel_button = Button.new()
	selection_cancel_button.text = "Cancel"
	selection_cancel_button.custom_minimum_size = Vector2(200, 50)
	selection_cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	selection_cancel_button.pressed.connect(func(): selection_overlay.visible = false)
	vbox.add_child(selection_cancel_button)

func _show_dice_selection(title: String, filter_sides: int = -1):
	if not player: return
	selection_title.text = title
	selection_overlay.visible = true
	
	for child in selection_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		if filter_sides != -1 and die.sides != filter_sides:
			continue
			
		var btn = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		selection_grid.add_child(btn)
		btn.set_die(die, true)
		btn.scale = Vector2.ONE
		btn.pressed.connect(_on_selection_die_clicked.bind(die))

func _on_selection_die_clicked(die: Die):
	selection_overlay.visible = false
	
	if title_label.text.begins_with("Choose up to 2"): # Crypt Mode
		if crypt_selected_effect_data:
			die.effect = crypt_selected_effect_data.effect
			crypt_choices_remaining -= 1
			title_label.text = "Choose up to %d Inscriptions" % crypt_choices_remaining
			
			# Disable the button for the used effect (find it by text/data)
			for child in dice_choices_container.get_children():
				if child is Button and child.text.contains(crypt_selected_effect_data.effect.name):
					child.disabled = true
					child.text += " (Applied)"
					break
			
			if crypt_choices_remaining <= 0:
				emit_signal("reward_chosen", "done")
				
	elif title_label.text.begins_with("Promote"): # Forge Mode
		if forge_promoted_dice.has(die):
			# Should filter these out in selection really, but safety check
			return
			
		player.upgrade_die(die)
		forge_promoted_dice.append(die)
		forge_promotions_remaining -= 1
		
		var btn = dice_choices_container.get_child(0) as Button
		btn.text = "Select Die to Promote (%d left)" % forge_promotions_remaining
		
		if forge_promotions_remaining <= 0:
			emit_signal("reward_chosen", "done")

func _on_die_display_clicked(display: RewardsDieDisplay):	
	if (!rewardChosen):
		rewardChosen = true
		# Select the clicked die to give visual feedback
		if display.has_method("select"):
			display.select()

		# After a short delay to show the selection, confirm the choice.
		await get_tree().create_timer(0.3).timeout
		emit_signal("reward_chosen", display.die)

func _on_skip_rewards_clicked(_display):
	if (!rewardChosen):
		rewardChosen = true
		if title_label.text.begins_with("Choose up to") or title_label.text.begins_with("Promote"):
			# For Crypt/Forge, "Skip" acts as "Done"
			emit_signal("reward_chosen", "done")
		else:
			# Normal skip (gives gold)
			print("Skipping reward...")
			emit_signal("reward_chosen", null)

func _on_viewport_size_changed():
	var base_height = 648.0
	var viewport_size = get_viewport().get_visible_rect().size
	var scale_factor = viewport_size.y / base_height
	
	for display in dice_choices_container.get_children():
		if display.has_method("update_scale"):
			display.update_scale(scale_factor)
