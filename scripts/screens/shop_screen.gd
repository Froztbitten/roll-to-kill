extends Control

@onready var gold_label: Label = $Panel/VBoxContainer/Header/GoldLabel
@onready var remove_die_button: Button = $Panel/VBoxContainer/Options/RemoveDieButton
@onready var upgrade_die_button: Button = $Panel/VBoxContainer/Options/UpgradeDieButton
@onready var effects_container: HBoxContainer = $Panel/VBoxContainer/Options/EffectsContainer
@onready var abilities_container: HBoxContainer = $Panel/VBoxContainer/Options/AbilitiesContainer
@onready var selection_overlay: Control = $SelectionOverlay
@onready var selection_grid: GridContainer = $SelectionOverlay/ScrollContainer/GridContainer
@onready var selection_title: Label = $SelectionOverlay/TitleLabel
@onready var close_button: Button = $Panel/VBoxContainer/CloseButton

var player: Player
var current_mode = "" # "remove" or "upgrade"

func _ready():
	visible = false
	selection_overlay.visible = false
	
	# Set tooltips for static shop buttons
	remove_die_button.tooltip_text = "Select a die to permanently remove from your bag."
	upgrade_die_button.tooltip_text = "Select a die to increase the value of all its faces by 1.\nCost increases with each upgrade."
	
	# Style static buttons
	_style_shop_button(remove_die_button)
	_style_shop_button(upgrade_die_button)
	_style_shop_button(close_button)
	
	# Auto-connect to MapScreen if present in the scene tree
	var map_screen = get_node_or_null("../MapScreen")
	if map_screen:
		map_screen.node_selected.connect(_on_map_node_selected)

func _on_map_node_selected(node_data):
	if node_data.type == "shop":
		open()

func open():
	player = get_node_or_null("../../Player")
	if not player: return
	
	visible = true
	_update_ui()
	_generate_shop_inventory()

func _update_ui():
	gold_label.text = "Gold: %d" % player.gold
	remove_die_button.text = "Remove Die (%dg)" % player.die_removal_cost
	
	if player.gold < player.die_removal_cost:
		remove_die_button.disabled = true
	else:
		remove_die_button.disabled = false

func _generate_shop_inventory():
	# Clear previous
	for child in effects_container.get_children():
		child.queue_free()
	for child in abilities_container.get_children():
		child.queue_free()
		
	# Generate 3 Random Upgrades
	for i in range(3):
		_generate_offer()

	# Generate 3 Random Abilities
	var ability_files = DirAccess.get_files_at("res://resources/abilities/")
	if ability_files:
		var shuffled_files = Array(ability_files)
		shuffled_files.shuffle()
		for i in range(min(3, shuffled_files.size())):
			var file_name = shuffled_files[i]
			if file_name.ends_with(".tres") or file_name.ends_with(".remap"):
				file_name = file_name.replace(".remap", "")
				var ability = load("res://resources/abilities/" + file_name) as AbilityData
				if ability:
					var btn = Button.new()
					btn.text = "%s (150g)" % ability.title
					btn.tooltip_text = _clean_bbcode(ability.description)
					btn.custom_minimum_size = Vector2(100, 50)
					btn.pressed.connect(_on_buy_ability_pressed.bind(ability, 150, btn))
					_style_shop_button(btn)
					abilities_container.add_child(btn)

func _generate_offer(existing_container: VBoxContainer = null):
	if player._game_dice_bag.is_empty():
		if existing_container:
			existing_container.queue_free()
		return

	var random_die = player._game_dice_bag.pick_random()
	var random_face = random_die.faces.pick_random()
	
	# Use EffectLibrary to get a compatible effect
	var effect = EffectLibrary.get_random_effect_for_die(random_die.sides)
	
	if effect:
		var offer_vbox = existing_container
		if not offer_vbox:
			offer_vbox = VBoxContainer.new()
			offer_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			offer_vbox.custom_minimum_size.x = 240
			effects_container.add_child(offer_vbox)
		else:
			for child in offer_vbox.get_children():
				offer_vbox.remove_child(child)
				child.queue_free()
		
		var die_display = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		offer_vbox.add_child(die_display)
		die_display.set_die(random_die)
		die_display.scale = Vector2.ONE
		die_display.size_flags_horizontal = SIZE_SHRINK_CENTER
		die_display.disabled = true
		die_display.mouse_filter = Control.MOUSE_FILTER_PASS
		
		var sep = HSeparator.new()
		sep.custom_minimum_size.y = 10
		sep.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sep_style = StyleBoxLine.new()
		sep_style.color = Color(1, 1, 1, 0.2)
		sep_style.thickness = 1
		sep.add_theme_stylebox_override("separator", sep_style)
		offer_vbox.add_child(sep)
		
		var desc_container = HFlowContainer.new()
		desc_container.alignment = FlowContainer.ALIGNMENT_CENTER
		offer_vbox.add_child(desc_container)
		
		if random_face.effects.is_empty():
			_add_text_label(desc_container, "Add")
			_add_effect_label(desc_container, effect, random_face.value)
			_add_text_label(desc_container, "to Face %d" % random_face.value)
		else:
			var old_effect = random_face.effects[0]
			_add_text_label(desc_container, "Replace")
			_add_effect_label(desc_container, old_effect, random_face.value)
			_add_text_label(desc_container, "with")
			_add_effect_label(desc_container, effect, random_face.value)
			_add_text_label(desc_container, "on Face %d" % random_face.value)
		
		var btn = Button.new()
		btn.text = "Buy (50g)"
		btn.custom_minimum_size = Vector2(100, 40)
		_style_shop_button(btn)
		btn.pressed.connect(_on_buy_specific_upgrade_pressed.bind(random_die, random_face, effect, 50, btn, die_display))
		offer_vbox.add_child(btn)

func _on_remove_die_pressed():
	if player.gold < player.die_removal_cost: return
	current_mode = "remove"
	_show_dice_selection("Select Die to Remove")

func _on_upgrade_die_pressed():
	current_mode = "upgrade"
	_show_dice_selection("Select Die to Upgrade")

func _show_dice_selection(title: String):
	selection_title.text = title
	selection_overlay.visible = true
	
	for child in selection_grid.get_children():
		child.queue_free()
		
	for die in player._game_dice_bag:
		var btn = preload("res://scenes/screens/rewards_die_display.tscn").instantiate()
		selection_grid.add_child(btn)
		btn.set_die(die, true)
		btn.scale = Vector2.ONE
		btn.pressed.connect(_on_die_selected.bind(die))

func _on_die_selected(die: Die):
	if current_mode == "remove":
		if player.gold >= player.die_removal_cost:
			player.add_gold(-player.die_removal_cost)
			player.remove_die_from_bag(die)
			player.die_removal_cost += 25
			
			# Reroll any shop offers that were for this die
			for offer_vbox in effects_container.get_children():
				if offer_vbox.get_child_count() > 0:
					var display = offer_vbox.get_child(0)
					if display is RewardsDieDisplay and display.die == die:
						_generate_offer(offer_vbox)
			
			_update_ui()
			selection_overlay.visible = false
			
	elif current_mode == "upgrade":
		var upgrades = die.get_meta("upgrade_count", 0)
		if upgrades >= 3:
			print("Die is fully upgraded!")
			return
			
		var cost = 50 * (upgrades + 1)
		if player.gold >= cost:
			player.add_gold(-cost)
			player.upgrade_die(die)
			_update_ui()
			selection_overlay.visible = false
		else:
			print("Not enough gold!")

func _on_buy_specific_upgrade_pressed(die: Die, face, effect: DieFaceEffect, cost: int, button: Button, die_display: Control):
	if player.gold >= cost:
		player.add_gold(-cost)
		face.effects.clear()
		face.effects.append(effect)
		button.disabled = true
		button.text = "Sold"
		_update_ui()
		
		die_display.set_die(die)
		die_display.scale = Vector2.ONE

func _on_buy_ability_pressed(ability, cost, button):
	if player.gold >= cost:
		player.add_gold(-cost)
		player.add_ability(ability)
		button.disabled = true
		button.text = "Sold"
		_update_ui()

func _on_close_button_pressed():
	visible = false
	# Signal Main to continue or go back to map?
	# Assuming Main handles state, but for now we just hide.
	# If MapScreen is visible behind, we might need to re-enable it.
	if not MainGame.debug_mode:
		var map_screen = get_node_or_null("../MapScreen")
		if map_screen:
			map_screen.visible = true

func _on_cancel_selection_pressed():
	selection_overlay.visible = false

func _clean_bbcode(text: String) -> String:
	var regex = RegEx.new()
	regex.compile("\\[.*?\\]")
	return regex.sub(text, "", true)

func _add_text_label(parent: Control, text: String):
	var label = Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)

func _add_effect_label(parent: Control, effect: DieFaceEffect, face_value: int):
	var panel = PanelContainer.new()
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.15, 0.15, 1.0)
	style.border_width_bottom = 2
	style.border_color = effect.highlight_color
	style.content_margin_left = 6
	style.content_margin_right = 6
	panel.add_theme_stylebox_override("panel", style)
	
	var label = Label.new()
	label.text = effect.name
	label.add_theme_color_override("font_color", effect.highlight_color)
	panel.add_child(label)
	
	var tooltip_desc = effect.description
	tooltip_desc = tooltip_desc.replace("{value}", str(face_value))
	tooltip_desc = tooltip_desc.replace("{value / 2}", str(ceili(face_value / 2.0)))
	panel.tooltip_text = _clean_bbcode(tooltip_desc)
	panel.mouse_default_cursor_shape = Control.CURSOR_HELP
	
	parent.add_child(panel)

func _style_shop_button(btn: Button):
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.2, 0.25, 1.0)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.5, 0.5, 0.6, 1.0)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_bottom_left = 4
	
	btn.add_theme_stylebox_override("normal", style)
	
	var hover_style = style.duplicate()
	hover_style.bg_color = Color(0.3, 0.3, 0.35, 1.0)
	btn.add_theme_stylebox_override("hover", hover_style)
	
	var pressed_style = style.duplicate()
	pressed_style.bg_color = Color(0.1, 0.1, 0.15, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_style)
